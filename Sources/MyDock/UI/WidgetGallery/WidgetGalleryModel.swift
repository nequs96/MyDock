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
    var browseAction: DockBrowseAction?
}

/// The pickers the Add Item window and ⌘K open. Behaviour keys on the case, never on the title.
enum DockBrowseAction: String, CaseIterable, Identifiable, Equatable {
    case application, folder, file, link

    var id: String { rawValue }
    var title: String {
        switch self {
        case .application: "Choose Application…"
        case .folder: "Folder…"
        case .file: "File…"
        case .link: "Link…"
        }
    }
    var symbol: String {
        switch self {
        case .application: "plus.app"
        case .folder: "folder"
        case .file: "doc"
        case .link: "globe"
        }
    }
    var detail: String {
        switch self {
        case .application: "Add an app from another location."
        case .folder: "Keep a folder within reach."
        case .file: "Open a document from your Dock."
        case .link: "Add a website or URL."
        }
    }

    /// macOS Dock layouts hold apps and spacers only.
    static func available(for kind: DockProfileKind) -> [DockBrowseAction] {
        kind == .custom ? allCases : [.application]
    }
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

    /// The layout Command-Return or a search-field Return adds and a gallery tile previews: the family's default.
    static func defaultLayout(for kind: String) -> WidgetLayout {
        WidgetRegistry.definition(named: kind)?.capabilities.defaultLayout ?? WidgetPresentationCatalog.defaultLayout(for: kind)
    }

    /// Shown wherever adding is unavailable because no Dock is selected.
    static let noDockMessage = "Choose a Dock to add items."

    /// The pages of the detail view's size pager; never empty, so previews cannot index past it.
    static func layoutOptions(for kind: String) -> [WidgetLayoutOption] {
        let options = WidgetPresentationCatalog.options(for: kind)
        return options.isEmpty ? WidgetLayoutPresets.generic : options
    }

    /// The option a preview draws for `layout`: that size, else the family's first.
    static func layoutOption(for kind: String, layout: WidgetLayout) -> WidgetLayoutOption {
        let options = layoutOptions(for: kind)
        return options.first { $0.layout == layout } ?? options.first ?? WidgetLayoutPresets.generic[0]
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
        isAdded(item, addedIdentities: addedIdentities(in: profile), recentlyAdded: recentlyAdded)
    }

    /// The identities of the widgets and apps on a Dock, built once per pass so each tile and row
    /// is a set lookup instead of a path resolution per Dock item.
    static func addedIdentities(in profile: DockProfile) -> Set<String> {
        Set(profile.items.lazy.filter { $0.type == .widget || $0.type == .application }.map(identity))
    }

    static func isAdded(_ item: DockItem, addedIdentities: Set<String>, recentlyAdded: Set<String>) -> Bool {
        guard item.type == .widget || item.type == .application else { return false }
        let key = identity(item)
        return recentlyAdded.contains(key) || addedIdentities.contains(key)
    }

    /// Apps match every query word against the name and bundle identifier, like widget search.
    static func applicationEntries(_ applications: [InstalledApplication], query: String) -> [WidgetGalleryApplicationEntry] {
        var counts: [String: Int] = [:]
        for application in applications { counts[application.name, default: 0] += 1 }
        return applications
            .filter { WidgetDiscovery.matchesTerms($0.name + " " + $0.bundleIdentifier, query: query) }
            .map { application in
                let ambiguous = (counts[application.name] ?? 0) > 1
                return WidgetGalleryApplicationEntry(application: application, detail: ambiguous ? duplicateDetail(application) : "")
            }
    }

    /// Tells same-named apps apart: the version when the bundle has one, and the containing folder.
    static func duplicateDetail(_ application: InstalledApplication) -> String {
        let folder = application.url.deletingLastPathComponent().lastPathComponent
        return [application.version.isEmpty ? nil : "Version " + application.version, folder.isEmpty ? nil : folder]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// Spacers, then the pickers. Native Docks only offer Choose Application… besides spacers.
    static func moreEntries(kind: DockProfileKind, query: String) -> [WidgetGalleryMoreEntry] {
        var result = SpacerKind.allCases.map { spacer in
            WidgetGalleryMoreEntry(id: "spacer:" + spacer.rawValue, title: spacer.title,
                                   detail: spacerDetail(spacer), symbol: "rectangle.split.2x1", item: .spacer(spacer))
        }
        for action in DockBrowseAction.available(for: kind) {
            result.append(WidgetGalleryMoreEntry(id: "browse:" + action.rawValue, title: action.title, detail: action.detail,
                                                 symbol: action.symbol, browseAction: action))
        }
        return result.filter { WidgetDiscovery.matchesTerms($0.title + " " + $0.detail, query: query) }
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

    /// Grid tiles carry the family name only; Everyday Tools adds the description line Suggested tiles show,
    /// because those names say little on their own.
    static func showsDescription(in category: WidgetCategory) -> Bool { category == .utilities }

    /// Grid columns for a content width: two to four, never narrower than `minimumTile`.
    static func columnCount(for width: CGFloat, minimumTile: CGFloat = 230, spacing: CGFloat = 16) -> Int {
        guard width.isFinite, width > 0 else { return 2 }
        let fitting = Int((width + spacing) / (minimumTile + spacing))
        return min(4, max(2, fitting))
    }

    /// The result Return acts on is always the one drawn highlighted: the arrow-key selection, or the first result
    /// while a search narrows the list. A gallery opened with no search highlights, and adds, nothing.
    static func highlightedIndex(keyboardNavigation: Bool, hasQuery: Bool, selected: Int, count: Int) -> Int? {
        guard count > 0, keyboardNavigation || hasQuery else { return nil }
        return min(max(0, selected), count - 1)
    }

    /// The Widgets segment as drawn: the Suggested row chunked by `heroColumns`, then every section
    /// chunked by `columns`. Each section starts a new row, so rows can be shorter than `columns`.
    static func gridRows(heroIDs: [String], heroColumns: Int, sections: [[String]], columns: Int) -> [[String]] {
        func rows(_ ids: [String], width: Int) -> [[String]] {
            let width = max(1, width)
            return stride(from: 0, to: ids.count, by: width).map { Array(ids[$0..<min($0 + width, ids.count)]) }
        }
        return rows(heroIDs, width: heroColumns) + sections.flatMap { rows($0, width: columns) }
    }

    /// The tile the arrow keys reach from `id`: left and right step through the reading order;
    /// up and down keep the column in the adjacent row, clamped to that row's length.
    /// `nil` when `id` is not in `rows`.
    static func movedID(from id: String, direction: WidgetGalleryMoveDirection, rows: [[String]]) -> String? {
        guard let row = rows.firstIndex(where: { $0.contains(id) }),
              let column = rows[row].firstIndex(of: id) else { return nil }
        switch direction {
        case .left, .right:
            let order = rows.flatMap { $0 }
            guard let index = order.firstIndex(of: id) else { return nil }
            return order[min(order.count - 1, max(0, index + (direction == .left ? -1 : 1)))]
        case .up, .down:
            let target = row + (direction == .up ? -1 : 1)
            guard rows.indices.contains(target), !rows[target].isEmpty else { return id }
            return rows[target][min(column, rows[target].count - 1)]
        }
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
        canAdd ? "Click or press Return to see sizes. Press Command-Return to add."
               : "Click or press Return to see sizes."
    }
}
