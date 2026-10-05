#if DEBUG
import AppKit
import SwiftUI

/// RD-11 render matrix (`MYDOCK_MOTION_QA=1`).
///
/// - The onboarding "Your Dock, clearer" reveal in light and dark, with Reduce Transparency and
///   Increase Contrast variants, plus the hero's start and end frames.
/// - Starter preset cards, each with the Dock it creates in its quick style.
/// - The Glass style (glass modules in the item-stack container) at the bottom, left and right.
/// - A popout's open frames: the start and end of the appear spring, with its anchor active.
///
/// Offscreen captures cannot see the Liquid Glass compositor, so glass draws its fallback here.
/// Native morphs, the interactive specular highlight and the NSPopover window are not captured.
@MainActor
enum MotionQA {
    static func schemeName(_ scheme: ColorScheme) -> String { scheme == .dark ? "dark" : "light" }

    /// The popout as `CustomDockView` hosts it since FX-03: no host padding or slab; the NSPopover's
    /// own material is the one surface (emulated here with `.regularMaterial`, opaque under Reduce
    /// Transparency through `WidgetPopoverSurface`). Pinned to one frame of the appear spring, which
    /// scales the content inside the unscaled popover window, and drawn above the Dock with its anchor active.
    static func popoutScene(store: ProfileStore, profile: DockProfile, item: DockItem, progress: Double,
                            reduceMotion: Bool = false) -> some View {
        let popover = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return ZStack {
            DockStyleQA.wallpaper
            VStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    WidgetPopout(store: store, item: item, profileID: profile.id)
                        .frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
                }
                .modifier(DockPopoutAppearEffect(anchor: .bottom, progress: progress))
                .modifier(WidgetPopoverSurface())
                .fixedSize()
                .background(.regularMaterial, in: popover)
                .clipShape(popover)
                .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
                DockStyleQA.indicatorFixtures(DockLayoutPreview(store: store, profile: profile, maximumSideLength: 560))
                    .environment(\.dockPreviewActivePopoutAnchor, item.id)
            }
            .padding(20)
        }
        .environment(\.dockAccessibilityPreview, DockAccessibilityPreview(contrast: .standard, reduceTransparency: false,
                                                                         reduceMotion: reduceMotion))
    }

    /// The profile the Dock presets sheet creates for `preset` (same construction as `DockManagerView`).
    static func presetProfile(_ preset: DockStarterPreset, settings: AppSettings) -> DockProfile {
        var profile = DockProfile(name: preset.title, kind: .custom, color: preset.color.rawValue, items: preset.resolve().items)
        profile.appearance = preset.appearance(basedOn: settings)
        return profile
    }

    static func presetSheet(store: ProfileStore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(DockStarterPreset.allCases) { preset in
                let profile = presetProfile(preset, settings: store.state.settings)
                HStack(alignment: .center, spacing: 14) {
                    PresetLibraryTile(preset: preset).frame(width: 560)
                    VStack(alignment: .leading, spacing: 6) {
                        ZStack {
                            SwatchWallpaper()
                            // The finished Dock fitted by scale: no overflow chevrons or cut modules.
                            DockLayoutPreview(store: store, profile: profile, maximumSideLength: 160, fitsByScale: true)
                                .padding(.horizontal, 10)
                        }
                        .frame(width: 560, height: 116).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Created as \(preset.quickStyle.title)").font(DockDesign.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DockDesign.page)
    }
}

extension PremiumVisualQA {
    static func exportMotionUI(to directory: URL, store: ProfileStore) async throws {
        BatteryQAFixture.override = [BatteryReading(name: "InternalBattery-0", percentage: 84, isCharging: false, isInternal: true)]
        defer { BatteryQAFixture.override = nil }

        let id = try store.createProfileAndPersist(kind: .custom, name: "Custom Dock")
        for bundle in ["com.apple.finder", "com.apple.Safari", "com.apple.mail"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: id) }
        }
        store.add(.spacer(.small), to: id)
        store.add(.widget("Clock"), to: id)
        store.add(.widget("Battery"), to: id)
        store.activate(id)
        func profile() -> DockProfile { store.state.profiles.first { $0.id == id }! }
        store.updateSettings {
            $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false
            $0.magnificationEnabled = false; $0.customDockPosition = .bottom
        }
        let baseline = store.state.settings

        // 1. Onboarding reveal: the saved look is Clear; the baseline is today's look.
        store.updateSettings { DockQuickStyle.clear.apply(to: &$0) }
        for scheme in [ColorScheme.light, .dark] {
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light }
            var themed = baseline
            themed.customDockTheme = store.state.settings.customDockTheme
            let suffix = MotionQA.schemeName(scheme)
            let variants: [(String, ColorSchemeContrast, Bool)] = [("", .standard, false),
                                                                   ("-reduce-transparency", .standard, true),
                                                                   ("-increase-contrast", .increased, false)]
            for (variant, contrast, transparency) in variants {
                // Reduce Motion shows the end state at once, so the capture shows the finished reveal.
                let view = OnboardingView(store: store, revealingFrom: themed, onFinish: {})
                    .environment(\.dockAccessibilityPreview, DockAccessibilityPreview(contrast: contrast, reduceTransparency: transparency,
                                                                                     reduceMotion: true))
                try await DockStyleQA.render(view, name: "motion-onboarding-reveal-\(suffix)\(variant)",
                                             size: NSSize(width: 760, height: 600), scheme: scheme, directory: directory,
                                             contrast: contrast, reduceTransparency: transparency)
            }
            for (frame, phase) in [("start", false), ("end", true)] {
                try await DockStyleQA.render(OnboardingClearRevealHero(store: store, baseline: themed, phase: phase).padding(20)
                                                .background(DockDesign.page),
                                             name: "motion-onboarding-hero-\(frame)-\(suffix)",
                                             size: NSSize(width: 560, height: 270), scheme: scheme, directory: directory)
            }
        }

        // 2. Starter presets and the style each creates.
        store.updateSettings { DockStyleQA.resetAppearance(&$0) }
        for scheme in [ColorScheme.light, .dark] {
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light }
            try await DockStyleQA.render(MotionQA.presetSheet(store: store), name: "motion-starter-presets-\(MotionQA.schemeName(scheme))",
                                         size: NSSize(width: 1180, height: 1300), scheme: scheme, directory: directory)
        }

        // 3. Glass modules in the item-stack container, at each position.
        for position in [DockPosition.bottom, .left, .right] {
            for scheme in [ColorScheme.light, .dark] {
                store.updateSettings {
                    DockStyleQA.resetAppearance(&$0)
                    DockQuickStyle.glass.apply(to: &$0)
                    $0.customDockPosition = position
                    $0.customDockTheme = scheme == .dark ? .dark : .light
                }
                let horizontal = position == .bottom
                try await DockStyleQA.render(DockStyleQA.dockScene(store: store, profile: profile(), horizontal: horizontal),
                    name: "motion-glass-container-\(position.rawValue)-\(MotionQA.schemeName(scheme))",
                    size: horizontal ? NSSize(width: 820, height: 150) : NSSize(width: 300, height: 640),
                    scheme: scheme, directory: directory)
            }
        }

        // 4. Popout open: start and end of the appear spring, anchor active.
        let battery = profile().items.first { $0.widgetKind == "Battery" }!
        for scheme in [ColorScheme.light, .dark] {
            store.updateSettings {
                DockStyleQA.resetAppearance(&$0)
                DockQuickStyle.glass.apply(to: &$0)
                $0.customDockPosition = .bottom
                $0.customDockTheme = scheme == .dark ? .dark : .light
            }
            for (frame, progress) in [("start", 0.0), ("mid", 0.5), ("end", 1.0)] {
                try await DockStyleQA.render(MotionQA.popoutScene(store: store, profile: profile(), item: battery, progress: progress),
                    name: "motion-popout-\(frame)-\(MotionQA.schemeName(scheme))",
                    size: NSSize(width: 820, height: 560), scheme: scheme, directory: directory)
            }
        }
        // Reduce Motion: the start frame is already the end frame.
        try await DockStyleQA.render(MotionQA.popoutScene(store: store, profile: profile(), item: battery, progress: 0, reduceMotion: true),
            name: "motion-popout-start-dark-reduce-motion", size: NSSize(width: 820, height: 560), scheme: .dark, directory: directory)
    }
}
#endif
