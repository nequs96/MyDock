import Foundation
import Testing
@testable import MyDock

@MainActor
struct SettingsScopeUndoTests {
    @Test(arguments: ["dock-to-defaults", "defaults-to-dock", "dock-to-dock"])
    func undoCannotRestoreOutsideDisplayedScope(direction: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let a = try store.createProfileAndPersist(kind: .custom, name: "A")
        let b = try store.createProfileAndPersist(kind: .custom, name: "B")
        let source: UUID? = direction == "defaults-to-dock" ? nil : a
        let displayed: UUID? = direction == "dock-to-defaults" ? nil : direction == "dock-to-dock" ? b : a
        let undo = try #require(SettingsAppearanceEditing.capture(in: store, profileID: source))
        SettingsAppearanceEditing.update(in: store, profileID: source) { $0.customDockSize = 1.4 }
        if let source { store.setProfileColor(source, to: .orange) }
        let edited = store.state

        #expect(!undo.isAvailable(for: displayed))
        #expect(!undo.restore(in: store, editingProfileID: displayed))
        #expect(store.state == edited)
        // The entry still correctly restores its own target when that scope is displayed.
        #expect(undo.isAvailable(for: source))
        #expect(undo.restore(in: store, editingProfileID: source))
        if let source {
            let restored = try #require(store.customProfiles.first { $0.id == source })
            #expect(restored.appearance == undo.appearance)
            #expect(DockProfileColor(rawValue: restored.color) == undo.color)
        } else {
            #expect(store.state.settings.customDockSize == undo.settings.customDockSize)
        }
    }

    @Test func removedUndoTargetNeverMutatesDefaults() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let missing = UUID()
        let undo = SettingsAppearanceEditing.Undo(profileID: missing, appearance: nil,
                                                   settings: AppSettings(), color: .red)
        let before = store.state
        #expect(!undo.restore(in: store, editingProfileID: missing))
        #expect(store.state == before)
    }

    @Test func quickStyleColorFollowsSelectedDockAndDefaultsAreNeutral() {
        var a = DockProfile(name: "A", kind: .custom)
        var b = DockProfile(name: "B", kind: .custom)
        a.color = DockProfileColor.orange.rawValue
        b.color = DockProfileColor.purple.rawValue
        #expect(SettingsAppearanceEditing.previewColor(profiles: [a, b], profileID: a.id) == .orange)
        #expect(SettingsAppearanceEditing.previewColor(profiles: [a, b], profileID: b.id) == .purple)
        #expect(SettingsAppearanceEditing.previewColor(profiles: [a, b], profileID: nil) == nil)
        #expect(SettingsAppearanceEditing.previewColor(profiles: [a, b], profileID: UUID()) == nil)
        a.color = "legacy-invalid"
        #expect(SettingsAppearanceEditing.previewColor(profiles: [a], profileID: a.id) == .blue)
    }

    #if DEBUG
    @Test(arguments: ["AirDrop", "Trash", "Calculator", "Unit Converter", "Color Picker", "App Folder"])
    func galleryUsesSupportedSemanticGeometry(kind: String) {
        let icon = WidgetGalleryPreviewInputs.option(for: kind, width: .compact)
        let expanded = WidgetGalleryPreviewInputs.option(for: kind, width: .wide)
        #expect(icon.layout == .icon)
        #expect(icon.width == 54)
        #expect(expanded.layout == .compact)
        #expect(expanded.width > icon.width)
        #expect(WidgetPresentationCatalog.options(for: kind).contains(expanded))
        let catalog = WidgetPresentationCatalog.options(for: kind)
        #expect(Set(catalog.map(\.layout)).count == catalog.count)
        #expect(!catalog.contains { $0.layout == .wide })
    }

    @Test(arguments: ["connected", "partial", "failure"])
    func focusedActivityStateSurvivesProjectionAndFixtureRefresh(state: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Fixture")
        let item = PremiumVisualQA.activityFixture(state: state)
        let snapshot = try #require(item.widgetConfiguration?.aiActivitySnapshot)
        store.widgetData = WidgetDataCoordinator(store: store, loader: { _, _ in .activity(snapshot) })
        store.add(item, to: id)
        #expect(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot == snapshot)
        await store.widgetData.refresh(item: item, profileID: id)
        let projected = try #require(store.presentationConfiguration(for: item, in: id).aiActivitySnapshot)
        #expect(projected == snapshot)
        #expect(projected.available == (state != "failure"))
        #expect(projected.partial == (state != "connected"))
        if state != "failure" { #expect(projected.totals.totalTokens == 643_868_378) }
    }
    #endif
}
