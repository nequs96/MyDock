import AppKit
import Foundation

struct AIAccountStatus: Sendable, Equatable {
    enum State: Sendable, Equatable { case signedIn, signedOut, notInstalled, unavailable }
    var state: State
    var message: String
    var configurationDirectory: URL?
}

/// Uses the providers' own authentication commands. Credentials stay with the provider.
enum AIAccountService {
    static func executable(for provider: AIProvider, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                           environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        guard provider == .codex || provider == .claude else { return nil }
        let name = provider.rawValue
        var candidates = (environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
        candidates += [".local/bin", ".npm-global/bin", "bin"].map { home.appendingPathComponent($0).appendingPathComponent(name) }
        if provider == .codex {
            for app in [URL(fileURLWithPath: "/Applications/Codex.app"), home.appendingPathComponent("Applications/Codex.app")] {
                candidates += ["Contents/Resources/codex", "Contents/MacOS/codex"].map { app.appendingPathComponent($0) }
            }
        }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func claudeDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let path = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    static func parseStatus(provider: AIProvider, output: BoundedSubprocessOutput) -> AIAccountStatus {
        if provider == .claude {
            guard let json = try? JSONSerialization.jsonObject(with: output.standardOutput) as? [String: Any],
                  let loggedIn = json["loggedIn"] as? Bool else {
                return .init(state: .unavailable, message: "Could not check Claude Code. Update Claude Code, then try again.")
            }
            let directory = (json["configDirectory"] as? String).flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            return .init(state: loggedIn ? .signedIn : .signedOut,
                         message: loggedIn ? "Using the Claude Code account on this Mac" : "Sign in to Claude Code to connect this widget",
                         configurationDirectory: directory)
        }
        let text = String(decoding: output.standardOutput + output.standardError, as: UTF8.self).lowercased()
        // Only display a fixed status, never CLI output that could contain account details.
        if output.terminationStatus == 0 && text.contains("logged in") {
            return .init(state: .signedIn, message: text.contains("api key")
                         ? "An API key is connected. Subscription limits require a ChatGPT account."
                         : "Using the Codex account on this Mac")
        }
        if text.contains("not logged in") || text.contains("logged out") {
            return .init(state: .signedOut, message: "Sign in with ChatGPT to connect this widget")
        }
        return .init(state: .unavailable, message: "Could not check Codex. Open Codex, then try again.")
    }

    static func detect(_ provider: AIProvider) -> AIAccountStatus {
        guard let executable = executable(for: provider) else {
            return .init(state: .notInstalled, message: provider == .claude
                         ? "Install Claude Code to read usage from this Mac"
                         : "Install Codex or Codex CLI to read usage from this Mac")
        }
        do {
            if provider == .codex {
                let response = try CodexAccountRPC.request(executable: executable, method: "account/read", parameters: ["refreshToken": false])
                return try parseCodexAccount(response)
            }
            let output = try BoundedSubprocessCapture.run(executableURL: executable,
                arguments: provider == .codex ? ["login", "status"] : ["auth", "status"],
                maximumOutputBytes: 64_000, maximumErrorBytes: 16_000, timeout: 8,
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser)
            return parseStatus(provider: provider, output: output)
        } catch {
            return .init(state: .unavailable, message: "Account check did not finish. Open \(provider.title), then try again.")
        }
    }

    static func parseCodexAccount(_ data: Data) throws -> AIAccountStatus {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any] else { throw AIUsageError.codexResponseInvalid }
        guard let account = result["account"] as? [String: Any] else {
            return .init(state: .signedOut, message: "Sign in with ChatGPT to connect this widget")
        }
        return .init(state: .signedIn, message: account["type"] as? String == "apiKey"
                     ? "An API key is connected. Subscription limits require a ChatGPT account."
                     : "Using the Codex account on this Mac")
    }

    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// A Terminal window keeps interactive login prompts reachable. No credentials are copied into MyDock.
    @MainActor static func signIn(_ provider: AIProvider) throws {
        guard let executable = executable(for: provider) else {
            let address = provider == .codex ? "https://developers.openai.com/codex/cli" : "https://code.claude.com/docs/en/quickstart"
            NSWorkspace.shared.open(URL(string: address)!)
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Login", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let script = directory.appendingPathComponent(provider.title + "-" + UUID().uuidString + ".command")
        let arguments = provider == .codex ? "login" : "auth login"
        let source = "#!/bin/sh\n\(shellQuote(executable.path)) \(arguments)\nresult=$?\nrm -f -- \"$0\"\nprintf '\\nReturn to MyDock and choose Find Account to refresh.\\n'\nexit \"$result\"\n"
        try Data(source.utf8).write(to: script, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        guard NSWorkspace.shared.open(script) else { throw CocoaError(.executableNotLoadable) }
    }
}

enum ClaudeLimitsSetup {
    static let marker = "# MyDock limits bridge v1"

    static func bridgeCommand(directory: URL, previousCommand: String?) -> String {
        let target = AIAccountService.shellQuote(directory.appendingPathComponent("mydock-rate-limits.json").path)
        let template = AIAccountService.shellQuote(directory.appendingPathComponent("mydock-limits.XXXXXX").path)
        let previous = previousCommand.map { "/bin/sh -c \(AIAccountService.shellQuote($0)) < \"$input\"" } ?? "printf 'Claude Code'"
        return """
        \(marker)
        umask 077
        input=$(/usr/bin/mktemp -t mydock-status) || exit 0
        trap 'rm -f -- "$input"' EXIT
        /bin/cat > "$input"
        if limits=$(/usr/bin/plutil -extract rate_limits json -o - "$input" 2>/dev/null); then
          output=$(/usr/bin/mktemp \(template))
          if [ -n "$output" ]; then
            printf '{"updated_at":%s,"rate_limits":%s}' "$(/bin/date +%s)" "$limits" > "$output"
            /bin/mv -f -- "$output" \(target)
          fi
        fi
        \(previous)
        """
    }

    static func isEnabled(directory: URL) -> Bool {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("settings.json")), data.count <= 1_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["statusLine"] as? [String: Any], let command = status["command"] as? String else { return false }
        return command.hasPrefix(marker)
    }

    /// Idempotent, atomic setup. Other settings and the existing terminal display are preserved.
    static func enable(directory: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        var root: [String: Any] = [:]
        var original: Data?
        if manager.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_000_000 else { throw CocoaError(.fileReadCorruptFile) }
            original = try Data(contentsOf: url)
            guard let parsed = try JSONSerialization.jsonObject(with: original!) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            root = parsed
        }
        var status = root["statusLine"] as? [String: Any] ?? [:]
        if let value = root["statusLine"], !(value is [String: Any]) { throw CocoaError(.fileReadCorruptFile) }
        if let command = status["command"] as? String, command.hasPrefix(marker) { return }
        if !status.isEmpty, status["type"] as? String != "command" { throw CocoaError(.fileReadCorruptFile) }
        status["command"] = bridgeCommand(directory: directory, previousCommand: status["command"] as? String)
        status["type"] = "command"
        root["statusLine"] = status
        if let original {
            let backup = directory.appendingPathComponent("settings.before-mydock-" + UUID().uuidString + ".json")
            try original.write(to: backup, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
