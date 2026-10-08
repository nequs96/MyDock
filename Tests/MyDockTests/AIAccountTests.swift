import Foundation
import Testing
@testable import MyDock

struct AIAccountTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYDOCK_LOCAL_AI_ACCOUNT_TESTS"] == "1"))
    func existingCodexAccountProvidesReadOnlyLimits() async throws {
        // Only this test's own task may read the local account; the rest of the run stays isolated.
        try await AppRuntimeEnvironment.withLiveSystemAccess(enabledBy: "MYDOCK_LOCAL_AI_ACCOUNT_TESTS") {
            let status = AIAccountService.detect(.codex)
            #expect(status.state == .signedIn)
            let reading = try await CodexAppServerLimitReader.read()
            #expect(reading.availability == .available)
            #expect(reading.windows.contains { $0.usedPercent != nil })
            print("Existing Codex account discovered; read-only quota windows received. No task started.")
        }
    }
    @Test func accountStatusUsesProviderResponsesWithoutDisplayingSecrets() {
        let claude = BoundedSubprocessOutput(standardOutput: Data(#"{"loggedIn":true,"email":"private@example.com","configDirectory":"/tmp/Claude Config"}"#.utf8), standardError: Data(), terminationStatus: 0)
        let status = AIAccountService.parseClaudeStatus(claude)
        #expect(status.state == .signedIn)
        #expect(status.configurationDirectory?.path == "/tmp/Claude Config")
        #expect(!status.message.contains("private"))
        let signedOut = BoundedSubprocessOutput(standardOutput: Data(), standardError: Data("Not logged in".utf8), terminationStatus: 1)
        #expect(AIAccountService.parseClaudeStatus(signedOut).state == .unavailable)
        let loggedOut = BoundedSubprocessOutput(standardOutput: Data(#"{"loggedIn":false}"#.utf8), standardError: Data(), terminationStatus: 1)
        #expect(AIAccountService.parseClaudeStatus(loggedOut).state == .signedOut)
    }

    @Test func codexAccountDiscoveryUsesStructuredAccountState() throws {
        let connected = try AIAccountService.parseCodexAccount(Data(#"{"result":{"account":{"type":"chatgpt","email":"private@example.com","planType":"plus"}}}"#.utf8))
        #expect(connected.state == .signedIn)
        #expect(!connected.message.contains("private"))
        let missing = try AIAccountService.parseCodexAccount(Data(#"{"result":{"account":null,"requiresOpenaiAuth":true}}"#.utf8))
        #expect(missing.state == .signedOut)
        let apiKey = try AIAccountService.parseCodexAccount(Data(#"{"result":{"account":{"type":"apiKey","key":"sk-private-value"}}}"#.utf8))
        #expect(apiKey.state == .signedIn)
        #expect(!apiKey.message.contains("sk-"))
        #expect(apiKey.message.contains("ChatGPT"))
        #expect(throws: AIUsageError.codexResponseInvalid) { try AIAccountService.parseCodexAccount(Data(#"{"error":{"message":"expired"}}"#.utf8)) }
    }

    @Test func claudeSetupPreservesSettingsAndDisplayAndIsIdempotent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock '\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = directory.appendingPathComponent("settings.json")
        let original = Data(#"{"theme":"dark","permissions":{"allow":["Read"]},"statusLine":{"type":"command","command":"printf 'existing display'","padding":2}}"#.utf8)
        try original.write(to: settings)
        try ClaudeLimitsSetup.enable(directory: directory)
        #expect(ClaudeLimitsSetup.isEnabled(directory: directory))
        let data = try Data(contentsOf: settings)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["theme"] as? String == "dark")
        #expect((json["permissions"] as? [String: Any])?["allow"] as? [String] == ["Read"])
        let status = try #require(json["statusLine"] as? [String: Any])
        #expect(status["padding"] as? Int == 2)
        let command = try #require(status["command"] as? String)
        let output = try BoundedSubprocessCapture.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command],
            input: Data(#"{"rate_limits":{"five_hour":{"used_percentage":23,"resets_at":1900000000}},"prompt":"private prompt"}"#.utf8),
            maximumOutputBytes: 64_000, maximumErrorBytes: 16_000, timeout: 3)
        #expect(output.terminationStatus == 0)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "existing display")
        let snapshot = try Data(contentsOf: directory.appendingPathComponent("mydock-rate-limits.json"))
        #expect(!String(decoding: snapshot, as: UTF8.self).contains("private prompt"))
        #expect(try ClaudeStatusLineLimitParser.reading(from: snapshot).windows.first?.remainingPercent == 77)
        try ClaudeLimitsSetup.enable(directory: directory)
        #expect(try Data(contentsOf: settings) == data)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("settings.before-mydock-") }
        #expect(backups.count == 1)
        #expect(try Data(contentsOf: #require(backups.first)) == original)
    }

    @Test func invalidAndSymlinkedClaudeSettingsAreNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = directory.appendingPathComponent("settings.json")
        let original = Data("invalid-json".utf8)
        try original.write(to: settings)
        #expect(throws: CocoaError.self) { try ClaudeLimitsSetup.enable(directory: directory) }
        #expect(try Data(contentsOf: settings) == original)
        // The symlink points at valid settings, so only the symlink guard can refuse it.
        let target = directory.appendingPathComponent("original.json")
        let valid = Data(#"{"theme":"dark"}"#.utf8)
        try FileManager.default.removeItem(at: settings)
        try valid.write(to: target)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: target)
        // A linked settings file is refused with its own explanation, never written through.
        #expect(throws: ClaudeLimitsSetupError.symlinkedSettings) { try ClaudeLimitsSetup.enable(directory: directory) }
        #expect(try Data(contentsOf: target) == valid)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path) == target.path)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("settings.before-mydock-") }
        #expect(backups.isEmpty)
    }

    @Test func codexReaderWaitsForInitializationAndKeepsInputOpenUntilReply() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        [ "$1" = app-server ] && [ "$2" = --listen ] && [ "$3" = stdio:// ] || exit 2
        IFS= read -r initialize || exit 3
        printf '{"id":1,"result":{"userAgent":"fixture"}}\n'
        IFS= read -r initialized || exit 4
        IFS= read -r request || exit 5
        printf '{"id":2,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":31,"windowDurationMins":300}}}}\n'
        IFS= read -r finish
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let response = try CodexAccountRPC.request(executable: executable, method: "account/rateLimits/read", timeout: 3)
        #expect(try CodexRateLimitParser.reading(from: response).windows.first?.remainingPercent == 69)
    }
}
