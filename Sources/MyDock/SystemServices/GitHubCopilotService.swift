import Foundation
import CoreFoundation
import Security

struct GitHubCopilotCredentials: Codable, Equatable, Sendable {
    var username: String
    var token: String
}

enum GitHubCopilotUsernamePolicy {
    static func isValid(_ username: String) -> Bool {
        let value = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...39).contains(value.utf8.count),
              let first = value.utf8.first, let last = value.utf8.last,
              first != 45, last != 45,
              !value.contains("--") else { return false }
        return value.utf8.allSatisfy { byte in
            (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 45
        }
    }
}

enum GitHubCopilotCredentialStore {
    static let didChange = Notification.Name("MyDock.CopilotCredentialsDidChange")
    private static let authority = CopilotCredentialAuthority()
    static var revision: UInt64 { authority.revision }
    private static func changed() {
        authority.invalidate()
        NotificationCenter.default.post(name: didChange, object: nil)
    }
    private static let account = "github-copilot"
    private static var service: String { Product.bundleIdentifier + ".integration-credentials" }

    static func read() throws -> GitHubCopilotCredentials? {
        guard AppRuntimeEnvironment.allowsCredentials else { return nil }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw GitHubCopilotCredentialError.keychain(status)
        }
        guard let data = result as? Data,
              let credentials = try? JSONDecoder().decode(GitHubCopilotCredentials.self, from: data),
              GitHubCopilotUsernamePolicy.isValid(credentials.username),
              !credentials.token.isEmpty else {
            throw GitHubCopilotCredentialError.corruptEntry
        }
        return credentials
    }

    static func write(username: String, token: String) throws {
        try AppRuntimeEnvironment.requireCredentials()
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubCopilotUsernamePolicy.isValid(normalizedUsername), !normalizedToken.isEmpty else {
            throw GitHubCopilotCredentialError.invalidCredentials
        }
        let data = try JSONEncoder().encode(GitHubCopilotCredentials(username: normalizedUsername,
                                                                      token: normalizedToken))
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw GitHubCopilotCredentialError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw GitHubCopilotCredentialError.keychain(status)
        }
        changed()
    }

    static func delete() throws {
        try AppRuntimeEnvironment.requireCredentials()
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitHubCopilotCredentialError.keychain(status)
        }
        changed()
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}

private enum GitHubCopilotCredentialError: LocalizedError {
    case invalidCredentials
    case corruptEntry
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            "Enter a valid GitHub username and fine-grained personal access token."
        case .corruptEntry:
            "The saved GitHub Copilot credentials could not be decoded. Remove them from Integrations and save them again."
        case .keychain(let status):
            "GitHub Copilot credentials could not be read from or saved to Keychain (\(status))."
        }
    }
}

enum GitHubCopilotBillingParser {
    static let maximumResponseBytes = 1_000_000

    static func reading(from data: Data,
                        username: String,
                        monthlyAllowance: Int,
                        now: Date = .now) throws -> AIProviderLimitReading {
        guard data.count <= maximumResponseBytes,
              GitHubCopilotUsernamePolicy.isValid(username),
              (1...1_000_000).contains(monthlyAllowance) else {
            throw GitHubCopilotBillingError.invalidResponse
        }
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GitHubCopilotBillingError.invalidResponse
            }
            root = object
        } catch {
            throw GitHubCopilotBillingError.invalidResponse
        }
        guard
              let returnedUsername = root["user"] as? String,
              returnedUsername.caseInsensitiveCompare(username) == .orderedSame,
              let items = root["usageItems"] as? [[String: Any]] else {
            throw GitHubCopilotBillingError.invalidResponse
        }

        var usedCredits = 0.0
        for item in items where isCopilotCredit(item) {
            guard let quantity = item["grossQuantity"] as? NSNumber,
                  CFGetTypeID(quantity) != CFBooleanGetTypeID(),
                  quantity.doubleValue.isFinite,
                  quantity.doubleValue >= 0,
                  quantity.doubleValue <= 1_000_000_000 else {
                throw GitHubCopilotBillingError.invalidResponse
            }
            usedCredits += quantity.doubleValue
        }

        let rawPercent = (usedCredits / Double(monthlyAllowance) * 100).rounded()
        let usedPercent = Int(min(100_000, max(0, rawPercent)))
        return AIProviderLimitReading(provider: .copilot,
                                      availability: .available,
                                      plan: nil,
                                      windows: [AILimitWindow(name: "Monthly AI credits",
                                                              usedPercent: usedPercent,
                                                              resetsAt: nextMonthlyReset(after: now),
                                                              durationMinutes: nil)],
                                      updatedAt: now,
                                      message: nil,
                                      verifiedAccountIdentity: "github:" + returnedUsername.lowercased())
    }

    private static func isCopilotCredit(_ item: [String: Any]) -> Bool {
        let product = (item["product"] as? String ?? "").lowercased()
        let sku = (item["sku"] as? String ?? "").lowercased()
        let unit = (item["unitType"] as? String ?? "").lowercased()
        let hasCopilotProduct = product.contains("copilot") || sku.contains("copilot")
        let isCreditQuantity = unit == "ai-credits" || unit == "credits"
        return hasCopilotProduct && isCreditQuantity
    }

    private static func nextMonthlyReset(after date: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { return nil }
        calendar.timeZone = utc
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        guard let startOfMonth else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth)
    }
}

enum GitHubCopilotBillingError: LocalizedError {
    case invalidResponse
    case responseTooLarge
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub returned a Copilot billing report MyDock could not safely read."
        case .responseTooLarge:
            "GitHub returned a Copilot billing report that exceeded MyDock's response limit."
        case .httpStatus(401), .httpStatus(403):
            "GitHub rejected the token. Check that it has fine-grained Plan read permission and applies to your personal account."
        case .httpStatus(404):
            "GitHub did not return personal Copilot billing usage. Organization-billed Copilot plans are not supported by this reader."
        case .httpStatus(429):
            "GitHub rate-limited the Copilot billing request. Try again later."
        case .httpStatus(let status):
            "GitHub Copilot billing is temporarily unavailable (HTTP \(status))."
        }
    }
}

enum GitHubCopilotBillingClient {
    /// No disk cache or cookies: the request carries the personal token and the reply is billing data.
    private static let ephemeral = BoundedHTTPFetch.ephemeralSession()
    static func makeRequest(username: String, token: String, now: Date = .now) throws -> URLRequest {
        guard GitHubCopilotUsernamePolicy.isValid(username), !token.isEmpty else {
            throw GitHubCopilotBillingError.invalidResponse
        }

        var components = URLComponents(string: "https://api.github.com/users/\(username)/settings/billing/ai_credit/usage")
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else { throw GitHubCopilotBillingError.invalidResponse }
        calendar.timeZone = utc
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        components?.queryItems = [URLQueryItem(name: "year", value: String(year)),
                                  URLQueryItem(name: "month", value: String(month)),
                                  URLQueryItem(name: "product", value: "Copilot AI Credits")]
        guard let url = components?.url else { throw GitHubCopilotBillingError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func read(credentials: GitHubCopilotCredentials,
                     monthlyAllowance: Int,
                     now: Date = .now,
                     session: URLSession? = nil) async throws -> AIProviderLimitReading {
        if session == nil { try AppRuntimeEnvironment.requireNetwork() }
        guard (1...1_000_000).contains(monthlyAllowance) else {
            throw GitHubCopilotBillingError.invalidResponse
        }
        let request = try makeRequest(username: credentials.username, token: credentials.token, now: now)

        let (bytes, response) = try await (session ?? Self.ephemeral).bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GitHubCopilotBillingError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubCopilotBillingError.httpStatus(response.statusCode)
        }
        var data = Data()
        data.reserveCapacity(16_384)
        for try await byte in bytes {
            guard data.count < GitHubCopilotBillingParser.maximumResponseBytes else {
                throw GitHubCopilotBillingError.responseTooLarge
            }
            data.append(byte)
        }
        return try GitHubCopilotBillingParser.reading(from: data,
                                                      username: credentials.username,
                                                      monthlyAllowance: monthlyAllowance,
                                                      now: now)
    }
}

extension GitHubCopilotBillingError {
    /// Authentication and unsupported/malformed responses cannot inherit a previous account's allowance.
    static func limitFailure(_ error: Error, requestedUsername: String) -> AILimitReadFailure {
        let kind: AILimitFailureKind
        switch error {
        case GitHubCopilotBillingError.httpStatus(401), GitHubCopilotBillingError.httpStatus(403): kind = .authentication
        case GitHubCopilotBillingError.httpStatus(429): kind = .transient
        case GitHubCopilotBillingError.httpStatus(let status) where (500...599).contains(status): kind = .transient
        case is URLError: kind = .transient
        default: kind = .unavailable
        }
        return .init(kind: kind, requestedAccountIdentity: "github:" + requestedUsername.lowercased(),
                     message: DataSourceProvenance.sanitized(error.localizedDescription))
    }
}

struct GitHubCopilotLimitAdapter: AILimitProviderAdapter {
    let provider: AIProvider = .copilot
    var monthlyAllowance: Int?

    func read(now: Date) async throws -> AIProviderLimitReading {
        guard let credentials = try GitHubCopilotCredentialStore.read() else {
            return AIProviderLimitReading(provider: .copilot, availability: .setupRequired,
                                          plan: nil, windows: [], updatedAt: nil,
                                          message: "Add your GitHub username and fine-grained token in Settings → Integrations.")
        }
        guard let monthlyAllowance, (1...1_000_000).contains(monthlyAllowance) else {
            return AIProviderLimitReading(provider: .copilot, availability: .setupRequired,
                                          plan: nil, windows: [], updatedAt: nil,
                                          message: "Set the included monthly Copilot AI-credit allowance in this widget's controls.")
        }
        do {
            return try await GitHubCopilotBillingClient.read(credentials: credentials, monthlyAllowance: monthlyAllowance, now: now)
        } catch {
            throw GitHubCopilotBillingError.limitFailure(error, requestedUsername: credentials.username)
        }
    }
}

/// In-memory authority generation rejects results begun before a successful credential mutation.
private final class CopilotCredentialAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0
    var revision: UInt64 { lock.lock(); defer { lock.unlock() }; return value }
    func invalidate() { lock.lock(); defer { lock.unlock() }; value &+= 1 }
}
