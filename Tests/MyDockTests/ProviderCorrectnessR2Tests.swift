import Foundation
import Testing
@testable import MyDock

// Wave-2 R2: PR-04 / PR-15 provider correctness. Fixtures only; no network, no real home directory.

private func r2Temporary() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("r2-" + UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func r2WriteLines(_ rows: [[String: Any]], to url: URL, modified: String = "2026-09-24T10:30:00Z") throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var data = Data()
    for row in rows { data.append(try JSONSerialization.data(withJSONObject: row)); data.append(0x0A) }
    try data.write(to: url)
    try FileManager.default.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: modified)!], ofItemAtPath: url.path)
}

private let r2Now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
private let r2UTC = TimeZone(secondsFromGMT: 0)!

private func claudeRow(session: String = "s1", message: String?, request: String? = "req-1", at time: String = "2026-09-24T10:00:00Z",
                       input: Int = 100, output: Int = 30, content: [[String: Any]] = []) -> [String: Any] {
    var messageObject: [String: Any] = ["usage": ["input_tokens": input, "output_tokens": output], "content": content]
    if let message { messageObject["id"] = message }
    var row: [String: Any] = ["type": "assistant", "sessionId": session, "timestamp": time, "message": messageObject]
    if let request { row["requestId"] = request }
    return row
}

struct AIActivityDedupeTests {
    @Test func claudeMessageRepeatedAcrossRowsAndFilesCountsOnceButKeepsEachToolUse() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let projects = home.appendingPathComponent(".claude/projects/p", isDirectory: true)
        // One API message logged once per content block, then copied into a resumed file.
        let first = [claudeRow(message: "msg_1", content: [["type": "tool_use", "id": "toolu_1"]]),
                     claudeRow(message: "msg_1", content: [["type": "tool_use", "id": "toolu_2"]])]
        try r2WriteLines(first, to: projects.appendingPathComponent("a.jsonl"))
        try r2WriteLines(first, to: projects.appendingPathComponent("b.jsonl"))
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.totalTokens == 130)
        #expect(snapshot.totals.requests == 1)
        #expect(snapshot.totals.toolCalls == 2)
        #expect(snapshot.totals.sessions == 1)
        #expect(!snapshot.partial)
    }

    @Test func distinctMessagesWithEqualUsageAreNeverCollapsed() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let rows = [claudeRow(message: "msg_a", request: "req_a"), claudeRow(message: "msg_b", request: "req_b")]
        try r2WriteLines(rows, to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.totalTokens == 260)
        #expect(snapshot.totals.requests == 2)
        #expect(!snapshot.partial)
    }

    @Test func growingStreamingCountersAddOnlyTheIncrease() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let rows = [claudeRow(message: "msg_1", output: 10), claudeRow(message: "msg_1", output: 30)]
        try r2WriteLines(rows, to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.outputTokens == 30)
        #expect(snapshot.totals.totalTokens == 130)
        #expect(snapshot.totals.requests == 1)
    }

    @Test func rowsWithoutIdentityAreCountedButMarkedPartialWhenIdenticalRowsAppear() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let row = claudeRow(message: nil, request: nil)
        try r2WriteLines([row, row], to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.totalTokens == 260)
        #expect(snapshot.partial)
    }

    private func codexRows(session: String, totals: [Int]) -> [[String: Any]] {
        var rows: [[String: Any]] = [["type": "session_meta", "payload": ["session_id": session]]]
        for (index, total) in totals.enumerated() {
            rows.append(["type": "event_msg", "timestamp": "2026-09-24T1\(index):00:00Z", "payload": [
                "type": "token_count", "info": ["total_token_usage": ["total_tokens": total, "input_tokens": total, "cached_input_tokens": 0, "output_tokens": 0]]]])
        }
        return rows
    }

    @Test func codexCopiedAndResumedSessionFilesCountEachCumulativePointOnce() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex/sessions/2026/09/24", isDirectory: true)
        try r2WriteLines(codexRows(session: "sess", totals: [100, 130]), to: directory.appendingPathComponent("a.jsonl"))
        try r2WriteLines(codexRows(session: "sess", totals: [100, 130]), to: directory.appendingPathComponent("copy.jsonl"))
        try r2WriteLines(codexRows(session: "sess", totals: [100, 130, 150]), to: directory.appendingPathComponent("resumed.jsonl"))
        let snapshot = AIActivityReader.read(provider: .codex, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.totalTokens == 150)
        #expect(snapshot.totals.sessions == 1)
        #expect(!snapshot.partial)
    }

    @Test func codexDistinctSessionsWithEqualUsageAreBothCounted() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let directory = home.appendingPathComponent(".codex/sessions/2026/09/24", isDirectory: true)
        try r2WriteLines(codexRows(session: "one", totals: [130]), to: directory.appendingPathComponent("a.jsonl"))
        try r2WriteLines(codexRows(session: "two", totals: [130]), to: directory.appendingPathComponent("b.jsonl"))
        let snapshot = AIActivityReader.read(provider: .codex, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.totalTokens == 260)
        #expect(snapshot.totals.sessions == 2)
    }

    @Test func codexLogWithoutSessionIdentityIsMarkedPartial() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let rows = Array(codexRows(session: "x", totals: [100]).dropFirst())
        try r2WriteLines(rows, to: home.appendingPathComponent(".codex/sessions/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .codex, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.totalTokens == 100)
        #expect(snapshot.partial)
    }

    // MD-P10
    @Test func sessionTotalIsDistinctAcrossTheRangeWhileDailyPointsKeepDailyCounts() throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let rows = [claudeRow(session: "midnight", message: "m1", request: "r1", at: "2026-09-23T23:50:00Z"),
                    claudeRow(session: "midnight", message: "m2", request: "r2", at: "2026-09-24T00:10:00Z"),
                    claudeRow(session: "other", message: "m3", request: "r3", at: "2026-09-24T09:00:00Z")]
        try r2WriteLines(rows, to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(snapshot.totals.sessions == 2)
        #expect(snapshot.points.map(\.sessions).reduce(0, +) == 3)
        #expect(snapshot.points.last?.sessions == 2)
        #expect(snapshot.semanticVersion == AIActivitySnapshot.currentSemanticVersion)
    }

    @Test func oldCachedActivityTotalsAreMarkedForRecomputeAndReplaceSavedHistory() throws {
        let current = AIActivitySnapshot(provider: .codex, range: .sevenDays, fetchedAt: .now, sourceDescription: "x", available: true,
                                         estimated: false, partial: false, points: [],
                                         totals: AIActivityDailyPoint(date: .now, sessions: 2, toolCalls: 0, totalTokens: 1, cachedInputTokens: 0,
                                                                      inputTokens: 0, outputTokens: 0, requests: 0, reportedCostUSD: nil),
                                         sourceScope: AIUsageSourceScope.activity(provider: .codex, range: .sevenDays))
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        json["semanticVersion"] = nil
        let old = try JSONDecoder().decode(AIActivitySnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.semanticVersion == 1)
        #expect(!old.hasCurrentSemantics)
        #expect(current.hasCurrentSemantics)

        var configuration = WidgetConfiguration()
        configuration.aiActivityProvider = old.provider
        configuration.aiActivityRange = old.range
        configuration.aiActivitySnapshot = old
        var unreadable = current
        unreadable.available = false; unreadable.partial = true
        WidgetDataValue.activity(unreadable).apply(to: &configuration)
        #expect(configuration.aiActivitySnapshot?.hasCurrentSemantics == true)
        // A current-version saved snapshot is still preserved against an unreadable refresh.
        configuration.aiActivitySnapshot = current
        WidgetDataValue.activity(unreadable).apply(to: &configuration)
        #expect(configuration.aiActivitySnapshot?.available == true)
    }
}

// MD-P02
struct ClaudeConfigDirectoryTests {
    @Test func accountActivityAndLimitsBridgeShareOneConfiguredDirectory() async throws {
        let home = r2Temporary(); defer { try? FileManager.default.removeItem(at: home) }
        let custom = home.appendingPathComponent("custom-claude", isDirectory: true)
        let environment = ["CLAUDE_CONFIG_DIR": custom.path]
        #expect(AIAccountService.claudeDirectory(home: home, environment: environment).standardizedFileURL == custom.standardizedFileURL)
        #expect(AIAccountService.claudeDirectory(home: home, environment: [:]).lastPathComponent == ".claude")

        try r2WriteLines([claudeRow(message: "m1")], to: custom.appendingPathComponent("projects/p/a.jsonl"))
        try r2WriteLines([claudeRow(message: "other")], to: home.appendingPathComponent(".claude/projects/p/a.jsonl"))
        let activity = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC,
                                             homeDirectory: home, environment: environment)
        #expect(activity.totals.requests == 1)
        let defaultActivity = AIActivityReader.read(provider: .claude, range: .sevenDays, now: r2Now, timeZone: r2UTC, homeDirectory: home)
        #expect(defaultActivity.totals.requests == 1)

        let sample = #"{"updated_at":1800000000,"rate_limits":{"five_hour":{"used_percentage":40}}}"#
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        try Data(sample.utf8).write(to: custom.appendingPathComponent("mydock-rate-limits.json"))
        let reading = try await ClaudeStatusLineLimitAdapter(homeDirectory: home, environment: environment)
            .read(now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(reading.availability == .available)
        let missing = try await ClaudeStatusLineLimitAdapter(homeDirectory: home, environment: [:])
            .read(now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(missing.availability == .setupRequired)
    }
}

// MD-P03 / MD-P09
struct ConnectionIdentityTests {
    private func store(_ domain: String, id: String = UUID().uuidString) -> ShopifyConnectedStore {
        ShopifyConnectedStore(id: id, name: "S", domain: domain, timeZoneID: "UTC", currency: "USD", color: "green")
    }

    @Test func shopifySameStoreComparesNormalizedDomainNotLocalID() {
        #expect(ShopifyAPIProvider.isSameStore(store("acme.myshopify.com"), store("acme.myshopify.com")))
        #expect(ShopifyAPIProvider.isSameStore(store("https://ACME.myshopify.com/"), store("acme")))
        #expect(!ShopifyAPIProvider.isSameStore(store("acme.myshopify.com"), store("other.myshopify.com")))
        #expect(!ShopifyAPIProvider.isSameStore(store("not a domain"), store("not a domain")))
    }

    @Test func tenantPolicyClearsOnTenantChangeOrUnknownIdentityButNotSameTenantOrSameKey() {
        #expect(!ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: "acct_1", newIdentity: "acct_1", credentialsChanged: true))
        #expect(ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: "acct_1", newIdentity: "acct_2", credentialsChanged: true))
        #expect(ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: nil, newIdentity: "acct_2", credentialsChanged: true))
        #expect(ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: "acct_1", newIdentity: nil, credentialsChanged: true))
        #expect(ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: nil, newIdentity: nil, credentialsChanged: true))
        #expect(!ConnectionTenantPolicy.shouldClearSnapshots(oldIdentity: nil, newIdentity: nil, credentialsChanged: false))
    }

    @MainActor @Test func clearingPersistedSnapshotsKeepsAssignmentAndOtherConnections() throws {
        let directory = r2Temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        func snapshot(_ id: String) -> StripeSnapshot {
            StripeSnapshot(accountID: id, accountName: "N", fetchedAt: .now, period: .thirtyDays, periodStart: .now, periodEnd: .now,
                           currencies: [], unsupportedSubscriptionItems: 0)
        }
        var mine = DockItem.widget("Stripe")
        mine.widgetConfiguration?.stripeAccountID = "conn-1"; mine.widgetConfiguration?.stripeSnapshot = snapshot("conn-1")
        var other = DockItem.widget("Stripe")
        other.widgetConfiguration?.stripeAccountID = "conn-2"; other.widgetConfiguration?.stripeSnapshot = snapshot("conn-2")
        _ = try store.createProfile(DockProfile(name: "P", kind: .custom, items: [mine, other]))
        #expect(store.clearPersistedSnapshots(for: .stripe("conn-1")) == 1)
        let items = try #require(store.state.profiles.last.map { store.presentationProfile($0).items })
        #expect(items[0].widgetConfiguration?.stripeSnapshot == nil)
        #expect(items[0].widgetConfiguration?.stripeAccountID == "conn-1")
        #expect(items[1].widgetConfiguration?.stripeSnapshot != nil)
    }

    // MD-P06
    @Test func paddleSetupCopyRequiresMetricsRead() {
        #expect(PaddleAPIKeyStore.permissionSetupCopy.contains("metrics.read"))
        #expect(PaddleDataError.missingPermission.errorDescription?.contains("metrics.read") == true)
    }
}

// MD-P04
private actor ScriptedShopifyTransport: ShopifyDataTransport {
    private let bodies: [Data]
    private(set) var orderRequests = 0
    init(bodies: [Data]) { self.bodies = bodies }

    func response(for request: URLRequest) async throws -> ShopifyHTTPResponse {
        switch request.url?.path {
        case "/admin/oauth/access_token":
            return ShopifyHTTPResponse(statusCode: 200, data: Data(#"{"access_token":"t","expires_in":86399}"#.utf8))
        default:
            let index = min(orderRequests, bodies.count - 1)
            orderRequests += 1
            return ShopifyHTTPResponse(statusCode: 200, data: bodies[index])
        }
    }
}

private actor ThrottleWaitRecorder {
    private(set) var values: [Duration] = []
    func record(_ value: Duration) { values.append(value) }
}

private func shopifyNode(_ id: String, amount: String = "10.00") -> [String: Any] {
    ["id": id, "createdAt": "2026-09-24T11:00:00Z", "test": false,
     "currentTotalPriceSet": ["shopMoney": ["amount": amount, "currencyCode": "USD"]],
     "lineItems": ["nodes": [], "pageInfo": ["hasNextPage": false]], "customerJourneySummary": NSNull()]
}

private func shopifyPage(_ ids: [String], next: String?) -> [String: Any] {
    ["nodes": ids.map { shopifyNode($0) }, "pageInfo": ["hasNextPage": next != nil, "endCursor": next.map { $0 as Any } ?? NSNull()]]
}

struct ShopifyPaginationGuardTests {
    private var store: ShopifyConnectedStore { ShopifyConnectedStore(id: "s", name: "S", domain: "acme.myshopify.com", timeZoneID: "UTC", currency: "USD", color: "green") }
    private var credential: ShopifyCredential { ShopifyCredential(clientID: "c", clientSecret: "s", accessToken: "t", tokenExpiresAt: .distantFuture) }
    private var now: Date { ISO8601DateFormatter().date(from: "2026-09-24T16:00:00Z")! }

    private func run(_ pages: [[String: Any]], maximumPages: Int = 60) async throws -> ShopifySnapshot {
        let bodies = try pages.map { try JSONSerialization.data(withJSONObject: ["data": ["orders": $0]]) }
        let provider = ShopifyAPIProvider(transport: ScriptedShopifyTransport(bodies: bodies), pageSize: 2, maximumPages: maximumPages)
        return try await provider.snapshot(store: store, credential: credential, period: .today, now: now).snapshot
    }

    @Test func overlappingPagesCountEachOrderIDOnce() async throws {
        let snapshot = try await run([shopifyPage(["o1", "o2"], next: "c1"), shopifyPage(["o2", "o3"], next: nil)])
        #expect(snapshot.orderCount == 3)
        #expect(snapshot.orderValue == 30)
    }

    @Test func repeatedCursorFailsExplicitlyWithoutAPartialTotal() async throws {
        await #expect(throws: ShopifyDataError.incompletePagination) {
            _ = try await run([shopifyPage(["o1"], next: "c1"), shopifyPage([], next: "c1")])
        }
        await #expect(throws: ShopifyDataError.incompletePagination) {
            _ = try await run([shopifyPage(["o1"], next: "")])
        }
    }

    @Test func emptyAdvancingPagesStopAtThePageBudget() async throws {
        var pages = [shopifyPage(["o1"], next: "c0")]
        for index in 1..<20 { pages.append(shopifyPage([], next: "c\(index)")) }
        await #expect(throws: ShopifyDataError.incompletePagination) { _ = try await run(pages, maximumPages: 5) }
    }

    /// S03-001: totals and the costlier line items and visits are separate queries, each under Shopify's
    /// 1,000-point single-query limit.
    @Test func everyShopifyQueryStaysUnderTheSingleQueryCostLimit() {
        let provider = ShopifyAPIProvider()
        #expect(ShopifyAPIProvider.totalsQueryCost(pageSize: provider.pageSize) <= ShopifyAPIProvider.maximumQueryCost)
        #expect(ShopifyAPIProvider.detailQueryCost(pageSize: provider.detailPageSize) <= ShopifyAPIProvider.maximumQueryCost)
        #expect(!ShopifyAPIProvider.totalsQuery.contains("lineItems"))
        #expect(!ShopifyAPIProvider.totalsQuery.contains("customerJourneySummary"))
        #expect(ShopifyAPIProvider.detailQuery.contains("lineItems(first: \(ShopifyAPIProvider.detailLineItemLimit))"))
        #expect(ShopifyAPIProvider.detailQuery.contains("reverse: true"))
    }

    @Test func breakdownsCoverTheMostRecentOrdersAndSayHowMany() async throws {
        func light(_ id: String) -> [String: Any] {
            var node = shopifyNode(id)
            node["lineItems"] = nil
            node["customerJourneySummary"] = nil
            return node
        }
        let totals: [String: Any] = ["nodes": ["o1", "o2", "o3"].map(light), "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]
        var detailed = shopifyNode("o3")
        detailed["lineItems"] = ["nodes": [["name": "Mug", "currentQuantity": 2]], "pageInfo": ["hasNextPage": false]]
        let details: [String: Any] = ["nodes": [detailed, shopifyNode("o2")], "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]
        let snapshot = try await run([totals, details])
        #expect(snapshot.orderCount == 3 && snapshot.orderValue == 30)
        #expect(snapshot.breakdownSampleOrders == 2)
        #expect(snapshot.productBreakdown == [ShopifyBreakdownEntry(name: "Mug", units: 2, orders: 0)])
    }

    /// S03-006: Shopify throttles with HTTP 200 and a THROTTLED error; MyDock waits for the bucket, then reports
    /// rate limiting instead of a raw provider message.
    @Test func throttledQueriesWaitAndRetryThenReportRateLimiting() async throws {
        let throttled = try JSONSerialization.data(withJSONObject: [
            "errors": [["message": "Throttled", "extensions": ["code": "THROTTLED"]]],
            "extensions": ["cost": ["requestedQueryCost": 752,
                                    "throttleStatus": ["maximumAvailable": 1000, "currentlyAvailable": 2, "restoreRate": 50]]]])
        let page = try JSONSerialization.data(withJSONObject: ["data": ["orders": shopifyPage(["o1"], next: nil)]])
        let waits = ThrottleWaitRecorder()
        let provider = ShopifyAPIProvider(transport: ScriptedShopifyTransport(bodies: [throttled, page]), pageSize: 2,
                                          throttleWait: { await waits.record($0) })
        let snapshot = try await provider.snapshot(store: store, credential: credential, period: .today, now: now).snapshot
        #expect(snapshot.orderCount == 1)
        #expect(await waits.values == [.seconds(10)])
        let stubborn = ShopifyAPIProvider(transport: ScriptedShopifyTransport(bodies: [throttled]), pageSize: 2,
                                          maximumThrottleRetries: 1, throttleWait: { _ in })
        await #expect(throws: ShopifyDataError.rateLimited) {
            _ = try await stubborn.snapshot(store: store, credential: credential, period: .today, now: now)
        }
    }

    @Test func ordersWithoutAnIdentityAreRejectedBecauseTheyCannotBeDeduplicated() async throws {
        var node = shopifyNode("x"); node["id"] = nil
        await #expect(throws: ShopifyDataError.invalidResponse) {
            _ = try await run([["nodes": [node], "pageInfo": ["hasNextPage": false, "endCursor": NSNull()]]])
        }
    }
}

// MD-P05
private actor ScriptedStripeTransport: StripeDataTransport {
    var itemPages: [String]
    private(set) var itemRequests: [URLRequest] = []
    init(itemPages: [String]) { self.itemPages = itemPages }
    func response(for request: URLRequest) async throws -> StripeHTTPResponse {
        guard request.url?.path == "/v1/subscription_items" else { return StripeHTTPResponse(statusCode: 200, data: Data("{}".utf8)) }
        itemRequests.append(request)
        let index = min(itemRequests.count - 1, itemPages.count - 1)
        return StripeHTTPResponse(statusCode: 200, data: Data(itemPages[index].utf8))
    }
}

struct StripeNestedItemsTests {
    private func item(_ id: String, amount: Int = 1000) -> String {
        #"{"id":"\#(id)","quantity":1,"price":{"currency":"usd","unit_amount":\#(amount),"billing_scheme":"per_unit","recurring":{"interval":"month","interval_count":1,"usage_type":"licensed"}}}"#
    }

    private func subscription(items: [String], hasMore: Bool) throws -> [String: Any] {
        let json = #"{"id":"sub_1","status":"active","customer":"cus_1","items":{"has_more":\#(hasMore),"data":[\#(items.joined(separator: ","))]}}"#
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    private func parse(_ subscriptions: [[String: Any]]) throws -> StripeSnapshot {
        try StripeSnapshotParser.snapshot(accountID: "a", accountName: "A", balanceData: Data(#"{"available":[],"pending":[]}"#.utf8),
                                          transactionRows: [], subscriptionRows: subscriptions, period: .thirtyDays,
                                          interval: DateInterval(start: .now.addingTimeInterval(-100), end: .now))
    }

    @Test func partialEmbeddedItemListIsFlaggedUnsupportedInsteadOfUndercounting() throws {
        let snapshot = try parse([try subscription(items: [item("si_1")], hasMore: true)])
        #expect(snapshot.unsupportedSubscriptionItems >= 1)
        #expect(snapshot.metrics(for: "USD")?.mrrMinor ?? 0 == 0)
    }

    @Test func remainingItemsAreFetchedWithinBudgetAndTotalsAreComplete() async throws {
        let transport = ScriptedStripeTransport(itemPages: [
            "{\"has_more\":true,\"data\":[\(item("si_1")),\(item("si_2"))]}",
            "{\"has_more\":false,\"data\":[\(item("si_3"))]}"])
        let provider = StripeAPIProvider(transport: transport)
        let completed = try await provider.completingItems([try subscription(items: [item("si_1")], hasMore: true)], apiKey: "rk_test_x")
        let snapshot = try parse(completed)
        #expect(snapshot.unsupportedSubscriptionItems == 0)
        #expect(snapshot.metrics(for: "USD")?.mrrMinor == 3000)
        let requests = await transport.itemRequests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.query?.contains("subscription=sub_1") == true)
    }

    @Test func exhaustedExpansionBudgetLeavesTheSubscriptionPartial() async throws {
        let provider = StripeAPIProvider(transport: ScriptedStripeTransport(itemPages: []), maximumItemExpansions: 0)
        let completed = try await provider.completingItems([try subscription(items: [item("si_1")], hasMore: true)], apiKey: "rk_test_x")
        let snapshot = try parse(completed)
        #expect(snapshot.unsupportedSubscriptionItems >= 1)
    }
}

// MD-P07
struct NetworkCounterResetTests {
    @Test func resetIsNotMistakenForAThirtyTwoBitWrap() {
        #expect(NetworkRateCalculator.plausibleDelta(from: 1_000_000, to: 100) == nil)
        #expect(NetworkRateCalculator.plausibleDelta(from: UInt64(UInt32.max) - 5, to: 3) == 9)
        #expect(NetworkRateCalculator.plausibleDelta(from: 5_000_000_000, to: 10) == nil)
        #expect(NetworkRateCalculator.plausibleDelta(from: 100, to: 400) == 300)
        let before = NetworkCountersReading(uptime: 0, interfaces: [NetworkInterfaceCounters(name: "en0", receivedBytes: 1_000_000, sentBytes: 50, addresses: [])])
        let after = NetworkCountersReading(uptime: 4, interfaces: [NetworkInterfaceCounters(name: "en0", receivedBytes: 100, sentBytes: 90, addresses: [])])
        let rate = NetworkRateCalculator.rates(previous: before, current: after).first
        #expect(rate?.receivedBytesPerSecond == nil)
        #expect(rate?.sentBytesPerSecond == 10)
    }

    @Test func realWrapNearTheTopOfTheRangeStillProducesARate() {
        let near = UInt64(UInt32.max) - 1_000
        let before = NetworkCountersReading(uptime: 0, interfaces: [NetworkInterfaceCounters(name: "en0", receivedBytes: near, sentBytes: 0, addresses: [])])
        let after = NetworkCountersReading(uptime: 2, interfaces: [NetworkInterfaceCounters(name: "en0", receivedBytes: 1_000, sentBytes: 0, addresses: [])])
        #expect(NetworkRateCalculator.rates(previous: before, current: after).first?.receivedBytesPerSecond == 1_000.5)
    }
}

// MD-P08
private struct CountingBytes: AsyncSequence {
    typealias Element = UInt8
    final class Counter: @unchecked Sendable { var pulled = 0 }
    let counter: Counter
    let total: Int
    struct Iterator: AsyncIteratorProtocol {
        let counter: Counter
        var remaining: Int
        mutating func next() async -> UInt8? {
            guard remaining > 0 else { return nil }
            remaining -= 1; counter.pulled += 1
            return 0x41
        }
    }
    func makeAsyncIterator() -> Iterator { Iterator(counter: counter, remaining: total) }
}

struct BoundedTransferTests {
    @Test func transferStopsAsSoonAsTheLimitIsExceeded() async {
        let counter = CountingBytes.Counter()
        await #expect(throws: BoundedHTTPFetchError.tooLarge) {
            _ = try await BoundedHTTPFetch.collect(CountingBytes(counter: counter, total: 10_000_000), maximumBytes: 1_000)
        }
        #expect(counter.pulled <= 1_001)
    }

    @Test func declaredLengthOverTheLimitIsRejectedBeforeReadingAnyBody() async {
        let counter = CountingBytes.Counter()
        await #expect(throws: BoundedHTTPFetchError.tooLarge) {
            _ = try await BoundedHTTPFetch.collect(CountingBytes(counter: counter, total: 10), expectedLength: 9_999, maximumBytes: 1_000)
        }
        #expect(counter.pulled == 0)
    }

    @Test func bodiesAtOrUnderTheLimitAreReturnedWhole() async throws {
        let exact = try await BoundedHTTPFetch.collect(CountingBytes(counter: .init(), total: 1_000), expectedLength: 1_000, maximumBytes: 1_000)
        #expect(exact.count == 1_000)
        let unknownLength = try await BoundedHTTPFetch.collect(CountingBytes(counter: .init(), total: 10), maximumBytes: 1_000)
        #expect(unknownLength.count == 10)
    }
}
