import AppKit
import Combine
import CryptoKit
import Foundation

struct WidgetDataQuery: Hashable, Sendable {
    var kind: String
    var key: String

    var aiSourceScope: String? {
        if kind == "AI Activity" { return key }
        if kind == "AI Limits", let start = key.range(of: "limits-v") { return String(key[start.lowerBound...]) }
        return nil
    }

    static func make(kind: String?, configuration c: WidgetConfiguration, now: Date = .now, homeDirectory: URL? = nil, environment: [String: String]? = nil, timeZone: TimeZone = .current) -> Self? {
        switch kind {
        case "Stripe" where !c.stripeAccountID.isEmpty:
            Self(kind: "Stripe", key: "\(c.stripeAccountID)|\(c.stripePeriod.rawValue)")
        case "Paddle" where !c.paddleAccountID.isEmpty:
            Self(kind: "Paddle", key: "\(c.paddleAccountID)|\(c.paddlePeriod.rawValue)")
        case "Shopify" where !c.shopifyStoreID.isEmpty:
            Self(kind: "Shopify", key: "\(c.shopifyStoreID)|\(c.shopifyPeriod.rawValue)")
        case "Stock" where !c.stockSymbol.isEmpty:
            Self(kind: "Stock", key: "\(c.stockSymbol.uppercased())|\(c.stockCurrency)")
        case "Watchlist" where !c.watchlistStocks.isEmpty:
            Self(kind: "Watchlist", key: c.watchlistStocks.map { "\($0.symbol)|\($0.currency)" }.joined(separator: ";"))
        case "AI Limits":
            Self(kind: "AI Limits", key: c.aiLimitsVisibleProviders.map(\.rawValue).sorted().joined(separator: ";") + "|\(c.aiCopilotMonthlyCreditAllowance ?? 0)|" + AIUsageSourceScope.limits(providers: c.aiLimitsVisibleProviders, homeDirectory: homeDirectory, environment: environment, now: now))
        case "AI Activity":
            Self(kind: "AI Activity", key: AIUsageSourceScope.activity(provider: c.aiActivityProvider, range: c.aiActivityRange, homeDirectory: homeDirectory, environment: environment, timeZone: timeZone, now: now))
        default: nil
        }
    }
}

enum WidgetDataValue {
    case stripe(StripeSnapshot), paddle(PaddleSnapshot), shopify(ShopifySnapshot)
    /// `limitReached`: the provider's request limit stopped the refresh before every symbol was read.
    case stock(StockMarketSnapshot), watchlist([String: StockMarketSnapshot], failedSymbols: [String], limitReached: Bool)
    case limits(AILimitsSnapshot), activity(AIActivitySnapshot)

    var partialError: String? {
        if case .watchlist(_, let failed, let limitReached) = self, !failed.isEmpty {
            if limitReached { return (MarketDataError.providerLimit.errorDescription ?? "") + " Saved quotes were kept." }
            return "Some symbols did not refresh: " + failed.prefix(10).joined(separator: ", ") + ". Saved quotes were kept."
        }
        if case .activity(let snapshot) = self, !snapshot.available, snapshot.partial { return "Local activity couldn’t be read. Try refreshing." }
        if case .limits(let snapshot) = self, snapshot.readings.contains(where: { $0.availability == .error || $0.lastRefreshError != nil }) {
            return "Some provider limits could not refresh. Saved readings are shown only for a matching verified account."
        }
        return nil
    }

    func apply(to c: inout WidgetConfiguration, now: Date = .now, sourceScope: String? = nil) {
        switch self {
        // Readings only: `publish` keeps nothing else, so an authored setting changed here would be dropped. The shown
        // Stripe currency is resolved at display time (`WidgetConfiguration.stripeDisplayCurrency`).
        case .stripe(let snapshot): c.stripeSnapshot = snapshot
        case .paddle(let snapshot): c.paddleSnapshot = snapshot
        case .shopify(let snapshot): c.shopifySnapshot = snapshot
        case .stock(let snapshot): c.stockSnapshot = snapshot
        case .watchlist(let snapshots, _, _):
            for index in c.watchlistStocks.indices {
                if let snapshot = snapshots[c.watchlistStocks[index].symbol] { c.watchlistStocks[index].snapshot = snapshot }
            }
        case .limits(var snapshot):
            let scope = sourceScope ?? AIUsageSourceScope.limits(providers: c.aiLimitsVisibleProviders, now: now)
            guard snapshot.sourceScope == scope else { return }
            if let previous = c.aiLimitsSnapshot, previous.sourceScope == scope {
                snapshot.readings = snapshot.readings.map { reading in
                    guard reading.provider == .copilot, reading.failureKind == .transient,
                          let identity = reading.requestedAccountIdentity,
                          let old = previous.reading(for: reading.provider), old.availability == .available,
                          reading.availability == .error, !identity.isEmpty,
                          old.verifiedAccountIdentity == identity, !old.windows.isEmpty else { return reading }
                    var retained = old
                    retained.lastRefreshError = DataSourceProvenance.sanitized(reading.message ?? "Refresh failed. The saved reading is shown.")
                    return retained
                }
                if !snapshot.readings.isEmpty, snapshot.readings.allSatisfy({ $0.lastRefreshError != nil }) {
                    snapshot.fetchedAt = previous.fetchedAt
                }
            }
            c.aiLimitsSnapshot = snapshot
        case .activity(let snapshot):
            guard snapshot.provider == c.aiActivityProvider, snapshot.range == c.aiActivityRange, snapshot.hasCurrentSemantics else { return }
            let scope = sourceScope ?? AIUsageSourceScope.activity(provider: c.aiActivityProvider, range: c.aiActivityRange, now: now)
            guard snapshot.sourceScope == scope else { return }
            // An unreadable refresh must not erase useful history. A successful
            // empty scan can replace it (for example, after logs are removed).
            if !snapshot.available, snapshot.partial, c.aiActivitySnapshot?.available == true,
               c.aiActivitySnapshot?.hasCurrentSemantics == true, c.aiActivitySnapshot?.sourceScope == scope { return }
            c.aiActivitySnapshot = snapshot
        }
    }
}

/// Refresh ownership follows visible Dock content, independently of popout lifetime.
@MainActor
final class WidgetDataCoordinator: ObservableObject {
    @Published private(set) var errors: [WidgetDataQuery: String] = [:]
    @Published private(set) var refreshing: Set<WidgetDataQuery> = []
    private weak var store: ProfileStore?
    private var observation: AnyCancellable?
    private var wakeObservation: AnyCancellable?
    private var credentialObservation: AnyCancellable?
    private var visible = false
    private var jobs: [WidgetDataQuery: Task<Void, Never>] = [:]
    private var jobIntervals: [WidgetDataQuery: TimeInterval] = [:]
    private var requests: [WidgetDataQuery: Task<Void, Never>] = [:]
    private var requestIDs: [WidgetDataQuery: UUID] = [:]
    private var cache: [WidgetDataQuery: (date: Date, value: WidgetDataValue)] = [:]
    private var failures: [WidgetDataQuery: Int] = [:]
    private let limiter = WidgetRefreshLimiter(maximumConcurrent: 4)
    private let queryMaker: (String?, WidgetConfiguration) -> WidgetDataQuery?
    private let loader: (WidgetDataQuery, WidgetConfiguration) async throws -> WidgetDataValue

    /// `loader` precedes `queryMaker` so a lone trailing closure is the injected loader; pass `queryMaker:` by label.
    init(store: ProfileStore, loader: ((WidgetDataQuery, WidgetConfiguration) async throws -> WidgetDataValue)? = nil, queryMaker: @escaping (String?, WidgetConfiguration) -> WidgetDataQuery? = { WidgetDataQuery.make(kind: $0, configuration: $1) }) {
        self.store = store
        self.queryMaker = queryMaker
        self.loader = loader ?? Self.load
        credentialObservation = NotificationCenter.default.publisher(for: GitHubCopilotCredentialStore.didChange)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.store?.invalidateCopilotLimitReadings() }
        observation = store.$state.receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcile() }
        wakeObservation = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.restartVisibleJobs() }
    }

    func setVisible(_ visible: Bool) {
        guard self.visible != visible else { return }
        self.visible = visible
        reconcile()
    }

    deinit {
        jobs.values.forEach { $0.cancel() }
        requests.values.forEach { $0.cancel() }
    }

    func refresh(item: DockItem, profileID: UUID, force: Bool = true) async {
        guard let c = item.widgetConfiguration, let query = queryMaker(item.widgetKind, c) else { return }
        await refresh(query, configuration: c, force: force)
    }

    func connectionsDidChange() {
        for request in requests.values { request.cancel() }
        requests = [:]; requestIDs = [:]; refreshing = []; errors = [:]
        restartVisibleJobs()
    }

    private func restartVisibleJobs() {
        for job in jobs.values { job.cancel() }
        jobs = [:]
        jobIntervals = [:]
        cache = [:]
        reconcile()
    }

    private func reconcile() {
        var desired: [WidgetDataQuery: WidgetConfiguration] = [:]
        if visible, let profile = store?.activeCustomProfile {
            for item in profile.items {
                if let c = item.widgetConfiguration, let query = queryMaker(item.widgetKind, c) {
                    if let existing = desired[query], Self.interval(query, configuration: existing) <= Self.interval(query, configuration: c) { continue }
                    desired[query] = c
                }
            }
        }
        for query in Array(jobs.keys) where desired[query] == nil || desired[query].map({ Self.interval(query, configuration: $0) }) != jobIntervals[query] {
            jobs.removeValue(forKey: query)?.cancel()
            jobIntervals[query] = nil
            requests.removeValue(forKey: query)?.cancel()
        }
        for (query, configuration) in desired where jobs[query] == nil {
            jobIntervals[query] = Self.interval(query, configuration: configuration)
            jobs[query] = Task { [weak self] in
                while !Task.isCancelled {
                    guard self?.store != nil else { return }
                    // Root/time-zone/period changes restart the query even without an authored edit.
                    guard self?.queryMaker(query.kind, configuration) == query else {
                        self?.reconcile(); return
                    }
                    await self?.refresh(query, configuration: configuration, force: false)
                    let delay = Self.nextRefreshDelay(interval: Self.interval(query, configuration: configuration), failures: self?.failures[query])
                    do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                }
            }
        }
    }

    /// After a failure the next attempt never comes sooner than the normal cadence; repeated failures back off
    /// exponentially up to an hour, so a rate-limited provider is polled less, not more.
    nonisolated static func nextRefreshDelay(interval: TimeInterval, failures: Int?) -> TimeInterval {
        guard let failures else { return interval }
        return max(interval, min(3_600, 60 * pow(2, Double(min(failures, 6)))))
    }

    static func interval(_ query: WidgetDataQuery, configuration: WidgetConfiguration) -> TimeInterval {
        switch query.kind {
        case "Stock", "Watchlist": Double(max(1, configuration.stockRefreshIntervalMinutes)) * 60
        case "AI Activity": 120
        default: 300
        }
    }

    private func refresh(_ query: WidgetDataQuery, configuration: WidgetConfiguration, force: Bool) async {
        guard !Task.isCancelled else { return }
        if !force, let cached = cache[query], Date.now.timeIntervalSince(cached.date) < Self.interval(query, configuration: configuration) {
            publish(cached.value, query: query)
            return
        }
        let request: Task<Void, Never>
        if let existing = requests[query] { request = existing }
        else {
            let loader = self.loader
            let limiter = self.limiter
            let requestID = UUID()
            let credentialRevision = GitHubCopilotCredentialStore.revision
            requestIDs[query] = requestID
            request = Task { [weak self] in
                let result: Result<WidgetDataValue, Error>
                do {
                    try await limiter.acquire()
                    do {
                        try Task.checkCancellation()
                        let value = try await loader(query, configuration)
                        await limiter.release()
                        result = .success(value)
                    } catch {
                        await limiter.release()
                        result = .failure(error)
                    }
                } catch { result = .failure(error) }
                self?.finishRefresh(result, query: query, requestID: requestID, configuration: configuration, credentialRevision: credentialRevision, cancelled: Task.isCancelled)
            }
            requests[query] = request
            refreshing.insert(query)
        }
        await request.value
    }

    /// A shared request owns its result once, regardless of how many tiles await it.
    private func finishRefresh(_ result: Result<WidgetDataValue, Error>, query: WidgetDataQuery,
                               requestID: UUID, configuration: WidgetConfiguration, credentialRevision: UInt64, cancelled: Bool) {
        guard requestIDs[query] == requestID else { return }
        defer {
            requests[query] = nil; requestIDs[query] = nil; refreshing.remove(query)
        }
        guard !cancelled, (query.kind != "AI Limits" || !configuration.aiLimitsVisibleProviders.contains(.copilot) ||
                           credentialRevision == GitHubCopilotCredentialStore.revision),
              queryMaker(query.kind, configuration) == query else { return }
        switch result {
        case .success(let value):
            cache[query] = (.now, value)
            if cache.count > 128, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key { cache[oldest] = nil }
            errors[query] = value.partialError
            // A watchlist stopped by the provider's request limit keeps the quotes it read but backs off like a failure.
            if case .watchlist(_, _, true) = value { failures[query, default: 0] += 1 } else { failures[query] = nil }
            publish(value, query: query)
        case .failure(let error):
            errors[query] = error.localizedDescription
            failures[query, default: 0] += 1
        }
        if errors.count > 128, let oldest = errors.keys.first { errors[oldest] = nil; failures[oldest] = nil }
    }

    private func publish(_ value: WidgetDataValue, query: WidgetDataQuery) {
        guard let store else { return }
        let targets = store.state.profiles.flatMap { profile in
            profile.items.filter { item in
                item.widgetConfiguration.map { queryMaker(item.widgetKind, $0) == query } ?? false
            }.map { (profile.id, $0.id) }
        }
        for (profileID, itemID) in targets {
            store.publishRuntimeReadings(itemID: itemID, in: profileID) { c in
                guard queryMaker(query.kind, c) == query else { return }
                value.apply(to: &c, sourceScope: query.aiSourceScope)
            }
        }
    }

    private static func load(_ query: WidgetDataQuery, _ c: WidgetConfiguration) async throws -> WidgetDataValue {
        // The default graph cannot reach account processes, credential stores or remote providers in validation.
        try AppRuntimeEnvironment.requireNetwork()
        switch query.kind {
        case "Stripe":
            let accountID = c.stripeAccountID
            guard let key = try await readCredential({ try StripeAPIKeyStore.read(accountID: accountID) }) else { throw StripeDataError.missingKey }
            return .stripe(try await StripeAPIProvider().snapshot(apiKey: key, accountID: c.stripeAccountID,
                                                                  accountName: StripeConnectionDirectory.accounts().first { $0.id == c.stripeAccountID }?.name ?? c.stripeDisplayName, period: c.stripePeriod))
        case "Paddle":
            let accountID = c.paddleAccountID
            guard let key = try await readCredential({ try PaddleAPIKeyStore.read(accountID: accountID) }) else { throw PaddleDataError.missingKey }
            return .paddle(try await PaddleAPIProvider().snapshot(apiKey: key, accountID: c.paddleAccountID,
                                                                  accountName: PaddleConnectionDirectory.accounts().first { $0.id == c.paddleAccountID }?.name ?? c.paddleDisplayName, period: c.paddlePeriod))
        case "Shopify":
            let storeID = c.shopifyStoreID
            guard let account = ShopifyConnectionDirectory.stores().first(where: { $0.id == storeID }),
                  let credential = try await readCredential({ try ShopifyCredentialStore.read(storeID: storeID) }) else { throw ShopifyDataError.invalidCredentials }
            let result = try await ShopifyAPIProvider().snapshot(store: account, credential: credential, period: c.shopifyPeriod)
            try ShopifyCredentialStore.writeRefreshed(result.credential, replacing: credential, storeID: c.shopifyStoreID)
            return .shopify(result.snapshot)
        case "Stock", "Watchlist":
            guard let key = try await readCredential({ try MarketAPIKeyStore.read() }) else { throw MarketDataError.missingAPIKey }
            if query.kind == "Stock" { return .stock(try await SharedMarketSnapshots.shared.snapshot(symbol: c.stockSymbol, currency: c.stockCurrency, apiKey: key)) }
            var snapshots: [String: StockMarketSnapshot] = [:]
            var failed: [String] = []
            var limitReached = false
            for stock in c.watchlistStocks {
                try Task.checkCancellation()
                // Once the provider's request limit is reached, the remaining symbols cannot succeed either.
                guard !limitReached else { failed.append(stock.symbol); continue }
                do { snapshots[stock.symbol] = try await SharedMarketSnapshots.shared.snapshot(symbol: stock.symbol, currency: stock.currency, apiKey: key) }
                catch MarketDataError.providerLimit {
                    // Nothing refreshed: report a failure so the next attempt backs off.
                    guard !snapshots.isEmpty else { throw MarketDataError.providerLimit }
                    limitReached = true; failed.append(stock.symbol)
                } catch { try Task.checkCancellation(); failed.append(stock.symbol) }
            }
            return .watchlist(snapshots, failedSymbols: failed, limitReached: limitReached)
        case "AI Limits":
            let providers = c.aiLimitsVisibleProviders
            let allowance = c.aiCopilotMonthlyCreditAllowance
            let worker = Task.detached(priority: .utility) {
                await AILimitsCollector.collect(providers: providers, copilotMonthlyCreditAllowance: allowance)
            }
            return .limits(await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() })
        case "AI Activity":
            let provider = c.aiActivityProvider
            let range = c.aiActivityRange
            // The scan runs on a utility queue, not a Swift-concurrency thread; cancelling the refresh stops it.
            return .activity(await AIActivityReader.readInBackground(provider: provider, range: range))
        default: throw MarketDataError.invalidResponse
        }
    }

    /// Keychain reads can block on a locked or slow keychain, so they run off the main actor. Only Sendable values cross.
    private static func readCredential<T: Sendable>(_ read: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .utility) { try read() }.value
    }
}

/// Stock tiles and watchlists share the same symbol request. Credentials remain in memory only.
private actor SharedMarketSnapshots {
    static let shared = SharedMarketSnapshots()
    private var requests: [String: Task<StockMarketSnapshot, Error>] = [:]
    private var cache: [String: StockMarketSnapshot] = [:]

    func snapshot(symbol: String, currency: String, apiKey: String) async throws -> StockMarketSnapshot {
        let fingerprint = SHA256.hash(data: Data(apiKey.utf8)).map { String(format: "%02x", $0) }.joined()
        let key = "\(symbol.uppercased())|\(currency)|\(fingerprint)"
        if let value = cache[key], Date.now.timeIntervalSince(value.fetchedAt) < 60 { return value }
        if let request = requests[key] { return try await request.value }
        let request = Task { try await AlphaVantageMarketProvider().snapshot(symbol: symbol, currency: currency, apiKey: apiKey) }
        requests[key] = request
        defer { requests[key] = nil }
        let value = try await request.value
        cache[key] = value
        if cache.count > 128, let oldest = cache.min(by: { $0.value.fetchedAt < $1.value.fetchedAt })?.key { cache[oldest] = nil }
        return value
    }
}
