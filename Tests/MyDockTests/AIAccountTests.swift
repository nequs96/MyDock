import Foundation
import Testing
@testable import MyDock

struct AIAccountTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYDOCK_LOCAL_AI_ACCOUNT_TESTS"] == "1"))
    func existingCodexAccountProvidesReadOnlyLimits() throws {
        let status = AIAccountService.detect(.codex)
        #expect(status.state == .signedIn)
        let reading = try CodexAppServerLimitReader.read()
        #expect(reading.availability == .available)
        #expect(reading.windows.contains { $0.usedPercent != nil })
        print("Existing Codex account discovered; read-only quota windows received. No task started.")
    }
    @Test func accountStatusUsesProviderResponsesWithoutDisplayingSecrets() {
        let claude = BoundedSubprocessOutput(standardOutput: Data(#"{"loggedIn":true,"email":"private@example.com","configDirectory":"/tmp/Claude Config"}"#.utf8), standardError: Data(), terminationStatus: 0)
        let status = AIAccountService.parseStatus(provider: .claude, output: claude)
        #expect(status.state == .signedIn)
        #expect(status.configurationDirectory?.path == "/tmp/Claude Config")
        #expect(!status.message.contains("private"))
        let signedOut = BoundedSubprocessOutput(standardOutput: Data(), standardError: Data("Not logged in".utf8), terminationStatus: 1)
        #expect(AIAccountService.parseStatus(provider: .codex, output: signedOut).state == .signedOut)
        let api = BoundedSubprocessOutput(standardOutput: Data(), standardError: Data("Logged in using an API key: sk-private-value".utf8), terminationStatus: 0)
        let apiStatus = AIAccountService.parseStatus(provider: .codex, output: api)
        #expect(apiStatus.state == .signedIn)
        #expect(!apiStatus.message.contains("sk-"))
        #expect(apiStatus.message.contains("ChatGPT"))
        #expect(AIAccountService.parseStatus(provider: .claude, output: signedOut).state == .unavailable)
    }

    @Test func codexAccountDiscoveryUsesStructuredAccountState() throws {
        let connected = try AIAccountService.parseCodexAccount(Data(#"{"result":{"account":{"type":"chatgpt","email":"private@example.com","planType":"plus"}}}"#.utf8))
        #expect(connected.state == .signedIn)
        #expect(!connected.message.contains("private"))
        let missing = try AIAccountService.parseCodexAccount(Data(#"{"result":{"account":null,"requiresOpenaiAuth":true}}"#.utf8))
        #expect(missing.state == .signedOut)
        #expect(throws: (any Error).self) { try AIAccountService.parseCodexAccount(Data(#"{"error":{"message":"expired"}}"#.utf8)) }
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
        #expect(throws: (any Error).self) { try ClaudeLimitsSetup.enable(directory: directory) }
        #expect(try Data(contentsOf: settings) == original)
        try FileManager.default.moveItem(at: settings, to: directory.appendingPathComponent("original.json"))
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: directory.appendingPathComponent("original.json"))
        #expect(throws: (any Error).self) { try ClaudeLimitsSetup.enable(directory: directory) }
        #expect(try Data(contentsOf: settings) == original)
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
