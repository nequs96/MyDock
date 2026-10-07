import AppKit
import SwiftUI
import Foundation
import Testing
@testable import MyDock

@MainActor
struct ProductRuntimeTests {
    @Test func librariesSanitizeAndRoundTripWithoutRuntimeOrConnections() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var profile = DockProfile(name: "Private", kind: .custom, items: [.widget("Sticky Note"), .widget("Stripe"), .widget("Focus Timer")])
        profile.items[0].widgetConfiguration?.noteText = "Sensitive note"
        profile.items[1].widgetConfiguration?.stripeAccountID = "private-account"
        profile.items[2].widgetConfiguration?.startFocusTimer()
        let library = ProfileLibrary(fileURL: folder.appendingPathComponent("presets.json"))
        library.record(profile, reason: "Preset")
        let entry = try #require(library.entries.first)
        #expect(entry.profile.items[0].widgetConfiguration?.noteText == "")
        #expect(entry.profile.items[1].widgetConfiguration?.stripeAccountID == "")
        #expect(entry.profile.items[2].widgetConfiguration?.focusStartedAt == nil)
        let data = try library.exportPreset(entry.id)
        #expect(!String(decoding: data, as: UTF8.self).contains("Sensitive note"))
        let reopened = ProfileLibrary(fileURL: folder.appendingPathComponent("presets.json"))
        #expect(reopened.entries.count == 1)
        try reopened.importPreset(data)
        #expect(reopened.entries.count == 2)
    }

    @Test func updateRepositoryAndVersionValidationAreStrict() {
        #expect(ReleaseRepository(url: "http://github.com/a/b") == nil)
        #expect(ReleaseRepository(url: "https://github.com/a/b/releases") != nil)
        #expect(ReleaseRepository(url: "https://github.com/a/b?token=secret") == nil)
        #expect(ReleaseVersion.isNewer("v1.2.10", than: "1.2.9"))
        #expect(!ReleaseVersion.isNewer("1.2.0-beta", than: "1.1.0"))
        #expect(!ReleaseVersion.isNewer("1.0.0", than: "1.0.0"))
        #expect(!ReleaseVersion.isNewer("2.٢.0", than: "1.0.0"))
        #expect(ReleaseRepository(url: "https://github.com/a/b")?.validates(URL(string: "https://github.com:444/a/b/releases/tag/v2.0.0")!) == false)
    }

    @Test func overviewSuppressionIgnoresNormalDockShelf() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        #expect(!SystemOverviewPolicy.isPresent(screen: screen, dockFrames: [NSRect(x: 100, y: 0, width: 1200, height: 80)]))
        #expect(SystemOverviewPolicy.isPresent(screen: screen, dockFrames: [screen]))
    }

    @Test func desktopWindowsCannotSuppressDockAfterPresentationTick() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let shelf = NSRect(x: 100, y: 0, width: 1200, height: 80)
        let surfaces = [(layer: -2147483623, frame: screen), (layer: 20, frame: shelf)]
            .filter { SystemDockWindowPolicy.isPresentationSurface(layer: $0.layer, alpha: 1, frame: $0.frame) }
            .map(\.frame)
        #expect(surfaces == [shelf])
        #expect(!SystemOverviewPolicy.isPresent(screen: screen, dockFrames: surfaces))
        #expect(!SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: NSRect(x: 0, y: 200, width: 80, height: 500), systemDockFrames: surfaces))
        // Genuine foreground overview surfaces must still suppress the panel.
        #expect(SystemDockWindowPolicy.isPresentationSurface(layer: 0, alpha: 1, frame: screen))
        #expect(SystemOverviewPolicy.isPresent(screen: screen, dockFrames: [screen]))
    }

    @Test func invisibleAndInvalidDockWindowsAreExcluded() {
        let frame = NSRect(x: 0, y: 0, width: 600, height: 80)
        #expect(!SystemDockWindowPolicy.isPresentationSurface(layer: 20, alpha: 0, frame: frame))
        #expect(!SystemDockWindowPolicy.isPresentationSurface(layer: 20, alpha: .nan, frame: frame))
        #expect(!SystemDockWindowPolicy.isPresentationSurface(layer: 20, alpha: 1, frame: .zero))
        #expect(!SystemDockWindowPolicy.isPresentationSurface(layer: 20, alpha: 1, frame: NSRect(x: 0, y: 0, width: CGFloat.infinity, height: 80)))
    }

    @Test func queuedRevealCannotResurrectDisabledOrMissingDock() {
        for mode in SetupMode.allCases {
            #expect(!CustomDockVisibilityPolicy.canPresent(mode: mode, hasActiveProfile: false))
            #expect(CustomDockVisibilityPolicy.canPresent(mode: mode, hasActiveProfile: true) == (mode != .nativeOnly))
        }
    }

    @Test func everyWidgetHasADrawableNativeSymbol() {
        for widget in WidgetRegistry.all {
            #expect(NSImage(systemSymbolName: widget.symbol, accessibilityDescription: nil) != nil,
                    "Missing SF Symbol for \(widget.name): \(widget.symbol)")
        }
    }

    @Test func dockResizeFollowsTheScreenEdgeRatherThanItsLength() {
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: 0, height: -36), position: .bottom) == 1.2)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: 36, height: 0), position: .left) == 1.2)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: -36, height: 0), position: .right) == 1.2)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: 90, height: 0), position: .bottom) == 1)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: 0, height: 90), position: .left) == 1)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: 0, height: -1_000), position: .bottom) == 1.5)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: -1_000, height: 0), position: .left) == 0.65)
        let onePoint = DockResizePolicy.size(start: 1, translation: CGSize(width: 0, height: -1), position: .bottom)
        let twoPoints = DockResizePolicy.size(start: 1, translation: CGSize(width: 0, height: -2), position: .bottom)
        #expect(onePoint > 1 && onePoint < 1.01)
        #expect(twoPoints > onePoint && twoPoints < 1.02)
    }

    /// An isolated Custom Dock panel exercises the real 500 ms presentation loop.
    /// It never starts NativeDockAutoHideController or changes Apple's Dock.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYDOCK_CUSTOM_DOCK_RUNTIME_TESTS"] == "1"))
    func customDockRemainsVisibleAcrossPresentationTicksAndModeChanges() async throws {
        let application = NSApplication.shared
        let existingWindows = Set(application.windows.map(\.windowNumber))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Presentation regression")
        store.add(.widget("Clock"), to: id)
        store.updateSettings {
            $0.setupMode = .both
            $0.showRunningApps = false
            $0.showTrash = false
            $0.automaticallyHideCustomDock = false
            $0.hideCustomDockWhenSystemDockAppears = false
            $0.customDockTheme = .dark
        }
        // Overview metadata is tested independently. A lock-screen surface must not
        // change the result of this isolated panel's presentation/interaction test.
        let controller = CustomDockWindowController(store: store, overviewIsPresent: { _, _ in false })
        controller.update(state: store.state)
        let panel = try #require(application.windows.first {
            !existingWindows.contains($0.windowNumber) && $0.contentView is NSHostingView<CustomDockView>
        })
        defer {
            store.updateSettings { $0.setupMode = .nativeOnly }
            controller.update(state: store.state)
            panel.close()
            store.flush()
            try? FileManager.default.removeItem(at: directory)
        }
        for position in DockPosition.allCases {
            store.updateSettings { $0.customDockPosition = position }
            for mode in [SetupMode.both, .customMain, .nativeOnly, .both] {
                store.setSetupMode(mode)
                controller.update(state: store.state)
                // Cover two polling ticks and both transition animations for every mode.
                for _ in 0..<6 {
                    try await Task.sleep(for: .milliseconds(200))
                    #expect(panel.isVisible == (mode != .nativeOnly), "\(position.rawValue), \(mode.rawValue)")
                }
                #expect(panel.alphaValue == (mode == .nativeOnly ? 0 : 1))
            }
        }
        // A submenu extends outside its Dock anchor. Tracking must retain that anchor.
        let menu = NSMenu(title: "Spacer fixture")
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        defer { NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu) }
        store.updateSettings { $0.automaticallyHideCustomDock = true }
        controller.update(state: store.state)
        try await Task.sleep(for: .milliseconds(700))
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        DockInteractionState.isResizing = true
        defer { DockInteractionState.isResizing = false }
        store.setDockSize(0.93, for: id)
        controller.update(state: store.state)
        try await Task.sleep(for: .milliseconds(700))
        #expect(panel.isVisible)
        #expect(panel.alphaValue == 1)
    }

    @Test func renderModelIncludesEveryRuntimeClassAndFinalTrash() {
        var settings = AppSettings()
        settings.showTrash = true; settings.showMinimizedWindows = true
        var media = DockItem.widget("Now Playing")
        media.widgetConfiguration?.nowPlayingHidesWhenClosed = true
        let profile = DockProfile(name: "Test", kind: .custom, items: [.widget("Clock"), media])
        let app = DockItem.application(at: URL(fileURLWithPath: "/Applications/Test.app"))
        let window = DockWindowDescriptor(processID: 42, windowIndex: 0, bundleIdentifier: "test", applicationName: "Test", title: "Document", isMinimized: true)
        let model = DockRenderModel(profile: profile, settings: settings, runningApplications: [app], windows: [window], runningMediaSources: [])
        #expect(!model.entries.contains { $0.id == media.id.uuidString })
        #expect(model.entries.contains { $0.id == app.id.uuidString })
        #expect(model.entries.contains { $0.id == window.id })
        #expect(model.entries.last?.id == DockRenderModel.systemTrash.id.uuidString)
        let expected = model.entries.reduce(CGFloat(0)) { $0 + $1.length(settings: settings, scale: 1) }
            + CGFloat(model.entries.count - 1) * CGFloat(settings.customDockItemSpacing) + 2
        #expect(model.contentLength(settings: settings, scale: 1) == expected)
    }

    @Test func continuousWaveAndRuntimeIdentityAreStable() {
        #expect(RuntimeDockIdentity.uuid("app") == RuntimeDockIdentity.uuid("app"))
        #expect(RuntimeDockIdentity.uuid("app") != RuntimeDockIdentity.uuid("other"))
        let scale = DockContinuousMagnification.scale(center: 50, pointer: 50, radius: 100, isWidget: false, enabled: true, reduceMotion: false)
        #expect(abs(scale - 1.38) < 0.001)
        let near = DockContinuousMagnification.scale(center: 50, pointer: 51, radius: 100, isWidget: false, enabled: true, reduceMotion: false)
        #expect(abs(scale - near) < 0.001)
        #expect(DockContinuousMagnification.scale(center: 50, pointer: 50, radius: 100, isWidget: false, enabled: true, reduceMotion: true) == 1)
    }

    @Test func groupMovePreservesRelativeOrderAndSupportsEnd() {
        let items = [DockItem.widget("Clock"), .spacer(.small), .widget("Battery"), .widget("Weather")]
        let moved = DockItemOrderingPolicy.moving(items, ids: Set([items[0].id, items[2].id]), before: nil)
        #expect(moved.map(\.id) == [items[1].id, items[3].id, items[0].id, items[2].id])
        #expect(DockItemOrderingPolicy.moving(items, ids: [items[0].id], before: items[0].id) == items)
    }

    @Test func windowRestoreNeverGuessesBetweenMatchingWindows() {
        #expect(WindowRestoreIdentity.uniqueIndex([1]) == 1)
        #expect(WindowRestoreIdentity.uniqueIndex([0, 1]) == nil)
        #expect(WindowRestoreIdentity.uniqueIndex([]) == nil)
    }

    @Test func profileAppearanceInheritsAndOverridesWithoutChangingBehavior() throws {
        var settings = AppSettings(); settings.showRunningApps = false
        var local = settings; local.customDockMaterial = .dark; local.customDockSize = 0.8
        let resolved = ProfileAppearance(settings: local).applying(to: settings)
        #expect(resolved.customDockSize == 0.8)
        #expect(!resolved.showRunningApps)
        var invalid = ProfileAppearance(settings: settings); invalid.size = .infinity
        #expect(throws: ProfileValidationError.self) { try invalid.validate() }
    }

    @Test func sharedWidgetQueriesCoalesceAndPreserveConfiguration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let id = try store.createProfileAndPersist(kind: .custom)
        let first = DockItem.widget("AI Limits"), second = DockItem.widget("AI Limits")
        store.add(first, to: id); store.add(second, to: id)
        var count = 0
        let coordinator = WidgetDataCoordinator(store: store) { query, _ in
            count += 1
            try await Task.sleep(for: .milliseconds(20))
            return .limits(AILimitsSnapshot(fetchedAt: Date(timeIntervalSince1970: 123), readings: [], sourceScope: query.aiSourceScope))
        }
        async let a: Void = coordinator.refresh(item: first, profileID: id)
        async let b: Void = coordinator.refresh(item: second, profileID: id)
        store.updateWidgetConfiguration(itemID: second.id, in: id) { $0.cardWidth = .wide }
        _ = await (a, b)
        #expect(count == 1)
        let items = try #require(store.activeCustomProfile.map { store.presentationProfile($0).items })
        #expect(items.allSatisfy { $0.widgetConfiguration?.aiLimitsSnapshot?.fetchedAt == Date(timeIntervalSince1970: 123) })
        #expect(items[1].widgetConfiguration?.cardWidth == .wide)
        store.flush()
    }

    @Test func queuedOlderSnapshotCannotOverwriteImmediateFlush() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let id = try store.createProfileAndPersist(kind: .custom)
        let item = DockItem.widget("Sticky Note"); store.add(item, to: id)
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.noteText = "Old" }
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.noteText = "Newest" }
        store.flush()
        try await Task.sleep(for: .milliseconds(220))
        let restored = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        #expect(restored.activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "Newest")
    }

    @Test func unitSeparatorMediaParsingPreservesNewlinesInTrackTitles() throws {
        let text = "Title\nwith newline\u{1f}Artist\u{1f}Album\u{1f}playing\u{1f}10\u{1f}120\u{1f}"
        #expect(try NowPlayingResponseParser.snapshot(from: text)?.title == "Title\nwith newline")
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNGf89504E47»") == Data([0x89, 0x50, 0x4e, 0x47]))
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNGfXYZ»") == nil)
    }
}
