import Foundation
import Testing
@testable import MyDock

@MainActor
struct RedesignSettingsTests {
    @Test(arguments: DockQuickStyle.allCases, [false, true])
    func stylesApplyThroughScopeAndUndo(style: DockQuickStyle, dockScope: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Style test")
        let other = try store.createProfileAndPersist(kind: .custom, name: "Untouched")
        let scope: UUID? = dockScope ? id : nil
        var prior = AppSettings()
        prior.customDockSize = 1.21
        prior.customDockEdgeStyle = .contrastOnly
        prior.customDockFloatingInset = 17
        prior.customDockTintMode = .auto
        prior.customDockTintStrength = 0.27
        prior.customDockGlassOpacity = 0.42
        SettingsAppearanceEditing.update(in: store, profileID: scope) { $0 = ProfileAppearance(settings: prior).applying(to: $0) }
        let before = scope.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        let defaultsBefore = store.state.settings
        let otherBefore = store.customProfiles.first { $0.id == other }?.appearance
        let undo = try #require(SettingsAppearanceEditing.capture(in: store, profileID: scope))
        #expect(SettingsAppearanceEditing.update(in: store, profileID: scope) { style.apply(to: &$0) })
        let edited = scope.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        // Expected definitions are explicit rather than mirroring the application helper.
        let expected: (CustomDockMaterial, DockEdgeStyle, DockWidgetSurface, Double) = switch style {
        case .clear: (.liquidGlassClear, .none, .plain, 0)
        case .glass: (.liquidGlass, .hairline, .glass, 0.04)
        case .frosted: (.frosted, .hairline, .tile, 0.02)
        case .solid: (.solid, .hairline, .tile, 0.03)
        case .midnight: (.dark, .hairline, .glass, 0.10)
        }
        #expect(edited.customDockMaterial == expected.0)
        #expect(edited.customDockEdgeStyle == expected.1)
        #expect(edited.customDockWidgetSurface == expected.2)
        #expect(edited.customDockTintStrength == expected.3)
        #expect(edited.customDockTintMode == .custom)
        #expect(edited.customDockGlassOpacity == 0)
        #expect(edited.customDockSize == before.customDockSize)
        #expect(edited.customDockFloatingInset == 17)
        if dockScope { #expect(store.state.settings == defaultsBefore) }
        #expect(store.customProfiles.first { $0.id == other }?.appearance == otherBefore)
        #expect(undo.restore(in: store, editingProfileID: scope))
        let restored = scope.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        #expect(ProfileAppearance(settings: restored) == ProfileAppearance(settings: before))
    }

    @Test(arguments: DockQuickStyle.allCases)
    func selectedStyleRequiresEveryDefinedField(style: DockQuickStyle) {
        var settings = AppSettings()
        style.apply(to: &settings)
        #expect(DockQuickStyle.allCases.filter { $0.matches(settings) } == [style])
        let mutations: [(inout AppSettings) -> Void] = [
            { $0.customDockMaterial = style == .clear ? .frosted : .liquidGlassClear },
            { $0.customDockEdgeStyle = .contrastOnly },
            { $0.customDockWidgetSurface = style.surface == .tile ? .plain : .tile },
            { $0.customDockTintMode = .auto },
            { $0.customDockTintStrength += 0.01 },
            { $0.customDockGlassOpacity = 0.1 }
        ]
        for mutate in mutations {
            var custom = settings
            mutate(&custom)
            #expect(!DockQuickStyle.allCases.contains { $0.matches(custom) })
        }
    }

    @Test func undoRestoresInheritedAppearance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Inherited")
        store.setAppearance(nil, for: id)
        let undo = try #require(SettingsAppearanceEditing.capture(in: store, profileID: id))
        SettingsAppearanceEditing.update(in: store, profileID: id) { DockQuickStyle.clear.apply(to: &$0) }
        #expect(store.customProfiles.first { $0.id == id }?.appearance != nil)
        #expect(undo.restore(in: store, editingProfileID: id))
        #expect(store.customProfiles.first { $0.id == id }?.appearance == nil)
    }

    @Test(arguments: ["edge", "widget surface", "floating inset", "auto tint", "tint strength", "glass opacity", "Clear", "Glass", "Frosted", "Solid", "Midnight"])
    func searchFindsNewControls(query: String) {
        #expect(SettingsSearchCatalog.matches(query).contains { $0.page == .appearance })
        #expect(SettingsSearchCatalog.pages(matching: query).contains(.appearance))
    }
    @Test(arguments: [false, true])
    func restoreCompleteDefaultsAndUndo(dockScope: Bool) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Restore test")
        let other = try store.createProfileAndPersist(kind: .custom, name: "Untouched")
        let scope: UUID? = dockScope ? id : nil
        store.updateSettings { $0.customDockPosition = .left; $0.showRunningApps = false }
        SettingsAppearanceEditing.update(in: store, profileID: scope) {
            DockQuickStyle.midnight.apply(to: &$0)
            $0.customDockTheme = .dark
            $0.customDockSize = 1.3
            $0.customDockItemSpacing = 19
            $0.customDockCornerRadius = 9
            $0.customDockEdgeStyle = .contrastOnly
            $0.customDockWidgetSurface = .plain
            $0.customDockFloatingInset = 17
            $0.customDockTintMode = .auto
            $0.customDockGlassOpacity = 0.6
            $0.customDockWidgetStyle = .compact
            $0.showWidgetLabels = false
        }
        let before = scope.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        let globalBefore = store.state.settings
        let otherBefore = store.customProfiles.first { $0.id == other }?.appearance
        let undo = try #require(SettingsAppearanceEditing.capture(in: store, profileID: scope))
        #expect(SettingsAppearanceEditing.update(in: store, profileID: scope) { SettingsAppearanceDefaults.restore(to: &$0) })
        let restored = scope.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        #expect(ProfileAppearance(settings: restored) == ProfileAppearance(settings: AppSettings()))
        #expect(restored.customDockPosition == .left)
        #expect(!restored.showRunningApps)
        if dockScope { #expect(store.state.settings == globalBefore) }
        #expect(store.customProfiles.first { $0.id == other }?.appearance == otherBefore)
        #expect(undo.restore(in: store, editingProfileID: scope))
        let undone = scope.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
        #expect(ProfileAppearance(settings: undone) == ProfileAppearance(settings: before))
    }

    @Test(arguments: CustomDockMaterial.allCases)
    func singleFinishControlReachesEveryMaterial(material: CustomDockMaterial) throws {
        #expect(SettingsAppearanceDefaults.finishes.contains(material))
        let source = try uiSource("Settings/AppearanceSettingsPage.swift")
        #expect(source.components(separatedBy: "selection: appearanceBinding(\\.customDockMaterial)").count - 1 == 1)
        #expect(source.contains("ForEach(SettingsAppearanceDefaults.finishes)"))
        #expect(source.contains(".id(\"Finish\")"))
    }

    @Test func searchCatalogAnchorsResolve() throws {
        let sources: [MyDockSettingsPage: [String]] = [
            .dock: ["Settings/DockSettingsPage.swift"],
            .appearance: ["Settings/AppearanceSettingsPage.swift"],
            .behavior: ["Settings/BehaviorSettingsPage.swift"],
            .general: ["Settings/GeneralSettingsPage.swift", "AppLifecycleSettingsView.swift", "RecoveryCenterView.swift"],
            .shortcuts: ["Settings/ShortcutsSettingsPage.swift"],
            .integrations: ["Settings/IntegrationsSettingsPage.swift", "ConnectionsCenterView.swift"],
            .permissions: ["Settings/PermissionsSettingsPage.swift"]
        ]
        for entry in SettingsSearchCatalog.entries {
            let source = try #require(sources[entry.page]).map { try uiSource($0) }.joined(separator: "\n")
            if entry.section.hasPrefix("Style ") {
                #expect(source.contains(".id(\"Style \" + style.title)"))
                #expect(DockQuickStyle.allCases.contains { "Style " + $0.title == entry.section })
            } else {
                #expect(source.contains(".id(\"" + entry.section + "\")"), "Missing anchor: \(entry.section)")
            }
        }
        #expect(SettingsSearchCatalog.matches("glass finish").contains { $0.section == "Finish" })
    }

    private func uiSource(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/MyDock/UI/" + path), encoding: .utf8)
    }

}
