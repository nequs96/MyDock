import Foundation
import Security

enum ShopifyMetric: String, Codable, CaseIterable, Identifiable {
    case orderValue
    case orders
    case averageOrderValue

    var id: String { rawValue }
    var title: String {
        switch self {
        case .orderValue: "Order value"
        case .orders: "Orders"
        case .averageOrderValue: "Average order value"
        }
    }
}

enum ShopifyPeriod: String, Codable, CaseIterable, Identifiable {
    case today
    case sevenDays
    case monthToDate
    case thirtyDays

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "Last 7 days"
        case .monthToDate: "Month to date"
        case .thirtyDays: "Last 30 days"
        }
    }

    func interval(endingAt now: Date, timeZoneID: String) throws -> DateInterval {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { throw ShopifyDataError.invalidStore }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let startOfToday = calendar.startOfDay(for: now)
        let start: Date
        switch self {
        case .today:
            start = startOfToday
        case .sevenDays:
            start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday.addingTimeInterval(-6 * 86_400)
        case .monthToDate:
            start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? startOfToday
        case .thirtyDays:
            start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday.addingTimeInterval(-29 * 86_400)
        }
        return DateInterval(start: start, end: now)
    }
}

struct ShopifyDailyPoint: Codable, Hashable, Identifiable {
    var date: Date
    var orderValue: Decimal
    var orders: Int
    var id: Date { date }
}

struct ShopifyBreakdownEntry: Codable, Hashable, Identifiable {
    var name: String
    var units: Int
    var orders: Int
    var id: String { name }
}

struct ShopifySnapshot: Codable, Hashable {
    var storeID: String
    var storeName: String
    var storeDomain: String
    var fetchedAt: Date
    var period: ShopifyPeriod
    var periodStart: Date
    var periodEnd: Date
    var timeZoneID: String
    var currency: String
    var orderValue: Decimal
    var orderCount: Int
    var dailyPoints: [ShopifyDailyPoint]
    var productBreakdown: [ShopifyBreakdownEntry]
    var trafficBreakdown: [ShopifyBreakdownEntry]
    var productBreakdownIncompleteOrders: Int
    var trafficAttributedOrders: Int

    var averageOrderValue: Decimal? {
        guard orderCount > 0 else { return nil }
        var value = orderValue
        var divisor = Decimal(orderCount)
        var result = Decimal.zero
        guard NSDecimalDivide(&result, &value, &divisor, .bankers) == .noError else { return nil }
        return result
    }
}

struct ShopifyCredential: Codable, Hashable {
    var clientID: String
    var clientSecret: String
    var accessToken: String
    var tokenExpiresAt: Date
}

enum ShopifyCredentialUpdatePolicy {
    static func mayRefresh(original: ShopifyCredential, current: ShopifyCredential?, registered: Bool, cancelled: Bool) -> Bool {
        registered && !cancelled && current?.clientID == original.clientID && current?.clientSecret == original.clientSecret
    }
}

struct ShopifyConnectedStore: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var domain: String
    var timeZoneID: String
    var currency: String
    var color: String

    init(id: String = UUID().uuidString, name: String, domain: String, timeZoneID: String, currency: String, color: String) {
        self.id = id
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        self.domain = domain
        self.timeZoneID = TimeZone(identifier: timeZoneID) == nil ? "UTC" : timeZoneID
        self.currency = currency.uppercased()
        self.color = DockProfileColor(rawValue: color) == nil ? DockProfileColor.green.rawValue : color
    }
}

struct ShopifyHTTPResponse: Sendable {
    var statusCode: Int
    var data: Data
}

protocol ShopifyDataTransport: Sendable {
    func response(for request: URLRequest) async throws -> ShopifyHTTPResponse
}

struct URLSessionShopifyDataTransport: ShopifyDataTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    func response(for request: URLRequest) async throws -> ShopifyHTTPResponse {
        let (data, response) = try await Self.session.data(for: request)
        guard let response = response as? HTTPURLResponse, data.count <= 8_000_000 else {
            throw ShopifyDataError.invalidResponse
        }
        return ShopifyHTTPResponse(statusCode: response.statusCode, data: data)
    }
}

enum ShopifyDataError: LocalizedError, Equatable {
    case invalidStore
    case invalidCredentials
    case missingPermission
    case invalidResponse
    case rateLimited
    case tooManyOrders
    case currencyMismatch
    case graphQLError(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidStore: "Enter the store's myshopify.com domain, such as example.myshopify.com."
        case .invalidCredentials: "Shopify could not authenticate these app credentials for this store. Confirm the app is installed and belongs to the same Shopify organization."
        case .missingPermission: "This Shopify app needs only the read_orders access scope."
        case .invalidResponse: "Shopify returned data MyDock could not read. The last successful values are still shown."
        case .rateLimited: "Shopify rate-limited the request. The last successful values are still shown."
        case .tooManyOrders: "This period contains more than 10,000 orders. MyDock did not calculate a partial total."
        case .currencyMismatch: "Shopify returned an order in a currency different from the store currency. MyDock did not combine currencies."
        case .graphQLError(let message): message
        case .httpStatus(let code): "Shopify is temporarily unavailable (HTTP \(code))."
        }
    }
}

struct ShopifyAPIProvider: Sendable {
    static let apiVersion = "2026-07"
    static let orderLimit = 10_000
    var transport: any ShopifyDataTransport = URLSessionShopifyDataTransport()
    var pageSize = 250
    var maximumOrders = Self.orderLimit

    struct Connection: Sendable {
        var store: ShopifyConnectedStore
        var credential: ShopifyCredential
    }

    func connect(domain: String, clientID: String, clientSecret: String, color: String) async throws -> Connection {
        let normalizedDomain = try Self.normalizedDomain(domain)
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { throw ShopifyDataError.invalidCredentials }
        let credential = try await accessToken(domain: normalizedDomain,
                                               clientID: id,
                                               clientSecret: secret)
        let metadata = try await shopMetadata(domain: normalizedDomain, token: credential.accessToken)
        let store = ShopifyConnectedStore(name: metadata.name,
                                          domain: normalizedDomain,
                                          timeZoneID: metadata.timeZoneID,
                                          currency: metadata.currency,
                                          color: color)
        return Connection(store: store, credential: credential)
    }

    func snapshot(store: ShopifyConnectedStore,
                  credential: ShopifyCredential,
                  period: ShopifyPeriod,
                  now: Date = .now) async throws -> (snapshot: ShopifySnapshot, credential: ShopifyCredential) {
        let domain = try Self.normalizedDomain(store.domain)
        let tokenCredential: ShopifyCredential
        if credential.tokenExpiresAt.timeIntervalSince(now) > 300, !credential.accessToken.isEmpty {
            tokenCredential = credential
        } else {
            tokenCredential = try await accessToken(domain: domain,
                                                    clientID: credential.clientID,
                                                    clientSecret: credential.clientSecret)
        }
        let interval = try period.interval(endingAt: now, timeZoneID: store.timeZoneID)
        let query = Self.searchQuery(from: interval.start, through: interval.end)
        var orders: [ShopifyOrderRecord] = []
        var after: String?
        repeat {
            let page = try await fetchOrders(domain: domain, token: tokenCredential.accessToken, query: query, after: after)
            orders.append(contentsOf: page.orders)
            if orders.count > maximumOrders { throw ShopifyDataError.tooManyOrders }
            if page.hasNextPage && orders.count >= maximumOrders { throw ShopifyDataError.tooManyOrders }
            after = page.endCursor
            if !page.hasNextPage { break }
            guard let next = after, !next.isEmpty else { throw ShopifyDataError.invalidResponse }
        } while orders.count < maximumOrders

        let snapshot = try ShopifySnapshotParser.snapshot(orders: orders,
                                                          store: store,
                                                          period: period,
                                                          interval: interval,
                                                          now: now)
        return (snapshot, tokenCredential)
    }

    private func accessToken(domain: String, clientID: String, clientSecret: String) async throws -> ShopifyCredential {
        guard let url = URL(string: "https://\(domain)/admin/oauth/access_token") else { throw ShopifyDataError.invalidStore }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "grant_type", value: "client_credentials"),
                                  URLQueryItem(name: "client_id", value: clientID),
                                  URLQueryItem(name: "client_secret", value: clientSecret)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
        let response = try await transport.response(for: request)
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: throw ShopifyDataError.invalidCredentials
        case 429: throw ShopifyDataError.rateLimited
        default: throw ShopifyDataError.httpStatus(response.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let token = root["access_token"] as? String, !token.isEmpty,
              let expiresIn = root["expires_in"] as? NSNumber else { throw ShopifyDataError.invalidResponse }
        return ShopifyCredential(clientID: clientID,
                                 clientSecret: clientSecret,
                                 accessToken: token,
                                 tokenExpiresAt: Date().addingTimeInterval(expiresIn.doubleValue))
    }

    private func shopMetadata(domain: String, token: String) async throws -> (name: String, timeZoneID: String, currency: String) {
        let data = try await graphQL(domain: domain,
                                     token: token,
                                     query: "query StoreMetadata { shop { name ianaTimezone currencyCode } }",
                                     variables: [:])
        guard let shop = data["shop"] as? [String: Any],
              let name = shop["name"] as? String,
              let zone = shop["ianaTimezone"] as? String,
              TimeZone(identifier: zone) != nil,
              let currency = shop["currencyCode"] as? String,
              currency.count == 3 else { throw ShopifyDataError.invalidResponse }
        return (name, zone, currency.uppercased())
    }

    private struct OrderPage {
        var orders: [ShopifyOrderRecord]
        var hasNextPage: Bool
        var endCursor: String?
    }

    private func fetchOrders(domain: String, token: String, query: String, after: String?) async throws -> OrderPage {
        let queryText = #"""
        query Orders($query: String!, $after: String, $first: Int!) {
          orders(first: $first, after: $after, query: $query, sortKey: CREATED_AT) {
            nodes {
              createdAt
              cancelledAt
              test
              currentTotalPriceSet { shopMoney { amount currencyCode } }
              lineItems(first: 250) { nodes { name currentQuantity } pageInfo { hasNextPage } }
              customerJourneySummary {
                firstVisit { source utmParameters { source medium campaign } }
                lastVisit { source utmParameters { source medium campaign } }
              }
            }
            pageInfo { hasNextPage endCursor }
          }
        }
        """#
        let data = try await graphQL(domain: domain,
                                     token: token,
                                     query: queryText,
                                     variables: ["query": query,
                                                 "after": after.map { $0 as Any } ?? NSNull(),
                                                 "first": min(max(pageSize, 1), 250)])
        guard let connection = data["orders"] as? [String: Any],
              let nodes = connection["nodes"] as? [[String: Any]],
              let pageInfo = connection["pageInfo"] as? [String: Any],
              let hasNext = pageInfo["hasNextPage"] as? Bool else { throw ShopifyDataError.invalidResponse }
        let records = try nodes.map(ShopifySnapshotParser.orderRecord)
        return OrderPage(orders: records, hasNextPage: hasNext, endCursor: pageInfo["endCursor"] as? String)
    }

    private func graphQL(domain: String, token: String, query: String, variables: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "https://\(domain)/admin/api/\(Self.apiVersion)/graphql.json") else { throw ShopifyDataError.invalidStore }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "X-Shopify-Access-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables], options: [.sortedKeys])
        let response = try await transport.response(for: request)
        switch response.statusCode {
        case 200..<300: break
        case 401: throw ShopifyDataError.invalidCredentials
        case 403: throw ShopifyDataError.missingPermission
        case 429: throw ShopifyDataError.rateLimited
        default: throw ShopifyDataError.httpStatus(response.statusCode)
        }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { throw ShopifyDataError.invalidResponse }
        if let errors = root["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { $0["message"] as? String }
            if messages.contains(where: { $0.localizedCaseInsensitiveContains("access denied") || $0.localizedCaseInsensitiveContains("read_orders") }) {
                throw ShopifyDataError.missingPermission
            }
            throw ShopifyDataError.graphQLError(messages.first.map { String($0.prefix(220)) } ?? "Shopify rejected the GraphQL request.")
        }
        guard let data = root["data"] as? [String: Any] else { throw ShopifyDataError.invalidResponse }
        return data
    }

    static func normalizedDomain(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        value = value.replacingOccurrences(of: "https://", with: "")
        value = value.replacingOccurrences(of: "http://", with: "")
        while value.hasSuffix("/") { value.removeLast() }
        if !value.hasSuffix(".myshopify.com") { value += ".myshopify.com" }
        let host = String(value.dropLast(".myshopify.com".count))
        let allowed = host.range(of: #"^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$"#, options: .regularExpression) != nil
        guard allowed, value == "\(host).myshopify.com", URL(string: "https://\(value)")?.host == value else {
            throw ShopifyDataError.invalidStore
        }
        return value
    }

    static func searchQuery(from start: Date, through end: Date) -> String {
        "created_at:>=\(isoDate(start)) created_at:<=\(isoDate(end))"
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct ShopifyOrderRecord {
    struct LineItem {
        var name: String
        var currentQuantity: Int
    }
    var createdAt: Date
    var cancelledAt: Date?
    var isTest: Bool
    var amount: Decimal
    var currency: String
    var lineItems: [LineItem]
    var lineItemsTruncated: Bool
    var trafficSource: String?
}

enum ShopifySnapshotParser {
    static func snapshot(orders: [ShopifyOrderRecord],
                         store: ShopifyConnectedStore,
                         period: ShopifyPeriod,
                         interval: DateInterval,
                         now: Date = .now) throws -> ShopifySnapshot {
        guard !store.id.isEmpty,
              let timeZone = TimeZone(identifier: store.timeZoneID),
              store.currency.count == 3 else { throw ShopifyDataError.invalidResponse }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var total = Decimal.zero
        var count = 0
        var products: [String: Int] = [:]
        var sources: [String: Int] = [:]
        var incomplete = 0
        var attributed = 0
        var daily: [Date: (amount: Decimal, orders: Int)] = [:]
        for order in orders where interval.contains(order.createdAt) {
            guard !order.isTest, order.cancelledAt == nil else { continue }
            guard order.currency.uppercased() == store.currency else { throw ShopifyDataError.currencyMismatch }
            total += order.amount
            count += 1
            let day = calendar.startOfDay(for: order.createdAt)
            daily[day, default: (.zero, 0)].amount += order.amount
            daily[day, default: (.zero, 0)].orders += 1
            for line in order.lineItems where line.currentQuantity > 0 {
                products[line.name, default: 0] += line.currentQuantity
            }
            if order.lineItemsTruncated { incomplete += 1 }
            if let source = order.trafficSource, !source.isEmpty {
                sources[source, default: 0] += 1
                attributed += 1
            }
        }
        let points = daily.keys.sorted().map { day in
            let value = daily[day] ?? (.zero, 0)
            return ShopifyDailyPoint(date: day, orderValue: value.amount, orders: value.orders)
        }
        return ShopifySnapshot(storeID: store.id,
                               storeName: store.name,
                               storeDomain: store.domain,
                               fetchedAt: now,
                               period: period,
                               periodStart: interval.start,
                               periodEnd: interval.end,
                               timeZoneID: store.timeZoneID,
                               currency: store.currency,
                               orderValue: total,
                               orderCount: count,
                               dailyPoints: points,
                               productBreakdown: products.map { ShopifyBreakdownEntry(name: $0.key, units: $0.value, orders: 0) }.sorted { $0.units > $1.units }.prefix(10).map { $0 },
                               trafficBreakdown: sources.map { ShopifyBreakdownEntry(name: $0.key, units: 0, orders: $0.value) }.sorted { $0.orders > $1.orders }.prefix(10).map { $0 },
                               productBreakdownIncompleteOrders: incomplete,
                               trafficAttributedOrders: attributed)
    }

    fileprivate static func orderRecord(_ raw: [String: Any]) throws -> ShopifyOrderRecord {
        guard let createdAt = date(raw["createdAt"] as? String),
              let isTest = raw["test"] as? Bool,
              let moneyBag = raw["currentTotalPriceSet"] as? [String: Any],
              let shopMoney = moneyBag["shopMoney"] as? [String: Any],
              let amountString = shopMoney["amount"] as? String,
              let amount = Decimal(string: amountString, locale: Locale(identifier: "en_US_POSIX")),
              let currency = shopMoney["currencyCode"] as? String,
              let lineConnection = raw["lineItems"] as? [String: Any],
              let lineNodes = lineConnection["nodes"] as? [[String: Any]],
              let linePage = lineConnection["pageInfo"] as? [String: Any] else { throw ShopifyDataError.invalidResponse }
        let lineItems = try lineNodes.map { line -> ShopifyOrderRecord.LineItem in
            guard let name = line["name"] as? String,
                  let quantity = line["currentQuantity"] as? Int else { throw ShopifyDataError.invalidResponse }
            return ShopifyOrderRecord.LineItem(name: String(name.prefix(160)), currentQuantity: quantity)
        }
        let journey = raw["customerJourneySummary"] as? [String: Any]
        let firstVisit = journey?["firstVisit"] as? [String: Any]
        let lastVisit = journey?["lastVisit"] as? [String: Any]
        let firstUTM = firstVisit?["utmParameters"] as? [String: Any]
        let lastUTM = lastVisit?["utmParameters"] as? [String: Any]
        let source = (lastUTM?["source"] as? String)
            ?? (lastVisit?["source"] as? String)
            ?? (firstUTM?["source"] as? String)
            ?? (firstVisit?["source"] as? String)
        return ShopifyOrderRecord(createdAt: createdAt,
                                  cancelledAt: date(raw["cancelledAt"] as? String),
                                  isTest: isTest,
                                  amount: amount,
                                  currency: currency.uppercased(),
                                  lineItems: lineItems,
                                  lineItemsTruncated: linePage["hasNextPage"] as? Bool ?? false,
                                  trafficSource: source.map { String($0.prefix(100)) })
    }

    static func records(from nodes: [[String: Any]]) throws -> [ShopifyOrderRecord] {
        try nodes.map(orderRecord)
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = fractional.date(from: value) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

enum ShopifyCredentialStore {
    @MainActor
    static func writeRefreshed(_ credential: ShopifyCredential, replacing original: ShopifyCredential, storeID: String) throws {
        let current = try read(storeID: storeID)
        guard ShopifyCredentialUpdatePolicy.mayRefresh(original: original, current: current,
            registered: ShopifyConnectionDirectory.stores().contains { $0.id == storeID }, cancelled: Task.isCancelled) else {
            throw EditSessionSaveError.failed("This Shopify connection changed or was removed while refreshing. Its credentials were left untouched.")
        }
        try write(credential, storeID: storeID)
    }
    private static var service: String { Product.bundleIdentifier + ".integration-credentials" }
    fileprivate static var directoryKey: String { Product.bundleIdentifier + ".shopify-connected-stores" }

    static func read(storeID: String) throws -> ShopifyCredential? {
        var query = baseQuery(storeID: storeID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status) }
        do { return try JSONDecoder().decode(ShopifyCredential.self, from: data) }
        catch { throw ShopifyDataError.invalidResponse }
    }

    static func write(_ credential: ShopifyCredential, storeID: String) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery(storeID: storeID)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if status != errSecSuccess { throw KeychainError(status) }
    }

    static func delete(storeID: String) throws {
        let status = SecItemDelete(baseQuery(storeID: storeID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private static func baseQuery(storeID: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "shopify.\(storeID)"]
    }

    private struct KeychainError: LocalizedError {
        var status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "Shopify credentials could not be saved in Keychain (\(status))." }
    }
}

enum ShopifyConnectionDirectory {
    static func stores(defaults: UserDefaults = .standard) -> [ShopifyConnectedStore] {
        guard let data = defaults.data(forKey: ShopifyCredentialStore.directoryKey),
              let stores = try? JSONDecoder().decode([ShopifyConnectedStore].self, from: data) else { return [] }
        return stores
    }

    static func save(_ store: ShopifyConnectedStore, credential: ShopifyCredential, defaults: UserDefaults = .standard) throws {
        try ShopifyCredentialStore.write(credential, storeID: store.id)
        var values = stores(defaults: defaults)
        values.removeAll { $0.id == store.id }
        values.append(store)
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: ShopifyCredentialStore.directoryKey) }
    }

    static func update(_ store: ShopifyConnectedStore, defaults: UserDefaults = .standard) {
        var values = stores(defaults: defaults)
        guard let index = values.firstIndex(where: { $0.id == store.id }) else { return }
        values[index] = store
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: ShopifyCredentialStore.directoryKey) }
    }

    static func remove(storeID: String, defaults: UserDefaults = .standard) throws {
        try ShopifyCredentialStore.delete(storeID: storeID)
        let remaining = stores(defaults: defaults).filter { $0.id != storeID }
        if let data = try? JSONEncoder().encode(remaining) { defaults.set(data, forKey: ShopifyCredentialStore.directoryKey) }
    }
}
