import Foundation
import Testing
@testable import MyDock

/// PR-13 phase 1: provider readings live in `runtime-cache.json`, not in authored state. Isolated fixture directories only.
@MainActor
struct WidgetRuntimeCacheTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var writes: Int { lock.lock(); defer { lock.unlock() }; return count }
        func writer() -> RevisionedStateWriter {
            RevisionedStateWriter { [self] state, url in
                lock.lock(); count += 1; lock.unlock()
                try RevisionedStateWriter.persist(state, to: url)
            }
        }
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-RuntimeCache-\(UUID().uuidString)", isDirectory: true)
    }

    private func stripe(_ account: String, at date: Date = .now) -> StripeSnapshot {
        StripeSnapshot(accountID: account, accountName: "N", fetchedAt: date, period: .thirtyDays, periodStart: date, periodEnd: date,
                       currencies: [], unsupportedSubscriptionItems: 0)
    }

    private func quote(_ symbol: String, close: Double = 10, at date: Date = .now) -> StockMarketSnapshot {
        StockMarketSnapshot(symbol: symbol, points: [StockMarketPoint(date: date, close: close, volume: 1)], currency: "USD", fetchedAt: date)
    }

    private func stripeItem(account: String = "acct", snapshot: StripeSnapshot? = nil) -> DockItem {
        var item = DockItem.widget("Stripe")
        item.widgetConfiguration?.stripeAccountID = account
        item.widgetConfiguration?.stripeSnapshot = snapshot
        return item
    }

    private func read(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }

    @Test func migrationCopiesEmbeddedReadingsToCacheAndStripsThemOnSave() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("state.json")
        var stock = DockItem.widget("Stock")
        stock.widgetConfiguration?.stockSymbol = "AAPL"
        stock.widgetConfiguration?.stockSnapshot = quote("AAPL", close: 42)
        var watch = DockItem.widget("Watchlist")
        watch.widgetConfiguration?.watchlistStocks = [WatchlistStock(symbol: "MSFT", name: "M", currency: "USD", snapshot: quote("MSFT"))]
        let item = stripeItem(snapshot: stripe("acct"))
        var legacy = PersistentState()
        legacy.profiles = [DockProfile(name: "P", kind: .custom, items: [item, stock, watch])]
        let legacyData = try JSONEncoder().encode(legacy)
        try legacyData.write(to: file)
        #expect(String(decoding: legacyData, as: UTF8.self).contains("stripeSnapshot"))

        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let loaded = try #require(store.state.profiles.first?.items)
        #expect(loaded[0].widgetConfiguration?.stripeSnapshot != nil)
        #expect(loaded[1].widgetConfiguration?.stockSnapshot?.latest?.close == 42)
        #expect(loaded[2].widgetConfiguration?.watchlistStocks.first?.snapshot != nil)
        #expect(store.runtimeCache.readings(for: item.id)?.stripe != nil)

        store.flush()
        let saved = read(file)
        #expect(!saved.contains("stripeSnapshot") && !saved.contains("stockSnapshot") && !saved.contains("\"snapshot\""))
        #expect(saved.contains("acct"))
        // Old fields still decode, so earlier files and imported backups load.
        let decoded = try JSONDecoder().decode(PersistentState.self, from: legacyData)
        #expect(decoded.profiles[0].items[0].widgetConfiguration?.stripeSnapshot != nil)
        #expect(decoded.schemaVersion == Product.stateSchemaVersion)

        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(relaunched.state.profiles[0].items[0].widgetConfiguration?.stripeSnapshot != nil)
        #expect(relaunched.state.profiles[0].items[2].widgetConfiguration?.watchlistStocks.first?.snapshot?.symbol == "MSFT")
    }

    @Test func newerCachedReadingBeatsOlderEmbeddedOne() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let item = stripeItem()
        let first = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let profileID = try first.createProfile(DockProfile(name: "P", kind: .custom, items: [item]))
        let newer = stripe("acct", at: Date(timeIntervalSince1970: 2_000))
        first.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.stripeSnapshot = newer }
        first.flush()
        // Re-embed an older reading in the authored file, as an older app version would.
        var legacy = first.state
        legacy.profiles[0].items[0].widgetConfiguration?.stripeSnapshot = stripe("acct", at: Date(timeIntervalSince1970: 1_000))
        try JSONEncoder().encode(legacy).write(to: file)
        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(relaunched.state.profiles[0].items[0].widgetConfiguration?.stripeSnapshot?.fetchedAt == newer.fetchedAt)
    }

    @Test func refreshNeverRewritesStateOrCommits() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let counter = Counter()
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false, stateWriter: counter.writer())
        var stock = DockItem.widget("Stock")
        stock.widgetConfiguration?.stockSymbol = "AAPL"
        let profileID = try store.createProfile(DockProfile(name: "P", kind: .custom, items: [stock]))
        let bytes = try Data(contentsOf: file)
        let writes = counter.writes
        let loaded = quote("AAPL", close: 7)
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in .stock(loaded) }
        await coordinator.refresh(item: stock, profileID: profileID)
        try await Task.sleep(for: .milliseconds(400))

        #expect(store.state.profiles[0].items[0].widgetConfiguration?.stockSnapshot == loaded)
        #expect(store.runtimeCache.readings(for: stock.id)?.stock?.value == loaded)
        #expect(try Data(contentsOf: file) == bytes)
        #expect(counter.writes == writes)
        #expect(!store.hasUnpersistedChanges && !store.isSaving)
    }

    @Test func offlineRelaunchShowsLastGoodReadingFromCache() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        var stock = DockItem.widget("Stock")
        stock.widgetConfiguration?.stockSymbol = "AAPL"
        let profileID = try store.createProfile(DockProfile(name: "P", kind: .custom, items: [stock]))
        let loaded = quote("AAPL", close: 9)
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in .stock(loaded) }
        await coordinator.refresh(item: stock, profileID: profileID)
        store.flush()

        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let offline = WidgetDataCoordinator(store: relaunched) { _, _ in throw MarketDataError.invalidResponse }
        await offline.refresh(item: stock, profileID: profileID)
        #expect(relaunched.state.profiles[0].items[0].widgetConfiguration?.stockSnapshot == loaded)
        #expect(!read(file).contains("\"stockSnapshot\""))
    }

    @Test func backupExportContainsNoRuntimeReadings() throws {
        var item = stripeItem(snapshot: stripe("acct"))
        item.widgetConfiguration?.cachedWeatherForecast = WeatherForecast(temperature: 1, apparentTemperature: 1, relativeHumidity: 1,
            precipitation: 0, windSpeed: 1, weatherCode: 1, isDay: true, fetchedAt: .now, timeZoneIdentifier: "UTC", hourly: [])
        var stock = DockItem.widget("Watchlist")
        stock.widgetConfiguration?.watchlistStocks = [WatchlistStock(symbol: "AAPL", name: "A", currency: "USD", snapshot: quote("AAPL"))]
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "P", kind: .custom, items: [item, stock])])
        let text = String(decoding: archive, as: UTF8.self)
        for key in ["stripeSnapshot", "cachedWeatherForecast", "\"snapshot\"", "stockSnapshot"] { #expect(!text.contains(key), "\(key)") }
        #expect(text.contains("acct"))
    }

    @Test func deletingItemsAndProfilesPrunesCacheEntries() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let a = stripeItem(snapshot: stripe("acct")), b = stripeItem(account: "b", snapshot: stripe("b"))
        let other = stripeItem(account: "c", snapshot: stripe("c"))
        let first = try store.createProfile(DockProfile(name: "P", kind: .custom, items: [a, b]))
        let second = try store.createProfile(DockProfile(name: "Q", kind: .custom, items: [other]))
        #expect(store.runtimeCache.entries.count == 3)
        store.removeItem(a.id, from: first)
        #expect(store.runtimeCache.readings(for: a.id) == nil && store.runtimeCache.readings(for: b.id) != nil)
        store.deleteProfile(second)
        #expect(store.runtimeCache.readings(for: other.id) == nil)
        store.flush()
        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(Array(relaunched.runtimeCache.entries.keys) == [b.id])
    }

    @Test func tenantClearAndIdentityChangeDropReadingsFromCache() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let mine = stripeItem(account: "conn-1", snapshot: stripe("conn-1"))
        let other = stripeItem(account: "conn-2", snapshot: stripe("conn-2"))
        _ = try store.createProfile(DockProfile(name: "P", kind: .custom, items: [mine, other]))
        #expect(store.clearPersistedSnapshots(for: .stripe("conn-1")) == 1)
        #expect(store.runtimeCache.readings(for: mine.id) == nil)
        #expect(store.runtimeCache.readings(for: other.id)?.stripe != nil)
        store.flush()
        let relaunched = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(relaunched.state.profiles[0].items[0].widgetConfiguration?.stripeSnapshot == nil)
        #expect(relaunched.state.profiles[0].items[1].widgetConfiguration?.stripeSnapshot != nil)

        // A reading cached for another connection is never shown for the current one.
        var cached = try #require(relaunched.runtimeCache.readings(for: other.id))
        cached.stripe?.identity = "conn-9"
        relaunched.runtimeCache.set(cached, for: other.id)
        #expect(relaunched.runtimeCache.flush())
        let third = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(third.state.profiles[0].items[1].widgetConfiguration?.stripeSnapshot == nil)
    }

    @Test func corruptOversizedAndFutureCachesAreSetAsideWithoutBlocking() throws {
        let payloads = [Data("not json".utf8), Data(repeating: 0x20, count: WidgetRuntimeCache.maximumBytes + 10),
                        Data(#"{"version":99,"entries":{}}"#.utf8)]
        for payload in payloads {
            let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try payload.write(to: dir.appendingPathComponent("runtime-cache.json"))
            let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
            let item = stripeItem(snapshot: stripe("acct"))
            _ = try store.createProfile(DockProfile(name: "P", kind: .custom, items: [item]))
            #expect(store.runtimeCache.recovered)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.hasPrefix("runtime-cache.json.corrupt-") })
            #expect(store.runtimeCache.readings(for: item.id)?.stripe != nil)
            #expect(store.runtimeCache.flush())
        }
    }

    @Test func cacheFileIsPrivateVersionedAndBounded() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = WidgetRuntimeCache(fileURL: dir.appendingPathComponent("runtime-cache.json"))
        var readings = WidgetRuntimeReadings()
        readings.watchlist = ["AAPL|USD": quote("AAPL")]
        for _ in 0..<(WidgetRuntimeCache.maximumEntries + 25) { cache.set(readings, for: UUID()) }
        #expect(cache.flush())
        let attributes = try FileManager.default.attributesOfItem(atPath: cache.fileURL.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int) == 0o700)
        let reloaded = WidgetRuntimeCache(fileURL: cache.fileURL)
        #expect(reloaded.entries.count == WidgetRuntimeCache.maximumEntries)
        #expect(read(cache.fileURL).contains("\"version\":1"))
        // Cached values obey the same bounds as authored ones (MD-A03).
        var bad = WidgetRuntimeReadings()
        bad.watchlist = ["X|USD": quote("X", close: -5)]
        #expect(cache.set(bad, for: UUID()) == false)
    }
}
