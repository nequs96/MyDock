import Foundation
import CoreGraphics

/// The Add Item window's segments. Native Dock profiles have no widgets, so they show Apps and More only.
enum AddLibraryTab: String, CaseIterable, Identifiable, Hashable {
    case widgets = "Widgets"
    case apps = "Apps"
    case more = "More"

    var id: String { rawValue }
    var title: String { rawValue }
    var searchPlaceholder: String {
        switch self {
        case .widgets: "Search Widgets"
        case .apps: "Search Apps"
        case .more: "Search"
        }
    }

    static func available(for kind: DockProfileKind) -> [AddLibraryTab] {
        kind == .custom ? [.widgets, .apps, .more] : [.apps, .more]
    }

    /// Maps the sidebar category names callers have always passed ("All", "Widgets",
    /// "Applications"/"Apps", "System") to a segment. "All" and unknown names open the
    /// profile's first segment; a segment the profile lacks falls back the same way.
    static func initial(category: String, kind: DockProfileKind) -> AddLibraryTab {
        let tabs = available(for: kind)
        let requested: AddLibraryTab?
        switch category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "widgets": requested = .widgets
        case "applications", "apps": requested = .apps
        case "system", "more": requested = .more
        default: requested = nil
        }
        if let requested, tabs.contains(requested) { return requested }
        return tabs[0]
    }
}

/// One category section of the Widgets segment.
struct WidgetGallerySection: Identifiable, Equatable {
    var category: WidgetCategory
    var widgets: [WidgetDefinition]
    var id: String { category.rawValue }
}

/// A row of the Apps segment, with the version and folder only when two apps share a name.
struct WidgetGalleryApplicationEntry: Identifiable {
    var application: InstalledApplication
    var detail: String
    var id: String { application.id }
    var title: String { application.name }
}

/// A tile of the More segment: a spacer to add, or a picker to open.
struct WidgetGalleryMoreEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var item: DockItem?
    var browseAction: String?
}

/// Pure decisions behind the gallery, kept out of the views so they can be tested.
enum WidgetGalleryModel {
    /// Families most people want first. Suggested takes one per category in this order,
    /// then fills from the rest, so the row stays varied and deterministic.
    static let suggestionPriority = [
        "Calendar", "Weather", "Clock", "System Activity", "Now Playing", "Quick Checklist",
        "AI Limits", "Stock", "Reminders", "Focus Timer", "Battery", "World Clock",
        "Sticky Note", "File Shelf", "Disk Space", "Network Activity"
    ]

    /// Up to `limit` families that fit a custom Dock and are not on it yet. Native profiles,
    /// and windows that cannot add (no Dock selected), get none.
    static func suggestions(for profile: DockProfile, allowsAdding: Bool, limit: Int = 4) -> [WidgetDefinition] {
        guard allowsAdding, profile.kind == .custom, limit > 0 else { return [] }
        let present = Set(profile.items.compactMap { $0.type == .widget ? ($0.widgetKind ?? $0.title) : nil })
        let prioritized = suggestionPriority.compactMap(WidgetRegistry.definition(named:))
        let ordered = prioritized + WidgetRegistry.all.filter { !suggestionPriority.contains($0.name) }
        let candidates = ordered.filter { !present.contains($0.name) }
        var picked: [WidgetDefinition] = []
        var categories = Set<WidgetCategory>()
        for candidate in candidates where picked.count < limit && !categories.contains(candidate.category) {
            picked.append(candidate)
            categories.insert(candidate.category)
        }
        for candidate in candidates where picked.count < limit && !picked.contains(candidate) {
            picked.append(candidate)
        }
        return picked
    }

    /// Category sections in `WidgetCategory` order, filtered through `WidgetDiscovery` search
    /// and the capability filter. Empty sections are dropped.
    static func sections(query: String, filter: WidgetDiscoveryFilter = .all) -> [WidgetGallerySection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = WidgetRegistry.all.filter { filter.includes($0) && WidgetDiscovery.matches($0, query: trimmed) }
        return WidgetCategory.allCases.compactMap { category in
            let members = matching.filter { $0.category == category }
            return members.isEmpty ? nil : WidgetGallerySection(category: category, widgets: members)
        }
    }

    /// The layout a double-click or Return adds and a gallery tile previews: the family's default.
    static func defaultLayout(for kind: String) -> WidgetLayout {
        WidgetRegistry.definition(named: kind)?.capabilities.defaultLayout ?? WidgetPresentationCatalog.defaultLayout(for: kind)
    }

    /// The pages of the detail view's size pager.
    static func layoutOptions(for kind: String) -> [WidgetLayoutOption] {
        WidgetPresentationCatalog.options(for: kind)
    }

    /// A new widget item. `nil` is the quick add: no stored layout, exactly as the gallery's
    /// plus button always added, so the family default (or a compact Dock's compact default)
    /// applies. A chosen layout is stored the same way the layout context menu stores it.
    static func item(kind: String, layout: WidgetLayout?) -> DockItem {
        var item = DockItem.widget(kind)
        if let layout { item.widgetConfiguration?.widgetLayout = layout }
        return item
    }

    /// Widgets are one identity per family, apps per normalized bundle location.
    static func identity(_ item: DockItem) -> String {
        switch item.type {
        case .application: "app:" + (WidgetDiscovery.applicationKey(item) ?? item.id.uuidString)
        case .widget: "widget:" + (item.widgetKind ?? item.title)
        default: item.id.uuidString
        }
    }

    /// Widgets and apps already on the Dock, or added while the window is open, show as added.
    static func isAdded(_ item: DockItem, in profile: DockProfile, recentlyAdded: Set<String>) -> Bool {
        guard item.type == .widget || item.type == .application else { return false }
        let key = identity(item)
        return recentlyAdded.contains(key) || profile.items.contains { identity($0) == key }
    }

    static func applicationEntries(_ applications: [InstalledApplication], query: String) -> [WidgetGalleryApplicationEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var counts: [String: Int] = [:]
        for application in applications { counts[application.name, default: 0] += 1 }
        return applications
            .filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) }
            .map { application in
                let ambiguous = (counts[application.name] ?? 0) > 1
                return WidgetGalleryApplicationEntry(
                    application: application,
                    detail: ambiguous ? "Version \(application.version) · \(application.url.deletingLastPathComponent().lastPathComponent)" : "")
            }
    }

    /// Spacers, then the pickers. Native Docks only offer Choose Application… besides spacers.
    static func moreEntries(kind: DockProfileKind, query: String) -> [WidgetGalleryMoreEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = SpacerKind.allCases.map { spacer in
            WidgetGalleryMoreEntry(id: "spacer:" + spacer.rawValue, title: spacer.title,
                                   detail: spacerDetail(spacer), symbol: "rectangle.split.2x1", item: .spacer(spacer))
        }
        let pickers = [("Choose Application…", "plus.app", "Add an app from another location."),
                       ("Folder…", "folder", "Keep a folder within reach."),
                       ("File…", "doc", "Open a document from your Dock."),
                       ("Link…", "globe", "Add a website or URL.")]
        for (name, symbol, detail) in pickers {
            if kind == .native && name != "Choose Application…" { continue }
            result.append(WidgetGalleryMoreEntry(id: name, title: name, detail: detail, symbol: symbol, browseAction: name))
        }
        return result.filter { trimmed.isEmpty || ($0.title + " " + $0.detail).localizedStandardContains(trimmed) }
    }

    /// One short, distinct line per spacer size.
    static func spacerDetail(_ spacer: SpacerKind) -> String {
        switch spacer {
        case .small: "A slim gap between neighbouring items."
        case .regular: "A wide gap that splits the Dock into groups."
        }
    }

    /// The configuration a new widget of `kind` is created with. Previews render from it, so a
    /// sample looks like what gets added (Mono icons today, set by `DockItem.widget`).
    static func creationConfiguration(for kind: String) -> WidgetConfiguration {
        item(kind: kind, layout: nil).widgetConfiguration ?? WidgetConfiguration()
    }

    /// The detail pager caption: the size name and what that size shows, on one line.
    static func pagerCaption(_ option: WidgetLayoutOption) -> String {
        let detail = option.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty, detail.caseInsensitiveCompare(option.title) != .orderedSame else { return option.title }
        return option.title + " · " + detail
    }

    /// Sizes whose catalog wording names a shape the sample does not draw; the gallery says what the face shows.
    private static let sizeDetailOverrides: [String: String] = [
        "Battery#compact": "Charge ring and percentage",
        "Disk Space#compact": "Free space and a usage ring",
        "System Activity#meter": "CPU in a ring gauge"
    ]

    /// What a size shows, as the gallery words it: the catalog detail unless the sample draws something else.
    static func sizeDetail(kind: String, option: WidgetLayoutOption) -> String {
        sizeDetailOverrides[kind + "#" + option.layout.rawValue] ?? option.detail
    }

    /// The detail pager caption for a family's size, using the gallery's wording.
    static func pagerCaption(kind: String, option: WidgetLayoutOption) -> String {
        var worded = option
        worded.detail = sizeDetail(kind: kind, option: option)
        return pagerCaption(worded)
    }

    /// Grid tiles carry the family name only; Everyday Tools adds the description line Suggested tiles show,
    /// because those names say little on their own.
    static func showsDescription(in category: WidgetCategory) -> Bool { category == .utilities }

    /// Grid columns for a content width: two to four, never narrower than `minimumTile`.
    static func columnCount(for width: CGFloat, minimumTile: CGFloat = 230, spacing: CGFloat = 16) -> Int {
        guard width.isFinite, width > 0 else { return 2 }
        let fitting = Int((width + spacing) / (minimumTile + spacing))
        return min(4, max(2, fitting))
    }

    /// The entry the arrow keys reach from `index` in a flat list laid out `columns` wide:
    /// left/right step by one, up/down by a row, clamped to the list.
    static func movedIndex(from index: Int, direction: WidgetGalleryMoveDirection, columns: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let step: Int
        switch direction {
        case .left: step = -1
        case .right: step = 1
        case .up: step = -max(1, columns)
        case .down: step = max(1, columns)
        }
        return min(count - 1, max(0, index + step))
    }
}

enum WidgetGalleryMoveDirection: Equatable { case left, right, up, down }

/// How a gallery sample is drawn: the per-widget presentation a newly added widget gets.
struct WidgetGalleryPreviewStyle: Equatable {
    var appearance: WidgetIconAppearance
    var accent: WidgetAccent
    var glassTint: WidgetGlassTint

    init(configuration: WidgetConfiguration) {
        appearance = configuration.iconAppearance
        accent = configuration.widgetAccent ?? .auto
        glassTint = configuration.glassTint ?? .none
    }

    /// The style of a widget exactly as the gallery creates it.
    static func creation(kind: String) -> WidgetGalleryPreviewStyle {
        WidgetGalleryPreviewStyle(configuration: WidgetGalleryModel.creationConfiguration(for: kind))
    }
}

/// Keys the gallery acts on.
enum WidgetGalleryKey: Equatable { case returnKey, space, escape }

/// Where the keyboard is: a focused widget tile, the search field driving the highlighted
/// result, or the open detail view.
enum WidgetGalleryKeyContext: Equatable { case tile, searchResults, detail }

enum WidgetGalleryKeyAction: Equatable {
    case showSizes, addDefault, addSelectedSize, closeDetail, clearSearch, close, none
}

/// The gallery keymap, kept pure so both keyboard routes are testable.
///
/// - Focused widget tile: Return or Space shows sizes; Command-Return adds the default size;
///   arrow keys move focus between tiles.
/// - Search field: Up/Down move the highlight; Return (or Command-Return) adds the highlighted
///   item's default size, as it always has; Tab moves focus onto the highlighted widget tile.
/// - Detail: Return adds the selected size; Left/Right change size.
/// - Escape: closes the detail first (focus returns to its tile), then clears the search,
///   then closes the window.
enum WidgetGalleryKeymap {
    static func action(for key: WidgetGalleryKey, command: Bool = false, context: WidgetGalleryKeyContext,
                       canAdd: Bool = true, hasQuery: Bool = false) -> WidgetGalleryKeyAction {
        if key == .escape { return escape(detailOpen: context == .detail, hasQuery: hasQuery) }
        switch context {
        case .tile:
            if key == .returnKey && command { return canAdd ? .addDefault : .none }
            return .showSizes
        case .searchResults:
            guard key == .returnKey else { return .none }
            return canAdd ? .addDefault : .none
        case .detail:
            guard key == .returnKey else { return .none }
            return canAdd ? .addSelectedSize : .none
        }
    }

    /// Escape closes the detail first, then clears the search, then closes.
    static func escape(detailOpen: Bool, hasQuery: Bool) -> WidgetGalleryKeyAction {
        detailOpen ? .closeDetail : hasQuery ? .clearSearch : .close
    }

    /// The VoiceOver hint of a widget tile, naming its keys.
    static func tileHint(canAdd: Bool) -> String {
        canAdd ? "Return or Space shows sizes. Command-Return adds the default size."
               : "Return or Space shows sizes."
    }

    /// The tooltip of a widget tile: the mouse and keyboard routes together.
    static func tileHelp(canAdd: Bool) -> String {
        canAdd ? "Click or press Return to see sizes. Double-click or press Command-Return to add."
               : "Click or press Return to see sizes."
    }
}
