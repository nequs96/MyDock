import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import UserNotifications
@testable import MyDock

// Audit lane B: providers, AI readers, Calendar and notifications. Fixtures only: no network, Keychain,
// real home directory, notification centre or Dock preferences.

private func laneBTemporary() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("lane-b-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let laneBNow = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
private let laneBUTC = TimeZone(secondsFromGMT: 0)!

private func laneBLine(_ row: [String: Any]) throws -> Data {
    var data = try JSONSerialization.data(withJSONObject: row)
    data.append(0x0A)
    return data
}

/// Writes `head`, then old padding rows until the file is over the activity reader's 32 MB window, then `tail`.
private func laneBWriteOversizedLog(head: [[String: Any]], padding: [String: Any], tail: [[String: Any]], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = Data()
    for row in head { data.append(try laneBLine(row)) }
    let paddingLine = try laneBLine(padding)
    while data.count < 33_000_000 { data.append(paddingLine) }
    for row in tail { data.append(try laneBLine(row)) }
    try data.write(to: url)
    try FileManager.default.setAttributes([.modificationDate: laneBNow], ofItemAtPath: url.path)
}

private func laneBExecutable(_ script: String) throws -> (directory: URL, executable: URL) {
    let directory = laneBTemporary()
    let executable = directory.appendingPathComponent("codex")
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    return (directory, executable)
}

// MARK: - Stripe (S03-008, S03-009)

private actor LaneBStripeTransport: StripeDataTransport {
    private(set) var requests: [URLRequest] = []

    func response(for request: URLRequest) async throws -> StripeHTTPResponse {
        requests.append(request)
        let type = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "type" }?.value
        let body: String
        switch request.url?.path {
        case "/v1/balance":
            body = #"{"available":[{"currency":"usd","amount":5000}],"pending":[]}"#
        case "/v1/balance_transactions" where type == "charge":
            body = #"{"has_more":false,"data":[{"id":"txn_1","created":2000,"type":"charge","currency":"usd","amount":1000,"net":970}]}"#
        case "/v1/balance_transactions":
            body = #"{"has_more":false,"data":[]}"#
        case "/v1/subscriptions":
            // More subscriptions than one page allows: only the subscription metrics become unavailable.
            body = #"{"has_more":true,"data":[{"id":"sub_\#(requests.count)","status":"active","customer":"cus_1"}]}"#
        default:
            body = "{}"
        }
        return StripeHTTPResponse(statusCode: 200, data: Data(body.utf8))
    }
}

struct AuditLaneBStripeTests {
    @Test func subscriptionsOverBudgetLeaveBalanceAndRevenuePublished() async throws {
        let transport = LaneBStripeTransport()
        let snapshot = try await StripeAPIProvider(transport: transport, maximumPages: 1)
            .snapshot(apiKey: "rk_test_fixture", accountID: "acct_fixture", accountName: "Fixture", period: .thirtyDays,
                      now: Date(timeIntervalSince1970: 2_500), calendar: Calendar(identifier: .gregorian))
        #expect(!snapshot.isAvailable(.mrr) && !snapshot.isAvailable(.arr))
        #expect(!snapshot.isAvailable(.payingSubscribers) && !snapshot.isAvailable(.arpu))
        #expect(snapshot.isAvailable(.revenue) && snapshot.isAvailable(.availableBalance))
        let usd = try #require(snapshot.metrics(for: "USD"))
        #expect(usd.revenueMinor == 1000)
        #expect(usd.netAfterFeesMinor == 970)
        #expect(usd.availableBalanceMinor == 5000)
        let provenance = DataSourceProvenance.stripe(snapshot: snapshot, localName: "Fixture", metric: .mrr, error: nil)
        #expect(provenance.health == .partial)
    }

    @Test func balanceTransactionsAreRequestedPerRevenueTypeWithAPinnedVersion() async throws {
        let transport = LaneBStripeTransport()
        _ = try await StripeAPIProvider(transport: transport, maximumPages: 1)
            .snapshot(apiKey: "rk_test_fixture", accountID: "acct_fixture", accountName: "Fixture", period: .sevenDays,
                      now: Date(timeIntervalSince1970: 2_500), calendar: Calendar(identifier: .gregorian))
        let requests = await transport.requests
        let types = requests.filter { $0.url?.path == "/v1/balance_transactions" }.compactMap { request in
            request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first { $0.name == "type" }?.value
        }
        #expect(types == StripeAPIProvider.revenueTransactionTypes)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Stripe-Version") == StripeAPIProvider.apiVersion })
    }

    @Test func snapshotsSavedBeforeUnavailableMetricsDecodeAsFullyAvailable() throws {
        let legacy = #"{"accountID":"acct_1","accountName":"A","fetchedAt":0,"period":"thirtyDays","periodStart":0,"periodEnd":1,"currencies":[],"unsupportedSubscriptionItems":0}"#
        let snapshot = try JSONDecoder().decode(StripeSnapshot.self, from: Data(legacy.utf8))
        #expect(snapshot.unavailableMetrics == nil)
        #expect(StripeMetric.allCases.allSatisfy(snapshot.isAvailable))
    }
}

// MARK: - Bounded transfers (S03-010)

private struct LaneBSlowBytes: AsyncSequence {
    typealias Element = UInt8
    let total: Int
    struct Iterator: AsyncIteratorProtocol {
        var produced = 0
        let total: Int
        mutating func next() async -> UInt8? {
            guard produced < total else { return nil }
            // The first byte arrives late, so the transfer's deadline passes mid-stream.
            if produced == 0 { try? await Task.sleep(nanoseconds: 200_000_000) }
            produced += 1
            return 0x41
        }
    }
    func makeAsyncIterator() -> Iterator { Iterator(total: total) }
}

struct AuditLaneBTransferTests {
    @Test func deadlineThatPassesMidStreamStopsTheTransfer() async {
        await #expect(throws: BoundedHTTPFetchError.deadlineExceeded) {
            _ = try await BoundedHTTPFetch.collect(LaneBSlowBytes(total: 8_192), maximumBytes: 100_000, maximumDuration: 0.05)
        }
    }
}

// MARK: - Favicons (S03-012)

struct AuditLaneBFaviconTests {
    private func image(side: Int) throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return try #require(context.makeImage())
    }

    @Test func largestFrameIsUsedWhenTheSmallestIsListedFirst() throws {
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 2, nil))
        CGImageDestinationAddImage(destination, try image(side: 16), nil)
        CGImageDestinationAddImage(destination, try image(side: 64), nil)
        #expect(CGImageDestinationFinalize(destination))
        let png = try #require(SiteFaviconFetcher.normalizedPNG(from: data as Data))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 64)
    }
}

// MARK: - Shared integration storage (S03-013)

private struct LaneBConnection: Codable, Identifiable, Equatable {
    var id: String
    var name: String
}

struct AuditLaneBConnectionDirectoryTests {
    @Test func directoryInsertsReplacesUpdatesAndRemovesByIdentifier() throws {
        try #require(AppRuntimeEnvironment.isIsolated)
        let defaults = AppRuntimeEnvironment.defaults
        let directory = ConnectionDirectory<LaneBConnection>(defaultsKey: "lane-b-" + UUID().uuidString)
        defer { defaults.removeObject(forKey: directory.defaultsKey) }
        #expect(directory.entries(defaults: defaults).isEmpty)
        directory.insert(.init(id: "a", name: "First"), defaults: defaults)
        directory.insert(.init(id: "b", name: "Second"), defaults: defaults)
        directory.insert(.init(id: "a", name: "First again"), defaults: defaults)
        #expect(directory.entries(defaults: defaults) == [.init(id: "b", name: "Second"), .init(id: "a", name: "First again")])
        directory.update(.init(id: "b", name: "Renamed"), defaults: defaults)
        directory.update(.init(id: "missing", name: "Ignored"), defaults: defaults)
        #expect(directory.entries(defaults: defaults).map(\.name) == ["Renamed", "First again"])
        directory.remove(id: "a", defaults: defaults)
        #expect(directory.entries(defaults: defaults) == [.init(id: "b", name: "Renamed")])
    }
}

// MARK: - AI activity (S04-003, S04-004, S04-005, S20-006)

struct AuditLaneBActivityTests {
    private func claudeAssistant(message: String, at time: String) -> [String: Any] {
        ["type": "assistant", "sessionId": "s1", "timestamp": time, "requestId": "r-" + message,
         "message": ["id": message, "usage": ["input_tokens": 100, "output_tokens": 30], "content": [] as [Any]]]
    }

    @Test func oversizedClaudeLogIsReadFromItsNewestRecords() throws {
        let home = laneBTemporary(); defer { try? FileManager.default.removeItem(at: home) }
        let padding: [String: Any] = ["type": "user", "sessionId": "s1", "timestamp": "2026-01-01T00:00:00Z",
                                      "message": ["content": String(repeating: "x", count: 1_000)]]
        try laneBWriteOversizedLog(head: [], padding: padding,
                                   tail: [claudeAssistant(message: "m1", at: "2026-09-24T09:00:00Z"),
                                          claudeAssistant(message: "m2", at: "2026-09-24T10:00:00Z")],
                                   to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: laneBNow, timeZone: laneBUTC, homeDirectory: home)
        #expect(snapshot.available)
        #expect(snapshot.totals.totalTokens == 260)
        // The skipped head is older than the range, so nothing in range was missed.
        #expect(!snapshot.partial)
    }

    @Test func oversizedCodexLogUsesItsFirstReadCounterAsABaseline() throws {
        let home = laneBTemporary(); defer { try? FileManager.default.removeItem(at: home) }
        let padding: [String: Any] = ["type": "response_item", "timestamp": "2026-01-01T00:00:00Z",
                                      "payload": ["type": "message", "text": String(repeating: "x", count: 1_000)]]
        let counters = [1_000, 1_300, 1_500].enumerated().map { index, total -> [String: Any] in
            ["type": "event_msg", "timestamp": "2026-09-24T0\(index + 7):00:00Z", "payload": [
                "type": "token_count", "info": ["total_token_usage": ["total_tokens": total, "input_tokens": total,
                                                                     "cached_input_tokens": 0, "output_tokens": 0]]]]
        }
        try laneBWriteOversizedLog(head: [["type": "session_meta", "payload": ["session_id": "sess-1"]]], padding: padding,
                                   tail: counters, to: home.appendingPathComponent(".codex/sessions/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .codex, range: .sevenDays, now: laneBNow, timeZone: laneBUTC, homeDirectory: home)
        // The first counter read after the skipped head is cumulative, so only the later increases are counted.
        #expect(snapshot.totals.totalTokens == 500)
        #expect(snapshot.totals.sessions == 1)
        // The session identity comes from the file's first line, so duplicates are still ruled out.
        #expect(!snapshot.possiblyOverstated)
        // The baseline reading's own increase is unknown, so the total is a lower bound.
        #expect(snapshot.partial)
    }

    @Test @MainActor func possiblyOverstatedTotalsAreMarkedAsApproximateNotAsALowerBound() throws {
        var snapshot = try #require(AIActivityPreviewData.item().widgetConfiguration?.aiActivitySnapshot)
        let plain = AIFacePresentation.activityValue(snapshot: snapshot)
        snapshot.possiblyOverstated = true
        #expect(AIFacePresentation.activityValue(snapshot: snapshot) == "~" + plain)
        #expect(snapshot.tokensText.hasPrefix("About "))
        snapshot.partial = true
        #expect(!AIFacePresentation.activityValue(snapshot: snapshot).hasSuffix("+"))
        let provenance = DataSourceProvenance.aiActivity(snapshot: snapshot, error: nil)
        #expect(provenance.summary(now: .now).contains("duplicates could not be ruled out"))
        var older = snapshot
        older.possiblyOverstated = false
        let encoded = try JSONEncoder().encode(older)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "possiblyOverstated")
        let decoded = try JSONDecoder().decode(AIActivitySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!decoded.possiblyOverstated)
    }

    @Test func timestampsParseWithAndWithoutFractionalSeconds() {
        #expect(ISO8601Timestamp.date("2026-09-24T10:00:00Z") == Date(timeIntervalSince1970: 1_790_244_000))
        let fractional = ISO8601Timestamp.date("2026-09-24T10:00:00.250Z")?.timeIntervalSince1970 ?? 0
        #expect(abs(fractional - 1_790_244_000.25) < 0.001)
        #expect(ISO8601Timestamp.date("2026-09-24") == nil)
        #expect(ISO8601Timestamp.date("not a date") == nil)
        #expect(ISO8601Timestamp.date(nil) == nil)
        #expect(ISO8601Timestamp.string(Date(timeIntervalSince1970: 1_790_244_000)) == "2026-09-24T10:00:00Z")
        let day = UTCDayFormat.date("2026-09-24")
        #expect(day == Date(timeIntervalSince1970: 1_790_208_000))
        #expect(day.map(UTCDayFormat.string) == "2026-09-24")
    }
}

// MARK: - Codex app-server (S04-006, S04-007)

struct AuditLaneBCodexTests {
    @Test func serverThatExitsBeforeReplyingIsReportedAsUnsupported() throws {
        let fixture = try laneBExecutable("#!/bin/sh\nexit 0\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        #expect(throws: AIUsageError.codexAppServerUnsupported) {
            _ = try CodexAccountRPC.request(executable: fixture.executable, method: "account/rateLimits/read", timeout: 3)
        }
    }

    @Test func missingMethodIsUnsupportedAndAnAuthenticationErrorStillAsksToSignIn() throws {
        func reply(_ error: String) throws -> (directory: URL, executable: URL) {
            try laneBExecutable("""
            #!/bin/sh
            IFS= read -r initialize || exit 3
            printf '{"id":1,"result":{"userAgent":"fixture"}}\\n'
            IFS= read -r initialized || exit 4
            IFS= read -r request || exit 5
            printf '{"id":2,"error":\(error)}\\n'
            IFS= read -r finish
            """)
        }
        let missing = try reply(#"{"code":-32601,"message":"Method not found"}"#)
        defer { try? FileManager.default.removeItem(at: missing.directory) }
        #expect(throws: AIUsageError.codexAppServerUnsupported) {
            _ = try CodexAccountRPC.request(executable: missing.executable, method: "account/rateLimits/read", timeout: 3)
        }
        let auth = try reply(#"{"code":-32000,"message":"codex account authentication required"}"#)
        defer { try? FileManager.default.removeItem(at: auth.directory) }
        #expect(throws: AIUsageError.codexAuthenticationUnavailable) {
            _ = try CodexAccountRPC.request(executable: auth.executable, method: "account/rateLimits/read", timeout: 3)
        }
    }

    @Test func cancellingABackgroundRequestStopsWaitingForTheServer() async throws {
        let fixture = try laneBExecutable("#!/bin/sh\nIFS= read -r initialize\nsleep 30\n")
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let started = Date.now
        let request = Task {
            try await CodexAccountRPC.requestInBackground(executable: fixture.executable, method: "account/read", timeout: 20)
        }
        request.cancel()
        await #expect(throws: CancellationError.self) { _ = try await request.value }
        #expect(Date.now.timeIntervalSince(started) < 10)
    }

    @Test func unsupportedCodexIsShownAsUnavailableRatherThanSetup() async {
        struct OutdatedCodex: AILimitProviderAdapter {
            let provider: AIProvider = .codex
            func read(now: Date) async throws -> AIProviderLimitReading { throw AIUsageError.codexAppServerUnsupported }
        }
        let snapshot = await AILimitsCollector.collect(providers: [.codex], now: laneBNow, adapters: [OutdatedCodex()])
        #expect(snapshot.reading(for: .codex)?.availability == .unavailable)
        #expect(snapshot.reading(for: .codex)?.message?.contains("Update Codex") == true)
    }

    @Test func slowReaderDoesNotHoldBackTheOthers() async {
        actor Probe {
            private var started = Set<AIProvider>()
            func markStarted(_ provider: AIProvider) { started.insert(provider) }
            func hasStarted(_ provider: AIProvider) -> Bool { started.contains(provider) }
        }
        struct SlowCodex: AILimitProviderAdapter {
            let probe: Probe
            let provider: AIProvider = .codex
            func read(now: Date) async throws -> AIProviderLimitReading {
                // Waits (with a deadline) until Claude has started, which only happens when readers run concurrently.
                let deadline = Date.now.addingTimeInterval(5)
                while !(await probe.hasStarted(.claude)), Date.now < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
                let sawClaude = await probe.hasStarted(.claude)
                return AIProviderLimitReading(provider: provider, availability: sawClaude ? .available : .error, windows: [])
            }
        }
        struct QuickClaude: AILimitProviderAdapter {
            let probe: Probe
            let provider: AIProvider = .claude
            func read(now: Date) async throws -> AIProviderLimitReading {
                await probe.markStarted(provider)
                return AIProviderLimitReading(provider: provider, availability: .available, windows: [])
            }
        }
        let probe = Probe()
        let snapshot = await AILimitsCollector.collect(providers: [.codex, .claude], now: laneBNow,
                                                       adapters: [SlowCodex(probe: probe), QuickClaude(probe: probe)])
        #expect(snapshot.readings.map(\.provider) == [.codex, .claude])
        #expect(snapshot.reading(for: .codex)?.availability == .available)
    }
}

// MARK: - Claude Code limits bridge (S04-008, S04-009)

struct AuditLaneBClaudeLimitsTests {
    private func makeDirectory() throws -> URL {
        let url = laneBTemporary().appendingPathComponent("claude config", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func settings(_ directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("settings.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func runBridge(in directory: URL, input: String) throws -> BoundedSubprocessOutput {
        let status = try #require(try settings(directory)["statusLine"] as? [String: Any])
        let command = try #require(status["command"] as? String)
        return try BoundedSubprocessCapture.run(executableURL: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", command],
                                                input: Data(input.utf8), maximumOutputBytes: 64_000, maximumErrorBytes: 16_000, timeout: 10)
    }

    @Test func turnOffRestoresTheWrappedStatusLineAndRemovesTheSnapshot() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        // JSON escapes the backslash: the command is printf 'it'\''s mine'.
        let original = #"{"theme":"dark","statusLine":{"type":"command","command":"printf 'it'\\''s mine'","padding":2}}"#
        try Data(original.utf8).write(to: directory.appendingPathComponent("settings.json"))
        try ClaudeLimitsSetup.enable(directory: directory)
        // A payload with JSON null elsewhere still yields a snapshot.
        let output = try runBridge(in: directory, input: #"{"rate_limits":{"five_hour":{"used_percentage":1,"resets_at":1900000000}},"x":null}"#)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "it's mine")
        let snapshot = directory.appendingPathComponent("mydock-rate-limits.json")
        #expect(try ClaudeStatusLineLimitParser.reading(from: Data(contentsOf: snapshot)).windows.first?.usedPercent == 1)

        try ClaudeLimitsSetup.disable(directory: directory)
        #expect(!ClaudeLimitsSetup.isEnabled(directory: directory))
        #expect(!FileManager.default.fileExists(atPath: snapshot.path))
        let restored = try settings(directory)
        #expect(restored["theme"] as? String == "dark")
        let status = try #require(restored["statusLine"] as? [String: Any])
        #expect(status["command"] as? String == "printf 'it'\\''s mine'")
        #expect(status["padding"] as? Int == 2)
    }

    @Test func aStatusLineMyDockAddedStaysEmptyAndIsRemovedOnTurnOff() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        try Data(#"{"theme":"light"}"#.utf8).write(to: directory.appendingPathComponent("settings.json"))
        try ClaudeLimitsSetup.enable(directory: directory)
        let output = try runBridge(in: directory, input: #"{"model":{"id":"fixture"}}"#)
        #expect(output.terminationStatus == 0)
        #expect(output.standardOutput.isEmpty)
        try ClaudeLimitsSetup.disable(directory: directory)
        let restored = try settings(directory)
        #expect(restored["statusLine"] == nil)
        #expect(restored["theme"] as? String == "light")
    }

    @Test func firstVersionBridgesAreReadAndUpgradedAroundTheCommandTheyWrap() throws {
        let wrapped = "/bin/sh -c " + AIAccountService.shellQuote("printf 'a'\nprintf 'b'") + " < \"$input\""
        let v1 = "# MyDock limits bridge v1\numask 077\nif limits=$(true); then\n  if [ -n \"$output\" ]; then\n    :\n  fi\nfi\n" + wrapped
        #expect(ClaudeLimitsSetup.wrappedStatusLine(in: v1) == .command("printf 'a'\nprintf 'b'"))
        let bare = "# MyDock limits bridge v1\nif true; then\n  :\nfi\nprintf 'Claude Code'"
        #expect(ClaudeLimitsSetup.wrappedStatusLine(in: bare) == ClaudeLimitsSetup.WrappedStatusLine.none)
        #expect(ClaudeLimitsSetup.wrappedStatusLine(in: "printf 'unrelated'") == nil)

        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory.deletingLastPathComponent()) }
        let settings = ["statusLine": ["type": "command", "command": v1]]
        try JSONSerialization.data(withJSONObject: settings).write(to: directory.appendingPathComponent("settings.json"))
        try ClaudeLimitsSetup.enable(directory: directory)
        let status = try #require(try self.settings(directory)["statusLine"] as? [String: Any])
        let upgraded = try #require(status["command"] as? String)
        #expect(upgraded.hasPrefix(ClaudeLimitsSetup.marker))
        #expect(ClaudeLimitsSetup.wrappedStatusLine(in: upgraded) == .command("printf 'a'\nprintf 'b'"))
    }
}

// MARK: - CLI discovery (S04-010)

struct AuditLaneBDiscoveryTests {
    @Test func versionManagerAndInstallerLocationsAreSearchedNewestNodeFirst() throws {
        let home = laneBTemporary(); defer { try? FileManager.default.removeItem(at: home) }
        for version in ["v9.0.0", "v22.1.0"] {
            let bin = home.appendingPathComponent(".nvm/versions/node/\(version)/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try Data("#!/bin/sh\n".utf8).write(to: bin.appendingPathComponent("claude"))
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bin.appendingPathComponent("claude").path)
        }
        let claude = AIAccountService.candidates(for: .claude, home: home, environment: [:]).map(\.path)
        let newest = try #require(claude.firstIndex(of: home.appendingPathComponent(".nvm/versions/node/v22.1.0/bin/claude").path))
        let oldest = try #require(claude.firstIndex(of: home.appendingPathComponent(".nvm/versions/node/v9.0.0/bin/claude").path))
        #expect(newest < oldest)
        #expect(claude.contains(home.appendingPathComponent(".claude/local/claude").path))
        #expect(claude.contains(home.appendingPathComponent(".volta/bin/claude").path))
        #expect(claude.contains(home.appendingPathComponent(".bun/bin/claude").path))
        #expect(claude.contains(home.appendingPathComponent("Library/pnpm/claude").path))
        let codex = AIAccountService.candidates(for: .codex, home: home, environment: [:]).map(\.path)
        #expect(!codex.contains(home.appendingPathComponent(".claude/local/codex").path))
        #expect(AIAccountService.executable(for: .claude, home: home, environment: [:]) != nil)
    }
}

// MARK: - Alarms (S04-011)

@MainActor
private final class LaneBAlarmClient: AlarmNotificationClient {
    var pending: [String] = []
    var added: [UNNotificationRequest] = []
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async throws -> Bool { true }
    func add(_ request: UNNotificationRequest) async throws { added.append(request); pending.append(request.identifier) }
    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { [] }
    func removePending(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0) } }
    func removeDelivered(_ identifiers: [String]) {}
}

struct AuditLaneBAlarmTests {
    @Test @MainActor func everyDayAlarmUsesOneDailyRequest() async throws {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Daily", hour: 7, minute: 30, repeatWeekdays: [1, 2, 3, 4, 5, 6, 7], isEnabled: true)
        let client = LaneBAlarmClient()
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
        #expect(client.added.count == 1)
        let trigger = try #require(client.added.first?.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats && trigger.dateComponents.weekday == nil)
        #expect(trigger.dateComponents.hour == 7 && trigger.dateComponents.minute == 30)
        #expect(client.pending == [AlarmNotificationService.dailyID(widgetID: widget, alarmID: alarm.id, operationID: operation)])
        #expect(AlarmNotificationService.isScheduled(widgetID: widget, alarm: alarm, pending: Set(client.pending)))
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
        #expect(client.pending.isEmpty)
    }

    @Test @MainActor func everyDayAlarmScheduledPerWeekdayStillCountsAsScheduled() {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Daily", hour: 7, minute: 30, repeatWeekdays: [1, 2, 3, 4, 5, 6, 7], isEnabled: true)
        let weekdays = Set((1...7).map {
            AlarmNotificationService.repeatingID(widgetID: widget, alarmID: alarm.id, operationID: operation, weekday: $0)
        })
        #expect(AlarmNotificationService.isScheduled(widgetID: widget, alarm: alarm, pending: weekdays))
        var missingOne = weekdays
        missingOne.remove(AlarmNotificationService.repeatingID(widgetID: widget, alarmID: alarm.id, operationID: operation, weekday: 3))
        #expect(!AlarmNotificationService.isScheduled(widgetID: widget, alarm: alarm, pending: missingOne))
    }
}

// MARK: - Calendar selection (S18-009)

struct AuditLaneBCalendarTests {
    @Test func selectionNeverWidensToEveryCalendar() {
        #expect(CalendarSelectionPolicy.resolve(selected: [], available: ["a", "b"]) == .all)
        #expect(CalendarSelectionPolicy.resolve(selected: ["b", "gone"], available: ["a", "b"]) == .selected(["b"]))
        #expect(CalendarSelectionPolicy.resolve(selected: ["gone"], available: ["a", "b"]) == .unavailable)
        #expect(CalendarSelectionPolicy.resolve(selected: ["gone"], available: []) == .unavailable)
    }

    @Test func refreshTokenTakenBeforeASelectionChangeIsNotCurrent() {
        var configuration = WidgetConfiguration()
        configuration.selectedCalendarIDs = ["a"]
        let request = UUID()
        let token = CalendarRefreshToken(requestID: request, selectedIDs: ["a"],
                                         includeAllDay: configuration.calendarShowsAllDayEvents, layout: configuration.calendarLayout)
        #expect(token.isCurrent(latestRequestID: request, configuration: configuration))
        #expect(!token.isCurrent(latestRequestID: UUID(), configuration: configuration))
        #expect(!token.isCurrent(latestRequestID: request, configuration: nil))
        configuration.selectedCalendarIDs = ["a", "b"]
        #expect(!token.isCurrent(latestRequestID: request, configuration: configuration))
    }

    @Test func summaryNamesSelectedCalendarsAndCountsMissingOnes() {
        let calendars = [CalendarListSnapshot(id: "a", title: "Work"), CalendarListSnapshot(id: "b", title: "Home")]
        #expect(CalendarSelectionSummary.label(calendars: calendars, selectedIDs: []) == "All accessible calendars")
        #expect(CalendarSelectionSummary.label(calendars: calendars, selectedIDs: ["a", "b"]) == "Work, Home")
        #expect(CalendarSelectionSummary.label(calendars: calendars, selectedIDs: ["b", "gone"]) == "Home · 1 unavailable")
        #expect(CalendarSelectionSummary.label(calendars: calendars, selectedIDs: ["gone"]) == "Selected calendars · 1 unavailable")
    }
}

// MARK: - App folder identity (S20-007)

struct AuditLaneBAppFolderTests {
    @Test func identityFollowsTheURLAndEqualityIgnoresTheDerivedPath() throws {
        var application = AppFolderApplication(url: URL(fileURLWithPath: "/MyDockFixtures/A/Editor.app"))
        #expect(application.id == "/MyDockFixtures/A/Editor.app")
        application.url = URL(fileURLWithPath: "/MyDockFixtures/B/Editor.app")
        #expect(application.id == "/MyDockFixtures/B/Editor.app")
        let decoded = try JSONDecoder().decode(AppFolderApplication.self, from: JSONEncoder().encode(application))
        #expect(decoded == application && decoded.id == application.id)
        let keys = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(application)) as? [String: Any]).keys
        #expect(!keys.contains("id"))
    }
}
