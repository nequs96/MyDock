import Foundation
import Security

/// Whether an integration credential is saved, read from its Keychain attributes only: the secret
/// is never decrypted just to show a status. Isolated validation never reads the real keychain.
enum IntegrationCredentialPresence {
    /// The service every integration credential is stored under.
    static var service: String { Product.bundleIdentifier + ".integration-credentials" }

    /// Keychain answered with something other than "found" or "not found".
    struct LookupError: LocalizedError, Equatable {
        /// The credential as the start of a sentence, such as "The Alpha Vantage key".
        let credential: String
        let status: OSStatus
        var errorDescription: String? { "\(credential) could not be checked in Keychain (\(status))." }
    }

    static func exists(account: String, credential: String) throws -> Bool {
        guard AppRuntimeEnvironment.allowsCredentials else { return false }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw LookupError(credential: credential, status: status) }
        return true
    }
}
