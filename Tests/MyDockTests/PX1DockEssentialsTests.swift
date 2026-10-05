import Foundation
import Testing
@testable import MyDock

/// PX-1: drop files on an app tile, the running-app menu policy, and the recent-apps section.
@MainActor
struct PX1DockEssentialsTests {
    private func recent(_ bundle: String, _ path: String) -> RecentApplication {
        RecentApplication(bundleIdentifier: bundle, name: bundle, bundleURL: URL(fileURLWithPath: path))
    }

    private func window(_ title: String, minimized: Bool = false, index: Int = 0) -> DockWindowDescriptor {
        DockWindowDescriptor(processID: 1, windowIndex: index, bundleIdentifier: "com.example.app",
                             applicationName: "App", title: title, isMinimized: minimized, accessibilityIdentifier: nil)
    }

    // MARK: Settings compatibility

    @Test func showRecentAppsDefaultsOffAndDecodesFromOldJSON() throws {
        #expect(!AppSettings().showRecentApps)
        let legacy = #"{"customDockPosition":"left","showRunningApps":false}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(!decoded.showRecentApps)
        #expect(!decoded.showRunningApps)
        var enabled = AppSettings()
        enabled.showRecentApps = true
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(enabled))
        #expect(restored.showRecentApps)
    }

    // MARK: Drop on an app tile

    @Test func onlyExistingFilesAndWebAddressesOpen() {
        let file = URL(fileURLWithPath: "/tmp/exists.txt")
        let missing = URL(fileURLWithPath: "/tmp/missing.txt")
        let web = URL(string: "https://example.com/page")!
        let ftp = URL(string: "ftp://example.com/file")!
        let hostless = URL(string: "https:///nohost")!
        let result = DockDropOpenPolicy.openableURLs([file, missing, web, ftp, hostless]) { $0 == file }
        #expect(result == [file, web])
    }

    @Test func openableURLsAreBounded() {
        let urls = (0..<250).map { URL(fileURLWithPath: "/tmp/f\($0).txt") }
        #expect(DockDropOpenPolicy.openableURLs(urls) { _ in true }.count == DockDropOpenPolicy.maximumURLs)
    }

    @Test func onlyApplicationTilesOpenDroppedContent() {
        #expect(DockDropOpenPolicy.opensDroppedContent(on: .application(at: URL(fileURLWithPath: "/Applications/Safari.app"))))
        #expect(!DockDropOpenPolicy.opensDroppedContent(on: .widget("Clock")))
        #expect(!DockDropOpenPolicy.opensDroppedContent(on: .file(at: URL(fileURLWithPath: "/tmp/a.txt"))))
        #expect(!DockDropOpenPolicy.opensDroppedContent(on: .file(at: URL(fileURLWithPath: "/tmp"), isFolder: true)))
    }

    @Test func reorderDragsDoNotHighlightATileAsAnOpenTarget() {
        #expect(DockDropOpenPolicy.carriesOpenableContent(typeIdentifiers: ["public.file-url"]))
        #expect(DockDropOpenPolicy.carriesOpenableContent(typeIdentifiers: ["public.utf8-plain-text", "public.url"]))
        #expect(!DockDropOpenPolicy.carriesOpenableContent(typeIdentifiers: ["app.mydock.items"]))
        #expect(!DockDropOpenPolicy.carriesOpenableContent(typeIdentifiers: []))
    }

    // MARK: Running-app menu

    @Test func hideTitleReflectsState() {
        #expect(RunningApplicationMenuPolicy.hideTitle(isHidden: false) == "Hide")
        #expect(RunningApplicationMenuPolicy.hideTitle(isHidden: true) == "Show")
    }

    @Test func inlineWindowsAreBoundedAndKeepOrder() {
        let windows = (0..<30).map { window("W\($0)", index: $0) }
        let inline = RunningApplicationMenuPolicy.inlineWindows(windows)
        #expect(inline.count == RunningApplicationMenuPolicy.inlineWindowLimit)
        #expect(inline.first?.title == "W0")
        #expect(RunningApplicationMenuPolicy.inlineWindows([]).isEmpty)
    }

    @Test func forceQuitCopyNamesTheApp() {
        #expect(RunningApplicationMenuPolicy.forceQuitTitle(name: "Notes") == "Force Quit Notes?")
        #expect(RunningApplicationMenuPolicy.discoveryTimeLimit < 2)
    }

    // MARK: Recent apps

    @Test func recordingMovesToFrontDedupesAndBounds() {
        let a = recent("a", "/Applications/A.app")
        let b = recent("b", "/Applications/B.app")
        var list = RecentApplicationsPolicy.recording(a, into: [])
        list = RecentApplicationsPolicy.recording(b, into: list)
        #expect(list.map(\.bundleIdentifier) == ["b", "a"])
        list = RecentApplicationsPolicy.recording(a, into: list)
        #expect(list.map(\.bundleIdentifier) == ["a", "b"])
        let many = (0..<30).reduce([RecentApplication]()) { RecentApplicationsPolicy.recording(recent("app\($1)", "/Applications/App\($1).app"), into: $0) }
        #expect(many.count == RecentApplicationsPolicy.capacity)
        #expect(many.first?.bundleIdentifier == "app29")
    }

    @Test func visibleRecentsSkipPinnedAndRunningAndStopAtThree() {
        let apps = ["a", "b", "c", "d", "e", "f"].map { recent($0, "/Applications/\($0.uppercased()).app") }
        let pinnedURL = InstalledApplicationIdentity.normalizedURL(URL(fileURLWithPath: "/Applications/A.app"))
        let items = RecentApplicationsPolicy.items(
            recents: apps, enabled: true, pinnedURLs: [pinnedURL], pinnedBundleIdentifiers: ["b"],
            runningBundleIdentifiers: ["c"], excludesRunning: true)
        #expect(items.compactMap(\.bundleIdentifier) == ["d", "e", "f"])
        // Running apps are not excluded when the running section is hidden.
        let showingRunning = RecentApplicationsPolicy.items(
            recents: apps, enabled: true, pinnedURLs: [pinnedURL], pinnedBundleIdentifiers: ["b"],
            runningBundleIdentifiers: ["c"], excludesRunning: false)
        #expect(showingRunning.compactMap(\.bundleIdentifier) == ["c", "d", "e"])
        #expect(RecentApplicationsPolicy.items(recents: apps, enabled: false, pinnedURLs: [], pinnedBundleIdentifiers: [],
                                               runningBundleIdentifiers: [], excludesRunning: true).isEmpty)
    }

    @Test func recentItemsAreStableUnpinnedApplications() {
        let first = recent("com.example.a", "/Applications/A.app")
        let second = recent("com.example.a", "/Applications/A.app")
        #expect(first.item.id == second.item.id)
        #expect(first.item.type == .application)
        #expect(first.item.bundleIdentifier == "com.example.a")
        #expect(first.item.url == URL(fileURLWithPath: "/Applications/A.app"))
    }

    @Test func recentSectionFollowsRunningAppsAndPrecedesWindowsAndTrash() {
        var settings = AppSettings()
        settings.showRunningApps = true
        settings.showRecentApps = true
        settings.showTrash = true
        settings.showMinimizedWindows = true
        let profile = DockProfile(name: "P", kind: .custom, items: [.widget("Clock")])
        let running = recent("run", "/Applications/Run.app").item
        let latest = recent("rec", "/Applications/Rec.app").item
        let minimized = window("Doc", minimized: true)
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [running],
                                    windows: [minimized], runningMediaSources: [], recentApplications: [latest])
        let ids = model.entries.map(\.id)
        let runIndex = ids.firstIndex(of: running.id.uuidString)
        let boundaryIndex = ids.firstIndex(of: DockRenderEntry.boundary("recent").id)
        let recentIndex = ids.firstIndex(of: latest.id.uuidString)
        let windowsIndex = ids.firstIndex(of: DockRenderEntry.boundary("windows").id)
        let trashIndex = ids.firstIndex(of: DockRenderModel.systemTrash.id.uuidString)
        #expect(runIndex != nil && boundaryIndex != nil && recentIndex != nil && windowsIndex != nil && trashIndex != nil)
        if let runIndex, let boundaryIndex, let recentIndex, let windowsIndex, let trashIndex {
            #expect(runIndex < boundaryIndex && boundaryIndex < recentIndex)
            #expect(recentIndex < windowsIndex && windowsIndex < trashIndex)
        }
    }

    @Test func noRecentSectionWhenOffOrEmpty() {
        var settings = AppSettings()
        settings.showRunningApps = false
        settings.showTrash = false
        let profile = DockProfile(name: "P", kind: .custom, items: [.widget("Clock")])
        let item = recent("rec", "/Applications/Rec.app").item
        let off = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                  runningMediaSources: [], recentApplications: [item])
        #expect(!off.entries.contains { $0.id == DockRenderEntry.boundary("recent").id })
        settings.showRecentApps = true
        let empty = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                    runningMediaSources: [], recentApplications: [])
        #expect(!empty.entries.contains { $0.id == DockRenderEntry.boundary("recent").id })
        let on = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                 runningMediaSources: [], recentApplications: [item])
        #expect(on.entries.contains { $0.id == DockRenderEntry.boundary("recent").id })
        #expect(on.entries.contains { $0.id == item.id.uuidString })
    }

    @Test func recentBoundaryDrawsALineOnlyBetweenContent() {
        var settings = AppSettings()
        settings.showRunningApps = false
        settings.showTrash = false
        settings.showRecentApps = true
        let profile = DockProfile(name: "P", kind: .custom, items: [.widget("Clock")])
        let item = recent("rec", "/Applications/Rec.app").item
        let model = DockRenderModel(profile: profile, settings: settings, unpinnedRunningApplications: [], windows: [],
                                    runningMediaSources: [], recentApplications: [item])
        // The pinned-end line already separates pinned items from the recents: never two in a row.
        let visible = DockSeparatorPolicy.visibleSeparatorIDs(model.entries)
        #expect(visible.contains(DockRenderEntry.insertion.id))
        #expect(!visible.contains(DockRenderEntry.boundary("recent").id))
    }

    @Test func recentsTrackingNeverRunsUnderIsolation() {
        // Tests run with native effects disabled: enabling the tracker must not observe the system.
        RecentApplicationsTracker.shared.setEnabled(true)
        #expect(RecentApplicationsTracker.shared.recents.isEmpty)
        RecentApplicationsTracker.shared.setEnabled(false)
    }
}
