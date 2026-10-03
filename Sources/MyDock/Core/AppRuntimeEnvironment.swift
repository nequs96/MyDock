import Foundation

/// Validation uses private files and memory-only preferences, and fails closed
/// before native actions or credentials. A temporary ProfileStore alone is not
/// a safe boundary for shared services or application termination.
enum AppRuntimeEnvironment {
    static let validationRoot: URL? = {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["MYDOCK_VALIDATION_ROOT"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #if DEBUG
        let flags = ["MYDOCK_VISUAL_PREVIEW", "MYDOCK_COUNTDOWN_VISUAL_PREVIEW", "MYDOCK_UNIT_TEST_HOST"]
        let previewBundle = Bundle.main.bundleIdentifier?.contains("VisualPreview") == true
        if previewBundle || flags.contains(where: { environment[$0] == "1" }) || environment["MYDOCK_RENDER_QA"] != nil {
            return FileManager.default.temporaryDirectory.appendingPathComponent(
                "MyDock-validation-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        #endif
        return nil
    }()

    static var isIsolated: Bool { validationRoot != nil }
    // Native acceptance is run in its separate explicitly opted-in harness
    // with injected backends. The default application graph never escapes.
    static var allowsNativeEffects: Bool { !isIsolated }
    static var allowsCredentials: Bool { !isIsolated }

    static var applicationSupportDirectory: URL {
        if let validationRoot { return validationRoot.appendingPathComponent("ApplicationSupport", isDirectory: true) }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(Product.name, isDirectory: true)
    }

    static var windowPreviewDirectory: URL {
        if let validationRoot { return validationRoot.appendingPathComponent("WindowPreviews", isDirectory: true) }
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(Product.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("WindowPreviews", isDirectory: true)
    }

    // UserDefaults is documented thread-safe; ValidationDefaults locks its storage.
    nonisolated(unsafe) static let defaults: UserDefaults = isIsolated ? ValidationDefaults() : .standard

    static func requireNativeEffects() throws {
        guard allowsNativeEffects else { throw ValidationBoundaryError.nativeEffectsDisabled }
    }

    static func requireCredentials() throws {
        guard allowsCredentials else { throw ValidationBoundaryError.credentialsDisabled }
    }
}

enum ValidationBoundaryError: LocalizedError {
    case nativeEffectsDisabled, credentialsDisabled
    var errorDescription: String? {
        switch self {
        case .nativeEffectsDisabled: "Native actions and permission requests are disabled in this isolated validation session."
        case .credentialsDisabled: "Connected credentials are unavailable in this isolated validation session."
        }
    }
}

/// No preference domain is written, including a disposable domain in the user's
/// Library. Foundation's typed getters use these primitive overrides.
private final class ValidationDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }; return values[defaultName]
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        lock.lock(); defer { lock.unlock() }; values[defaultName] = value
    }
    override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }
    override func synchronize() -> Bool { true }
    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }; return values
    }
    override func persistentDomain(forName domainName: String) -> [String: Any]? { dictionaryRepresentation() }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        lock.lock(); defer { lock.unlock() }; values = domain
    }
    override func removePersistentDomain(forName domainName: String) {
        lock.lock(); defer { lock.unlock() }; values.removeAll()
    }
    override func register(defaults registrationDictionary: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        values.merge(registrationDictionary) { existing, _ in existing }
    }
}
