import Foundation
import Testing
@testable import MyDock

// MD-A03 / MD-A04: cached and external numbers are bounded without discarding authored configuration.
struct CachedAIUsageDomainTests {
    private func configuration(percent: String, provider: String = "codex") throws -> WidgetConfiguration {
        let json = #"{"noteText":"authored note","aiLimitsSnapshot":{"fetchedAt":780000000,"readings":[{"provider":"\#(provider)","availability":"available","windows":[{"name":"5 hours","usedPercent":\#(percent),"resetsAt":780003600,"durationMinutes":300}],"updatedAt":780000000}]}}"#
        return try JSONDecoder().decode(WidgetConfiguration.self, from: Data(json.utf8))
    }

    private func percent(_ configuration: WidgetConfiguration) -> Int?? {
        configuration.aiLimitsSnapshot?.readings.first?.windows.first.map(\.usedPercent)
    }

    @Test func extremeAndNegativePercentagesBecomeUnavailableAndKeepAuthoredConfiguration() throws {
        for value in ["-9223372036854775808", "9223372036854775807", "-1", "101", "1000000"] {
            let decoded = try configuration(percent: value)
            #expect(decoded.noteText == "authored note")
            #expect(percent(decoded) == .some(nil), "\(value)")
            #expect(decoded.aiLimitsSnapshot?.readings.first?.windows.first?.remainingPercent == nil)
            #expect(decoded.aiLimitsSnapshot?.isValid == true)
        }
        #expect(AILimitWindow(name: "x", usedPercent: Int.min, resetsAt: nil, durationMinutes: nil).remainingPercent == nil)
        #expect(AILimitWindow(name: "x", usedPercent: Int.max, resetsAt: nil, durationMinutes: nil).remainingPercent == 0)
    }

    @Test func overageProvidersMayExceedOneHundredPercentButFixedWindowsMayNot() throws {
        #expect(percent(try configuration(percent: "125", provider: "claude")) == .some(125))
        #expect(percent(try configuration(percent: "125", provider: "grok")) == .some(nil))
        #expect(percent(try configuration(percent: "150", provider: "copilot")) == .some(150))
        #expect(percent(try configuration(percent: "150", provider: "codex")) == .some(nil))
        #expect(percent(try configuration(percent: "100001", provider: "copilot")) == .some(nil))
    }

    @Test func oldValidCachesStillDecodeUnchanged() throws {
        for value in ["0", "37", "100"] {
            let decoded = try configuration(percent: value)
            #expect(percent(decoded) == .some(Int(value)))
        }
        let decoded = try configuration(percent: "40")
        let window = try #require(decoded.aiLimitsSnapshot?.readings.first?.windows.first)
        #expect(window.durationMinutes == 300 && window.resetsAt != nil)
    }

    @Test func absurdDatesAndDurationsAreDroppedNotFatal() throws {
        let json = #"{"fetchedAt":1e300,"readings":[{"provider":"claude","availability":"available","windows":[{"name":"w","usedPercent":10,"resetsAt":1e300,"durationMinutes":-5}],"updatedAt":1e300}]}"#
        let snapshot = try JSONDecoder().decode(AILimitsSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.isValid)
        let window = try #require(snapshot.readings.first?.windows.first)
        #expect(window.usedPercent == 10 && window.resetsAt == nil && window.durationMinutes == nil)
    }

    @Test func activityCacheDropsAbsurdPointsAndClampsTotals() throws {
        let point = { (tokens: String) in #"{"date":780000000,"sessions":1,"toolCalls":0,"totalTokens":\#(tokens),"cachedInputTokens":0,"inputTokens":0,"outputTokens":0,"requests":1}"# }
        let json = #"{"provider":"codex","range":"sevenDays","fetchedAt":780000000,"sourceDescription":"x","available":true,"estimated":false,"partial":false,"points":[\#(point("5")),\#(point("9223372036854775807")),\#(point("-4"))],"totals":\#(point("-9223372036854775808"))}"#
        let snapshot = try JSONDecoder().decode(AIActivitySnapshot.self, from: Data(json.utf8))
        #expect(snapshot.points.count == 1 && snapshot.points[0].totalTokens == 5)
        #expect(snapshot.totals.totalTokens == 0)
        #expect(snapshot.isValid)
    }

    @Test func semanticValidatorRejectsUnsanitizedInMemorySnapshots() {
        var config = WidgetConfiguration()
        config.aiLimitsSnapshot = AILimitsSnapshot(fetchedAt: .now, readings: [
            AIProviderLimitReading(provider: .codex, availability: .available, windows:
                [AILimitWindow(name: "w", usedPercent: Int.min, resetsAt: nil, durationMinutes: nil)])])
        #expect(throws: ProfileValidationError.self) { try ProfileSemanticValidator.validate(config) }
    }
}

struct ProviderNumericBoundsTests {
    @Test func marketVolumeOutsideDomainRejectsTheResponse() throws {
        func payload(close: String, volume: String) -> Data {
            Data(#"{"Time Series (Daily)":{"2026-09-22":{"4. close":"\#(close)","5. volume":"\#(volume)"}}}"#.utf8)
        }
        _ = try MarketDataParser.dailySnapshot(from: payload(close: "10.5", volume: "1250000"), expectedSymbol: "AAPL")
        for (close, volume) in [("10", "1e30"), ("10", "nan"), ("10", "inf"), ("10", "-5"), ("1e30", "5"), ("nan", "5")] {
            #expect(throws: MarketDataError.self) {
                try MarketDataParser.dailySnapshot(from: payload(close: close, volume: volume), expectedSymbol: "AAPL")
            }
        }
    }

    @Test func stripeIntervalAndQuantityOverflowIsUnsupportedNotATrap() throws {
        let balance = Data(#"{"available":[],"pending":[]}"#.utf8)
        func rows(count: String, quantity: String = "1", amount: String = "1000") throws -> [[String: Any]] {
            let json = #"{"data":[{"status":"active","customer":"cus","items":{"data":[{"quantity":\#(quantity),"price":{"currency":"usd","unit_amount":\#(amount),"billing_scheme":"per_unit","recurring":{"interval":"year","interval_count":\#(count),"usage_type":"licensed"}}}]}}]}"#
            return try (JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        }
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 100))
        func parse(_ subscriptions: [[String: Any]]) throws -> StripeSnapshot {
            try StripeSnapshotParser.snapshot(accountID: "a", accountName: "n", balanceData: balance, transactionRows: [],
                                              subscriptionRows: subscriptions, period: .thirtyDays, interval: interval, now: .now)
        }
        let normal = try parse(try rows(count: "1"))
        #expect(normal.unsupportedSubscriptionItems == 0)
        #expect(normal.metrics(for: "USD")?.mrrMinor == Decimal(string: "83.33333333333333333333333333333333333")!)
        for (count, quantity, amount) in [("1e30", "1", "1000"), ("9223372036854775807", "1", "1000"), ("1", "1e30", "1000"),
                                          ("1", "1", "1e30"), ("0", "1", "1000"), ("-4", "1", "1000")] {
            let snapshot = try parse(try rows(count: count, quantity: quantity, amount: amount))
            #expect(snapshot.unsupportedSubscriptionItems == 1, "\(count) \(quantity) \(amount)")
            #expect((snapshot.metrics(for: "USD")?.mrrMinor ?? 0) == 0)
        }
    }

    @Test func paddleCountsAndAmountsOutsideDomainRejectTheResponse() throws {
        func fixture(currency: String? = nil, _ values: String) -> Data {
            let field = currency.map { "\"currency_code\":\"\($0)\"," } ?? ""
            return Data("{\"data\":{\(field)\"updated_at\":\"2026-09-24T23:00:00Z\",\"timeseries\":\(values)}}".utf8)
        }
        func parse(count: String, amount: String = "100") throws -> PaddleSnapshot {
            try PaddleMetricsParser.snapshot(
                revenueData: fixture(currency: "USD", #"[{"timestamp":"2026-09-23T00:00:00Z","amount":"\#(amount)"}]"#),
                mrrData: fixture(currency: "USD", #"[{"timestamp":"2026-09-23T00:00:00Z","amount":"100"}]"#),
                subscriberData: fixture(#"[{"timestamp":"2026-09-23T00:00:00Z","count":\#(count)}]"#),
                accountID: "a", accountName: "n", period: .sevenDays)
        }
        #expect(try parse(count: "7").latestActiveSubscribers == 7)
        for count in ["1e30", "9223372036854775807", "-1", "\"inf\"", "\"nan\""] {
            #expect(throws: PaddleDataError.self) { try parse(count: count) }
        }
        #expect(throws: PaddleDataError.self) { try parse(count: "1", amount: "1e30") }
    }

    @Test func weatherEnormousFiniteReadingsAreMalformedAtServiceLevel() throws {
        let location = WeatherLocation(id: "c", name: "Warsaw", administrativeArea: nil, country: "Poland",
                                       latitude: 52, longitude: 21, timeZoneIdentifier: "Europe/Warsaw")
        func payload(current: String = "18", hourly: String = "18", wind: String = "4") -> Data {
            Data(#"{"current":{"temperature_2m":\#(current),"relative_humidity_2m":50,"apparent_temperature":18,"precipitation":0,"weather_code":1,"is_day":1,"wind_speed_10m":\#(wind)},"hourly":{"time":[1727193600],"temperature_2m":[\#(hourly)],"weather_code":[1]}}"#.utf8)
        }
        _ = try OpenMeteoWeatherProvider.decodeForecast(payload(), location: location)
        for data in [payload(current: "1e30"), payload(current: "-1e308"), payload(hourly: "1e30"), payload(wind: "1e30")] {
            #expect(throws: WeatherServiceError.self) { try OpenMeteoWeatherProvider.decodeForecast(data, location: location) }
        }
    }
}

// Draft recovery and pruning (MD-A05 / MD-A06).
@MainActor
struct DraftRecoveryAndPruningTests {
    private func temporary() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Wave1-\(UUID().uuidString)", isDirectory: true)
    }

    private func recoveryFiles(beside file: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: file.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(file.lastPathComponent + ".recovery-") }
    }

    @Test func unreadableUtilityDraftsAreSetAsideAndQuitIsNotBlocked() throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("utility-drafts/drafts.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("not json".utf8)
        try garbage.write(to: file)
        let store = DockUtilityDraftStore(fileURL: file)
        #expect(store.recoveryNotice != nil)
        #expect(store.flush())
        let moved = try recoveryFiles(beside: file)
        #expect(moved.count == 1)
        #expect(try Data(contentsOf: moved[0]) == garbage)
        let draft = DockUtilityFormDraft(editingID: nil, title: "t", body: "b")
        try store.update(draft, itemID: UUID(), in: UUID(), kind: .snippet)
        #expect(store.flush())
    }

    @Test func oversizedUtilityDraftsAreSetAsideToo() throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("utility-drafts/drafts.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: 2 * 1_024 * 1_024 + 1).write(to: file)
        let store = DockUtilityDraftStore(fileURL: file)
        #expect(store.recoveryNotice != nil && store.flush())
        #expect(try recoveryFiles(beside: file).count == 1)
    }

    @Test func profileStoreSurfacesTheNoticeOnce() throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let drafts = directory.appendingPathComponent("utility-drafts/drafts.json")
        try FileManager.default.createDirectory(at: drafts.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: drafts)
        let state = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: state, allowsSystemChanges: false)
        #expect(store.persistenceWarning?.contains("utility drafts") == true)
        store.dismissPersistenceNotice()
        #expect(store.persistenceWarning == nil)
        #expect(ProfileStore(fileURL: state, allowsSystemChanges: false).persistenceWarning == nil)
    }

    @Test func removalAndLoadPruneUtilityAndNoteDrafts() throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let snippets = DockItem.widget("Text Snippets"), links = DockItem.widget("Quick Links"), note = DockItem.widget("Sticky Note")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let profileID = try store.createProfile(DockProfile(name: "A", kind: .custom, items: [snippets, links, note]))
        let otherID = try store.createProfile(DockProfile(name: "B", kind: .custom, items: [.widget("Text Snippets")]))
        let other = try #require(store.state.profiles.first { $0.id == otherID }?.items.first)
        let draft = DockUtilityFormDraft(editingID: nil, title: "t", body: "unfinished")
        try store.utilityDrafts.update(draft, itemID: snippets.id, in: profileID, kind: .snippet)
        try store.utilityDrafts.update(draft, itemID: links.id, in: profileID, kind: .link)
        try store.utilityDrafts.update(draft, itemID: other.id, in: otherID, kind: .snippet)
        #expect(store.utilityDrafts.flush())
        WidgetSetupDraftStore.shared.updateNoteDraft("pending", for: note.id, in: profileID)

        store.removeItem(snippets.id, from: profileID)
        #expect(store.utilityDrafts.draft(itemID: snippets.id, in: profileID, kind: .snippet) == nil)
        #expect(store.utilityDrafts.draft(itemID: links.id, in: profileID, kind: .link) == draft)
        store.removeItem(note.id, from: profileID)
        #expect(WidgetSetupDraftStore.shared.noteDraft(for: note.id, in: profileID) == nil)
        store.deleteProfile(profileID)
        #expect(store.utilityDrafts.draft(itemID: links.id, in: profileID, kind: .link) == nil)
        #expect(store.utilityDrafts.draft(itemID: other.id, in: otherID, kind: .snippet) == draft)

        // Orphans written while the app was not running are pruned at the next launch.
        let orphan = UUID()
        try store.utilityDrafts.update(draft, itemID: orphan, in: otherID, kind: .snippet)
        #expect(store.utilityDrafts.flush())
        let reopened = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(reopened.utilityDrafts.draft(itemID: orphan, in: otherID, kind: .snippet) == nil)
        #expect(reopened.utilityDrafts.draft(itemID: other.id, in: otherID, kind: .snippet) == draft)
    }

    @Test func protectedStateNeverPrunesDrafts() throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var future = PersistentState(); future.schemaVersion = Product.stateSchemaVersion + 1
        try JSONEncoder().encode(future).write(to: file)
        let seed = DockUtilityDraftStore(fileURL: directory.appendingPathComponent("utility-drafts/drafts.json"))
        let itemID = UUID(), profileID = UUID()
        let draft = DockUtilityFormDraft(editingID: nil, title: "t", body: "keep")
        try seed.update(draft, itemID: itemID, in: profileID, kind: .snippet)
        #expect(seed.flush())
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(store.utilityDrafts.draft(itemID: itemID, in: profileID, kind: .snippet) == draft)
    }

    @Test func aDeletedWidgetsNoteDraftNeverBlocksTheQuitFlush() throws {
        let directory = temporary(); defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let kept = DockItem.widget("Sticky Note")
        let profileID = try store.createProfile(DockProfile(name: "N", kind: .custom, items: [kept]))
        let drafts = WidgetSetupDraftStore()
        drafts.updateNoteDraft("orphaned", for: UUID(), in: profileID)
        drafts.updateNoteDraft("still valid", for: kept.id, in: profileID)
        try drafts.flushNotes(to: store).get()
        #expect(!drafts.hasPendingNotes)
        #expect(store.state.profiles.first?.items.first?.widgetConfiguration?.noteText == "still valid")
    }
}

// MD-Q01 / PR-05 additions.
@MainActor
struct IsolatedGlobalServiceTests {
    @Test func localAIAccountReadersDoNotTouchTheRealAccountWhenIsolated() async throws {
        #expect(AppRuntimeEnvironment.isIsolated)
        let activity = AIActivityReader.read(provider: .codex, range: .sevenDays)
        #expect(!activity.available)
        let snapshot = await AILimitsCollector.collect(providers: [.codex, .claude, .copilot])
        #expect(snapshot.readings.allSatisfy { reading in reading.windows.allSatisfy { $0.usedPercent == nil } })
        await #expect(throws: ValidationBoundaryError.self) { try await CodexLimitAdapter().read(now: .now) }
        await #expect(throws: ValidationBoundaryError.self) { try await ClaudeStatusLineLimitAdapter().read(now: .now) }
        #expect(AIAccountService.detect(.codex).state == .unavailable)
    }

    @Test func everyCredentialFacadeRefusesWritesAndDeletesWhenIsolated() {
        #expect(throws: ValidationBoundaryError.self) { try StripeAPIKeyStore.write("rk_fixture", accountID: "acct") }
        #expect(throws: ValidationBoundaryError.self) { try StripeAPIKeyStore.delete(accountID: "acct") }
        #expect(throws: ValidationBoundaryError.self) { try PaddleAPIKeyStore.write("fixture", accountID: "acct") }
        #expect(throws: ValidationBoundaryError.self) { try PaddleAPIKeyStore.delete(accountID: "acct") }
        #expect(throws: ValidationBoundaryError.self) { try GitHubCopilotCredentialStore.write(username: "u", token: "fixture") }
        #expect(throws: ValidationBoundaryError.self) { try GitHubCopilotCredentialStore.delete() }
        #expect(throws: ValidationBoundaryError.self) { try ShopifyCredentialStore.delete(storeID: "store") }
    }
}
