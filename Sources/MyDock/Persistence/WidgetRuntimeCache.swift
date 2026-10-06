import Combine
import Foundation
import OSLog

/// Provider readings are runtime data, not authored configuration. Each reading is tagged with the identity it was
/// fetched for (connection, symbol, location...) and is only shown while that identity still matches the widget.
struct WidgetRuntimeReadings: Codable, Equatable {
    struct Tagged<Value: Codable & Equatable>: Codable, Equatable {
        var identity: String
        var value: Value
    }

    var stock: Tagged<StockMarketSnapshot>?
    var stripe: Tagged<StripeSnapshot>?
    var paddle: Tagged<PaddleSnapshot>?
    var shopify: Tagged<ShopifySnapshot>?
    var aiLimits: Tagged<AILimitsSnapshot>?
    var aiActivity: Tagged<AIActivitySnapshot>?
    var weather: Tagged<WeatherForecast>?
    /// Keyed by `WidgetConfiguration.watchlistKey(symbol:currency:)`.
    var watchlist: [String: StockMarketSnapshot]?

    var isEmpty: Bool {
        stock == nil && stripe == nil && paddle == nil && shopify == nil && aiLimits == nil
            && aiActivity == nil && weather == nil && (watchlist?.isEmpty ?? true)
    }

    /// Drops values that fail the same bounds applied to authored configuration (MD-A03).
    func sanitized() -> WidgetRuntimeReadings {
        var copy = self
        if let stock = copy.stock, !Self.isValid(stock.value) { copy.stock = nil }
        copy.watchlist = copy.watchlist?.filter { Self.isValid($0.value) }
        if copy.watchlist?.isEmpty == true { copy.watchlist = nil }
        if copy.aiLimits?.value.isValid == false { copy.aiLimits = nil }
        if copy.aiActivity?.value.isValid == false { copy.aiActivity = nil }
        return copy
    }

    private static func isValid(_ snapshot: StockMarketSnapshot) -> Bool {
        snapshot.points.count <= 10_000 && snapshot.points.allSatisfy { $0.close.isFinite && $0.close >= 0 && $0.volume >= 0 }
    }

    /// Matching identities prefer newer timestamps (ties keep cache); corrected AI semantics supersede legacy totals.
    static func preferringNewer(cached: WidgetRuntimeReadings?, embedded: WidgetRuntimeReadings) -> WidgetRuntimeReadings {
        guard var result = cached else { return embedded }
        func pick<V: Codable & Equatable>(_ keyPath: WritableKeyPath<WidgetRuntimeReadings, Tagged<V>?>, _ date: (V) -> Date) {
            guard let new = embedded[keyPath: keyPath] else { return }
            if let old = result[keyPath: keyPath], old.identity == new.identity, date(old.value) >= date(new.value) { return }
            result[keyPath: keyPath] = new
        }
        pick(\.stock) { $0.fetchedAt }
        pick(\.stripe) { $0.fetchedAt }
        pick(\.paddle) { $0.fetchedAt }
        pick(\.shopify) { $0.fetchedAt }
        pick(\.aiLimits) { $0.fetchedAt }
        if let new = embedded.aiActivity {
            let old = result.aiActivity.flatMap { $0.identity == new.identity ? $0 : nil }
            // Corrected semantics supersede legacy totals without rewriting their original timestamps.
            let semanticUpgrade = old.map { !$0.value.hasCurrentSemantics && new.value.hasCurrentSemantics } ?? true
            let semanticDowngrade = old.map { $0.value.hasCurrentSemantics && !new.value.hasCurrentSemantics } ?? false
            if !semanticDowngrade && (semanticUpgrade || (old.map { $0.value.fetchedAt < new.value.fetchedAt } ?? true)) {
                result.aiActivity = new
            }
        }
        pick(\.weather) { $0.fetchedAt }
        for (key, snapshot) in embedded.watchlist ?? [:] {
            if let old = result.watchlist?[key], old.fetchedAt >= snapshot.fetchedAt { continue }
            result.watchlist = (result.watchlist ?? [:]).merging([key: snapshot]) { $1 }
        }
        return result
    }
}

/// Generic types are not inferred `Sendable`; this lets the cache hand readings to its background writer.
extension WidgetRuntimeReadings.Tagged: Sendable where Value: Sendable {}

extension WidgetConfiguration {
    static func watchlistKey(symbol: String, currency: String) -> String { "\(symbol.uppercased())|\(currency)" }

    private var stockIdentity: String { Self.watchlistKey(symbol: stockSymbol, currency: stockCurrency) }
    private var aiLimitsIdentity: String { aiLimitsIdentity(scope: AIUsageSourceScope.limits(providers: aiLimitsVisibleProviders)) }
    private func aiLimitsIdentity(scope: String) -> String {
        aiLimitsVisibleProviders.map(\.rawValue).sorted().joined(separator: ";") + "|\(aiCopilotMonthlyCreditAllowance ?? 0)|" + scope
    }
    private var aiActivityIdentity: String { AIUsageSourceScope.activity(provider: aiActivityProvider, range: aiActivityRange) }
    private var weatherIdentity: String { "\(weatherLocation?.id ?? "")|\(weatherUnit.rawValue)" }

    /// The runtime readings currently held by this configuration, tagged with their present identity.
    var runtimeReadings: WidgetRuntimeReadings {
        var readings = WidgetRuntimeReadings()
        readings.stock = stockSnapshot.map { .init(identity: stockIdentity, value: $0) }
        readings.stripe = stripeSnapshot.map { .init(identity: stripeAccountID, value: $0) }
        readings.paddle = paddleSnapshot.map { .init(identity: paddleAccountID, value: $0) }
        readings.shopify = shopifySnapshot.map { .init(identity: shopifyStoreID, value: $0) }
        readings.aiLimits = aiLimitsSnapshot.map { .init(identity: aiLimitsIdentity(scope: $0.sourceScope ?? "unattributed"), value: $0) }
        readings.aiActivity = aiActivitySnapshot.map { .init(identity: $0.sourceScope ?? "unattributed", value: $0) }
        readings.weather = cachedWeatherForecast.map { .init(identity: weatherIdentity, value: $0) }
        var watchlist: [String: StockMarketSnapshot] = [:]
        for stock in watchlistStocks { if let snapshot = stock.snapshot { watchlist[Self.watchlistKey(symbol: stock.symbol, currency: stock.currency)] = snapshot } }
        readings.watchlist = watchlist.isEmpty ? nil : watchlist
        return readings
    }

    /// Replaces every runtime reading with the cached ones whose identity still matches this configuration.
    mutating func resolveRuntimeReadings(_ readings: WidgetRuntimeReadings?, activityScope: String? = nil, limitsScope: String? = nil) {
        stripRuntimeReadings()
        guard let readings = readings?.sanitized() else { return }
        if let r = readings.stock, r.identity == stockIdentity { stockSnapshot = r.value }
        if let r = readings.stripe, r.identity == stripeAccountID, r.value.period == stripePeriod { stripeSnapshot = r.value }
        if let r = readings.paddle, r.identity == paddleAccountID, r.value.period == paddlePeriod { paddleSnapshot = r.value }
        if let r = readings.shopify, r.identity == shopifyStoreID, r.value.period == shopifyPeriod { shopifySnapshot = r.value }
        if let r = readings.aiLimits, r.identity == aiLimitsIdentity(scope: limitsScope ?? AIUsageSourceScope.limits(providers: aiLimitsVisibleProviders)),
           r.value.sourceScope == (limitsScope ?? AIUsageSourceScope.limits(providers: aiLimitsVisibleProviders)) { aiLimitsSnapshot = r.value }
        if let r = readings.aiActivity, r.identity == (activityScope ?? aiActivityIdentity), r.value.sourceScope == (activityScope ?? aiActivityIdentity),
           r.value.provider == aiActivityProvider, r.value.range == aiActivityRange, r.value.hasCurrentSemantics { aiActivitySnapshot = r.value }
        if let r = readings.weather, r.identity == weatherIdentity { cachedWeatherForecast = r.value }
        for index in watchlistStocks.indices {
            let stock = watchlistStocks[index]
            watchlistStocks[index].snapshot = readings.watchlist?[Self.watchlistKey(symbol: stock.symbol, currency: stock.currency)]
        }
    }

    /// Unchanged values keep their original query identity when a user changes setup.
    /// Otherwise an old account/location quote could be silently retagged for the new selection.
    mutating func invalidateUnchangedReadings(after previous: WidgetConfiguration) {
        var matching = self
        matching.resolveRuntimeReadings(previous.runtimeReadings)
        if stockSnapshot == previous.stockSnapshot { stockSnapshot = matching.stockSnapshot }
        if stripeSnapshot == previous.stripeSnapshot { stripeSnapshot = matching.stripeSnapshot }
        if paddleSnapshot == previous.paddleSnapshot { paddleSnapshot = matching.paddleSnapshot }
        if shopifySnapshot == previous.shopifySnapshot { shopifySnapshot = matching.shopifySnapshot }
        if cachedWeatherForecast == previous.cachedWeatherForecast { cachedWeatherForecast = matching.cachedWeatherForecast }
        if aiActivitySnapshot == previous.aiActivitySnapshot { aiActivitySnapshot = matching.aiActivitySnapshot }
        if aiLimitsSnapshot == previous.aiLimitsSnapshot { aiLimitsSnapshot = matching.aiLimitsSnapshot }
        for index in watchlistStocks.indices {
            let stock = watchlistStocks[index]
            if let old = previous.watchlistStocks.first(where: { $0.id == stock.id }), old.snapshot == stock.snapshot {
                watchlistStocks[index].snapshot = matching.watchlistStocks[index].snapshot
            }
        }
    }

    mutating func stripRuntimeReadings() {
        stockSnapshot = nil; stripeSnapshot = nil; paddleSnapshot = nil; shopifySnapshot = nil
        aiLimitsSnapshot = nil; aiActivitySnapshot = nil; cachedWeatherForecast = nil
        for index in watchlistStocks.indices { watchlistStocks[index].snapshot = nil }
    }

    var strippedOfRuntimeReadings: WidgetConfiguration {
        var copy = self; copy.stripRuntimeReadings(); return copy
    }
}

extension DockItem {
    var strippedOfRuntimeReadings: DockItem {
        var copy = self
        copy.widgetConfiguration?.stripRuntimeReadings()
        return copy
    }
}

extension DockProfile {
    var strippedOfRuntimeReadings: DockProfile {
        var copy = self
        for index in copy.items.indices where copy.items[index].widgetConfiguration != nil {
            copy.items[index].widgetConfiguration?.stripRuntimeReadings()
        }
        return copy
    }
}

extension PersistentState {
    /// The authored representation written to state.json, backups and libraries.
    var strippedOfRuntimeReadings: PersistentState {
        var copy = self
        copy.profiles = profiles.map(\.strippedOfRuntimeReadings)
        return copy
    }
}

/// Bounded, versioned, private cache of provider readings keyed by widget item ID (`runtime-cache.json`).
/// It is disposable: unreadable or oversized files are set aside, and a failed flush never blocks quitting.
@MainActor
final class WidgetRuntimeCache: ObservableObject {
    nonisolated static let version = 1
    nonisolated static let maximumBytes = 4 * 1_024 * 1_024
    nonisolated static let maximumEntries = 2_000

    struct Entry: Codable, Equatable {
        var savedAt: Date
        var readings: WidgetRuntimeReadings
    }
    private struct FileEnvelope: Codable {
        var version: Int
        var entries: [String: Entry]
    }
    private struct VersionEnvelope: Decodable { var version: Int? }

    @Published private(set) var entries: [UUID: Entry] = [:]
    private(set) var recovered = false
    let fileURL: URL
    private let writer: Writer
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "runtime-cache")
    private var generation: UInt64 = 0
    private var dirty = false

    init(fileURL: URL, persistEntries: (@Sendable ([UUID: Entry], URL) throws -> Void)? = nil) {
        self.fileURL = fileURL
        self.writer = Writer(persistEntries: persistEntries ?? { try WidgetRuntimeCache.persist($0, to: $1) })
        load()
    }

    func readings(for itemID: UUID) -> WidgetRuntimeReadings? { entries[itemID]?.readings }

    /// Empty readings remove the entry. Returns whether anything changed.
    @discardableResult
    func set(_ readings: WidgetRuntimeReadings, for itemID: UUID, now: Date = .now) -> Bool {
        let clean = readings.sanitized()
        if clean.isEmpty { return remove(itemID) }
        if entries[itemID]?.readings == clean { return false }
        entries[itemID] = Entry(savedAt: now, readings: clean)
        scheduleWrite()
        return true
    }

    @discardableResult
    func remove(_ itemID: UUID) -> Bool {
        guard entries.removeValue(forKey: itemID) != nil else { return false }
        scheduleWrite()
        return true
    }

    /// Drops entries whose widget no longer exists.
    func prune(keeping live: Set<UUID>) {
        let stale = entries.keys.filter { !live.contains($0) }
        guard !stale.isEmpty else { return }
        stale.forEach { entries[$0] = nil }
        scheduleWrite()
    }

    /// Writes the latest entries now. Failure is logged and diagnosed only; callers must not block on it.
    @discardableResult
    func flush() -> Bool {
        guard dirty else { return true }
        generation &+= 1
        let result = writer.writeNow(entries, to: fileURL, generation: generation)
        switch result {
        case .success: dirty = false; return true
        case .failure(let error):
            logger.error("Runtime cache flush failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticsService.shared.record(.runtimeCacheSaveFailed)
            return false
        }
    }

    private func scheduleWrite() {
        dirty = true
        generation &+= 1
        let current = generation
        writer.schedule(entries, to: fileURL, generation: current) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.generation == current else { return }
                switch result {
                case .success: self.dirty = false
                case .failure(let error):
                    self.logger.error("Runtime cache save failed: \(error.localizedDescription, privacy: .public)")
                    DiagnosticsService.shared.record(.runtimeCacheSaveFailed)
                }
            }
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try BackupManager.boundedArchiveData(from: fileURL, maximumBytes: Self.maximumBytes)
            guard try JSONDecoder().decode(VersionEnvelope.self, from: data).version == Self.version else {
                throw BackupError.unsupportedVersion(-1)
            }
            let envelope = try JSONDecoder().decode(FileEnvelope.self, from: data)
            guard envelope.entries.count <= Self.maximumEntries else { throw BackupError.tooLarge }
            for (key, entry) in envelope.entries {
                guard let id = UUID(uuidString: key) else { continue }
                let clean = entry.readings.sanitized()
                if !clean.isEmpty { entries[id] = Entry(savedAt: entry.savedAt, readings: clean) }
            }
        } catch {
            entries = [:]
            setAside()
        }
    }

    /// A cache is never worth blocking launch: keep one set-aside copy for diagnosis and start empty.
    private func setAside() {
        recovered = true
        DiagnosticsService.shared.record(.runtimeCacheRecovered)
        let folder = fileURL.deletingLastPathComponent()
        let prefix = fileURL.lastPathComponent + ".corrupt-"
        if let old = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for name in old where name.hasPrefix(prefix) { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
        }
        let aside = folder.appendingPathComponent(prefix + UUID().uuidString)
        do { try FileManager.default.moveItem(at: fileURL, to: aside) }
        catch { try? FileManager.default.removeItem(at: fileURL) }
    }

    /// Serial utility queue; superseded generations never replace a newer write.
    private final class Writer: @unchecked Sendable {
        private let queue = DispatchQueue(label: "app.mydock.runtime-cache-writer", qos: .utility)
        private let lock = NSLock()
        private var latest: UInt64 = 0
        private let persistEntries: @Sendable ([UUID: Entry], URL) throws -> Void

        init(persistEntries: @escaping @Sendable ([UUID: Entry], URL) throws -> Void) { self.persistEntries = persistEntries }

        private func announce(_ generation: UInt64) { lock.lock(); latest = max(latest, generation); lock.unlock() }
        private func isCurrent(_ generation: UInt64) -> Bool { lock.lock(); defer { lock.unlock() }; return latest == generation }

        func schedule(_ entries: [UUID: Entry], to url: URL, generation: UInt64,
                      completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
            announce(generation)
            queue.asyncAfter(deadline: .now() + .milliseconds(750)) { [self] in
                guard isCurrent(generation) else { return }
                completion(Result { try persistEntries(entries, url) })
            }
        }

        func writeNow(_ entries: [UUID: Entry], to url: URL, generation: UInt64) -> Result<Void, Error> {
            announce(generation)
            return queue.sync { Result { try persistEntries(entries, url) } }
        }
    }

    nonisolated static func persist(_ entries: [UUID: Entry], to url: URL) throws {
        var kept = entries
        if kept.count > maximumEntries {
            for key in kept.sorted(by: { $0.value.savedAt < $1.value.savedAt }).prefix(kept.count - maximumEntries).map(\.key) { kept[key] = nil }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(FileEnvelope(version: version, entries: Dictionary(uniqueKeysWithValues: kept.map { ($0.key.uuidString, $0.value) })))
        while data.count > maximumBytes, !kept.isEmpty {
            let oldest = kept.sorted { $0.value.savedAt < $1.value.savedAt }.prefix(max(1, kept.count / 2)).map(\.key)
            oldest.forEach { kept[$0] = nil }
            data = try encoder.encode(FileEnvelope(version: version, entries: Dictionary(uniqueKeysWithValues: kept.map { ($0.key.uuidString, $0.value) })))
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
