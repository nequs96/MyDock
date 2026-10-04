import Combine
import Foundation
import Testing
@testable import MyDock

/// PR-13's incremental in-memory boundary, using private fixtures and injected provider responses only.
@MainActor
struct ReliabilityPhaseTwoTests {
    private enum CacheFailure: Error { case unavailable }
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-PhaseTwo-\(UUID().uuidString)")
    }

    private func quote(_ symbol: String = "AAPL", close: Double = 12, at date: Date = .now) -> StockMarketSnapshot {
        StockMarketSnapshot(symbol: symbol, points: [.init(date: date, close: close, volume: 1)], currency: "USD", fetchedAt: date)
    }

    private func activity(provider: AIProvider = .codex, range: AIActivityRange = .today,
                          at date: Date, version: Int = AIActivitySnapshot.currentSemanticVersion) -> AIActivitySnapshot {
        AIActivitySnapshot(provider: provider, range: range, fetchedAt: date, sourceDescription: "Fixture logs",
            available: true, estimated: false, partial: false, points: [],
            totals: .init(date: date, sessions: 1, toolCalls: 0, totalTokens: 1, cachedInputTokens: 0,
                          inputTokens: 0, outputTokens: 0, requests: 0, reportedCostUSD: nil), semanticVersion: version,
            sourceScope: AIUsageSourceScope.activity(provider: provider, range: range, semanticVersion: version))
    }

    @Test func refreshLeavesAuthoredMemoryDraftUndoAndHistoryUnchanged() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("Stock")
        item.widgetConfiguration?.stockSymbol = "AAPL"
        let id = try store.createProfile(.init(name: "P", kind: .custom, items: [item]))
        let original = try #require(store.state.profiles.first)
        var draft = DockProfileDraft(profile: original)
        draft.update { $0.items.removeAll() }
        store.editSessions.load(original)
        let historyCount = store.history.entries.count
        var authoredPublications = 0, cachePublications = 0
        let authoredObservation = store.$state.dropFirst().sink { _ in authoredPublications += 1 }
        let cacheObservation = store.runtimeCache.$entries.dropFirst().sink { _ in cachePublications += 1 }
        let loaded = quote()
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in .stock(loaded) }
        await coordinator.refresh(item: item, profileID: id)

        #expect(store.state.profiles.first == original)
        #expect(authoredPublications == 0 && cachePublications == 1)
        #expect(store.state.profiles[0].items[0].widgetConfiguration?.stockSnapshot == nil)
        #expect(store.presentationItem(item).widgetConfiguration?.stockSnapshot == loaded)
        #expect(!store.editSessions.hasUnsavedChanges)
        #expect(store.history.entries.count == historyCount)
        // Removing an item in a pre-refresh draft remains a clean merge; inverse undo remains authored.
        let removed = try draft.merged(with: store.state.profiles[0])
        #expect(removed.items.isEmpty)
        var inverse = DockProfileDraft(profile: removed)
        inverse.update { $0 = original }
        #expect(try inverse.merged(with: removed) == original)
        withExtendedLifetime((authoredObservation, cacheObservation)) {}
    }

    @Test func changingQueryCannotRetagLastGoodReadingAndOldDraftCannotOverwriteNewCache() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("Stock")
        item.widgetConfiguration?.stockSymbol = "AAPL"
        let id = try store.createProfile(.init(name: "P", kind: .custom, items: [item]))
        let earlier = quote(close: 1, at: Date(timeIntervalSince1970: 1_000))
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.stockSnapshot = earlier }
        var draft = DockProfileDraft(profile: store.presentationProfile(store.state.profiles[0]))
        draft.update { $0.name = "Renamed" }
        let latest = quote(close: 2, at: Date(timeIntervalSince1970: 2_000))
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.stockSnapshot = latest }
        store.replaceProfile(try draft.merged(with: store.state.profiles[0]))
        #expect(store.presentationItem(item).widgetConfiguration?.stockSnapshot == latest)
        #expect(store.state.profiles[0].items[0].widgetConfiguration?.stockSnapshot == nil)
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.stockSymbol = "MSFT" }
        let live = store.state.profiles[0].items[0]
        #expect(store.presentationItem(live).widgetConfiguration?.stockSnapshot == nil)
        #expect(store.runtimeCache.readings(for: item.id)?.stock == nil)
    }

    @Test func weatherRefreshAndSetupChangeStaySeparatedAcrossRelaunch() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let item = DockItem.widget("Weather")
        let id = try store.createProfile(.init(name: "P", kind: .custom, items: [item]))
        let forecast = WeatherForecast(temperature: 15, apparentTemperature: 15, relativeHumidity: 40,
            precipitation: 0, windSpeed: 3, weatherCode: 1, isDay: true, fetchedAt: Date(timeIntervalSince1970: 1_000),
            timeZoneIdentifier: "UTC", hourly: [])
        let original = store.state
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.cachedWeatherForecast = forecast }
        #expect(store.state == original)
        #expect(store.presentationConfiguration(for: item, in: id).cachedWeatherForecast == forecast)
        store.flush()
        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(relaunched.state.profiles[0].items[0].widgetConfiguration?.cachedWeatherForecast == nil)
        #expect(relaunched.presentationConfiguration(for: item, in: id).cachedWeatherForecast == forecast)
        relaunched.updateWidgetConfiguration(itemID: item.id, in: id) {
            $0.weatherUnit = $0.weatherUnit == .celsius ? .fahrenheit : .celsius
        }
        #expect(relaunched.presentationConfiguration(for: item, in: id).cachedWeatherForecast == nil)
    }

    @Test func stripeRefreshKeepsAuthoredCurrencyAndTenantClearDoesNotPublishState() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("Stripe")
        item.widgetConfiguration?.stripeAccountID = "acct"
        item.widgetConfiguration?.stripeCurrency = "EUR"
        let id = try store.createProfile(.init(name: "P", kind: .custom, items: [item]))
        let original = store.state
        let date = Date(timeIntervalSince1970: 1_000)
        let loaded = StripeSnapshot(accountID: "acct", accountName: "N", fetchedAt: date, period: .thirtyDays,
            periodStart: date, periodEnd: date, currencies: [], unsupportedSubscriptionItems: 0)
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in .stripe(loaded) }
        await coordinator.refresh(item: item, profileID: id)
        #expect(store.state == original)
        #expect(store.presentationConfiguration(for: item, in: id).stripeCurrency == "EUR")
        #expect(store.clearPersistedSnapshots(for: .stripe("acct")) == 1)
        #expect(store.state == original)
        #expect(store.runtimeCache.readings(for: item.id)?.stripe == nil)
    }

    @Test func aiReadingsRemainCacheOnlyAndLastGoodSurvivesOfflineAndUnreadableRefresh() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let item = DockItem.widget("AI Activity"), limits = DockItem.widget("AI Limits")
        let id = try store.createProfile(.init(name: "AI", kind: .custom, items: [item, limits]))
        let original = store.state
        let date = Date(timeIntervalSince1970: 2_000)
        let good = activity(at: date)
        store.editSessions.load(store.state.profiles[0])
        let historyCount = store.history.entries.count
        let coordinator = WidgetDataCoordinator(store: store) { query, configuration in
            if query.kind == "AI Limits" { return .limits(.init(fetchedAt: date, readings: [],
                sourceScope: AIUsageSourceScope.limits(providers: configuration.aiLimitsVisibleProviders))) }
            return .activity(good)
        }
        await coordinator.refresh(item: item, profileID: id)
        await coordinator.refresh(item: limits, profileID: id)
        #expect(store.state == original)
        #expect(!store.editSessions.hasUnsavedChanges && store.history.entries.count == historyCount)
        #expect(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot == good)
        #expect(store.presentationConfiguration(for: limits, in: id).aiLimitsSnapshot?.fetchedAt == date)
        var unreadable = good
        unreadable.available = false; unreadable.partial = true; unreadable.fetchedAt = date.addingTimeInterval(60)
        let failedScan = WidgetDataCoordinator(store: store) { _, _ in .activity(unreadable) }
        await failedScan.refresh(item: item, profileID: id)
        #expect(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot == good)
        store.flush()
        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let offline = WidgetDataCoordinator(store: relaunched) { _, _ in throw MarketDataError.invalidResponse }
        await offline.refresh(item: item, profileID: id)
        #expect(relaunched.state.profiles[0].items.allSatisfy { $0.widgetConfiguration?.runtimeReadings.isEmpty == true })
        #expect(relaunched.presentationConfiguration(for: item, in: id).aiActivitySnapshot == good)
        #expect(relaunched.presentationConfiguration(for: item, in: id).aiActivitySnapshot?.semanticVersion == good.semanticVersion)
    }

    @Test func aiQueryChangesInvalidateAndMismatchedResponseCannotBeRetagged() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let item = DockItem.widget("AI Activity"), limits = DockItem.widget("AI Limits")
        let id = try store.createProfile(.init(name: "AI", kind: .custom, items: [item, limits]))
        let good = activity(at: Date(timeIntervalSince1970: 2_000))
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.aiActivitySnapshot = good }
        store.updateWidgetConfiguration(itemID: limits.id, in: id) { $0.aiLimitsSnapshot = .init(fetchedAt: good.fetchedAt, readings: []) }
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.aiActivityProvider = .claude; $0.aiActivityRange = .sevenDays }
        store.updateWidgetConfiguration(itemID: limits.id, in: id) { $0.aiCopilotMonthlyCreditAllowance = 10 }
        #expect(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot == nil)
        #expect(store.presentationConfiguration(for: limits, in: id).aiLimitsSnapshot == nil)
        let current = store.state.profiles[0].items[0]
        let wrongQuery = WidgetDataCoordinator(store: store) { _, _ in .activity(good) }
        await wrongQuery.refresh(item: current, profileID: id)
        #expect(store.runtimeCache.readings(for: item.id)?.aiActivity == nil)
        // Even a corrupt identity tag cannot make a different provider/range payload display.
        var readings = WidgetRuntimeReadings()
        readings.aiActivity = .init(identity: "claude|sevenDays", value: good)
        store.runtimeCache.set(readings, for: item.id)
        #expect(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot == nil)
    }

    @Test func aiMigrationPreservesCompatibleTimestampSemanticVersionAndRecomputesUnattributedLimits() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        let date = Date(timeIntervalSince1970: 2_000)
        let legacy = activity(at: date)
        var item = DockItem.widget("AI Activity")
        item.widgetConfiguration?.aiActivitySnapshot = legacy
        let limits = DockItem.widget("AI Limits")
        var state = PersistentState()
        state.profiles = [.init(name: "AI", kind: .custom, items: [item, limits])]
        try JSONEncoder().encode(state).write(to: file)
        let cache = WidgetRuntimeCache(fileURL: dir.appendingPathComponent("runtime-cache.json"))
        var readings = WidgetRuntimeReadings()
        readings.aiLimits = .init(identity: "limits", value: .init(fetchedAt: date, readings: []))
        cache.set(readings, for: limits.id)
        #expect(cache.flush())
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(store.state.profiles[0].items.allSatisfy { $0.widgetConfiguration?.runtimeReadings.isEmpty == true })
        #expect(store.presentationItem(item).widgetConfiguration?.aiActivitySnapshot == legacy)
        #expect(store.runtimeCache.readings(for: limits.id)?.aiLimits == nil)
        #expect(store.presentationItem(limits).widgetConfiguration?.aiLimitsSnapshot == nil)
        // New metric semantics win even if a legacy response carried a more recent timestamp.
        var old = WidgetRuntimeReadings(), corrected = WidgetRuntimeReadings()
        old.aiActivity = .init(identity: "codex|today", value: activity(at: date, version: 1))
        corrected.aiActivity = .init(identity: "codex|today", value: activity(at: date.addingTimeInterval(-60)))
        #expect(WidgetRuntimeReadings.preferringNewer(cached: old, embedded: corrected).aiActivity == corrected.aiActivity)
        #expect(WidgetRuntimeReadings.preferringNewer(cached: corrected, embedded: old).aiActivity == corrected.aiActivity)
    }

    @Test func failedCacheMigrationBlocksAuthoredReplacementAndReopenRecoversOriginalReading() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        var item = DockItem.widget("Stock")
        item.widgetConfiguration?.stockSymbol = "AAPL"
        let good = quote(at: Date(timeIntervalSince1970: 1_000))
        item.widgetConfiguration?.stockSnapshot = good
        var legacy = PersistentState()
        legacy.profiles = [.init(name: "Original", kind: .custom, items: [item])]
        let originalBytes = try JSONEncoder().encode(legacy)
        try originalBytes.write(to: file)
        let failingCache = WidgetRuntimeCache(fileURL: dir.appendingPathComponent("runtime-cache.json")) { _, _ in
            throw CacheFailure.unavailable
        }
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false, runtimeCache: failingCache)
        #expect(store.persistenceWarning != nil)
        #expect(store.state.profiles[0].items[0].widgetConfiguration?.stockSnapshot == nil)
        #expect(store.presentationConfiguration(for: item, in: legacy.profiles[0].id).stockSnapshot == good)
        store.renameProfile(legacy.profiles[0].id, to: "Pending edit")
        store.flush()
        #expect(store.hasUnpersistedChanges && store.persistenceError != nil)
        #expect(try Data(contentsOf: file) == originalBytes)
        #expect(throws: EditSessionSaveError.self) { _ = try store.createProfileAndPersist(kind: .custom) }
        #expect(try Data(contentsOf: file) == originalBytes)
        let reopened = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(reopened.state.profiles[0].name == "Original")
        #expect(reopened.presentationConfiguration(for: item, in: legacy.profiles[0].id).stockSnapshot == good)
        reopened.flush()
        let offline = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(offline.presentationConfiguration(for: item, in: legacy.profiles[0].id).stockSnapshot == good)
    }
}
