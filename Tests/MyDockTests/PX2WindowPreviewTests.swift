import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MyDock

/// PX-2: window previews on hover. Pure logic only; nothing here touches the real system.
@Suite struct PX2WindowPreviewTests {
    typealias Machine = WindowPreviewHoverMachine

    // MARK: Hover timing

    @Test func defaultTimings() {
        let machine = Machine()
        #expect(machine.showDelay == 0.5)
        #expect(machine.closeGrace == 0.3)
        #expect(machine.phase == .idle)
    }

    @Test func showsOnlyAfterTheHoverDelay() {
        var machine = makeMachine()
        #expect(machine.handle(.enterTile("safari"), at: 10) == .noChange)
        #expect(machine.nextDeadline == 10.5)
        #expect(machine.displayedTarget == nil)
        #expect(machine.handle(.tick, at: 10.3) == .noChange)
        #expect(machine.handle(.tick, at: 10.5) == .show("safari"))
        #expect(machine.displayedTarget == "safari")
        // Open with the pointer inside: no wake-up is pending.
        #expect(machine.nextDeadline == nil)
    }

    @Test func leavingBeforeTheDelayCancelsWithoutShowing() {
        var machine = makeMachine()
        _ = machine.handle(.enterTile("safari"), at: 0)
        #expect(machine.handle(.exitTile("safari"), at: 0.2) == .noChange)
        #expect(machine.phase == .idle)
        #expect(machine.nextDeadline == nil)
        #expect(machine.handle(.tick, at: 1) == .noChange)
    }

    @Test func movingToAnotherTileBeforeShowingRestartsTheDelay() {
        var machine = makeMachine()
        _ = machine.handle(.enterTile("safari"), at: 0)
        _ = machine.handle(.exitTile("safari"), at: 0.25)
        _ = machine.handle(.enterTile("notes"), at: 0.25)
        #expect(machine.nextDeadline == 0.75)
        #expect(machine.handle(.tick, at: 0.5) == .noChange)
        #expect(machine.handle(.tick, at: 0.75) == .show("notes"))
    }

    @Test func leavingBothTileAndPanelClosesAfterTheGrace() {
        var machine = openMachine("safari")
        #expect(machine.handle(.exitTile("safari"), at: 2) == .noChange)
        #expect(machine.nextDeadline == 2.25)
        #expect(machine.displayedTarget == "safari")
        #expect(machine.handle(.tick, at: 2.2) == .noChange)
        #expect(machine.handle(.tick, at: 2.25) == .close)
        #expect(machine.phase == .idle)
    }

    @Test func movingIntoThePanelKeepsItOpen() {
        var machine = openMachine("safari")
        _ = machine.handle(.exitTile("safari"), at: 2)
        #expect(machine.handle(.enterPanel, at: 2.125) == .noChange)
        #expect(machine.phase == .open("safari"))
        #expect(machine.handle(.tick, at: 5) == .noChange)
        // Leaving the panel (not onto a tile) starts the grace again.
        _ = machine.handle(.exitPanel, at: 5)
        #expect(machine.nextDeadline == 5.25)
        // Returning to the same tile within the grace keeps it, with no swap.
        #expect(machine.handle(.enterTile("safari"), at: 5.125) == .noChange)
        #expect(machine.phase == .open("safari"))
    }

    @Test func leavingTheTileWhileInsideThePanelDoesNotStartTheGrace() {
        var machine = openMachine("safari")
        _ = machine.handle(.enterPanel, at: 2)
        _ = machine.handle(.exitTile("safari"), at: 2)
        #expect(machine.phase == .open("safari"))
        #expect(machine.nextDeadline == nil)
    }

    @Test func anotherRunningAppSwapsWithoutADelay() {
        var machine = openMachine("safari")
        _ = machine.handle(.exitTile("safari"), at: 3)
        #expect(machine.handle(.enterTile("notes"), at: 3.05) == .swap("notes"))
        #expect(machine.displayedTarget == "notes")
        #expect(machine.nextDeadline == nil)
        // From the panel straight onto another tile also swaps at once.
        _ = machine.handle(.enterPanel, at: 3.2)
        _ = machine.handle(.exitTile("notes"), at: 3.2)
        _ = machine.handle(.exitPanel, at: 3.4)
        #expect(machine.handle(.enterTile("mail"), at: 3.45) == .swap("mail"))
    }

    @Test func aLateExitFromThePreviousTileIsIgnored() {
        var machine = openMachine("safari")
        #expect(machine.handle(.enterTile("notes"), at: 3) == .swap("notes"))
        #expect(machine.handle(.exitTile("safari"), at: 3.01) == .noChange)
        #expect(machine.phase == .open("notes"))
    }

    @Test func dismissClosesAndNeedsAFreshHoverToArmAgain() {
        var machine = openMachine("safari")
        #expect(machine.handle(.dismiss, at: 4) == .close)
        #expect(machine.phase == .idle)
        #expect(machine.handle(.tick, at: 9) == .noChange)
        // Dismissing while idle or arming shows nothing and closes nothing.
        var arming = makeMachine()
        _ = arming.handle(.enterTile("safari"), at: 0)
        #expect(arming.handle(.dismiss, at: 0.1) == .noChange)
        #expect(arming.handle(.tick, at: 1) == .noChange)
        // Leave and come back: the delay applies again.
        _ = machine.handle(.exitTile("safari"), at: 9)
        _ = machine.handle(.enterTile("safari"), at: 9)
        #expect(machine.nextDeadline == 9.5)
    }

    @Test func retainedTargetsCoverOnlyTheHoveredAndDisplayedTiles() {
        var machine = openMachine("safari")
        #expect(machine.retainedTargets == ["safari"])
        _ = machine.handle(.enterTile("notes"), at: 3)
        #expect(machine.retainedTargets == ["notes"])
        _ = machine.handle(.dismiss, at: 4)
        _ = machine.handle(.exitTile("notes"), at: 4)
        #expect(machine.retainedTargets.isEmpty)
    }

    // MARK: Anchor geometry

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func bottomDockPanelSitsAboveTheDockCentredOnTheTile() {
        let frame = WindowPreviewPanelGeometry.frame(size: CGSize(width: 380, height: 180),
                                                     tile: CGRect(x: 500, y: 11, width: 54, height: 54),
                                                     dock: CGRect(x: 400, y: 0, width: 640, height: 90),
                                                     position: .bottom, bounds: screen)
        #expect(frame == CGRect(x: 337, y: 98, width: 380, height: 180))
        // Near the screen edge it stays on screen.
        let edge = WindowPreviewPanelGeometry.frame(size: CGSize(width: 380, height: 180),
                                                    tile: CGRect(x: 10, y: 11, width: 54, height: 54),
                                                    dock: CGRect(x: 0, y: 0, width: 640, height: 90),
                                                    position: .bottom, bounds: screen)
        #expect(edge.minX == WindowPreviewPanelGeometry.screenMargin)
        #expect(edge.minY == 98)
    }

    @Test func leftDockPanelSitsBesideTheDock() {
        let frame = WindowPreviewPanelGeometry.frame(size: CGSize(width: 196, height: 300),
                                                     tile: CGRect(x: 11, y: 400, width: 54, height: 54),
                                                     dock: CGRect(x: 0, y: 200, width: 90, height: 500),
                                                     position: .left, bounds: screen)
        #expect(frame == CGRect(x: 98, y: 277, width: 196, height: 300))
    }

    @Test func rightDockPanelSitsBesideTheDockAndStaysBelowTheMenuBar() {
        let frame = WindowPreviewPanelGeometry.frame(size: CGSize(width: 196, height: 300),
                                                     tile: CGRect(x: 1361, y: 800, width: 54, height: 54),
                                                     dock: CGRect(x: 1350, y: 200, width: 90, height: 500),
                                                     position: .right, bounds: screen)
        #expect(frame.minX == 1146)
        #expect(frame.maxX == 1350 - WindowPreviewPanelGeometry.gap)
        #expect(frame.maxY == screen.maxY - WindowPreviewPanelGeometry.screenMargin)
    }

    @Test func oversizedPanelsShrinkToTheScreen() {
        let frame = WindowPreviewPanelGeometry.frame(size: CGSize(width: 2000, height: 2000),
                                                     tile: CGRect(x: 500, y: 11, width: 54, height: 54),
                                                     dock: CGRect(x: 400, y: 0, width: 640, height: 90),
                                                     position: .bottom, bounds: screen)
        #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
    }

    @Test func theGapStaysInsideTheRevealKeepVisibleMargins() {
        // The auto-hidden Dock stays revealed while the pointer crosses from tile to panel.
        let dock = NSRect(x: 400, y: 0, width: 640, height: 90)
        let panel = NSRect(x: 337, y: 98, width: 380, height: 180)
        for y in stride(from: dock.maxY, through: panel.minY, by: 1) {
            #expect(CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: NSPoint(x: 527, y: y),
                                                                       expandedFrame: dock, popoutFrames: [panel]))
        }
    }

    // MARK: Layout

    @Test func panelSizesFollowTheContent() {
        let thumbnails = WindowPreviewPresentation(body: .thumbnails, offersThumbnails: false)
        #expect(WindowPreviewPanelLayout.size(for: thumbnails, windowCount: 2, position: .bottom) == CGSize(width: 380, height: 180))
        #expect(WindowPreviewPanelLayout.size(for: thumbnails, windowCount: 9, position: .bottom).width == 748)
        #expect(WindowPreviewPanelLayout.size(for: thumbnails, windowCount: 5, position: .left) == CGSize(width: 196, height: 460))
        let titles = WindowPreviewPresentation(body: .titles, offersThumbnails: true)
        #expect(WindowPreviewPanelLayout.size(for: titles, windowCount: 3, position: .bottom) == CGSize(width: 280, height: 190))
        let plainTitles = WindowPreviewPresentation(body: .titles, offersThumbnails: false)
        #expect(WindowPreviewPanelLayout.size(for: plainTitles, windowCount: 20, position: .right).height == 288)
        let notice = WindowPreviewPresentation(body: .accessibilityRequired, offersThumbnails: false)
        #expect(WindowPreviewPanelLayout.size(for: notice, windowCount: 0, position: .bottom) == CGSize(width: 280, height: 92))
    }

    @Test func openWindowsListFirstAndTheListIsBounded() {
        let windows = (0..<15).map { index in
            DockWindowDescriptor(processID: 7, windowIndex: index, bundleIdentifier: "com.example.editor",
                                 applicationName: "Editor", title: "Window \(index)", isMinimized: index % 3 == 0,
                                 accessibilityIdentifier: nil)
        }
        let displayed = WindowPreviewListPolicy.displayed(windows)
        #expect(displayed.count == WindowPreviewPanelLayout.maximumWindows)
        #expect(displayed.prefix(10).allSatisfy { !$0.isMinimized })
        #expect(displayed.suffix(2).allSatisfy { $0.isMinimized })
        #expect(displayed.first?.windowIndex == 1)
    }

    // MARK: Permission → presentation

    @Test func permissionsMapToOneHonestPresentation() {
        func present(_ ax: Bool, _ recording: Bool, _ supported: Bool = true,
                     _ discovery: WindowPreviewDiscoveryState = .windows(2)) -> WindowPreviewPresentation {
            WindowPreviewPresentationPolicy.presentation(accessibilityTrusted: ax, screenRecordingAllowed: recording,
                                                         captureSupported: supported, discovery: discovery)
        }
        // Without Accessibility: one explanatory line, whatever else is allowed.
        #expect(present(false, true) == .init(body: .accessibilityRequired, offersThumbnails: false))
        #expect(present(true, true, true, .permissionRequired).body == .accessibilityRequired)
        // Both allowed: thumbnails.
        #expect(present(true, true) == .init(body: .thumbnails, offersThumbnails: false))
        // No Screen Recording: titles only, with one "Show thumbnails…" row.
        #expect(present(true, false) == .init(body: .titles, offersThumbnails: true))
        // Capture unsupported (macOS 13): titles only, no offer that cannot be honoured.
        #expect(present(true, false, false) == .init(body: .titles, offersThumbnails: false))
        #expect(present(true, true, false).body == .titles)
        // Discovery states.
        #expect(present(true, false, true, .pending) == .init(body: .loading, offersThumbnails: false))
        #expect(present(true, true, true, .windows(0)).body == .empty)
        #expect(present(true, true, true, .unavailable).body == .unavailable)
    }

    @Test func onlyRunningAppsInTheLiveDockCarryTheHoverRegion() {
        #expect(WindowPreviewEligibility.showsRegion(itemType: .application, isRunning: true, isPreview: false, popoutOpen: false, enabled: true))
        #expect(!WindowPreviewEligibility.showsRegion(itemType: .application, isRunning: true, isPreview: false, popoutOpen: false, enabled: false))
        #expect(!WindowPreviewEligibility.showsRegion(itemType: .application, isRunning: false, isPreview: false, popoutOpen: false, enabled: true))
        #expect(!WindowPreviewEligibility.showsRegion(itemType: .application, isRunning: true, isPreview: true, popoutOpen: false, enabled: true))
        #expect(!WindowPreviewEligibility.showsRegion(itemType: .application, isRunning: true, isPreview: false, popoutOpen: true, enabled: true))
        #expect(!WindowPreviewEligibility.showsRegion(itemType: .folder, isRunning: true, isPreview: false, popoutOpen: false, enabled: true))
    }

    // MARK: Thumbnail cache

    @Test func thumbnailCacheIsBoundedByCountAndAge() {
        var cache = WindowPreviewThumbnailCache<Int>(capacity: 2, maximumAge: 60)
        cache.store(1, for: "a", at: 0)
        cache.store(2, for: "b", at: 1)
        let touched = cache.image(for: "a", at: 2)   // "a" is now most recently used
        #expect(touched == 1)
        cache.store(3, for: "c", at: 3)
        #expect(cache.count == 2)
        let evicted = cache.image(for: "b", at: 4)    // least recently used went first
        let kept = cache.image(for: "a", at: 4)
        #expect(evicted == nil)
        #expect(kept == 1)
        #expect(cache.isFresh("c", within: 5, at: 4))
        #expect(!cache.isFresh("c", within: 5, at: 9))
        let expired = cache.image(for: "c", at: 100)
        #expect(expired == nil)
        cache.removeAll()
        #expect(cache.count == 0)
    }

    // MARK: Settings compatibility

    @Test func oldSettingsDecodeWithPreviewsOnHoverOff() throws {
        let old = #"{"showMinimizedWindows":true,"showWindowPreviews":true,"showRunningApps":true}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(!decoded.showWindowPreviewsOnHover)
        #expect(decoded.showWindowPreviews)
        #expect(!AppSettings().showWindowPreviewsOnHover)

        let malformed = #"{"showWindowPreviewsOnHover":"yes"}"#
        #expect(try !JSONDecoder().decode(AppSettings.self, from: Data(malformed.utf8)).showWindowPreviewsOnHover)

        var current = AppSettings()
        current.showWindowPreviewsOnHover = true
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current))
        #expect(restored.showWindowPreviewsOnHover)
        #expect(!restored.showWindowPreviews)
    }

    @Test func settingIsSearchable() {
        #expect(SettingsSearchCatalog.matches("hover").contains { $0.title == "Show window previews" && $0.page == .behavior })
        #expect(SettingsSearchCatalog.pages(matching: "window previews").contains(.behavior))
    }

    // MARK: Helpers

    /// Binary-exact timings keep deadline comparisons exact.
    private func makeMachine() -> Machine { Machine(showDelay: 0.5, closeGrace: 0.25) }

    private func openMachine(_ key: String) -> Machine {
        var machine = makeMachine()
        _ = machine.handle(.enterTile(key), at: 0)
        _ = machine.handle(.tick, at: 0.5)
        return machine
    }
}
