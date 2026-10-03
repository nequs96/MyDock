import AppKit
import Combine
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    static let shared = LaunchAtLoginController()
    @Published private(set) var enabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?
    var isAvailable: Bool { AppRuntimeEnvironment.allowsNativeEffects && Bundle.main.bundleIdentifier == Product.bundleIdentifier && Bundle.main.bundleURL.pathExtension == "app" }
    private init() { refresh() }
    func refresh() {
        enabled = isAvailable && [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
        requiresApproval = isAvailable && SMAppService.mainApp.status == .requiresApproval
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
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 12
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
            let (bytes, response) = try await session.bytes(from: repository.apiURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw EditSessionSaveError.failed("No public release is available from this repository.") }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 128 * 1_024, !Task.isCancelled else { throw CancellationError() }
                data.append(byte)
            }
            struct Release: Decodable { var tag_name: String; var html_url: URL; var draft: Bool; var prerelease: Bool }
            let release = try JSONDecoder().decode(Release.self, from: data)
            guard !release.draft, !release.prerelease, repository.validates(release.html_url) else { throw EditSessionSaveError.failed("The release response did not match this publisher repository.") }
            if ReleaseVersion.isNewer(release.tag_name, than: Product.marketingVersion) {
                message = "\(release.tag_name) is available. Review the publisher’s release and installer."
                releaseURL = release.html_url
            } else { message = "No newer stable version is listed. Installed: \(Product.marketingVersion)." }
        } catch { message = error.localizedDescription }
    }
}
