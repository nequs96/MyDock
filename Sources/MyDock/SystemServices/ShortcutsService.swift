import AppKit
import Combine
import Foundation

enum ShortcutsServiceError: LocalizedError {
    case commandUnavailable
    case commandFailed(String)
    case alreadyRunning
    case invalidName

    var errorDescription: String? {
        switch self {
        case .commandUnavailable: "The macOS Shortcuts command is unavailable."
        case .commandFailed(let message): message.isEmpty ? "The Shortcuts command failed." : message
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
        try await Task.detached(priority: .userInitiated) {
            ShortcutCatalogParser.parse(try runAndCapture(arguments: ["list"]))
        }.value
    }

    private static func runAndCapture(arguments: [String]) throws -> String {
        guard FileManager.default.isExecutableFile(atPath: commandURL.path) else {
            throw ShortcutsServiceError.commandUnavailable
        }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = commandURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ShortcutsServiceError.commandFailed(String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

@MainActor
final class ShortcutExecutionService: ObservableObject {
    static let shared = ShortcutExecutionService()

    @Published private(set) var statusByShortcut: [String: String] = [:]
    private var runningProcesses: [UUID: (name: String, process: Process)] = [:]

    func run(_ shortcutName: String) throws {
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
