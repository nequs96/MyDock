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
        candidates(for: provider, home: home, environment: environment)
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// Where a Finder-launched app looks for the CLI, first match wins. A GUI app's PATH is minimal, so the
    /// usual installer and Node version-manager locations are listed too; the newest nvm Node comes first.
    static func candidates(for provider: AIProvider, home: URL, environment: [String: String]) -> [URL] {
        guard provider == .codex || provider == .claude else { return [] }
        let name = provider.rawValue
        var candidates = (environment["PATH"] ?? "").split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
        candidates += ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
        if provider == .claude { candidates.append(home.appendingPathComponent(".claude/local").appendingPathComponent(name)) }
        candidates += [".local/bin", ".npm-global/bin", "bin", ".volta/bin", ".bun/bin", "Library/pnpm"]
            .map { home.appendingPathComponent($0).appendingPathComponent(name) }
        let nodeVersions = home.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nodeVersions.path)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        candidates += versions.map { nodeVersions.appendingPathComponent($0).appendingPathComponent("bin").appendingPathComponent(name) }
        if provider == .codex {
            for app in [URL(fileURLWithPath: "/Applications/Codex.app"), home.appendingPathComponent("Applications/Codex.app")] {
                candidates += ["Contents/Resources/codex", "Contents/MacOS/codex"].map { app.appendingPathComponent($0) }
            }
        }
        return candidates
    }

    /// The single Claude configuration-directory resolver: account setup, the limits bridge and local activity all use it.
    static func claudeDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                                environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["CLAUDE_CONFIG_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    /// Reads `claude auth status` JSON. Only fixed messages are displayed, never CLI output that could contain account details.
    static func parseClaudeStatus(_ output: BoundedSubprocessOutput) -> AIAccountStatus {
        guard let json = try? JSONSerialization.jsonObject(with: output.standardOutput) as? [String: Any],
              let loggedIn = json["loggedIn"] as? Bool else {
            return .init(state: .unavailable, message: "Could not check Claude Code. Update Claude Code, then try again.")
        }
        let directory = (json["configDirectory"] as? String).flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
        return .init(state: loggedIn ? .signedIn : .signedOut,
                     message: loggedIn ? "Using the Claude Code account on this Mac" : "Sign in to Claude Code to connect this widget",
                     configurationDirectory: directory)
    }

    /// The same check off the Swift-concurrency pool; cancelling the task stops a Codex check.
    static func detectInBackground(_ provider: AIProvider) async -> AIAccountStatus {
        await BackgroundWork.run { cancellation in AIAccountService.detect(provider, cancellation: cancellation) }
    }

    static func detect(_ provider: AIProvider, cancellation: BackgroundCancellation? = nil) -> AIAccountStatus {
        guard AppRuntimeEnvironment.allowsCredentials else {
            return .init(state: .unavailable, message: "Account detection is disabled in isolated validation.")
        }
        guard let executable = executable(for: provider) else {
            return .init(state: .notInstalled, message: provider == .claude
                         ? "Install Claude Code to read usage from this Mac"
                         : "Install Codex or Codex CLI to read usage from this Mac")
        }
        do {
            if provider == .codex {
                let response = try CodexAccountRPC.request(executable: executable, method: "account/read", parameters: ["refreshToken": false],
                                                           cancellation: cancellation)
                return try parseCodexAccount(response)
            }
            let output = try BoundedSubprocessCapture.run(executableURL: executable, arguments: ["auth", "status"],
                maximumOutputBytes: 64_000, maximumErrorBytes: 16_000, timeout: 8,
                currentDirectoryURL: FileManager.default.homeDirectoryForCurrentUser)
            return parseClaudeStatus(output)
        } catch AIUsageError.codexAppServerUnsupported {
            return .init(state: .unavailable, message: "This Codex version cannot report its account. Update Codex, then try again.")
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
        try AppRuntimeEnvironment.requireNativeEffects()
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

enum ClaudeLimitsSetupError: LocalizedError, Equatable {
    /// settings.json is a symbolic link, which MyDock never rewrites.
    case symlinkedSettings

    var errorDescription: String? {
        "Claude Code’s settings.json is a link (for example, to a dotfiles repository), so MyDock leaves it unchanged."
    }
}

enum ClaudeLimitsSetup {
    /// Every bridge version starts with this prefix; `marker` is the current one.
    static let markerPrefix = "# MyDock limits bridge v"
    static let marker = markerPrefix + "2"
    /// The second line records the status-line command the bridge wraps, so Turn Off can restore it.
    static let previousPrefix = "# MyDock previous: "

    /// What the bridge wraps: the user's own status-line command, or none.
    enum WrappedStatusLine: Equatable {
        case none
        case command(String)

        var command: String? {
            if case .command(let value) = self { return value }
            return nil
        }
    }

    static func bridgeCommand(directory: URL, previousCommand: String?) -> String {
        let target = AIAccountService.shellQuote(directory.appendingPathComponent("mydock-rate-limits.json").path)
        let template = AIAccountService.shellQuote(directory.appendingPathComponent("mydock-limits.XXXXXX").path)
        let recorded = previousCommand.map { Data($0.utf8).base64EncodedString() } ?? "none"
        // Without a previous command the status line stays empty, as it was.
        let previous = previousCommand.map { "/bin/sh -c \(AIAccountService.shellQuote($0)) < \"$input\"" } ?? ":"
        // plutil reads property lists, which have no null; when it refuses input that has limits, JavaScriptCore extracts them.
        let script = #"ObjC.import("Foundation"); function run(argv) { var text = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(argv[0], 4, null)); var limits = JSON.parse(text).rate_limits; return limits !== null && typeof limits === "object" ? JSON.stringify(limits) : "" }"#
        return """
        \(marker)
        \(previousPrefix)\(recorded)
        umask 077
        input=$(/usr/bin/mktemp -t mydock-status) || exit 0
        trap 'rm -f -- "$input"' EXIT
        /bin/cat > "$input"
        limits=$(/usr/bin/plutil -extract rate_limits json -o - "$input" 2>/dev/null) || limits=
        if [ -z "$limits" ] && /usr/bin/grep -q '"rate_limits"' "$input"; then
          limits=$(/usr/bin/osascript -l JavaScript -e \(AIAccountService.shellQuote(script)) "$input" 2>/dev/null) || limits=
        fi
        if [ -n "$limits" ]; then
          output=$(/usr/bin/mktemp \(template))
          if [ -n "$output" ]; then
            printf '{"updated_at":%s,"rate_limits":%s}' "$(/bin/date +%s)" "$limits" > "$output"
            /bin/mv -f -- "$output" \(target)
          fi
        fi
        \(previous)
        """
    }

    /// The command a bridge of any version wraps, or nil when the bridge cannot be read.
    /// Version 1 recorded it only as the command run after the bridge's final `fi`.
    static func wrappedStatusLine(in bridge: String) -> WrappedStatusLine? {
        guard bridge.hasPrefix(markerPrefix) else { return nil }
        let lines = bridge.components(separatedBy: "\n")
        if lines.count > 1, lines[1].hasPrefix(previousPrefix) {
            let value = String(lines[1].dropFirst(previousPrefix.count))
            if value == "none" { return WrappedStatusLine.none }
            guard let data = Data(base64Encoded: value), let command = String(data: data, encoding: .utf8) else { return nil }
            return .command(command)
        }
        guard let end = bridge.range(of: "\nfi\n") else { return nil }
        let tail = String(bridge[end.upperBound...])
        if tail == "printf 'Claude Code'" { return WrappedStatusLine.none }
        let head = "/bin/sh -c '", suffix = "' < \"$input\""
        guard tail.hasPrefix(head), tail.hasSuffix(suffix), tail.count >= head.count + suffix.count else { return nil }
        let quoted = String(tail.dropFirst(head.count).dropLast(suffix.count))
        return .command(quoted.replacingOccurrences(of: "'\\''", with: "'"))
    }

    /// The real account directory is never read or modified by an isolated validation session.
    private static func requireIsolationSafe(_ directory: URL) throws {
        if directory.standardizedFileURL == AIAccountService.claudeDirectory().standardizedFileURL {
            try AppRuntimeEnvironment.requireCredentials()
        }
    }

    static func isEnabled(directory: URL) -> Bool {
        guard (try? requireIsolationSafe(directory)) != nil, let data = try? Data(contentsOf: directory.appendingPathComponent("settings.json")), data.count <= 1_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = root["statusLine"] as? [String: Any], let command = status["command"] as? String else { return false }
        return command.hasPrefix(markerPrefix)
    }

    /// Idempotent, atomic setup. Other settings and the existing terminal display are preserved; an older
    /// bridge is upgraded in place around the command it already wraps.
    static func enable(directory: URL) throws { try install(directory: directory, upgradeOnly: false) }

    /// Rewrites a bridge from an earlier MyDock around the command it wraps, so limits sync that is already on
    /// gets this version's bridge. Without a bridge, or with a current one, nothing is written.
    static func upgradeIfOutdated(directory: URL) throws { try install(directory: directory, upgradeOnly: true) }

    private static func install(directory: URL, upgradeOnly: Bool) throws {
        try requireIsolationSafe(directory)
        let manager = FileManager.default
        if !upgradeOnly { try manager.createDirectory(at: directory, withIntermediateDirectories: true) }
        let url = directory.appendingPathComponent("settings.json")
        var root: [String: Any] = [:]
        let original = try readSettings(at: url)
        if let original {
            guard let parsed = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            root = parsed
        }
        var status = root["statusLine"] as? [String: Any] ?? [:]
        if let value = root["statusLine"], !(value is [String: Any]) { throw CocoaError(.fileReadCorruptFile) }
        if let command = status["command"] as? String, command.hasPrefix(markerPrefix) {
            guard !command.hasPrefix(marker), let wrapped = wrappedStatusLine(in: command) else { return }
            status["command"] = bridgeCommand(directory: directory, previousCommand: wrapped.command)
        } else {
            guard !upgradeOnly else { return }
            if !status.isEmpty, status["type"] as? String != "command" { throw CocoaError(.fileReadCorruptFile) }
            status["command"] = bridgeCommand(directory: directory, previousCommand: status["command"] as? String)
            status["type"] = "command"
        }
        root["statusLine"] = status
        if let original {
            let backup = directory.appendingPathComponent("settings.before-mydock-" + UUID().uuidString + ".json")
            try original.write(to: backup, options: .atomic)
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try writeSettings(root, to: url)
    }

    /// Turns limits sync off: restores the status-line command the bridge wraps (or removes the status line
    /// MyDock added) and deletes the limits snapshot. Other settings are untouched.
    static func disable(directory: URL) throws {
        try requireIsolationSafe(directory)
        let url = directory.appendingPathComponent("settings.json")
        if let original = try readSettings(at: url) {
            guard var root = try JSONSerialization.jsonObject(with: original) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
            if var status = root["statusLine"] as? [String: Any], let command = status["command"] as? String,
               command.hasPrefix(markerPrefix) {
                guard let wrapped = wrappedStatusLine(in: command) else { throw CocoaError(.fileReadCorruptFile) }
                switch wrapped {
                case .command(let previous):
                    status["command"] = previous
                    root["statusLine"] = status
                case .none:
                    root.removeValue(forKey: "statusLine")
                }
                try writeSettings(root, to: url)
            }
        }
        let snapshot = directory.appendingPathComponent("mydock-rate-limits.json")
        if FileManager.default.fileExists(atPath: snapshot.path) { try FileManager.default.removeItem(at: snapshot) }
    }

    /// The settings file's bytes, or nil when there is none. A symlink, non-file or oversized file is refused.
    private static func readSettings(at url: URL) throws -> Data? {
        // Checked first: fileExists follows links, and an atomic write would replace the link with a file.
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil { throw ClaudeLimitsSetupError.symlinkedSettings }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 1_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        return try Data(contentsOf: url)
    }

    private static func writeSettings(_ root: [String: Any], to url: URL) throws {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
