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
        if previewBundle || flags.contains(where: { environment[$0] == "1" }) || environment["MYDOCK_RENDER_QA"] != nil
            || isTestProcess(environment) {
            return FileManager.default.temporaryDirectory.appendingPathComponent(
                "MyDock-validation-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        #endif
        return nil
    }()

    #if DEBUG
    /// Any test run is isolated however it was started (./TestMyDock.sh, swift test, Xcode's Test action):
    /// a missing environment flag must never let a test reach the user's Dock, Keychain or files.
    private static func isTestProcess(_ environment: [String: String]) -> Bool {
        ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"].contains { environment[$0] != nil }
            || Bundle.allBundles.contains { $0.bundleURL.pathExtension == "xctest" }
    }
    #endif

    static var isIsolated: Bool { validationRoot != nil }
    // Native acceptance is run in its separate explicitly opted-in harness
    // with injected backends. The default application graph never escapes.
    static var allowsNativeEffects: Bool { !isIsolated }
    static var allowsCredentials: Bool { !isIsolated }
    static var allowsNetwork: Bool { allowsProductionNetwork(validationRoot: validationRoot) }
    static func allowsProductionNetwork(validationRoot: URL?) -> Bool { validationRoot == nil }

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

    /// Guard default production transports before creating sessions or resolving DNS.
    /// Explicitly injected fixture transports remain independent of this boundary.
    static func requireNetwork() throws {
        guard allowsNetwork else { throw ValidationBoundaryError.networkDisabled }
    }

    static func requireCredentials() throws {
        guard allowsCredentials else { throw ValidationBoundaryError.credentialsDisabled }
    }
}

enum ValidationBoundaryError: LocalizedError {
    case nativeEffectsDisabled, credentialsDisabled, networkDisabled
    var errorDescription: String? {
        switch self {
        case .nativeEffectsDisabled: "Native actions and permission requests are disabled in this isolated validation session."
        case .networkDisabled: "External requests are disabled in this isolated validation session."
        case .credentialsDisabled: "Connected credentials are unavailable in this isolated validation session."
        }
    }
}

/// No preference domain is written, including a disposable domain in the user's
/// Library. Foundation's typed getters use these primitive overrides. Like the real
/// store, writes notify KVO observers (`@AppStorage`) and registered defaults stay a
/// fallback that `removeObject` returns to.
private final class ValidationDefaults: UserDefaults {
    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]
    private var registered: [String: Any] = [:]
    override func object(forKey defaultName: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        if let value = values[defaultName] { return value }
        return registered[defaultName]
    }
    override func set(_ value: Any?, forKey defaultName: String) {
        willChangeValue(forKey: defaultName)
        lock.lock(); values[defaultName] = value; lock.unlock()
        didChangeValue(forKey: defaultName)
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: self)
    }
    override func removeObject(forKey defaultName: String) { set(nil, forKey: defaultName) }
    override func synchronize() -> Bool { true }
    override func dictionaryRepresentation() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }; return registered.merging(values) { _, stored in stored }
    }
    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        lock.lock(); defer { lock.unlock() }; return values
    }
    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        lock.lock(); defer { lock.unlock() }; values = domain
    }
    override func removePersistentDomain(forName domainName: String) {
        lock.lock(); defer { lock.unlock() }; values.removeAll()
    }
    override func register(defaults registrationDictionary: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        registered.merge(registrationDictionary) { _, new in new }
    }
}
