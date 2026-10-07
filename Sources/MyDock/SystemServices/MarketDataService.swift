import Foundation
import Security

struct MarketSymbol: Codable, Hashable, Identifiable {
    var symbol: String
    var name: String
    var type: String
    var region: String
    var currency: String
    var id: String { symbol }
}

enum MarketDataError: LocalizedError {
    case missingAPIKey
    case invalidSymbol
    case invalidResponse
    case providerLimit
    case providerFailure
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an Alpha Vantage API key in Settings → Integrations to use market widgets."
        case .invalidSymbol: "Enter a valid ticker symbol."
        case .invalidResponse: "The market data response could not be read. Try again later."
        case .providerLimit: "Alpha Vantage's request limit was reached. Try again later or review your plan."
        case .providerFailure: "Alpha Vantage could not find data for this request. Check the ticker and try again."
        case .httpStatus(let code): "Market data is temporarily unavailable (HTTP \(code))."
        }
    }
}

enum MarketFinanceURL {
    /// Alpha Vantage's exchange suffixes and Yahoo Finance's for the same listing (London, Toronto, TSX Venture,
    /// XETRA, Bombay, Shanghai, Shenzhen). Other symbols are the same on both.
    static let yahooSuffixes: [(alphaVantage: String, yahoo: String)] = [
        (".LON", ".L"), (".TRT", ".TO"), (".TRV", ".V"), (".DEX", ".DE"), (".BSE", ".BO"), (".SHH", ".SS"), (".SHZ", ".SZ")
    ]

    static func yahooSymbol(_ symbol: String) -> String {
        for suffix in yahooSuffixes where symbol.hasSuffix(suffix.alphaVantage) && symbol.count > suffix.alphaVantage.count {
            return String(symbol.dropLast(suffix.alphaVantage.count)) + suffix.yahoo
        }
        return symbol
    }

    static func url(for symbol: String) -> URL? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard MarketDataParser.isValidSymbol(normalized),
              var components = URLComponents(string: "https://finance.yahoo.com") else { return nil }
        components.path = "/quote/\(yahooSymbol(normalized))"
        return components.url
    }
}

protocol MarketDataTransport: Sendable {
    func data(for request: URLRequest) async throws -> Data
}

struct URLSessionMarketDataTransport: MarketDataTransport {
    private static let session = BoundedHTTPFetch.ephemeralSession()

    func data(for request: URLRequest) async throws -> Data {
        try AppRuntimeEnvironment.requireNetwork()
        let result: (data: Data, response: HTTPURLResponse)
        do {
            result = try await BoundedHTTPFetch.fetch(request, session: Self.session, maximumBytes: 5_000_000)
        } catch is BoundedHTTPFetchError {
            throw MarketDataError.invalidResponse
        }
        guard (200..<300).contains(result.response.statusCode) else { throw MarketDataError.httpStatus(result.response.statusCode) }
        return result.data
    }
}

struct AlphaVantageMarketProvider: Sendable {
    var transport: any MarketDataTransport = URLSessionMarketDataTransport()

    func search(_ query: String, apiKey: String) async throws -> [MarketSymbol] {
        guard !apiKey.isEmpty else { throw MarketDataError.missingAPIKey }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count <= 100 else { throw MarketDataError.invalidSymbol }
        let data = try await request(parameters: ["function": "SYMBOL_SEARCH", "keywords": trimmed, "apikey": apiKey])
        return try MarketDataParser.searchResults(from: data)
    }

    func snapshot(symbol: String, currency: String = "USD", apiKey: String) async throws -> StockMarketSnapshot {
        guard !apiKey.isEmpty else { throw MarketDataError.missingAPIKey }
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard MarketDataParser.isValidSymbol(normalized) else { throw MarketDataError.invalidSymbol }
        let data = try await request(parameters: ["function": "TIME_SERIES_DAILY", "symbol": normalized,
                                                  "outputsize": "compact", "apikey": apiKey])
        return try MarketDataParser.dailySnapshot(from: data, expectedSymbol: normalized, currency: currency)
    }

    private func request(parameters: [String: String]) async throws -> Data {
        guard var components = URLComponents(string: "https://www.alphavantage.co/query") else {
            throw MarketDataError.invalidResponse
        }
        components.queryItems = parameters.keys.sorted().compactMap { key in
            parameters[key].map { URLQueryItem(name: key, value: $0) }
        }
        guard let url = components.url else { throw MarketDataError.invalidResponse }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await transport.data(for: request)
    }
}

enum MarketDataParser {
    static func isValidSymbol(_ symbol: String) -> Bool {
        guard (1...20).contains(symbol.count) else { return false }
        return symbol.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-").contains(scalar)
        }
    }

    static func searchResults(from data: Data) throws -> [MarketSymbol] {
        let root = try responseObject(data)
        if root["Note"] != nil || root["Information"] != nil { throw MarketDataError.providerLimit }
        if root["Error Message"] != nil { throw MarketDataError.providerFailure }
        let rows = root["bestMatches"] as? [[String: Any]] ?? []
        return rows.prefix(10).compactMap { row in
            guard let symbol = row["1. symbol"] as? String,
                  let name = row["2. name"] as? String,
                  isValidSymbol(symbol.uppercased()) else { return nil }
            return MarketSymbol(symbol: symbol.uppercased(),
                                name: String(name.prefix(120)),
                                type: String((row["3. type"] as? String ?? "Equity").prefix(40)),
                                region: String((row["4. region"] as? String ?? "").prefix(60)),
                                currency: currencyCode(row["8. currency"] as? String))
        }
    }

    static let maximumPrice = 1e12
    static let maximumVolume = 1e15
    static let maximumPoints = 10_000

    static func dailySnapshot(from data: Data, expectedSymbol: String, currency: String = "USD", fetchedAt: Date = .now) throws -> StockMarketSnapshot {
        let root = try responseObject(data)
        guard let seriesKey = root.keys.first(where: { $0.hasPrefix("Time Series (Daily)") }),
              let series = root[seriesKey] as? [String: [String: Any]] else {
            if root["Note"] != nil || root["Information"] != nil { throw MarketDataError.providerLimit }
            if root["Error Message"] != nil { throw MarketDataError.providerFailure }
            throw MarketDataError.invalidResponse
        }
        var outOfDomain = false
        let points = series.compactMap { dateString, values -> StockMarketPoint? in
            guard let date = parseDate(dateString),
                  let close = number(values["4. close"]),
                  let volume = number(values["5. volume"]) else { return nil }
            // Well-formed but absurd numbers reject the whole response so the last good snapshot is kept.
            guard close.isFinite, (0...maximumPrice).contains(close),
                  volume.isFinite, (0...maximumVolume).contains(volume) else { outOfDomain = true; return nil }
            return StockMarketPoint(date: date, close: close, volume: Int64(volume))
        }.sorted { $0.date < $1.date }
        guard !outOfDomain else { throw MarketDataError.invalidResponse }
        guard !points.isEmpty else { throw MarketDataError.providerFailure }
        return StockMarketSnapshot(symbol: expectedSymbol, points: Array(points.suffix(maximumPoints)), currency: currency, fetchedAt: fetchedAt)
    }

    private static func responseObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MarketDataError.invalidResponse
        }
        return object
    }

    private static func number(_ value: Any?) -> Double? {
        if let string = value as? String { return Double(string) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func currencyCode(_ value: String?) -> String {
        guard let value, value.count == 3,
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz").contains($0) })
        else { return "USD" }
        return value.uppercased()
    }
}

enum MarketAPIKeyStore {
    private static let account = "alphavantage"
    private static var service: String { Product.bundleIdentifier + ".integration-credentials" }

    static func read() throws -> String? {
        guard AppRuntimeEnvironment.allowsCredentials else { return nil }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else { throw KeychainError(status) }
        return value
    }

    static func write(_ value: String) throws {
        try AppRuntimeEnvironment.requireCredentials()
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status)
        }
    }

    static func delete() throws {
        try AppRuntimeEnvironment.requireCredentials()
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private struct KeychainError: LocalizedError {
        var status: OSStatus
        init(_ status: OSStatus) { self.status = status }
        var errorDescription: String? { "The Alpha Vantage key could not be saved in Keychain (\(status))." }
    }
}
