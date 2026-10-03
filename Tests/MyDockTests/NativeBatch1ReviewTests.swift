import Foundation
import Testing
@testable import MyDock

struct NativeBatch1ReviewTests {
    private func identity(date: Date?) -> NativeApplicationIdentity {
        NativeApplicationIdentity(processID: 7, bundleIdentifier: "fixture.app",
                                  bundleURL: URL(fileURLWithPath: "/fixture/App.app"), launchDate: date)
    }

    @Test func missingLaunchDateStillMatchesSameProcessAndCopy() {
        #expect(identity(date: nil).matches(identity(date: nil)))
        // A published date on one side only is a lifetime change, not a match.
        #expect(!identity(date: nil).matches(identity(date: Date(timeIntervalSince1970: 5))))
    }

    @Test func nativeWindowMatchMustBeUnique() {
        #expect(WindowRestoreIdentity.uniqueIndex([2]) == 2)
        #expect(WindowRestoreIdentity.uniqueIndex([]) == nil)
        #expect(WindowRestoreIdentity.uniqueIndex([0, 1]) == nil)
    }

    @Test func presentationSignatureIgnoresUnrelatedSettings() {
        var settings = AppSettings()
        let base = DockPresentationSettings(settings)
        settings.lastSettingsPage = .appearance
        settings.onboardingComplete.toggle()
        settings.smoothNativeDockSwitches.toggle()
        settings.automaticallySaveNativeDockChanges.toggle()
        settings.showActiveProfileNameInMenuBar.toggle()
        settings.activeNativeProfileID = UUID()
        #expect(DockPresentationSettings(settings) == base)
        let changes: [(inout AppSettings) -> Void] = [
            { $0.customDockSize = 1.2 }, { $0.customDockPosition = .left }, { $0.showRunningApps.toggle() },
            { $0.customDockCornerRadius += 1 }, { $0.customDockDesktopMode.toggle() },
            { $0.showRevealHandle.toggle() }, { $0.magnificationEnabled.toggle() },
            { $0.dockAnimationStyle = .grow }]
        for change in changes {
            var changed = AppSettings()
            change(&changed)
            #expect(DockPresentationSettings(changed) != base)
        }
    }

    @Test func resizeGripKeepsMinimumHitAreaAtEveryScaleAndPosition() {
        for scale in stride(from: CGFloat(0.65), through: 1.5, by: 0.05) {
            for horizontal in [true, false] {
                let layout = DockResizeGripGeometry.layoutSize(horizontal: horizontal, scale: scale)
                let hit = DockResizeGripGeometry.hitSize(horizontal: horizontal, scale: scale)
                let outset = DockResizeGripGeometry.hitOutset(horizontal: horizontal, scale: scale)
                #expect(min(hit.width, hit.height) >= 14 - 0.0001)
                #expect(hit.width >= layout.width && hit.height >= layout.height)
                #expect(abs(hit.width - layout.width - 2 * outset.width) < 0.0001)
                #expect(abs(hit.height - layout.height - 2 * outset.height) < 0.0001)
                // The long dimension never grows, so neighbours are not overlapped lengthwise.
                if horizontal { #expect(hit.height == layout.height) } else { #expect(hit.width == layout.width) }
            }
        }
        #expect(DockResizeGripGeometry.hitOutset(horizontal: true, scale: 1.0) == .zero)
    }

    @Test func runtimePinningUsesNormalizedInstalledCopyURLs() {
        var pinned = DockItem.application(at: URL(fileURLWithPath: "/fixture/apps/../apps/Editor.app"))
        pinned.bundleIdentifier = "fixture.editor"
        var profile = DockProfile(name: "P", kind: .custom)
        profile.items = [pinned]
        let urls = RuntimeDockIdentity.pinnedApplicationURLs(in: profile)
        var same = DockItem.application(at: URL(fileURLWithPath: "/fixture/apps/Editor.app")); same.bundleIdentifier = "fixture.editor"
        var other = DockItem.application(at: URL(fileURLWithPath: "/fixture/other/Editor.app")); other.bundleIdentifier = "fixture.editor"
        var noURL = other; noURL.url = nil
        let visible = RuntimeDockIdentity.unpinned([same, other, noURL], pinnedURLs: urls)
        #expect(visible.map(\.id) == [other.id])
    }
}
