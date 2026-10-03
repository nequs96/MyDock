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
        return netAfterFeesMinorDecimalDivide(mrrMinor, by: Decimal(payingSubscribers))
    }

    private func netAfterFeesMinorDecimalDivide(_ value: Decimal, by divisor: Decimal) -> Decimal {
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

    var currencyCodes: [String] { currencies.map(\.currency).sorted() }

    func metrics(for currency: String) -> StripeCurrencyMetrics? {
        currencies.first { $0.currency == currency.uppercased() }
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
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func response(for request: URLRequest) async throws -> StripeHTTPResponse {
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 5_000_000 else {
            throw StripeDataError.invalidResponse
        }
        return StripeHTTPResponse(statusCode: response.statusCode, data: data)
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

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add a restricted Stripe API key in the Stripe widget."
        case .restrictedKeyRequired: "Stripe requires a restricted key beginning with rk_. Secret keys are not accepted."
        case .invalidResponse: "Stripe returned data MyDock could not read. Try again later."
        case .invalidRequest: "Stripe rejected the request. Check the key and its read permissions."
        case .missingPermission: "This Stripe key needs read access for Core → Balance and Billing → Subscriptions."
        case .rateLimited: "Stripe rate-limited the request. The last successful values are still shown."
        case .paginationLimit: "This Stripe account has more records than MyDock can safely load in one refresh. MyDock did not use a partial total."
        case .httpStatus(let code): "Stripe is temporarily unavailable (HTTP \(code))."
        }
    }
}

struct StripeAPIProvider: Sendable {
    var transport: any StripeDataTransport = URLSessionStripeDataTransport()
    var maximumPages = 10

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
        let transactionRows = try await allRows(path: "/v1/balance_transactions",
                                                parameters: ["created[gte]": String(Int(interval.start.timeIntervalSince1970)),
                                                             "created[lte]": String(Int(interval.end.timeIntervalSince1970))],
                                                apiKey: key)
        let activeSubscriptions = try await allRows(path: "/v1/subscriptions", parameters: ["status": "active"], apiKey: key)
        let pastDueSubscriptions = try await allRows(path: "/v1/subscriptions", parameters: ["status": "past_due"], apiKey: key)
        return try StripeSnapshotParser.snapshot(accountID: accountID,
                                                 accountName: accountName,
                                                 balanceData: balanceData,
                                                 transactionRows: transactionRows,
                                                 subscriptionRows: activeSubscriptions + pastDueSubscriptions,
                                                 period: period,
                                                 interval: interval,
                                                 now: now)
    }

    func validate(apiKey: String) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw StripeDataError.missingKey }
        guard StripeAPIKeyStore.isRestrictedKey(key) else { throw StripeDataError.restrictedKeyRequired }
        _ = try await get(path: "/v1/balance", parameters: [:], apiKey: key)
        _ = try await get(path: "/v1/subscriptions", parameters: ["status": "active", "limit": "1"], apiKey: key)
    }

    private func allRows(path: String, parameters: [String: String], apiKey: String) async throws -> [[String: Any]] {
        var result: [[String: Any]] = []
        var cursor: String?
        for pageIndex in 0..<max(1, maximumPages) {
            var pageParameters = parameters
            pageParameters["limit"] = "100"
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
            if pageIndex == max(1, maximumPages) - 1 { throw StripeDataError.paginationLimit }
        }
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
                         now: Date = .now) throws -> StripeSnapshot {
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
                  ["charge", "refund", "payment", "payment_refund", "payment_reversal"].contains(type),
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
            let items = (subscription["items"] as? [String: Any])?["data"] as? [[String: Any]] ?? []
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
                let count = max(1, Int(number(recurring["interval_count"]) ?? 1))
                let quantity = max(Decimal.zero, decimal(item["quantity"]) ?? Decimal(1))
                guard let normalizedMRR = monthlyAmount(amount * quantity, interval: intervalName, intervalCount: count) else {
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
                              unsupportedSubscriptionItems: unsupportedItems)
    }

    private static func monthlyAmount(_ amount: Decimal, interval: String, intervalCount: Int) -> Decimal? {
        guard intervalCount > 0 else { return nil }
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
        _ = NSDecimalDivide(&result, &source, &denominator, .bankers)
        return result
    }

    private static func object(_ data: Data) throws -> [String: Any]? {
        try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let string = value as? String { return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) }
        if let number = value as? NSNumber { return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")) }
        return nil
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
        currency.count == 3 && currency.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }
    }
}

enum StripeAPIKeyStore {
    private static var service: String { Product.bundleIdentifier + ".integration-credentials" }
    private static let directoryKey = Product.bundleIdentifier + ".stripe-connected-accounts"

    static func isRestrictedKey(_ value: String) -> Bool {
        value.hasPrefix("rk_") && value.count > 3 && value.count <= 200 && !value.contains { $0.isWhitespace }
    }

    static func read(accountID: String) throws -> String? {
        guard AppRuntimeEnvironment.allowsCredentials else { return nil }
        var query = baseQuery(accountID: accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError(status) }
        return value
    }

    static func write(_ value: String, accountID: String) throws {
        try AppRuntimeEnvironment.requireCredentials()
        guard isRestrictedKey(value) else { throw StripeDataError.restrictedKeyRequired }
        let data = Data(value.utf8)
        let query = baseQuery(accountID: accountID)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }
    }

    static func delete(accountID: String) throws {
        try AppRuntimeEnvironment.requireCredentials()
        let status = SecItemDelete(baseQuery(accountID: accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private static func baseQuery(accountID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "stripe.\(accountID)"]
    }

    private struct KeychainError: LocalizedError {
        var status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "The Stripe key could not be saved in Keychain (\(status))." }
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
    static func accounts(defaults: UserDefaults = AppRuntimeEnvironment.defaults) -> [StripeConnectedAccount] {
        guard let data = defaults.data(forKey: StripeAPIKeyStore.directoryKeyForDirectory),
              let accounts = try? JSONDecoder().decode([StripeConnectedAccount].self, from: data) else { return [] }
        return accounts
    }

    static func save(_ account: StripeConnectedAccount, key: String, defaults: UserDefaults = AppRuntimeEnvironment.defaults) throws {
        try StripeAPIKeyStore.write(key, accountID: account.id)
        var accounts = self.accounts(defaults: defaults)
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: StripeAPIKeyStore.directoryKeyForDirectory)
        }
    }

    static func update(_ account: StripeConnectedAccount, defaults: UserDefaults = AppRuntimeEnvironment.defaults) {
        var accounts = self.accounts(defaults: defaults)
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: StripeAPIKeyStore.directoryKeyForDirectory)
        }
    }

    static func remove(accountID: String, defaults: UserDefaults = AppRuntimeEnvironment.defaults) throws {
        try StripeAPIKeyStore.delete(accountID: accountID)
        let remaining = accounts(defaults: defaults).filter { $0.id != accountID }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: StripeAPIKeyStore.directoryKeyForDirectory)
        }
    }
}

private extension StripeAPIKeyStore {
    static var directoryKeyForDirectory: String { directoryKey }
}
