#if DEBUG
import AppKit
import SwiftUI

/// RD-07 snapshots use the production pages and accessibility preview overrides.
/// Native glass is replaced by the shared snapshot fallback, never system preferences.
extension PremiumVisualQA {
    static func exportSettingsUI(to directory: URL, store: ProfileStore) async throws {
        if store.customProfiles.isEmpty {
            var profile = DockProfile(name: "Everyday", kind: .custom, items: [.widget("Clock"), .widget("Weather"), .widget("Sticky Note")])
            var settings = store.state.settings
            DockQuickStyle.clear.apply(to: &settings)
            profile.appearance = ProfileAppearance(settings: settings)
            let id = try store.createProfile(profile)
            store.setActiveCustomProfile(id)
        }
        let variants: [(String, NSSize, ColorSchemeContrast, Bool)] = [
            ("wide", NSSize(width: 1160, height: 760), .standard, false),
            ("narrow", NSSize(width: 780, height: 600), .standard, false),
            ("reduce-transparency", NSSize(width: 1160, height: 760), .standard, true),
            ("increase-contrast", NSSize(width: 1160, height: 760), .increased, false)
        ]
        for (scheme, name) in [(ColorScheme.light, "light"), (.dark, "dark")] {
            for page in MyDockSettingsPage.allCases {
                for (variant, size, contrast, transparency) in variants {
                    try await render(SettingsView(store: store, initialPage: page),
                                     name: "settings-\(page.rawValue)-\(name)-\(variant)", size: size,
                                     scheme: scheme, directory: directory, contrast: contrast, reduceTransparency: transparency)
                }
            }
            for section in SettingsQASection.allCases {
                try await render(SettingsQASectionView(store: store, section: section),
                                 name: "settings-appearance-section-\(section.rawValue)-\(name)",
                                 size: NSSize(width: 780, height: 600), scheme: scheme, directory: directory)
            }
            if let profile = store.customProfiles.first {
                try await render(DockAppearanceInspector(store: store, profile: profile, close: {}),
                                 name: "settings-dock-inspector-\(name)", size: NSSize(width: 620, height: 400), scheme: scheme, directory: directory)
            }
            try await render(DockItemInspector(item: DockItem(type: .folder, title: "Projects", url: directory), update: { _ in }, replace: {}, close: {}),
                             name: "settings-item-inspector-\(name)", size: NSSize(width: 480, height: 520), scheme: scheme, directory: directory)
            let library = ProfileLibrary(fileURL: directory.appendingPathComponent("settings-qa-presets.json"))
            if library.entries.isEmpty, let profile = store.customProfiles.first { library.record(profile, reason: "QA") }
            try await render(PersonalPresetPicker(store: store, library: library, select: { _ in }).padding(24).background(DockDesign.page),
                             name: "settings-personal-presets-\(name)", size: NSSize(width: 620, height: 300), scheme: scheme, directory: directory)
        }
    }
}

private enum SettingsQASection: String, CaseIterable { case hero, style, glass, layout, widgets, scope }

private struct SettingsQASectionView: View {
    let store: ProfileStore
    let section: SettingsQASection
    var body: some View {
        let view = SettingsView(store: store, initialPage: .appearance)
        VStack(alignment: .leading, spacing: 20) {
            SettingsPageHeader(page: .appearance)
            switch section {
            case .hero: view.appearanceHero
            case .style: view.appearanceStyleSection
            case .glass: view.appearanceGlassSection
            case .layout: view.appearanceLayoutSection
            case .widgets: view.appearanceWidgetsSection
            case .scope: view.appearanceScopeSection
            }
            Spacer(minLength: 0)
        }.padding(24).background(DockDesign.page)
    }
}
#endif
