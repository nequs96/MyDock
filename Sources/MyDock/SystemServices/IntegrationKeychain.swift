import Foundation
import Security

/// One integration credential: a generic-password item under MyDock's integration-credentials service.
/// On macOS these items live in the login keychain, which is not synchronised to other devices; the
/// ThisDeviceOnly accessibility states the same intent for a data-protection keychain.
/// Isolated validation never reads or changes the real keychain.
struct IntegrationKeychainItem: Sendable {
    static var service: String { Product.bundleIdentifier + ".integration-credentials" }
    let account: String

    /// The stored bytes, or nil when there is no item (or credentials are disabled in validation).
    /// `failure` turns a Keychain status into the caller's own error.
    func readData(failure: (OSStatus) -> any Error) throws -> Data? {
        guard AppRuntimeEnvironment.allowsCredentials else { return nil }
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw failure(status) }
        guard let data = result as? Data else { throw failure(errSecDecode) }
        return data
    }

    /// Updates the item in place, or adds it when it does not exist yet.
    func write(_ data: Data, failure: (OSStatus) -> any Error) throws {
        try AppRuntimeEnvironment.requireCredentials()
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw failure(addStatus) }
        } else if status != errSecSuccess {
            throw failure(status)
        }
    }

    /// Removing an item that is already gone succeeds.
    func delete(failure: (OSStatus) -> any Error) throws {
        try AppRuntimeEnvironment.requireCredentials()
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }

    func readData(credential: String) throws -> Data? {
        try readData(failure: { IntegrationKeychainError(credential: credential, operation: .read, status: $0) })
    }

    func write(_ data: Data, credential: String) throws {
        try write(data, failure: { IntegrationKeychainError(credential: credential, operation: .write, status: $0) })
    }

    func delete(credential: String) throws {
        try delete(failure: { IntegrationKeychainError(credential: credential, operation: .delete, status: $0) })
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: account]
    }
}

/// A Keychain failure for one integration credential, worded for the operation that failed.
struct IntegrationKeychainError: LocalizedError, Equatable {
    enum Operation: Sendable { case read, write, delete }
    /// The credential as the start of a sentence, such as "The Stripe key".
    let credential: String
    let operation: Operation
    let status: OSStatus

    var errorDescription: String? {
        switch operation {
        case .read: "\(credential) could not be read from Keychain (\(status)). Save it again to reconnect."
        case .write: "\(credential) could not be saved in Keychain (\(status))."
        case .delete: "\(credential) could not be removed from Keychain (\(status))."
        }
    }
}

/// The non-secret list of saved connections for one provider, kept in user defaults. Credentials live
/// only in the Keychain; callers write the credential before adding its entry and delete it before removing it.
struct ConnectionDirectory<Entry: Codable & Identifiable>: Sendable where Entry.ID == String {
    let defaultsKey: String

    func entries(defaults: UserDefaults) -> [Entry] {
        guard let data = defaults.data(forKey: defaultsKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }

    /// Adds the entry, replacing one with the same identifier.
    func insert(_ entry: Entry, defaults: UserDefaults) {
        var values = entries(defaults: defaults)
        values.removeAll { $0.id == entry.id }
        values.append(entry)
        store(values, defaults: defaults)
    }

    /// Replaces an existing entry; an unknown identifier is ignored.
    func update(_ entry: Entry, defaults: UserDefaults) {
        var values = entries(defaults: defaults)
        guard let index = values.firstIndex(where: { $0.id == entry.id }) else { return }
        values[index] = entry
        store(values, defaults: defaults)
    }

    func remove(id: String, defaults: UserDefaults) {
        store(entries(defaults: defaults).filter { $0.id != id }, defaults: defaults)
    }

    private func store(_ values: [Entry], defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(values) { defaults.set(data, forKey: defaultsKey) }
    }
}
