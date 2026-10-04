import Foundation
import Testing
@testable import MyDock

struct RedesignGalleryTests {
    @Test func suggestionsAreDeterministicVariedAndSkipAddedFamilies() throws {
        let empty = DockProfile(name: "Empty", kind: .custom)
        let first = WidgetGalleryModel.suggestions(for: empty, allowsAdding: true)
        #expect(first.count == 4)
        #expect(first.map(\.name) == WidgetGalleryModel.suggestions(for: empty, allowsAdding: true).map(\.name))
        #expect(Set(first.map(\.category)).count == first.count)
        #expect(first.map(\.name) == ["Calendar", "Weather", "Clock", "System Activity"])

        let used = DockProfile(name: "Used", kind: .custom, items: [.widget("Calendar"), .widget("Clock")])
        let next = WidgetGalleryModel.suggestions(for: used, allowsAdding: true)
        #expect(next.count == 4)
        #expect(!next.contains { $0.name == "Calendar" || $0.name == "Clock" })
        #expect(next == WidgetGalleryModel.suggestions(for: used, allowsAdding: true))
    }

    @Test func suggestionsRespectNativeProfilesAddingAndLimits() {
        #expect(WidgetGalleryModel.suggestions(for: DockProfile(name: "Native", kind: .native), allowsAdding: true).isEmpty)
        #expect(WidgetGalleryModel.suggestions(for: DockProfile(name: "Custom", kind: .custom), allowsAdding: false).isEmpty)
        #expect(WidgetGalleryModel.suggestions(for: DockProfile(name: "Custom", kind: .custom), allowsAdding: true, limit: 3).count == 3)
        let full = DockProfile(name: "Full", kind: .custom, items: WidgetRegistry.all.map { DockItem.widget($0.name) })
        #expect(WidgetGalleryModel.suggestions(for: full, allowsAdding: true).isEmpty)
    }

    @Test func tabsFollowProfileKind() {
        #expect(AddLibraryTab.available(for: .custom) == [.widgets, .apps, .more])
        #expect(AddLibraryTab.available(for: .native) == [.apps, .more])
    }

    @Test func legacyInitialCategoriesMapToTabs() {
        #expect(AddLibraryTab.initial(category: "Widgets", kind: .custom) == .widgets)
        #expect(AddLibraryTab.initial(category: "Applications", kind: .custom) == .apps)
        #expect(AddLibraryTab.initial(category: "Apps", kind: .custom) == .apps)
        #expect(AddLibraryTab.initial(category: "System", kind: .custom) == .more)
        #expect(AddLibraryTab.initial(category: "All", kind: .custom) == .widgets)
        #expect(AddLibraryTab.initial(category: "All", kind: .native) == .apps)
        #expect(AddLibraryTab.initial(category: "Widgets", kind: .native) == .apps)
        #expect(AddLibraryTab.initial(category: "System", kind: .native) == .more)
        #expect(AddLibraryTab.initial(category: "Unknown", kind: .custom) == .widgets)
    }

    @Test func searchFindsWidgetsByNameAndCapabilityTermsThroughDiscovery() {
        let byName = WidgetGalleryModel.sections(query: "World Clock").flatMap(\.widgets).map(\.name)
        #expect(byName.contains("World Clock"))
        let byTask = WidgetGalleryModel.sections(query: "next meeting").flatMap(\.widgets).map(\.name)
        #expect(byTask == ["Calendar"])
        let all = WidgetGalleryModel.sections(query: "").flatMap(\.widgets)
        #expect(all.count == WidgetRegistry.all.count)
        let connected = WidgetGalleryModel.sections(query: "", filter: .connected).flatMap(\.widgets)
        #expect(!connected.isEmpty && connected.allSatisfy(\.capabilities.needsConnection))
        let revenue = WidgetGalleryModel.sections(query: "revenue", filter: .connected).flatMap(\.widgets).map(\.name)
        #expect(Set(revenue) == ["Stripe", "Paddle"])
        #expect(WidgetGalleryModel.sections(query: "no-match-xyz").isEmpty)
        // Sections keep WidgetCategory order and drop empty categories.
        let order = WidgetGalleryModel.sections(query: "").map(\.category)
        #expect(order == WidgetCategory.allCases.filter(order.contains))
    }

    @Test func quickAddUsesTheFamilyDefaultLayout() throws {
        for definition in WidgetRegistry.all {
            #expect(WidgetGalleryModel.defaultLayout(for: definition.name) == definition.capabilities.defaultLayout)
            let item = WidgetGalleryModel.item(kind: definition.name, layout: nil)
            #expect(item.type == .widget && item.widgetKind == definition.name)
            let configuration = try #require(item.widgetConfiguration)
            #expect(WidgetPresentationCatalog.resolvedLayout(for: definition.name, configuration: configuration) == definition.capabilities.defaultLayout)
        }
    }

    @Test func pagerLayoutIsStoredOnTheAddedWidget() throws {
        for definition in WidgetRegistry.all {
            for option in WidgetGalleryModel.layoutOptions(for: definition.name) {
                let item = WidgetGalleryModel.item(kind: definition.name, layout: option.layout)
                #expect(item.widgetConfiguration?.widgetLayout == option.layout)
                let configuration = try #require(item.widgetConfiguration)
                #expect(WidgetPresentationCatalog.resolvedLayout(for: definition.name, configuration: configuration, compactDefault: true) == option.layout)
            }
            #expect(WidgetGalleryModel.layoutOptions(for: definition.name) == definition.capabilities.layouts)
        }
        #expect(WidgetGalleryModel.item(kind: "Clock", layout: nil).id != WidgetGalleryModel.item(kind: "Clock", layout: nil).id)
    }

    @Test func addedStateCoversDockItemsAndRecentAdds() {
        let app = DockItem.application(at: URL(fileURLWithPath: "/Applications/Example.app"))
        let profile = DockProfile(name: "Dock", kind: .custom, items: [.widget("Clock"), app])
        #expect(WidgetGalleryModel.isAdded(.widget("Clock"), in: profile, recentlyAdded: []))
        #expect(!WidgetGalleryModel.isAdded(.widget("Weather"), in: profile, recentlyAdded: []))
        #expect(WidgetGalleryModel.isAdded(.widget("Weather"), in: profile, recentlyAdded: ["widget:Weather"]))
        #expect(WidgetGalleryModel.isAdded(.application(at: URL(fileURLWithPath: "/Applications/Example.app")), in: profile, recentlyAdded: []))
        #expect(!WidgetGalleryModel.isAdded(.spacer(.small), in: profile, recentlyAdded: []))
    }

    @Test func appEntriesDisambiguateDuplicateNamesAndFilter() {
        let apps = [
            InstalledApplication(url: URL(fileURLWithPath: "/Applications/Notes.app"), bundleIdentifier: "a", name: "Notes", version: "2.0"),
            InstalledApplication(url: URL(fileURLWithPath: "/Volumes/Old/Notes.app"), bundleIdentifier: "b", name: "Notes", version: "1.0"),
            InstalledApplication(url: URL(fileURLWithPath: "/Applications/Maps.app"), bundleIdentifier: "c", name: "Maps", version: "3.0")
        ]
        let entries = WidgetGalleryModel.applicationEntries(apps, query: "")
        #expect(entries.map(\.detail) == ["Version 2.0 · Applications", "Version 1.0 · Old", ""])
        let filtered = WidgetGalleryModel.applicationEntries(apps, query: " not ")
        #expect(filtered.count == 2 && filtered.allSatisfy { !$0.detail.isEmpty })
    }

    @Test func moreKeepsEverySystemEntry() {
        let custom = WidgetGalleryModel.moreEntries(kind: .custom, query: "").map(\.title)
        #expect(custom == SpacerKind.allCases.map(\.title) + ["Choose Application…", "Folder…", "File…", "Link…"])
        let native = WidgetGalleryModel.moreEntries(kind: .native, query: "").map(\.title)
        #expect(native == SpacerKind.allCases.map(\.title) + ["Choose Application…"])
        #expect(WidgetGalleryModel.moreEntries(kind: .custom, query: "website").map(\.title) == ["Link…"])
    }

    @Test func gridColumnsStayBetweenTwoAndFour() {
        #expect(WidgetGalleryModel.columnCount(for: 0) == 2)
        #expect(WidgetGalleryModel.columnCount(for: 300) == 2)
        #expect(WidgetGalleryModel.columnCount(for: 652) == 2)
        #expect(WidgetGalleryModel.columnCount(for: 872) == 3)
        #expect(WidgetGalleryModel.columnCount(for: 2000) == 4)
    }
}
