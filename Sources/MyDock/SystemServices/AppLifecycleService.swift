import AppKit
import Combine
import ServiceManagement

/// Registration and eligibility are different: approval can be revoked in System Settings.
enum LoginItemState: Equatable {
    case unavailable, notRegistered, enabled, requiresApproval, notFound, unknown

    init(status: SMAppService.Status) {
        switch status {
        case .notRegistered: self = .notRegistered
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        @unknown default: self = .unknown
        }
    }

    var registrationRequested: Bool { self == .enabled || self == .requiresApproval }
    /// The one copy of the login status, shown as the Application section footer in Settings.
    var message: String {
        switch self {
        case .unavailable: "Launch at login is not available in this session."
        case .notRegistered: "Not registered to launch at login."
        case .enabled: "Allowed to launch at login."
        case .requiresApproval: "macOS approval is required in Login Items."
        case .notFound: "macOS could not find this login service."
        case .unknown: "Check the login status in Login Items."
        }
    }
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()
    @Published private(set) var state: LoginItemState = .unavailable
    var enabled: Bool { state == .enabled }
    var requiresApproval: Bool { state == .requiresApproval }
    @Published private(set) var errorMessage: String?
    var isAvailable: Bool { AppRuntimeEnvironment.allowsNativeEffects && Bundle.main.bundleIdentifier == Product.bundleIdentifier && Bundle.main.bundleURL.pathExtension == "app" }
    private init() { refresh() }
    func refresh() {
        state = isAvailable ? LoginItemState(status: SMAppService.mainApp.status) : .unavailable
    }
    func setEnabled(_ enabled: Bool) {
        guard isAvailable else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        refresh()
    }
    func openApprovalSettings() { if AppRuntimeEnvironment.allowsNativeEffects { SMAppService.openSystemSettingsLoginItems() } }
}

struct ReleaseRepository: Equatable {
    var owner: String
    var name: String
    init?(url: String) {
        guard let components = URLComponents(string: url.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", components.host == "github.com", components.user == nil,
              components.password == nil, components.port == nil, components.query == nil, components.fragment == nil else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count == 2 || (parts.count == 3 && parts[2] == "releases"),
              parts.prefix(2).allSatisfy({ $0.count <= 100 && $0.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-").contains($0) } }) else { return nil }
        owner = String(parts[0]); name = String(parts[1])
    }
    var apiURL: URL { URL(string: "https://api.github.com/repos/\(owner)/\(name)/releases/latest")! }
    func validates(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com" && url.user == nil && url.password == nil
            && url.port == nil && url.query == nil && url.fragment == nil
            && url.path.hasPrefix("/\(owner)/\(name)/releases/")
    }
}

enum ReleaseVersion {
    static func isNewer(_ proposed: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int]? {
            let cleaned = value.hasPrefix("v") ? String(value.dropFirst()) : value
            let values = cleaned.split(separator: ".")
            guard values.count == 3, values.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
                  values.allSatisfy({ $0.count <= 6 }) else { return nil }
            return values.compactMap { Int($0) }
        }
        guard let candidate = parts(proposed), let installed = parts(current) else { return false }
        return candidate.lexicographicallyPrecedes(installed) == false && candidate != installed
    }
}

enum UpdateCheckError: LocalizedError, Equatable {
    case noRelease, mismatch, tooLarge, unreadable

    var errorDescription: String? {
        switch self {
        case .noRelease: "This repository has no public release."
        case .mismatch: "The release does not match this repository."
        case .tooLarge: "The release information is too large to read."
        case .unreadable: "The release information could not be read."
        }
    }
}

@MainActor
final class UpdateCheckService: ObservableObject {
    @Published private(set) var message: String?
    @Published private(set) var checking = false
    @Published private(set) var releaseURL: URL?
    func clearResult() { message = nil; releaseURL = nil }
    func check(repositoryURL: String) async {
        guard !checking else { return }
        clearResult()
        guard let repository = ReleaseRepository(url: repositoryURL) else { message = "Enter the publisher’s HTTPS GitHub repository URL."; return }
        checking = true; releaseURL = nil
        defer { checking = false }
        do {
            try AppRuntimeEnvironment.requireNetwork()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 12
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            let data: Data
            do {
                let result = try await BoundedHTTPFetch.fetch(URLRequest(url: repository.apiURL), session: session, maximumBytes: 128 * 1_024)
                guard result.response.statusCode == 200 else { throw UpdateCheckError.noRelease }
                data = result.data
            } catch let error as BoundedHTTPFetchError {
                throw error == .tooLarge ? UpdateCheckError.tooLarge : UpdateCheckError.unreadable
            }
            struct Release: Decodable { var tag_name: String; var html_url: URL; var draft: Bool; var prerelease: Bool }
            guard let release = try? JSONDecoder().decode(Release.self, from: data) else { throw UpdateCheckError.unreadable }
            guard !release.draft, !release.prerelease, repository.validates(release.html_url) else { throw UpdateCheckError.mismatch }
            if ReleaseVersion.isNewer(release.tag_name, than: Product.marketingVersion) {
                message = "\(release.tag_name) is available. Review the publisher’s release and installer."
                releaseURL = release.html_url
            } else { message = "No newer stable version is listed. Installed: \(Product.marketingVersion)." }
        } catch is CancellationError {
            message = nil
        } catch { message = error.localizedDescription }
    }
}
