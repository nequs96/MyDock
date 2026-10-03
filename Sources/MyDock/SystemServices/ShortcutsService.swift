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
        ShortcutCatalogParser.parse(try await runAndCapture(arguments: ["list"]))
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
            throw ShortcutsServiceError.commandFailed(String(decoding: captured.standardError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: captured.standardOutput, as: UTF8.self)
    }
}

@MainActor
final class ShortcutExecutionService: ObservableObject {
    static let shared = ShortcutExecutionService()

    @Published private(set) var statusByShortcut: [String: String] = [:]
    private var runningProcesses: [UUID: (name: String, process: Process)] = [:]

    func run(_ shortcutName: String) throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        let name = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ShortcutsServiceError.invalidName }
        guard !runningProcesses.values.contains(where: { $0.name == name }) else {
            throw ShortcutsServiceError.alreadyRunning
        }
        let commandURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        guard FileManager.default.isExecutableFile(atPath: commandURL.path) else {
            throw ShortcutsServiceError.commandUnavailable
        }

        let process = Process()
        let processID = UUID()
        process.executableURL = commandURL
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finishedProcess in
            let result = finishedProcess.terminationStatus == 0
                ? "Completed"
                : "Shortcut failed (exit code \(finishedProcess.terminationStatus))."
            Task { @MainActor [weak self] in self?.finish(processID: processID, name: name, result: result) }
        }
        try process.run()
        runningProcesses[processID] = (name, process)
        statusByShortcut[name] = "Running…"
    }

    func openShortcutsApp() {
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.shortcuts")
            ?? URL(fileURLWithPath: "/System/Applications/Shortcuts.app")
        NSWorkspace.shared.open(appURL)
    }

    private func finish(processID: UUID, name: String, result: String) {
        runningProcesses.removeValue(forKey: processID)
        statusByShortcut[name] = result
    }
}
