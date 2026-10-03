import AppKit
import Foundation

/// An installed copy is distinct from both its bundle identifier and its process.
enum InstalledApplicationIdentity {
    static func normalizedURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    static func key(bundleIdentifier: String, bundleURL: URL) -> String {
        bundleIdentifier + "|" + normalizedURL(bundleURL).absoluteString
    }
}

/// A temporary observation. Never persist this as an application launch target.
struct NativeApplicationIdentity: Hashable, Sendable {
    var processID: Int32
    var bundleIdentifier: String
    var bundleURL: URL
    /// Optional: some processes publish no launch date. PID, installed copy and
    /// bundle identifier still must match; a published date is additionally compared.
    var launchDate: Date?

    static func observing(_ app: NSRunningApplication) -> NativeApplicationIdentity? {
        guard AppRuntimeEnvironment.allowsNativeEffects, !app.isTerminated, let bundleIdentifier = app.bundleIdentifier,
              let bundleURL = app.bundleURL else { return nil }
        return NativeApplicationIdentity(processID: app.processIdentifier, bundleIdentifier: bundleIdentifier,
                                         bundleURL: bundleURL, launchDate: app.launchDate)
    }

    func matches(_ current: NativeApplicationIdentity) -> Bool {
        processID == current.processID && bundleIdentifier == current.bundleIdentifier
            && launchDate == current.launchDate
            && InstalledApplicationIdentity.normalizedURL(bundleURL) == InstalledApplicationIdentity.normalizedURL(current.bundleURL)
    }
}

struct RunningApplicationDescriptor: Equatable, Identifiable {
    var bundleIdentifier: String
    var name: String
    var bundleURL: URL
    var isRegularApplication: Bool
    var isTerminated: Bool

    var id: String { InstalledApplicationIdentity.key(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL) }
}

enum RunningApplicationFilter {
    static func visible(_ applications: [RunningApplicationDescriptor], excluding pinnedBundleIdentifiers: Set<String>) -> [RunningApplicationDescriptor] {
        var seen: Set<String> = []
        return applications
            .filter { $0.isRegularApplication && !$0.isTerminated && !pinnedBundleIdentifiers.contains($0.bundleIdentifier) && seen.insert($0.id).inserted }
            .sorted {
                let order = $0.name.localizedCaseInsensitiveCompare($1.name)
                return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
            }
    }
}
