import AppKit
import Combine
import Foundation

enum ShortcutsServiceError: LocalizedError {
    case commandUnavailable
    case commandFailed(String)
    case commandTimedOut
    case outputTooLarge
    case alreadyRunning
    case invalidName

    var errorDescription: String? {
        switch self {
        case .commandUnavailable: "The macOS Shortcuts command is unavailable."
        case .commandFailed(let message): message.isEmpty ? "The Shortcuts command failed." : message
        case .commandTimedOut: "The Shortcuts catalog did not respond in time. Try again."
        case .outputTooLarge: "The Shortcuts catalog returned more data than MyDock can safely read."
        case .alreadyRunning: "This shortcut is already running."
        case .invalidName: "Choose a shortcut first."
        }
    }
}

enum ShortcutCatalogParser {
    static func parse(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.localizedLowercase).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

enum ShortcutsCatalog {
    private static let commandURL = URL(fileURLWithPath: "/usr/bin/shortcuts")

    static func list() async throws -> [String] {
        try AppRuntimeEnvironment.requireNativeEffects()
        return ShortcutCatalogParser.parse(try await runAndCapture(arguments: ["list"]))
    }

    private static func runAndCapture(arguments: [String]) async throws -> String {
        guard FileManager.default.isExecutableFile(atPath: commandURL.path) else {
            throw ShortcutsServiceError.commandUnavailable
        }
        let captured: BoundedSubprocessOutput
        do {
            captured = try await BoundedSubprocessCapture.runCancellable(executableURL: commandURL,
                                                                         arguments: arguments,
                                                                         maximumOutputBytes: 4 * 1_024 * 1_024,
                                                                         maximumErrorBytes: 128 * 1_024,
                                                                         timeout: 20)
        } catch BoundedSubprocessCaptureError.timedOut {
            throw ShortcutsServiceError.commandTimedOut
        } catch BoundedSubprocessCaptureError.outputLimitExceeded {
            throw ShortcutsServiceError.outputTooLarge
        } catch BoundedSubprocessCaptureError.outputReadFailed {
            throw ShortcutsServiceError.commandFailed("MyDock could not safely read the Shortcuts catalog output.")
        }
        guard captured.terminationStatus == 0 else {
            throw ShortcutsServiceError.commandFailed(ShortcutRunMessages.detail(from: captured.standardError))
        }
        return String(decoding: captured.standardOutput, as: UTF8.self)
    }
}

enum ShortcutRunMessages {
    static let maximumStderrBytes = 16 * 1_024
    static let maximumDetailCharacters = 240

    static func completed() -> String { "Completed" }
    static func cancelling() -> String { "Cancelling…" }
    /// Cancel stops the `shortcuts` command MyDock waits on. The run itself belongs to the Shortcuts
    /// runtime, which may keep going, so the status does not claim the shortcut was stopped.
    /// It is short enough for the one-line Status value; Open Shortcuts sits beside it.
    static func cancelled() -> String { "Stopped waiting (may still run)" }
    static func running() -> String { "Running…" }

    /// A short, bounded failure message that includes the first useful stderr text.
    static func failed(exitCode: Int32, standardError: Data) -> String {
        let stderrDetail = Self.detail(from: standardError)
        let base = "Shortcut failed (exit code \(exitCode))."
        return stderrDetail.isEmpty ? base : "\(base) \(stderrDetail)"
    }

    /// The first two lines of stderr on one line, at most `maximumDetailCharacters` long; empty when there is none.
    static func detail(from standardError: Data) -> String {
        let text = String(decoding: standardError.prefix(maximumStderrBytes), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLines = text.split(whereSeparator: \.isNewline).prefix(2).joined(separator: " ")
        return firstLines.count > maximumDetailCharacters
            ? String(firstLines.prefix(maximumDetailCharacters)) + "…"
            : firstLines
    }
}

@MainActor
final class ShortcutExecutionService: ObservableObject {
    static let shared = ShortcutExecutionService()

    @Published private(set) var statusByShortcut: [String: String] = [:]
    @Published private(set) var runningNames: Set<String> = []
    private var runs: [UUID: (name: String, task: Task<Void, Never>)] = [:]
    private var cancelledRuns = Set<UUID>()
    private let commandURL: URL
    private let requiresNativeEffects: Bool

    /// `commandURL` and `requiresNativeEffects` are injectable so fixtures can use a harmless script.
    init(commandURL: URL = URL(fileURLWithPath: "/usr/bin/shortcuts"), requiresNativeEffects: Bool = true) {
        self.commandURL = commandURL
        self.requiresNativeEffects = requiresNativeEffects
    }

    func isRunning(_ name: String) -> Bool { runningNames.contains(name) }

    func run(_ shortcutName: String) throws {
        if requiresNativeEffects { try AppRuntimeEnvironment.requireNativeEffects() }
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ShortcutsServiceError.invalidName }
        guard !runningNames.contains(name) else { throw ShortcutsServiceError.alreadyRunning }
        guard FileManager.default.isExecutableFile(atPath: commandURL.path) else {
            throw ShortcutsServiceError.commandUnavailable
        }

        let runID = UUID()
        let commandURL = commandURL
        runningNames.insert(name)
        statusByShortcut[name] = ShortcutRunMessages.running()
        // Interactive shortcuts may legitimately wait for the user, so there is no execution deadline.
        // The run ends on exit, user Cancel or app quit.
        let task = Task { @MainActor [weak self] in
            let result: String
            do {
                let captured = try await BoundedSubprocessCapture.runCancellable(
                    executableURL: commandURL,
                    // "--" ends option parsing, so a name that starts with "-" is still the shortcut's name.
                    arguments: ["run", "--", name],
                    maximumOutputBytes: 8 * 1_024 * 1_024,
                    maximumErrorBytes: ShortcutRunMessages.maximumStderrBytes,
                    timeout: .infinity)
                result = captured.terminationStatus == 0
                    ? ShortcutRunMessages.completed()
                    : ShortcutRunMessages.failed(exitCode: captured.terminationStatus, standardError: captured.standardError)
            } catch is CancellationError {
                result = ShortcutRunMessages.cancelled()
            } catch BoundedSubprocessCaptureError.outputLimitExceeded {
                result = "Shortcut was stopped because it produced more output than MyDock can read."
            } catch {
                result = "Shortcut could not run: \(error.localizedDescription)"
            }
            self?.finish(runID: runID, name: name, result: result)
        }
        runs[runID] = (name, task)
    }

    /// Asks a running shortcut to stop. The child is terminated normally first and force-stopped after a short grace.
    func cancel(_ name: String) {
        for (runID, run) in runs where run.name == name {
            cancelledRuns.insert(runID)
            statusByShortcut[name] = ShortcutRunMessages.cancelling()
            run.task.cancel()
        }
    }

    /// Stops every running shortcut, for app quit.
    func cancelAll() {
        for name in Set(runs.values.map(\.name)) { cancel(name) }
    }

    func openShortcutsApp() {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
            ?? URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
        NSWorkspace.shared.open(appURL)
    }

    private func finish(runID: UUID, name: String, result: String) {
        guard runs.removeValue(forKey: runID) != nil else { return }
        let wasCancelled = cancelledRuns.remove(runID) != nil
        if !runs.values.contains(where: { $0.name == name }) { runningNames.remove(name) }
        // A shortcut the user cancelled reports "Cancelled" even if the child exited non-zero.
        statusByShortcut[name] = wasCancelled ? ShortcutRunMessages.cancelled() : result
    }
}
