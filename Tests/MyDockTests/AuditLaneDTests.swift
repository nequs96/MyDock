import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// Audit lane D: live Dock running state, accessibility values, drop routing, recents and bounds.
@MainActor
@Suite struct AuditLaneDTests {
    private func app(_ bundle: String, _ path: String) -> DockItem {
        var item = DockItem.application(at: URL(fileURLWithPath: path))
        item.bundleIdentifier = bundle
        return item
    }

    // MARK: Running dots

    @Test func recentAppsShowTheirRunningStateWhenTheRunningSectionIsHidden() {
        let recent = app("com.example.recent", "/Applications/Recent.app")
        #expect(DockTileRunningState.isRunning(recent, pinned: false, isRecent: true, runningPinnedIDs: [],
                                               runningBundleIdentifiers: ["com.example.recent"]))
        #expect(!DockTileRunningState.isRunning(recent, pinned: false, isRecent: true, runningPinnedIDs: [],
                                                runningBundleIdentifiers: ["com.example.other"]))
    }

    @Test func pinnedAppsUseTheMatchedRunningCopiesAndRunningEntriesAreRunning() {
        let pinned = app("com.example.pinned", "/Applications/Pinned.app")
        #expect(DockTileRunningState.isRunning(pinned, pinned: true, isRecent: false, runningPinnedIDs: [pinned.id],
                                               runningBundleIdentifiers: []))
        #expect(!DockTileRunningState.isRunning(pinned, pinned: true, isRecent: false, runningPinnedIDs: [],
                                                runningBundleIdentifiers: ["com.example.pinned"]))
        // The running section lists running apps only.
        #expect(DockTileRunningState.isRunning(pinned, pinned: false, isRecent: false, runningPinnedIDs: [],
                                               runningBundleIdentifiers: []))
        // The system Trash and other widgets never show a dot.
        #expect(!DockTileRunningState.isRunning(DockRenderModel.systemTrash, pinned: false, isRecent: false,
                                                runningPinnedIDs: [], runningBundleIdentifiers: []))
    }

    // MARK: VoiceOver

    @Test func tileValueReadsRunningMissingAndBadgeState() {
        #expect(DockTileAccessibility.value(isRunning: false, isMissing: false, badge: nil) == "")
        #expect(DockTileAccessibility.value(isRunning: true, isMissing: false, badge: nil) == "Running")
        #expect(DockTileAccessibility.value(isRunning: true, isMissing: true, badge: "3")
                == "Running, Saved location unavailable, Badge 3")
    }

    // MARK: Drop routing

    @Test func typedDropsMoveUnpinAndPinRuntimeApps() {
        let pinned = app("com.example.pinned", "/Applications/Pinned.app")
        let widget = DockItem.widget("Clock")
        let profile = DockProfile(name: "P", kind: .custom, items: [pinned, widget])
        let running = app("com.example.running", "/Applications/Running.app")
        let target = widget.id

        let move = DockDragPayload(profileID: profile.id, itemIDs: [pinned.id])
        #expect(DockDropRouter.typedDrop(move, profile: profile, runtimeApps: [running], before: target, unpin: false)
                == .move([pinned.id], before: target))
        // The running-apps boundary unpins applications only.
        #expect(DockDropRouter.typedDrop(move, profile: profile, runtimeApps: [], before: nil, unpin: true) == .unpin([pinned.id]))
        let widgetOnly = DockDragPayload(profileID: profile.id, itemIDs: [widget.id])
        #expect(DockDropRouter.typedDrop(widgetOnly, profile: profile, runtimeApps: [], before: nil, unpin: true) == DockDropAction.rejected)

        let pin = DockDragPayload(profileID: profile.id, itemIDs: [running.id])
        #expect(DockDropRouter.typedDrop(pin, profile: profile, runtimeApps: [running], before: target, unpin: false)
                == .pin([running], before: target))
        // A running app dropped back on its own section stays unpinned.
        #expect(DockDropRouter.typedDrop(pin, profile: profile, runtimeApps: [running], before: nil, unpin: true) == DockDropAction.rejected)
        // Another Dock's items are never moved here.
        let foreign = DockDragPayload(profileID: UUID(), itemIDs: [pinned.id])
        #expect(DockDropRouter.typedDrop(foreign, profile: profile, runtimeApps: [], before: nil, unpin: false) == DockDropAction.rejected)
    }

    @Test func bundleOnlyPayloadsPinOnlyAnUnambiguousCopy() {
        let profile = DockProfile(name: "P", kind: .custom, items: [])
        let first = app("com.example.app", "/Applications/App.app")
        let second = app("com.example.app", "/Volumes/Other/App.app")
        let payload = DockDragPayload(runningBundleIdentifier: "com.example.app")
        #expect(DockDropRouter.typedDrop(payload, profile: profile, runtimeApps: [first], before: nil, unpin: false)
                == .pin([first], before: nil))
        #expect(DockDropRouter.typedDrop(payload, profile: profile, runtimeApps: [first, second], before: nil, unpin: false)
                == DockDropAction.rejected)
    }

    @Test func externalDropsAddExistingFilesAndSafeLinksOnly() {
        let file = URL(fileURLWithPath: "/tmp/Report.pdf")
        let folder = URL(fileURLWithPath: "/tmp/Projects")
        let application = URL(fileURLWithPath: "/Applications/Example.APP")
        let missing = URL(fileURLWithPath: "/tmp/missing.txt")
        let link = URL(string: "https://example.com/page")!
        let credentials = URL(string: "https://user:secret@example.com/")!
        let ftp = URL(string: "ftp://example.com/file")!
        let existing: Set<URL> = [file, folder, application]
        let items = DockDropRouter.externalItems(for: [file, folder, application, missing, link, credentials, ftp],
                                                 fileExists: { existing.contains($0) }, isDirectory: { $0 == folder })
        #expect(items.map(\.type) == [.file, .folder, .application, .link])
        #expect(items.last?.url == link)
        #expect(items.last?.title == "example.com")
        #expect(!items.contains { $0.url?.absoluteString.contains("secret") == true })
    }

    @Test func externalDropsAreBounded() {
        let urls = (0..<250).map { URL(fileURLWithPath: "/tmp/f\($0).txt") }
        #expect(DockDropRouter.externalItems(for: urls, fileExists: { _ in true }, isDirectory: { _ in false }).count
                == DockDropOpenPolicy.maximumURLs)
    }

    @Test func openWithDropsRejectAddressesCarryingCredentials() {
        let safe = URL(string: "https://example.com/")!
        let credentials = URL(string: "https://user:secret@example.com/")!
        #expect(DockDropOpenPolicy.openableURLs([safe, credentials]) { _ in false } == [safe])
    }

    // MARK: Recent apps

    @Test func recentsRecordRegularAppsOtherThanMyDockAndPruneMissingBundles() {
        let tracker = RecentApplicationsTracker()
        let a = URL(fileURLWithPath: "/Applications/A.app")
        let b = URL(fileURLWithPath: "/Applications/B.app")
        var present: Set<URL> = [a, b]
        func record(_ bundle: String?, _ url: URL?, policy: NSApplication.ActivationPolicy = .regular) {
            tracker.record(bundleIdentifier: bundle, name: nil, bundleURL: url, activationPolicy: policy,
                           ownBundleIdentifier: "app.mydock", fileExists: { present.contains($0) })
        }
        record("com.example.a", a)
        record("com.example.b", b)
        #expect(tracker.recents.map(\.bundleIdentifier) == ["com.example.b", "com.example.a"])
        #expect(tracker.recents.first?.name == "com.example.b")
        // MyDock itself, background agents and apps without a bundle never count.
        record("app.mydock", URL(fileURLWithPath: "/Applications/MyDock.app"))
        record("com.example.agent", URL(fileURLWithPath: "/Applications/Agent.app"), policy: .accessory)
        record(nil, URL(fileURLWithPath: "/Applications/C.app"))
        record("com.example.c", nil)
        #expect(tracker.recents.map(\.bundleIdentifier) == ["com.example.b", "com.example.a"])
        // A bundle that was deleted drops out on the next activation.
        present.remove(b)
        record("com.example.a", a)
        #expect(tracker.recents.map(\.bundleIdentifier) == ["com.example.a"])
    }

    // MARK: Bounds and identities

    @Test func accessibilityMessagingNeverWaitsPastTheDeadline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(WindowAccessibilityService.messagingTimeout(until: now.addingTimeInterval(5), now: now) == 0.1)
        #expect(abs(WindowAccessibilityService.messagingTimeout(until: now.addingTimeInterval(0.04), now: now) - 0.04) < 0.0001)
        #expect(WindowAccessibilityService.messagingTimeout(until: now.addingTimeInterval(-1), now: now) == 0.01)
    }

    @Test func dockSizeBoundsAreSharedByLayoutAndResizing() {
        #expect(DockSurfaceMetrics.clampedScale(0.2) == DockSurfaceMetrics.scaleRange.lowerBound)
        #expect(DockSurfaceMetrics.clampedScale(9) == DockSurfaceMetrics.scaleRange.upperBound)
        #expect(DockSurfaceMetrics.clampedScale(.nan) == 1)
        #expect(DockSurfaceMetrics.clampedScale(1.2) == 1.2)
        // `pointsPerUnit` of travel changes the size by 100%: half of it away from the bottom edge adds 50%.
        let grown = DockResizePolicy.size(start: 0.7, translation: CGSize(width: 0, height: -DockResizePolicy.pointsPerUnit / 2),
                                          position: .bottom)
        #expect(abs(grown - 1.2) < 0.0001)
        #expect(DockResizePolicy.size(start: 1, translation: CGSize(width: 0, height: -900), position: .bottom)
                == DockSurfaceMetrics.scaleRange.upperBound)
    }

    @Test func boundaryEntriesKeepTheirStableIDs() {
        #expect(DockRenderEntry.boundary(.running).id == "boundary-running")
        #expect(DockRenderEntry.boundary(.recent).id == "boundary-recent")
        #expect(DockRenderEntry.boundary(.windows).id == "boundary-windows")
    }

    @Test func magnificationRunsWhereTheScrollViewDoesNotClipIt() {
        // Scroll clipping can be turned off from macOS 14; macOS 13 keeps tiles at rest size.
        let macOS14 = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        #expect(DockMagnificationSupport.isAvailable == ProcessInfo.processInfo.isOperatingSystemAtLeast(macOS14))
    }

    @Test func increaseContrastStrengthensDockSeparators() {
        #expect(DockDesign.DockChrome.separator(.standard) != DockDesign.DockChrome.separator(.increased))
        #expect(DockDesign.DockChrome.revealHandle(.increased, reduceTransparency: true) == .primary)
    }
}
