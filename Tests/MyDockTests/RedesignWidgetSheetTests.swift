import Foundation
import Testing
@testable import MyDock

/// RD-08 widget settings sheet: appearance writes go through the store, pure row/section policies,
/// pager layout writes keep catalog widths, and Remove Widget uses the Dock editor's edit session.
@MainActor
struct RedesignWidgetSheetTests {
    private func makeStore() throws -> (ProfileStore, UUID, [DockItem]) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("RedesignWidgetSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Sheet")
        let items = [DockItem.widget("Clock"), DockItem.widget("Weather"), DockItem.widget("Battery")]
        for item in items { store.add(item, to: profileID) }
        return (store, profileID, items)
    }

    private func configuration(_ store: ProfileStore, _ profileID: UUID, _ itemID: UUID) -> WidgetConfiguration? {
        store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == itemID }?.widgetConfiguration
    }

    @Test func everyAccentChoiceIsStoredAsChosen() throws {
        let (store, profileID, items) = try makeStore()
        let choices = WidgetAppearanceOptions.accentChoices
        #expect(choices.count == 2 + DockProfileColor.allCases.count)
        #expect(choices.first == .auto && choices.dropFirst().first == .mono)
        for accent in choices {
            let result = WidgetAppearanceWriter.setAccent(accent, itemID: items[0].id, profileID: profileID, store: store)
            #expect(result == .accepted || result == .unchanged)
            #expect(configuration(store, profileID, items[0].id)?.widgetAccent == accent)
            // Only that widget changes.
            #expect(configuration(store, profileID, items[1].id)?.widgetAccent == nil)
        }
        #expect(WidgetAppearanceOptions.accentTitle(.auto) == "Automatic")
        #expect(WidgetAppearanceOptions.accentTitle(.mono) == "Mono")
        #expect(WidgetAppearanceOptions.accentTitle(.profile(.teal)) == "Teal")
    }

    @Test func labelChoiceMapsFollowDockToNil() throws {
        let (store, profileID, items) = try makeStore()
        WidgetAppearanceWriter.setLabel(.shown, itemID: items[0].id, profileID: profileID, store: store)
        #expect(configuration(store, profileID, items[0].id)?.showsLabel == true)
        WidgetAppearanceWriter.setLabel(.hidden, itemID: items[0].id, profileID: profileID, store: store)
        #expect(configuration(store, profileID, items[0].id)?.showsLabel == false)
        WidgetAppearanceWriter.setLabel(.followDock, itemID: items[0].id, profileID: profileID, store: store)
        #expect(configuration(store, profileID, items[0].id)?.showsLabel == nil)
        for choice in WidgetLabelChoice.allCases { #expect(WidgetLabelChoice(stored: choice.stored) == choice) }
        // nil follows the Dock's own label setting.
        #expect(WidgetPresentationValues.showsLabel(configuration: configuration(store, profileID, items[0].id), dockShowsLabels: false) == false)
    }

    @Test func glassTintRowOnlyForGlassSurface() throws {
        #expect(WidgetAppearanceOptions.showsGlassTint(surface: .glass))
        #expect(!WidgetAppearanceOptions.showsGlassTint(surface: .plain))
        #expect(!WidgetAppearanceOptions.showsGlassTint(surface: .tile))
        let (store, profileID, items) = try makeStore()
        WidgetAppearanceWriter.setGlassTint(.accent, itemID: items[0].id, profileID: profileID, store: store)
        #expect(configuration(store, profileID, items[0].id)?.glassTint == .accent)
        WidgetAppearanceWriter.setGlassTint(.none, itemID: items[0].id, profileID: profileID, store: store)
        #expect(configuration(store, profileID, items[0].id)?.glassTint == WidgetGlassTint.none)
    }

    @Test func pagerSelectionStoresLayoutAndKeepsCatalogWidths() throws {
        let (store, profileID, items) = try makeStore()
        let weather = items[1]
        let settings = store.effectiveSettings(profileID: profileID)
        for option in WidgetPresentationCatalog.options(for: "Weather") {
            WidgetAppearanceWriter.setLayout(option.layout, itemID: weather.id, profileID: profileID, store: store)
            let stored = try #require(configuration(store, profileID, weather.id))
            #expect(stored.widgetLayout == option.layout)
            let resolved = WidgetPresentationCatalog.resolvedLayout(for: "Weather", configuration: stored)
            #expect(resolved == option.layout)
            #expect(WidgetPresentationCatalog.width(for: "Weather", layout: resolved) == option.width)
            let item = try #require(store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == weather.id })
            #expect(DockSurfaceMetrics.itemLength(item, settings: settings, scale: 1) == CGFloat(option.width))
        }
        // The preview scale keeps the widest page inside the pager and never shrinks below 1.
        let scale = WidgetSheetMetrics.previewScale(widestWidth: 184, dockPadding: 11, available: 372)
        #expect(scale * (184 + 22) <= 372.0001)
        #expect(WidgetSheetMetrics.previewScale(widestWidth: 54, dockPadding: 11, available: 372) == 1.8)
        #expect(WidgetSheetMetrics.previewScale(widestWidth: 900, dockPadding: 11, available: 372) == 1)
    }

    @Test func iconAppearanceWritesEveryTreatment() throws {
        let (store, profileID, items) = try makeStore()
        for appearance in WidgetIconAppearance.allCases {
            WidgetAppearanceWriter.setIconAppearance(appearance, itemID: items[2].id, profileID: profileID, store: store)
            #expect(configuration(store, profileID, items[2].id)?.iconAppearance == appearance)
        }
        #expect(!WidgetAppearanceOptions.showsIconStyle(kind: "Sticky Note"))
        #expect(!WidgetAppearanceOptions.showsIconStyle(kind: "Time Progress"))
        #expect(WidgetAppearanceOptions.showsIconStyle(kind: "Clock"))
    }

    @Test func dataSectionFollowsCapabilities() {
        // Static content, no permissions, no data source: the section is omitted.
        let calculator = WidgetSheetDataSummary.make(kind: "Calculator", configuration: WidgetConfiguration())
        #expect(calculator.isEmpty)
        // Private content only: the access note alone keeps the section.
        let note = WidgetSheetDataSummary.make(kind: "Sticky Note", configuration: WidgetConfiguration())
        #expect(!note.isEmpty && note.source == nil && note.accessNote != nil && !note.showsFreshness)
        #expect(WidgetSheetDataSummary.make(kind: "Clock", configuration: WidgetConfiguration()).source == "This Mac's clock")
        #expect(WidgetSheetDataSummary.make(kind: "Battery", configuration: WidgetConfiguration()).source == "This Mac")
        #expect(WidgetSheetDataSummary.make(kind: "Weather", configuration: WidgetConfiguration()).source == "Online")
        #expect(WidgetSheetDataSummary.make(kind: "Stripe", configuration: WidgetConfiguration()).source == "Connected account")
        #expect(WidgetSheetDataSummary.make(kind: "Calendar", configuration: WidgetConfiguration()).source == "Calendar")
        #expect(WidgetSheetDataSummary.make(kind: "Now Playing", configuration: WidgetConfiguration()).source == "Apps on this Mac")
        // Freshness follows the existing data query; AI Activity reports provenance itself.
        var stock = WidgetConfiguration()
        stock.stockSymbol = "AAPL"
        #expect(WidgetSheetDataSummary.make(kind: "Stock", configuration: stock).showsFreshness
                == (WidgetDataQuery.make(kind: "Stock", configuration: stock) != nil))
        #expect(!WidgetSheetDataSummary.make(kind: "AI Activity", configuration: WidgetConfiguration()).showsFreshness)
        // Every registry family resolves without crashing, and families with nothing to say omit the section.
        for definition in WidgetRegistry.all {
            let summary = WidgetSheetDataSummary.make(kind: definition.name, configuration: WidgetConfiguration())
            let expectEmpty = definition.capabilities.refreshDemand == .none && definition.capabilities.accessNote == nil
                && WidgetDataQuery.make(kind: definition.name, configuration: WidgetConfiguration()) == nil
            #expect(summary.isEmpty == expectEmpty, "\(definition.name)")
        }
    }

    @Test func removeDeletesExactlyThatItemThroughTheEditSession() throws {
        let (store, profileID, items) = try makeStore()
        let undo = UndoManager()
        let removed = try WidgetSheetRemoval.remove(itemID: items[1].id, profileID: profileID, store: store, undoManager: undo)
        #expect(removed)
        let remaining = store.state.profiles.first { $0.id == profileID }?.items.map(\.id)
        #expect(remaining == [items[0].id, items[2].id])
        // Saved through the edit session: its draft matches the store and is clean.
        #expect(store.editSessions.drafts[profileID]?.isDirty == false)
        #expect(store.editSessions.drafts[profileID]?.profile.items.map(\.id) == remaining)
        #expect(undo.canUndo)
        // A second removal of the same item does nothing.
        #expect(try WidgetSheetRemoval.remove(itemID: items[1].id, profileID: profileID, store: store) == false)
        #expect(store.state.profiles.first { $0.id == profileID }?.items.count == 2)
        // Undo restores it in the editor's draft, like an editor edit.
        undo.undo()
        #expect(store.editSessions.drafts[profileID]?.profile.items.map(\.id) == items.map(\.id))
    }
}
