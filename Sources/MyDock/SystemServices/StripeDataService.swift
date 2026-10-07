import Foundation
import Security

enum StripeMetric: String, Codable, CaseIterable, Identifiable {
    case revenue
    case netAfterFees
    case mrr
    case arr
    case payingSubscribers
    case arpu
    case availableBalance
    case pendingBalance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .revenue: "Revenue"
        case .netAfterFees: "Net after fees"
        case .mrr: "MRR"
        case .arr: "ARR"
        case .payingSubscribers: "Paying subscribers"
        case .arpu: "ARPU"
        case .availableBalance: "Available balance"
        case .pendingBalance: "Pending balance"
        }
    }
}

enum StripePeriod: String, Codable, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays
    case ninetyDays

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .ninetyDays: "90 days"
        }
    }

    func interval(endingAt now: Date, calendar sourceCalendar: Calendar = .current) -> DateInterval {
        let calendar = sourceCalendar
        let end = now
        let start: Date
        switch self {
        case .today:
            start = calendar.startOfDay(for: now)
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-6 * 86_400)
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-29 * 86_400)
        case .ninetyDays:
            start = calendar.date(byAdding: .day, value: -89, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(-89 * 86_400)
        }
        return DateInterval(start: start, end: end)
    }
}

struct StripeCurrencyMetrics: Codable, Hashable, Identifiable {
    var currency: String
    var revenueMinor: Decimal
    var netAfterFeesMinor: Decimal
    var mrrMinor: Decimal
    var payingSubscribers: Int
    var availableBalanceMinor: Decimal
    var pendingBalanceMinor: Decimal

    var id: String { currency }
    var arpuMinor: Decimal {
        guard payingSubscribers > 0 else { return .zero }
        return decimalDivide(mrrMinor, by: Decimal(payingSubscribers))
    }

    private func decimalDivide(_ value: Decimal, by divisor: Decimal) -> Decimal {
        var source = value
        var denominator = divisor
        var result = Decimal.zero
        _ = NSDecimalDivide(&result, &source, &denominator, .plain)
        return result
    }
}

struct StripeSnapshot: Codable, Hashable {
    var accountID: String
    var accountName: String
    var fetchedAt: Date
    var period: StripePeriod
    var periodStart: Date
    var periodEnd: Date
    var currencies: [StripeCurrencyMetrics]
    var unsupportedSubscriptionItems: Int
    /// Metrics whose source list exceeded the refresh budget. They are shown as unavailable rather than as a partial total.
    var unavailableMetrics: Set<StripeMetric>? = nil

    var currencyCodes: [String] { currencies.map(\.currency).sorted() }

    func isAvailable(_ metric: StripeMetric) -> Bool { !(unavailableMetrics?.contains(metric) ?? false) }

    func metrics(for currency: String) -> StripeCurrencyMetrics? {
        currencies.first { $0.currency == currency.uppercased() }
    }

    /// The account's main currency in this period: the most revenue, then the larger available balance, then
    /// alphabetical. Shown when the reading does not report the selected currency.
    var primaryCurrency: String? {
        currencies.max { lhs, rhs in
            (lhs.revenueMinor, lhs.availableBalanceMinor, rhs.currency) < (rhs.revenueMinor, rhs.availableBalanceMinor, lhs.currency)
        }?.currency
    }

    /// The currency the widget shows for the selected one: the selection while this reading reports it, otherwise the
    /// account's main currency, so a new connection (which starts on USD) on a EUR-only account shows EUR instead of
    /// "No data". Resolved at display time because provider readings never change authored settings: the selection
    /// stays as the user chose it and shows again once the account reports it.
    func displayCurrency(for selected: String) -> String {
        let code = selected.uppercased()
        return metrics(for: code) == nil ? (primaryCurrency ?? code) : code
    }
}

extension WidgetConfiguration {
    /// The currency Stripe faces and popouts show and the Currency picker selects; see `StripeSnapshot.displayCurrency`.
    var stripeDisplayCurrency: String {
        stripeSnapshot?.displayCurrency(for: stripeCurrency) ?? stripeCurrency
    }
}

struct StripeHTTPResponse: Sendable {
    var statusCode: Int
    var data: Data
}

protocol StripeDataTransport: Sendable {
    func response(for request: URLRequest) async throws -> StripeHTTPResponse
}

struct URLSessionStripeDataTransport: StripeDataTransport {
    private static let session = BoundedHTTPFetch.ephemeralSession()

    func response(for request: URLRequest) async throws -> StripeHTTPResponse {
        try AppRuntimeEnvironment.requireNetwork()
        do {
            let (data, response) = try await BoundedHTTPFetch.fetch(request, session: Self.session, maximumBytes: 5000000)
            return StripeHTTPResponse(statusCode: response.statusCode, data: data)
        } catch let error as BoundedHTTPFetchError {
            throw StripeDataError.transfer(error)
        }
    }
}

enum StripeDataError: LocalizedError {
    case missingKey
    case restrictedKeyRequired
    case invalidResponse
    case invalidRequest
    case missingPermission
    case rateLimited
    case paginationLimit
    case httpStatus(Int)
    case transfer(BoundedHTTPFetchError)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add a restricted Stripe API key in the Stripe widget."
        case .restrictedKeyRequired: "Stripe requires a restricted key beginning with rk_. Secret keys are not accepted."
        case .invalidResponse: "Stripe returned data MyDock could not read. Try again later."
        case .invalidRequest: "Stripe rejected the request. Check the key and its read permissions."
        case .missingPermission: "This Stripe key needs read access to \(StripeAPIKeyStore.requiredReadAccess)."
        case .rateLimited: "Stripe rate-limited the request. The last successful values are still shown."
        case .paginationLimit: "This Stripe account has more than \(StripeAPIProvider.recordBudget.formatted()) records of one kind for this period, more than MyDock loads in one refresh. MyDock did not use a partial total."
        case .httpStatus(let code): "Stripe is temporarily unavailable (HTTP \(code))."
        case .transfer(let error): error.message(provider: "Stripe")
        }
    }
}

struct StripeAPIProvider: Sendable {
    /// Requests pin the API version the parser and its fixtures model, so an account's default version cannot change the shapes read.
    static let apiVersion = "2025-03-31.basil"
    static let defaultMaximumPages = 10
    static let pageSize = 100
    /// Rows loaded per list before that list's metrics are reported as unavailable.
    static var recordBudget: Int { defaultMaximumPages * pageSize }
    /// Balance-transaction types that count as revenue. Each is listed separately so payouts, fees and transfers
    /// never use the budget.
    static let revenueTransactionTypes = ["charge", "refund", "payment", "payment_refund", "payment_reversal"]
    static let revenueMetrics: Set<StripeMetric> = [.revenue, .netAfterFees]
    static let subscriptionMetrics: Set<StripeMetric> = [.mrr, .arr, .payingSubscribers, .arpu]

    var transport: any StripeDataTransport = URLSessionStripeDataTransport()
    var maximumPages = StripeAPIProvider.defaultMaximumPages
    /// Subscriptions whose embedded item list is partial are completed through /v1/subscription_items, within this many expansions.
    var maximumItemExpansions = 20

    func snapshot(apiKey: String,
                  accountID: String,
                  accountName: String,
                  period: StripePeriod,
                  now: Date = .now,
                  calendar: Calendar = .current) async throws -> StripeSnapshot {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StripeDataError.missingKey }
        guard StripeAPIKeyStore.isRestrictedKey(key) else { throw StripeDataError.restrictedKeyRequired }

        let interval = period.interval(endingAt: now, calendar: calendar)
        let balanceData = try await get(path: "/v1/balance", parameters: [:], apiKey: key)
        // A list over budget makes only its own metrics unavailable; balance and the other list still publish.
        var unavailable: Set<StripeMetric> = []
        var transactionRows: [[String: Any]] = []
        do {
            for type in Self.revenueTransactionTypes {
                let rows = try await allRows(path: "/v1/balance_transactions",
                                             parameters: ["type": type,
                                                          "created[gte]": String(Int(interval.start.timeIntervalSince1970)),
                                                          "created[lte]": String(Int(interval.end.timeIntervalSince1970))],
                                             apiKey: key)
                transactionRows.append(contentsOf: rows)
            }
        } catch StripeDataError.paginationLimit {
            transactionRows = []
            unavailable.formUnion(Self.revenueMetrics)
        }
        var subscriptions: [[String: Any]] = []
        do {
            let activeSubscriptions = try await allRows(path: "/v1/subscriptions", parameters: ["status": "active"], apiKey: key)
            let pastDueSubscriptions = try await allRows(path: "/v1/subscriptions", parameters: ["status": "past_due"], apiKey: key)
            subscriptions = try await completingItems(activeSubscriptions + pastDueSubscriptions, apiKey: key)
        } catch StripeDataError.paginationLimit {
            subscriptions = []
            unavailable.formUnion(Self.subscriptionMetrics)
        }
        return try StripeSnapshotParser.snapshot(accountID: accountID,
                                                 accountName: accountName,
                                                 balanceData: balanceData,
                                                 transactionRows: transactionRows,
                                                 subscriptionRows: subscriptions,
                                                 period: period,
                                                 interval: interval,
                                                 now: now,
                                                 unavailableMetrics: unavailable)
    }

    /// The Stripe account ID behind a key, or nil when it cannot be determined (for example without Account read access).
    func accountIdentity(apiKey: String) async -> String? {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard StripeAPIKeyStore.isRestrictedKey(key),
              let data = try? await get(path: "/v1/account", parameters: [:], apiKey: key),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let id = root["id"] as? String, id.hasPrefix("acct_") else { return nil }
        return id
    }

    func validate(apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StripeDataError.missingKey }
        guard StripeAPIKeyStore.isRestrictedKey(key) else { throw StripeDataError.restrictedKeyRequired }
        _ = try await get(path: "/v1/balance", parameters: [:], apiKey: key)
        _ = try await get(path: "/v1/subscriptions", parameters: ["status": "active", "limit": "1"], apiKey: key)
    }

    /// Embedded `items` lists are independently paginated. Fetch the rest within budget; anything still
    /// partial keeps `has_more` so the parser counts it as unsupported instead of undercounting.
    func completingItems(_ subscriptions: [[String: Any]], apiKey: String) async throws -> [[String: Any]] {
        var remainingExpansions = max(0, maximumItemExpansions)
        var result: [[String: Any]] = []
        for var subscription in subscriptions {
            guard var items = subscription["items"] as? [String: Any], items["has_more"] as? Bool == true,
                  let id = subscription["id"] as? String, !id.isEmpty, remainingExpansions > 0 else {
                result.append(subscription)
                continue
            }
            remainingExpansions -= 1
            do {
                items["data"] = try await allRows(path: "/v1/subscription_items", parameters: ["subscription": id], apiKey: apiKey)
                items["has_more"] = false
                subscription["items"] = items
            } catch StripeDataError.paginationLimit {
                // Left partial on purpose.
            }
            result.append(subscription)
        }
        return result
    }

    private func allRows(path: String, parameters: [String: String], apiKey: String) async throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        var cursor: String?
        for _ in 0..<max(1, maximumPages) {
            var pageParameters = parameters
            pageParameters["limit"] = String(Self.pageSize)
            if let cursor { pageParameters["starting_after"] = cursor }
            let data = try await get(path: path, parameters: pageParameters, apiKey: apiKey)
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rows = root["data"] as? [[String: Any]],
                  let hasMore = root["has_more"] as? Bool else { throw StripeDataError.invalidResponse }
            result.append(contentsOf: rows)
            if !hasMore { return result }
            guard let nextCursor = rows.last?["id"] as? String, !nextCursor.isEmpty, nextCursor != cursor else {
                throw StripeDataError.invalidResponse
            }
            cursor = nextCursor
        }
        // Every page in the budget had more rows after it.
        throw StripeDataError.paginationLimit
    }

    private func get(path: String, parameters: [String: String], apiKey: String) async throws -> Data {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.stripe.com"
        components.path = path
        components.queryItems = parameters.keys.sorted().compactMap { key in
            parameters[key].map { URLQueryItem(name: key, value: $0) }
        }
        guard let url = components.url else { throw StripeDataError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Stripe-Version")
        let response = try await transport.response(for: request)
        switch response.statusCode {
        case 200..<300: return response.data
        case 401: throw StripeDataError.invalidRequest
        case 403: throw StripeDataError.missingPermission
        case 429: throw StripeDataError.rateLimited
        default: throw StripeDataError.httpStatus(response.statusCode)
        }
    }
}

enum StripeSnapshotParser {
    private struct Totals {
        var revenue = Decimal.zero
        var net = Decimal.zero
        var mrr = Decimal.zero
        var payingCustomers: Set<String> = []
        var available = Decimal.zero
        var pending = Decimal.zero
    }

    static func snapshot(accountID: String,
                         accountName: String,
                         balanceData: Data,
                         transactionRows: [[String: Any]],
                         subscriptionRows: [[String: Any]],
                         period: StripePeriod,
                         interval: DateInterval,
                         now: Date = .now,
                         unavailableMetrics: Set<StripeMetric> = []) throws -> StripeSnapshot {
        guard let balance = try object(balanceData), !accountID.isEmpty else {
            throw StripeDataError.invalidResponse
        }

        var totals: [String: Totals] = [:]
        func ensure(_ currency: String) -> String? {
            let code = currency.uppercased()
            guard validCurrency(code) else { return nil }
            if totals[code] == nil { totals[code] = Totals() }
            return code
        }
        func addAmounts(from rows: Any?, into keyPath: WritableKeyPath<Totals, Decimal>) {
            guard let rows = rows as? [[String: Any]] else { return }
            for row in rows {
                guard let code = row["currency"] as? String,
                      let normalized = ensure(code),
                      let amount = decimal(row["amount"]) else { continue }
                totals[normalized, default: Totals()][keyPath: keyPath] += amount
            }
        }
        addAmounts(from: balance["available"], into: \.available)
        addAmounts(from: balance["pending"], into: \.pending)

        for row in transactionRows {
            guard let created = number(row["created"]),
                  interval.start.timeIntervalSince1970 <= created,
                  created <= interval.end.timeIntervalSince1970,
                  let type = row["type"] as? String,
                  StripeAPIProvider.revenueTransactionTypes.contains(type),
                  let currency = row["currency"] as? String,
                  let code = ensure(currency),
                  let amount = decimal(row["amount"]),
                  let net = decimal(row["net"]) else { continue }
            totals[code, default: Totals()].revenue += amount
            totals[code, default: Totals()].net += net
        }

        var unsupportedItems = 0
        for subscription in subscriptionRows where ["active", "past_due"].contains(subscription["status"] as? String ?? "") {
            guard let customer = stringID(subscription["customer"]) else { continue }
            let itemList = subscription["items"] as? [String: Any]
            let items = itemList?["data"] as? [[String: Any]] ?? []
            if itemList?["has_more"] as? Bool == true {
                // A partial embedded list cannot yield a complete total; flag it rather than undercount.
                unsupportedItems += max(1, items.count)
                continue
            }
            let discountList = subscription["discounts"] as? [Any] ?? []
            let defaultTaxRates = subscription["default_tax_rates"] as? [Any] ?? []
            let automaticTaxEnabled = ((subscription["automatic_tax"] as? [String: Any])?["enabled"] as? Bool) == true
            let legacyDiscount = subscription["discount"] as? [String: Any] != nil
            if !discountList.isEmpty || !defaultTaxRates.isEmpty || automaticTaxEnabled || legacyDiscount {
                unsupportedItems += max(1, items.count)
                continue
            }
            for item in items {
                if !(item["discounts"] as? [Any] ?? []).isEmpty {
                    unsupportedItems += 1
                    continue
                }
                let price = item["price"] as? [String: Any] ?? item["plan"] as? [String: Any]
                guard let price, let recurring = price["recurring"] as? [String: Any] else { continue }
                let scheme = price["billing_scheme"] as? String ?? "per_unit"
                let usage = recurring["usage_type"] as? String ?? "licensed"
                guard scheme == "per_unit", usage == "licensed",
                      let amount = decimal(price["unit_amount_decimal"] ?? price["unit_amount"]),
                      let currency = price["currency"] as? String,
                      let code = ensure(currency),
                      let intervalName = recurring["interval"] as? String else {
                    unsupportedItems += 1
                    continue
                }
                let rawCount = number(recurring["interval_count"]) ?? 1
                let rawQuantity = item["quantity"] == nil ? Decimal(1) : decimal(item["quantity"])
                guard rawCount.isFinite, (1...maximumIntervalCount).contains(rawCount.rounded(.towardZero)),
                      let rawQuantity, rawQuantity <= maximumQuantity,
                      let normalizedMRR = monthlyAmount(max(Decimal.zero, amount) * max(Decimal.zero, rawQuantity),
                                                        interval: intervalName, intervalCount: Int(rawCount)) else {
                    unsupportedItems += 1
                    continue
                }
                totals[code, default: Totals()].mrr += normalizedMRR
                if normalizedMRR > 0 { totals[code, default: Totals()].payingCustomers.insert(customer) }
            }
        }

        let currencies = totals.map { code, value in
            StripeCurrencyMetrics(currency: code,
                                  revenueMinor: value.revenue,
                                  netAfterFeesMinor: value.net,
                                  mrrMinor: value.mrr,
                                  payingSubscribers: value.payingCustomers.count,
                                  availableBalanceMinor: value.available,
                                  pendingBalanceMinor: value.pending)
        }.sorted { $0.currency < $1.currency }
        return StripeSnapshot(accountID: accountID,
                              accountName: String(accountName.prefix(120)),
                              fetchedAt: now,
                              period: period,
                              periodStart: interval.start,
                              periodEnd: interval.end,
                              currencies: currencies,
                              unsupportedSubscriptionItems: unsupportedItems,
                              unavailableMetrics: unavailableMetrics.isEmpty ? nil : unavailableMetrics)
    }

    private static func monthlyAmount(_ amount: Decimal, interval: String, intervalCount: Int) -> Decimal? {
        guard (1...Int(maximumIntervalCount)).contains(intervalCount), amount.isFinite else { return nil }
        let divisor: Decimal
        let multiplier: Decimal
        switch interval {
        case "month": divisor = Decimal(intervalCount); multiplier = 1
        case "year": divisor = Decimal(intervalCount * 12); multiplier = 1
        case "week": divisor = Decimal(intervalCount * 12); multiplier = 52
        case "day": divisor = Decimal(intervalCount * 12); multiplier = Decimal(string: "365.25") ?? 365
        default: return nil
        }
        var source = amount * multiplier
        var denominator = divisor
        var result = Decimal.zero
        guard source.isFinite, NSDecimalDivide(&result, &source, &denominator, .bankers) == .noError, result.isFinite else { return nil }
        return result
    }

    private static func object(_ data: Data) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// Provider values outside this domain are treated as unusable instead of overflowing later arithmetic.
    static let maximumAmount = Decimal(string: "1000000000000000") ?? 1_000_000_000_000_000
    static let maximumQuantity = Decimal(1_000_000)
    static let maximumIntervalCount = 1_000.0

    private static func decimal(_ value: Any?) -> Decimal? {
        let parsed: Decimal?
        if let string = value as? String { parsed = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) }
        else if let number = value as? NSNumber { parsed = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite, abs(parsed) <= maximumAmount else { return nil }
        return parsed
    }

    private static func number(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func stringID(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        return (value as? [String: Any])?["id"] as? String
    }

    private static func validCurrency(_ currency: String) -> Bool {
        currency.count == 3 && currency.unicodeScalars.allSatisfy { currencyLetters.contains($0) }
    }

    private static let currencyLetters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
}

enum StripeAPIKeyStore {
    /// The read permissions a restricted key needs, shared by the setup copy and the missing-permission error.
    static let requiredReadAccess = "Account, Balance, Balance Transactions, and Subscriptions"
    fileprivate static let directoryKey = Product.bundleIdentifier + ".stripe-connected-accounts"

    static func isRestrictedKey(_ value: String) -> Bool {
        value.hasPrefix("rk_") && value.count > 3 && value.count <= 200 && !value.contains { $0.isWhitespace }
    }

    static func read(accountID: String) throws -> String? {
        guard let data = try item(accountID).readData(credential: credentialName) else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { throw IntegrationKeychainError(credential: credentialName, operation: .read, status: errSecDecode) }
        return value
    }

    static func write(_ value: String, accountID: String) throws {
        try AppRuntimeEnvironment.requireCredentials()
        guard isRestrictedKey(value) else { throw StripeDataError.restrictedKeyRequired }
        try item(accountID).write(Data(value.utf8), credential: credentialName)
    }

    static func delete(accountID: String) throws {
        try item(accountID).delete(credential: credentialName)
    }

    private static let credentialName = "The Stripe key"

    private static func item(_ accountID: String) -> IntegrationKeychainItem {
        IntegrationKeychainItem(account: "stripe.\(accountID)")
    }
}

struct StripeConnectedAccount: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var color: String

    init(id: String = UUID().uuidString, name: String, color: String) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.color = DockProfileColor(rawValue: color) == nil ? DockProfileColor.purple.rawValue : color
    }
}

enum StripeConnectionDirectory {
    private static var directory: ConnectionDirectory<StripeConnectedAccount> { .init(defaultsKey: StripeAPIKeyStore.directoryKey) }

    static func accounts(defaults: UserDefaults = AppRuntimeEnvironment.defaults) -> [StripeConnectedAccount] {
        directory.entries(defaults: defaults)
    }

    static func save(_ account: StripeConnectedAccount, key: String, defaults: UserDefaults = AppRuntimeEnvironment.defaults) throws {
        try StripeAPIKeyStore.write(key, accountID: account.id)
        directory.insert(account, defaults: defaults)
    }

    static func update(_ account: StripeConnectedAccount, defaults: UserDefaults = AppRuntimeEnvironment.defaults) {
        directory.update(account, defaults: defaults)
    }

    static func remove(accountID: String, defaults: UserDefaults = AppRuntimeEnvironment.defaults) throws {
        try StripeAPIKeyStore.delete(accountID: accountID)
        directory.remove(id: accountID, defaults: defaults)
    }
}
