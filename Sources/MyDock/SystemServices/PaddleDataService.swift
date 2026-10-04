import Foundation
import Security

enum PaddleMetric: String, Codable, CaseIterable, Identifiable {
    case netRevenue
    case mrr
    case arr
    case activeSubscribers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .netRevenue: "Net revenue"
        case .mrr: "MRR"
        case .arr: "ARR"
        case .activeSubscribers: "Active subscribers"
        }
    }
}

enum PaddlePeriod: String, Codable, CaseIterable, Identifiable {
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

    var dayCount: Int {
        switch self {
        case .today: 1
        case .sevenDays: 7
        case .thirtyDays: 30
        case .ninetyDays: 90
        }
    }

    func utcBounds(endingAt now: Date) -> (from: Date, to: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -(dayCount - 1), to: today) ?? today
        let to = calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
        return (from, to)
    }
}

struct PaddleMetricPoint: Codable, Hashable, Identifiable {
    var date: Date
    var netRevenueMinor: Decimal
    var mrrMinor: Decimal
    var activeSubscribers: Int
    var id: Date { date }
}

struct PaddleSnapshot: Codable, Hashable {
    var accountID: String
    var accountName: String
    var fetchedAt: Date
    var period: PaddlePeriod
    var currency: String
    var points: [PaddleMetricPoint]
    var updatedAt: Date

    var latest: PaddleMetricPoint? { points.last }
    var totalNetRevenueMinor: Decimal { points.reduce(.zero) { $0 + $1.netRevenueMinor } }
    var latestMRRMinor: Decimal { latest?.mrrMinor ?? .zero }
    var latestARRMinor: Decimal { latestMRRMinor * 12 }
    var latestActiveSubscribers: Int { latest?.activeSubscribers ?? 0 }
}

struct PaddleHTTPResponse: Sendable {
    var statusCode: Int
    var data: Data
}

protocol PaddleDataTransport: Sendable {
    func response(for request: URLRequest) async throws -> PaddleHTTPResponse
}

struct URLSessionPaddleDataTransport: PaddleDataTransport {
    private static let session = BoundedHTTPFetch.ephemeralSession()

    func response(for request: URLRequest) async throws -> PaddleHTTPResponse {
        try AppRuntimeEnvironment.requireNetwork()
        do {
            let (data, response) = try await BoundedHTTPFetch.fetch(request, session: Self.session, maximumBytes: 5000000)
            return PaddleHTTPResponse(statusCode: response.statusCode, data: data)
        } catch is BoundedHTTPFetchError {
            throw PaddleDataError.invalidResponse
        }
    }
}

enum PaddleDataError: LocalizedError {
    case missingKey
    case billingKeyRequired
    case invalidResponse
    case invalidRequest
    case missingPermission
    case expiredOrRevoked
    case rateLimited
    case currencyMismatch
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Connect a Paddle Billing account in the Paddle widget."
        case .billingKeyRequired: "Use a current Paddle Billing API key beginning with pdl_live_apikey_ or pdl_sdbx_apikey_. Paddle Classic and client-side tokens are not supported."
        case .invalidResponse: "Paddle returned metrics MyDock could not read. The last successful values are still shown."
        case .invalidRequest: "Paddle rejected the metrics request. Check that the key is current and uses the Billing API."
        case .missingPermission: "This Paddle API key needs Metrics → Read (metrics.read) permission."
        case .expiredOrRevoked: "This Paddle API key is invalid, expired, or revoked. Create a new Billing API key and reconnect."
        case .rateLimited: "Paddle rate-limited the request. The last successful values are still shown."
        case .currencyMismatch: "Paddle returned metrics in different primary balance currencies. MyDock kept the last successful snapshot."
        case .httpStatus(let code): "Paddle is temporarily unavailable (HTTP \(code))."
        }
    }
}

struct PaddleAPIProvider: Sendable {
    var transport: any PaddleDataTransport = URLSessionPaddleDataTransport()

    func snapshot(apiKey: String,
                  accountID: String,
                  accountName: String,
                  period: PaddlePeriod,
                  now: Date = .now) async throws -> PaddleSnapshot {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PaddleDataError.missingKey }
        guard PaddleAPIKeyStore.isBillingKey(key) else { throw PaddleDataError.billingKeyRequired }
        let bounds = period.utcBounds(endingAt: now)
        let from = Self.dateString(bounds.from)
        let to = Self.dateString(bounds.to)
        async let revenueData = get(path: "/metrics/revenue", from: from, to: to, apiKey: key)
        async let mrrData = get(path: "/metrics/monthly-recurring-revenue", from: from, to: to, apiKey: key)
        async let subscriberData = get(path: "/metrics/active-subscribers", from: from, to: to, apiKey: key)
        let (revenue, mrr, subscribers) = try await (revenueData, mrrData, subscriberData)
        return try PaddleMetricsParser.snapshot(revenueData: revenue,
                                               mrrData: mrr,
                                               subscriberData: subscribers,
                                               accountID: accountID,
                                               accountName: accountName,
                                               period: period,
                                               now: now)
    }

    func validate(apiKey: String, now: Date = .now) async throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw PaddleDataError.missingKey }
        guard PaddleAPIKeyStore.isBillingKey(key) else { throw PaddleDataError.billingKeyRequired }
        let date = Self.dateString(now)
        _ = try await get(path: "/metrics/revenue", from: date, to: Self.nextDateString(now), apiKey: key)
    }

    private func get(path: String, from: String, to: String, apiKey: String) async throws -> Data {
        let isSandbox = apiKey.hasPrefix("pdl_sdbx_")
        var components = URLComponents()
        components.scheme = "https"
        components.host = isSandbox ? "sandbox-api.paddle.com" : "api.paddle.com"
        components.path = path
        components.queryItems = [URLQueryItem(name: "from", value: from), URLQueryItem(name: "to", value: to)]
        guard let url = components.url else { throw PaddleDataError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 25
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("1", forHTTPHeaderField: "Paddle-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.response(for: request)
        switch response.statusCode {
        case 200..<300: return response.data
        case 401: throw PaddleDataError.expiredOrRevoked
        case 403: throw PaddleDataError.missingPermission
        case 429: throw PaddleDataError.rateLimited
        case 400: throw PaddleDataError.invalidRequest
        default: throw PaddleDataError.httpStatus(response.statusCode)
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func nextDateString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return dateString(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400))
    }
}

enum PaddleMetricsParser {
    private struct AmountSeries {
        var currency: String
        var updatedAt: Date
        var values: [Date: Decimal]
    }

    private struct CountSeries {
        var updatedAt: Date
        var values: [Date: Int]
    }

    static func snapshot(revenueData: Data,
                         mrrData: Data,
                         subscriberData: Data,
                         accountID: String,
                         accountName: String,
                         period: PaddlePeriod,
                         now: Date = .now) throws -> PaddleSnapshot {
        let revenue = try amountSeries(from: revenueData)
        let mrr = try amountSeries(from: mrrData)
        let subscribers = try countSeries(from: subscriberData)
        guard revenue.currency == mrr.currency else { throw PaddleDataError.currencyMismatch }
        let dates = Set(revenue.values.keys).union(mrr.values.keys).union(subscribers.values.keys).sorted()
        guard !dates.isEmpty,
              dates.count == revenue.values.count,
              dates.count == mrr.values.count,
              dates.count == subscribers.values.count,
              !accountID.isEmpty else { throw PaddleDataError.invalidResponse }
        let points = dates.map { date in
            PaddleMetricPoint(date: date,
                              netRevenueMinor: revenue.values[date] ?? .zero,
                              mrrMinor: mrr.values[date] ?? .zero,
                              activeSubscribers: subscribers.values[date] ?? 0)
        }
        return PaddleSnapshot(accountID: accountID,
                              accountName: String(accountName.prefix(80)),
                              fetchedAt: now,
                              period: period,
                              currency: revenue.currency,
                              points: points,
                              updatedAt: min(revenue.updatedAt, min(mrr.updatedAt, subscribers.updatedAt)))
    }

    private static func amountSeries(from data: Data) throws -> AmountSeries {
        let dataObject = try metricData(from: data)
        guard let currency = dataObject["currency_code"] as? String,
              validCurrency(currency),
              let rows = dataObject["timeseries"] as? [[String: Any]],
              let updatedAt = date(dataObject["updated_at"] as? String) else { throw PaddleDataError.invalidResponse }
        var values: [Date: Decimal] = [:]
        for row in rows {
            guard let timestamp = date(row["timestamp"] as? String),
                  let amount = decimal(row["amount"]) else { throw PaddleDataError.invalidResponse }
            values[dayStart(timestamp), default: .zero] += amount
        }
        return AmountSeries(currency: currency.uppercased(), updatedAt: updatedAt, values: values)
    }

    private static func countSeries(from data: Data) throws -> CountSeries {
        let dataObject = try metricData(from: data)
        guard let rows = dataObject["timeseries"] as? [[String: Any]],
              let updatedAt = date(dataObject["updated_at"] as? String) else { throw PaddleDataError.invalidResponse }
        var values: [Date: Int] = [:]
        for row in rows {
            guard let timestamp = date(row["timestamp"] as? String),
                  let count = number(row["count"]), count.isFinite, (0...maximumCount).contains(count) else { throw PaddleDataError.invalidResponse }
            values[dayStart(timestamp)] = Int(count)
        }
        return CountSeries(updatedAt: updatedAt, values: values)
    }

    private static func metricData(from data: Data) throws -> [String: Any] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = root["data"] as? [String: Any] else { throw PaddleDataError.invalidResponse }
        return value
    }

    /// Values outside these domains reject the response so the last good snapshot is kept.
    static let maximumAmount = Decimal(string: "1000000000000000") ?? 1_000_000_000_000_000
    static let maximumCount = 1_000_000_000.0

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

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func dayStart(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.startOfDay(for: date)
    }

    private static func validCurrency(_ currency: String) -> Bool {
        currency.count == 3 && currency.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ").contains($0) }
    }
}

struct PaddleConnectedAccount: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var color: String

    init(id: String = UUID().uuidString, name: String, color: String) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.color = DockProfileColor(rawValue: color) == nil ? DockProfileColor.blue.rawValue : color
    }
}

enum PaddleAPIKeyStore {
    /// One provider-owned explanation shared by Connections Center and the Paddle widget help.
    static let permissionSetupCopy = "Paddle Billing: create a Billing API key with Metrics → Read (metrics.read). Both live and sandbox keys are supported."

    private static var service: String { Product.bundleIdentifier + ".integration-credentials" }
    fileprivate static var directoryKey: String { Product.bundleIdentifier + ".paddle-connected-accounts" }

    static func isBillingKey(_ value: String) -> Bool {
        value.range(of: #"^pdl_(live|sdbx)_apikey_[a-z\d]{26}_[a-zA-Z\d]{22}_[a-zA-Z\d]{3}$"#,
                    options: .regularExpression) != nil
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
        guard isBillingKey(value) else { throw PaddleDataError.billingKeyRequired }
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
         kSecAttrAccount as String: "paddle.\(accountID)"]
    }

    private struct KeychainError: LocalizedError {
        var status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "The Paddle key could not be saved in Keychain (\(status))." }
    }
}

enum PaddleConnectionDirectory {
    static func accounts(defaults: UserDefaults = AppRuntimeEnvironment.defaults) -> [PaddleConnectedAccount] {
        guard let data = defaults.data(forKey: PaddleAPIKeyStore.directoryKey),
              let accounts = try? JSONDecoder().decode([PaddleConnectedAccount].self, from: data) else { return [] }
        return accounts
    }

    static func save(_ account: PaddleConnectedAccount, key: String, defaults: UserDefaults = AppRuntimeEnvironment.defaults) throws {
        try PaddleAPIKeyStore.write(key, accountID: account.id)
        var accounts = self.accounts(defaults: defaults)
        accounts.removeAll { $0.id == account.id }
        accounts.append(account)
        if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: PaddleAPIKeyStore.directoryKey) }
    }

    static func update(_ account: PaddleConnectedAccount, defaults: UserDefaults = AppRuntimeEnvironment.defaults) {
        var accounts = self.accounts(defaults: defaults)
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        if let data = try? JSONEncoder().encode(accounts) { defaults.set(data, forKey: PaddleAPIKeyStore.directoryKey) }
    }

    static func remove(accountID: String, defaults: UserDefaults = AppRuntimeEnvironment.defaults) throws {
        try PaddleAPIKeyStore.delete(accountID: accountID)
        let remaining = accounts(defaults: defaults).filter { $0.id != accountID }
        if let data = try? JSONEncoder().encode(remaining) { defaults.set(data, forKey: PaddleAPIKeyStore.directoryKey) }
    }
}
