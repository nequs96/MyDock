import AppKit
import Combine
import Foundation

// PX-1 Dock essentials: pure policies for dropping files on an app tile, the running-app
// context menu, and the optional recent-apps section, plus the runtime recency tracker.

/// Dropping Finder files or web addresses ON an application tile opens them with that app.
enum DockDropOpenPolicy {
    static let maximumURLs = 100

    /// Existing local files and http(s) addresses only. Anything else is ignored, so a drop that
    /// carries nothing openable is rejected rather than silently launching the app.
    static func openableURLs(_ urls: [URL], fileExists: (URL) -> Bool) -> [URL] {
        urls.prefix(maximumURLs).filter { url in
            if url.isFileURL { return fileExists(url) }
            return ["https", "http"].contains(url.scheme?.lowercased() ?? "") && url.host != nil
        }
    }

    /// Only an application tile can open dropped content.
    static func opensDroppedContent(on item: DockItem) -> Bool { item.type == .application }

    /// True when a drag carries Finder files or addresses, rather than one of the Dock's own
    /// reorder payloads, so reorder hovers do not look like "open with" targets.
    static func carriesOpenableContent(typeIdentifiers: [String]) -> Bool {
        typeIdentifiers.contains { ["public.file-url", "public.url"].contains($0) }
    }
}

/// The running-application context menu section (order and wording follow the macOS Dock).
enum RunningApplicationMenuPolicy {
    /// Keeps the menu short and quick to build.
    static let inlineWindowLimit = 12
    /// The window scan runs while the menu opens, so it gets a short bound (seconds).
    static let discoveryTimeLimit: TimeInterval = 0.35

    static func hideTitle(isHidden: Bool) -> String { isHidden ? "Show" : "Hide" }

    static func inlineWindows(_ windows: [DockWindowDescriptor]) -> [DockWindowDescriptor] {
        Array(windows.prefix(inlineWindowLimit))
    }

    static func forceQuitTitle(name: String) -> String { "Force Quit \(name)?" }
    static let forceQuitMessage = "Any unsaved changes in this app will be lost."
}

/// An application used recently. Runtime-only: never persisted, never exported.
struct RecentApplication: Equatable {
    var bundleIdentifier: String
    var name: String
    var bundleURL: URL
    /// Computed once here; the Dock body compares it against pinned apps on every pass.
    var normalizedURL: URL
    var item: DockItem

    init(bundleIdentifier: String, name: String, bundleURL: URL) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.bundleURL = bundleURL
        normalizedURL = InstalledApplicationIdentity.normalizedURL(bundleURL)
        var item = DockItem.application(at: bundleURL)
        item.id = RuntimeDockIdentity.uuid("recent:" + InstalledApplicationIdentity.key(bundleIdentifier: bundleIdentifier, bundleURL: bundleURL))
        item.title = name
        item.bundleIdentifier = bundleIdentifier
        self.item = item
    }
}

enum RecentApplicationsPolicy {
    /// Remembered at runtime (a few more than shown, so a pinned or running app can be skipped).
    static let capacity = 12
    /// The Dock shows at most this many, like macOS "Show suggested and recent apps".
    static let visibleLimit = 3

    /// Most recent first, one entry per bundle identifier, bounded.
    static func recording(_ app: RecentApplication, into list: [RecentApplication], capacity: Int = capacity) -> [RecentApplication] {
        var result = list.filter { $0.bundleIdentifier != app.bundleIdentifier }
        result.insert(app, at: 0)
        return Array(result.prefix(max(capacity, 1)))
    }

    /// The tiles to draw: recents that are not pinned and, when running apps are shown, not already
    /// running (they are in the running section). Nothing when the setting is off.
    static func items(recents: [RecentApplication], enabled: Bool,
                      pinnedURLs: Set<URL>, pinnedBundleIdentifiers: Set<String>,
                      runningBundleIdentifiers: Set<String>, excludesRunning: Bool,
                      limit: Int = visibleLimit) -> [DockItem] {
        guard enabled, limit > 0 else { return [] }
        return recents.filter { app in
            !pinnedURLs.contains(app.normalizedURL)
                && !pinnedBundleIdentifiers.contains(app.bundleIdentifier)
                && !(excludesRunning && runningBundleIdentifiers.contains(app.bundleIdentifier))
        }.prefix(limit).map(\.item)
    }
}

extension DockRenderModel {
    /// Inserts the recent-apps section after the pinned and running items and before minimized
    /// windows and the system Trash. It uses the existing boundary separator style.
    mutating func insertRecentApplications(_ items: [DockItem], settings: AppSettings) {
        guard settings.showRecentApps, !items.isEmpty else { return }
        let trashID = Self.systemTrash.id
        let index = entries.firstIndex { entry in
            switch entry {
            case .boundary(let kind): kind == "windows"
            case .item(let item, let pinned): !pinned && item.id == trashID
            case .insertion, .window: false
            }
        } ?? entries.count
        entries.insert(contentsOf: [DockRenderEntry.boundary("recent")] + items.map { DockRenderEntry.item($0, pinned: false) }, at: index)
    }
}

/// Recent-application tracking from NSWorkspace activation notifications. Observation exists only
/// while "Show recent apps" is on; turning it off drops the list.
@MainActor
final class RecentApplicationsTracker: ObservableObject {
    static let shared = RecentApplicationsTracker()

    @Published private(set) var recents: [RecentApplication] = []
    private var observation: AnyCancellable?
    /// Whether activation notifications are being observed; never true under isolation.
    var isObserving: Bool { observation != nil }

    func setEnabled(_ enabled: Bool) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        if !enabled {
            observation = nil
            if !recents.isEmpty { recents = [] }
            return
        }
        guard observation == nil else { return }
        observation = NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self,
                      let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.record(app)
            }
    }

    private func record(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, !app.isTerminated,
              let identifier = app.bundleIdentifier, let url = app.bundleURL,
              identifier != Bundle.main.bundleIdentifier else { return }
        let entry = RecentApplication(bundleIdentifier: identifier, name: app.localizedName ?? identifier, bundleURL: url)
        let updated = RecentApplicationsPolicy.recording(entry, into: recents)
            .filter { FileManager.default.fileExists(atPath: $0.bundleURL.path) }
        if updated != recents { recents = updated }
    }
}

extension RuntimeDockApplications {
    /// Recent, unpinned apps to draw after the pinned and running items. Empty when the setting
    /// is off. `runtime` is the running-app list already built for the same pass.
    static func recentItems(profile: DockProfile, settings: AppSettings, runtime: [DockItem],
                            pinnedURLs: Set<URL>) -> [DockItem] {
        guard settings.showRecentApps else { return [] }
        return RecentApplicationsPolicy.items(
            recents: RecentApplicationsTracker.shared.recents, enabled: true, pinnedURLs: pinnedURLs,
            pinnedBundleIdentifiers: Set(profile.items.compactMap { $0.type == .application ? $0.bundleIdentifier : nil }),
            runningBundleIdentifiers: Set(runtime.compactMap(\.bundleIdentifier)),
            excludesRunning: settings.showRunningApps)
    }
}
