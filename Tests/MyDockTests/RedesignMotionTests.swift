import AppKit
import SwiftUI
import Testing
@testable import MyDock

@MainActor
struct RedesignMotionTests {
    private func temporaryStoreURL() -> (directory: URL, file: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return (directory, directory.appendingPathComponent("state.json"))
    }

    // MARK: Starter presets

    @Test func starterPresetsMapToFittingQuickStyles() {
        let expected: [DockStarterPreset: DockQuickStyle] = [
            .everyday: .clear, .travel: .clear,
            .create: .glass, .develop: .glass, .ai: .glass,
            .focus: .solid,
            .commerce: .frosted, .homeOffice: .frosted, .monitor: .frosted
        ]
        #expect(Set(expected.keys) == Set(DockStarterPreset.allCases))
        for preset in DockStarterPreset.allCases { #expect(preset.quickStyle == expected[preset]) }
    }

    @Test func starterPresetAppearanceIsTheQuickStyleOverTheUsersSettings() throws {
        var base = AppSettings()
        base.customDockSize = 1.2
        base.customDockItemSpacing = 9
        base.customDockCornerRadius = 30
        base.customDockTheme = .dark
        base.customDockFloatingInset = 8
        for preset in DockStarterPreset.allCases {
            let appearance = preset.appearance(basedOn: base)
            try appearance.validate()
            let effective = appearance.applying(to: AppSettings())
            #expect(preset.quickStyle.matches(effective))
            // Everything the quick style does not own follows the user's settings.
            #expect(effective.customDockSize == 1.2)
            #expect(effective.customDockItemSpacing == 9)
            #expect(effective.customDockCornerRadius == 30)
            #expect(effective.customDockTheme == .dark)
            #expect(effective.customDockFloatingInset == 8)
        }
    }

    @Test func createdStarterProfileCarriesItsStyleSnapshotThroughPersistence() throws {
        let (directory, file) = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: file)
        for preset in [DockStarterPreset.everyday, .develop, .commerce, .focus] {
            // The same construction as the Dock presets sheet.
            var profile = DockProfile(name: preset.title, kind: .custom, color: preset.color.rawValue, items: [.widget("Clock")])
            profile.appearance = preset.appearance(basedOn: store.state.settings)
            let id = try store.createProfile(profile)
            let reloaded = ProfileStore(fileURL: file)
            let saved = try #require(reloaded.state.profiles.first { $0.id == id })
            #expect(saved.appearance == profile.appearance)
            #expect(preset.quickStyle.matches(reloaded.effectiveSettings(for: saved)))
        }
        // Global settings are untouched by a preset.
        #expect(ProfileStore(fileURL: file).state.settings.customDockMaterial == AppSettings().customDockMaterial)
    }

    // MARK: Onboarding

    private func finishSetup(_ store: ProfileStore, appliesClearStyle: Bool,
                             duringSetup: () -> Void = {}) -> OnboardingCompletion.Result {
        OnboardingCompletion.finish(store: store, appliesClearStyle: appliesClearStyle) {
            duringSetup()
            try store.finishOnboarding(setupMode: .both, customDockPosition: .bottom, customDockDisplayID: nil,
                                   importedNativeItems: [], starterWidgets: ["Clock", "Battery"])
        }
    }

    @Test func firstRunOnboardingAppliesClearAndPersistsBeforeCompletion() throws {
        let (directory, file) = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: file)
        #expect(!store.state.settings.onboardingComplete)
        var clearWasOnDiskBeforeSetup = false
        var completeBeforeSetup = true
        let result = finishSetup(store, appliesClearStyle: true) {
            let disk = ProfileStore(fileURL: file).state.settings
            clearWasOnDiskBeforeSetup = DockQuickStyle.clear.matches(disk)
            completeBeforeSetup = disk.onboardingComplete || store.state.settings.onboardingComplete
        }
        #expect(result == OnboardingCompletion.Result(error: nil, appliedClearStyle: true))
        #expect(clearWasOnDiskBeforeSetup)
        #expect(!completeBeforeSetup)
        #expect(!store.hasUnpersistedChanges)
        let reloaded = ProfileStore(fileURL: file)
        #expect(reloaded.state.settings.onboardingComplete)
        #expect(DockQuickStyle.clear.matches(reloaded.state.settings))
        // The new Custom Dock inherits the global Clear look.
        let custom = try #require(reloaded.activeCustomProfile)
        #expect(custom.appearance == nil)
        #expect(DockQuickStyle.clear.matches(reloaded.effectiveSettings(for: custom)))
    }

    @Test func replayedOnboardingKeepsTheExistingLook() {
        let (directory, file) = temporaryStoreURL()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: file)
        store.updateSettings(immediately: true) {
            $0.onboardingComplete = true
            DockQuickStyle.midnight.apply(to: &$0)
        }
        let result = finishSetup(store, appliesClearStyle: false)
        #expect(result == OnboardingCompletion.Result(error: nil, appliedClearStyle: false))
        #expect(DockQuickStyle.midnight.matches(ProfileStore(fileURL: file).state.settings))
    }

    @Test func failedOnboardingPublishesNeitherClearNorCompletion() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("blocked".utf8).write(to: folder)
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"))
        let original = store.state.settings
        var setupRan = false
        let result = finishSetup(store, appliesClearStyle: true) { setupRan = true }
        #expect(result.error != nil)
        #expect(!result.appliedClearStyle)
        #expect(!setupRan)
        #expect(!store.state.settings.onboardingComplete)
        #expect(store.state.settings == original)
        #expect(store.state.profiles.isEmpty)
    }

    // MARK: Reduce Motion

    @Test func everyNewMotionIsNilUnderReduceMotion() {
        #expect(DockMotionPolicy.anchorAnimation(reduceMotion: true) == nil)
        #expect(DockMotionPolicy.reorderAnimation(reduceMotion: true, animationsEnabled: true) == nil)
        #expect(DockMotionPolicy.profileTransformAnimation(reduceMotion: true, animationsEnabled: true) == nil)
        #expect(DockMotionPolicy.settleAnimation(reduceMotion: true, animationsEnabled: true) == nil)
        #expect(DockMotionPolicy.hoverAnimation(reduceMotion: true, animationsEnabled: true) == nil)
        // Turning Dock animations off also stops the Dock's own motion.
        #expect(DockMotionPolicy.reorderAnimation(reduceMotion: false, animationsEnabled: false) == nil)
        #expect(DockMotionPolicy.settleAnimation(reduceMotion: false, animationsEnabled: false) == nil)
        #expect(DockMotionPolicy.hoverAnimation(reduceMotion: false, animationsEnabled: false) == nil)

        #expect(DockMotionPolicy.anchorAnimation(reduceMotion: false) == DockDesign.Motion.hover)
        #expect(DockMotionPolicy.reorderAnimation(reduceMotion: false, animationsEnabled: true) == DockDesign.Motion.reorder)
        #expect(DockMotionPolicy.profileTransformAnimation(reduceMotion: false, animationsEnabled: true) == DockDesign.Motion.transform)
        #expect(DockMotionPolicy.settleAnimation(reduceMotion: false, animationsEnabled: true) == DockDesign.Motion.morph)
        #expect(DockMotionPolicy.hoverAnimation(reduceMotion: false, animationsEnabled: true) == DockDesign.Motion.hover)
    }

    @Test func motionTransformsRestAtIdentityAndVanishUnderReduceMotion() {
        // Popout content: 96% and transparent at the start, identity when open.
        // These are the inputs DockPopoutAppearEffect renders: progress 0 closed, 1 open.
        #expect(DockMotionPolicy.popoutContentScale(progress: 0, reduceMotion: false) == 0.96)
        #expect(DockMotionPolicy.popoutContentOpacity(progress: 0, reduceMotion: false) == 0)
        #expect(DockMotionPolicy.popoutContentScale(progress: 1, reduceMotion: false) == 1)
        #expect(DockMotionPolicy.popoutContentOpacity(progress: 1, reduceMotion: false) == 1)
        #expect(DockMotionPolicy.popoutContentScale(progress: 0, reduceMotion: true) == 1)
        #expect(DockMotionPolicy.popoutContentOpacity(progress: 0, reduceMotion: true) == 1)
        #expect(abs(DockMotionPolicy.popoutContentScale(progress: 0.5, reduceMotion: false) - 0.98) < 0.0001)
        #expect(DockMotionPolicy.popoutContentOpacity(progress: 0.5, reduceMotion: false) == 0.5)
        #expect(DockMotionPolicy.popoutContentScale(progress: 0.5, reduceMotion: true) == 1)
        #expect(DockMotionPolicy.popoutContentOpacity(progress: .nan, reduceMotion: false) == 1)
        // Anchor: pressed while open; Reduce Motion keeps only the brightening.
        #expect(DockMotionPolicy.anchorScale(isActive: true, reduceMotion: false) == 0.97)
        #expect(DockMotionPolicy.anchorScale(isActive: true, reduceMotion: true) == 1)
        #expect(DockMotionPolicy.anchorScale(isActive: false, reduceMotion: false) == 1)
        #expect(DockMotionPolicy.anchorBrightness(isActive: false, dark: true) == 0)
        #expect(DockMotionPolicy.anchorBrightness(isActive: true, dark: true) > DockMotionPolicy.anchorBrightness(isActive: true, dark: false))
        // Settle: a dip only while settling and only with motion.
        #expect(DockMotionPolicy.settleScale(isSettling: true, reduceMotion: false) == 0.94)
        #expect(DockMotionPolicy.settleScale(isSettling: true, reduceMotion: true) == 1)
        #expect(DockMotionPolicy.settleScale(isSettling: false, reduceMotion: false) == 1)
    }

    // MARK: Interactive glass

    private final class Counter { var value = 0 }

    /// Clicks a plain Button whose label is a glass module, in an offscreen window.
    private func clicks(interactive: Bool) async throws -> Int {
        let counter = Counter()
        let root = Button { counter.value += 1 } label: {
            GlassModule(width: 80, height: 54, interactive: interactive) { Color.primary.opacity(0.001) }
        }
        .buttonStyle(.plain)
        .frame(width: 120, height: 100)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 120, height: 100),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 120, height: 100)
        window.contentView = host
        // Off every display: present for event routing, never visible.
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let point = NSPoint(x: 60, y: 50)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                                        clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(50))
        }
        // SwiftUI may dispatch the action after the event returns; wait for it within a poll budget.
        var budget = PollBudget()
        while counter.value == 0, try await budget.wait() {}
        window.close()
        return counter.value
    }

    @Test func interactiveGlassDoesNotSwallowClicks() async throws {
        let plain = try await clicks(interactive: false)
        let interactive = try await clicks(interactive: true)
        #expect(plain == 1)
        #expect(interactive == plain)
    }

    // MARK: Glass composition

    @Test func glassContainerWrapsTheItemStackForGlassMaterialsOnly() {
        #expect(DockGlassComposition.scope(material: .liquidGlass, reduceTransparency: false) == .itemStack)
        #expect(DockGlassComposition.scope(material: .liquidGlassClear, reduceTransparency: false) == .itemStack)
        #expect(DockGlassComposition.scope(material: .liquidGlass, reduceTransparency: true) == .none)
        for material in [CustomDockMaterial.frosted, .solid, .dark] {
            #expect(DockGlassComposition.scope(material: material, reduceTransparency: false) == .none)
        }
        #expect(DockGlassComposition.moduleSpacing == 0)
    }
}
