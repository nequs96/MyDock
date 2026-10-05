import AppKit
import SwiftUI

/// The Add Item window. Browser mode is a Control Center–style gallery (Widgets · Apps · More)
/// with an in-place widget detail; command mode (⌘K) is `CommandLibrary`, unchanged.
struct AddLibrary: View {
    @ObservedObject var store: ProfileStore
    let profile: DockProfile
    var commandMode = false
    var allowsAdding = true
    let add: (DockItem) -> Void
    let switchProfile: (UUID) -> Void
    let newDock: () -> Void
    let settings: () -> Void
    let browse: (String) -> Void
    let close: () -> Void
    @State private var query: String
    @State private var tab: AddLibraryTab
    @State private var scan: InstalledAppScan?
    @State private var loading = true
    @State private var refreshID = UUID()
    @State private var selected = 0
    @State private var keyboardNavigation = false
    @State private var recentlyAdded: Set<String> = []
    @State private var addGenerations: [String: Int] = [:]
    @State private var actionError: String?
    @State private var capabilityFilter: WidgetDiscoveryFilter = .all
    @State private var detail: WidgetDefinition?
    @State private var detailLayout: WidgetLayout = .compact
    /// The widget tile with keyboard focus (its entry id).
    @FocusState private var focusedTile: String?
    /// The tile a keyboard-opened detail came from; closing the detail focuses it again.
    @State private var detailOrigin: String?
    /// True while focus is being handed back to `detailOrigin`, so the search field that
    /// reappears does not take focus.
    @State private var returningFocus = false
    /// Frozen when the window opens so a tile does not vanish the moment it is added.
    @State private var suggestions: [WidgetDefinition]
    @State private var contentWidth: CGFloat = 780
    @DockAccessibilityStyle() private var accessibility
    #if DEBUG
    @Environment(\.addLibraryPreview) private var preview
    #endif

    init(store: ProfileStore, profile: DockProfile, commandMode: Bool = false, allowsAdding: Bool = true,
         initialQuery: String = "", initialCategory: String = "All",
         add: @escaping (DockItem) -> Void, switchProfile: @escaping (UUID) -> Void,
         newDock: @escaping () -> Void, settings: @escaping () -> Void,
         browse: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.store = store; self.profile = profile; self.commandMode = commandMode; self.allowsAdding = allowsAdding
        self.add = add; self.switchProfile = switchProfile; self.newDock = newDock
        self.settings = settings; self.browse = browse; self.close = close
        _query = State(initialValue: initialQuery)
        _tab = State(initialValue: AddLibraryTab.initial(category: initialCategory, kind: profile.kind))
        _suggestions = State(initialValue: WidgetGalleryModel.suggestions(for: profile, allowsAdding: allowsAdding))
    }

    // MARK: Entries

    private enum EntryKind {
        case widget(WidgetDefinition)
        case application(WidgetGalleryApplicationEntry)
        case more(WidgetGalleryMoreEntry)
    }
    private struct Entry: Identifiable {
        var id: String
        var kind: EntryKind
        var item: DockItem? {
            switch kind {
            case .widget(let widget): .widget(widget.name)
            case .application(let entry): entry.application.dockItem
            case .more(let entry): entry.item
            }
        }
    }

    private var tabs: [AddLibraryTab] { AddLibraryTab.available(for: profile.kind) }
    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sections: [WidgetGallerySection] {
        guard profile.kind == .custom else { return [] }
        var result = WidgetGalleryModel.sections(query: searchText, filter: capabilityFilter)
        #if DEBUG
        if let start = preview?.startSection, let index = result.firstIndex(where: { $0.category == start }) {
            result = Array(result[index...])
        }
        #endif
        return result
    }
    private var showsSuggested: Bool {
        #if DEBUG
        if preview?.startSection != nil { return false }
        #endif
        return searchText.isEmpty && capabilityFilter == .all && !suggestions.isEmpty
    }
    private var columns: Int { WidgetGalleryModel.columnCount(for: contentWidth, spacing: WidgetGalleryMetrics.gridSpacing) }
    /// Three heroes in a row, four when there is room; narrow windows show four as a 2 × 2 block
    /// so heroes never shrink below the grid tiles.
    private var heroCount: Int { min(suggestions.count, columns == 2 || contentWidth >= 960 ? 4 : 3) }
    private var heroColumns: Int { columns == 2 ? 2 : max(1, heroCount) }
    private var applications: [WidgetGalleryApplicationEntry] {
        WidgetGalleryModel.applicationEntries(scan?.applications ?? [], query: searchText)
    }
    private var moreEntries: [WidgetGalleryMoreEntry] { WidgetGalleryModel.moreEntries(kind: profile.kind, query: searchText) }

    private func entries(for tab: AddLibraryTab) -> [Entry] {
        switch tab {
        case .widgets:
            let heroes = showsSuggested ? suggestions.prefix(heroCount).map { Entry(id: "suggested:" + $0.name, kind: .widget($0)) } : []
            return heroes + sections.flatMap(\.widgets).map { Entry(id: "widget:" + $0.name, kind: .widget($0)) }
        case .apps: return applications.map { Entry(id: $0.id, kind: .application($0)) }
        case .more: return moreEntries.map { Entry(id: $0.id, kind: .more($0)) }
        }
    }
    private var navigationEntries: [Entry] { entries(for: tab) }
    private func added(_ item: DockItem?) -> Bool {
        guard let item else { return false }
        return WidgetGalleryModel.isAdded(item, in: profile, recentlyAdded: recentlyAdded)
    }
    private func generation(_ item: DockItem) -> Int { addGenerations[WidgetGalleryModel.identity(item)] ?? 0 }
    private func isSelected(_ id: String) -> Bool {
        keyboardNavigation && navigationEntries.indices.contains(selected) && navigationEntries[selected].id == id
    }
    private func isFocused(_ id: String) -> Bool {
        #if DEBUG
        if let focused = preview?.focusedTile { return focused == id }
        #endif
        return focusedTile == id
    }
    private func tileWidth(columns: Int) -> CGFloat {
        let spacing = WidgetGalleryMetrics.gridSpacing
        return floor((contentWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    // MARK: Body

    var body: some View {
        Group {
            if commandMode {
                CommandLibrary(store: store, profile: profile, commandMode: true, allowsAdding: allowsAdding,
                               add: add, switchProfile: switchProfile, newDock: newDock, settings: settings, browse: browse, close: close)
            } else { browser }
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                if let detail {
                    GeometryReader { viewport in
                        DockScrollView {
                            WidgetGalleryDetail(widget: detail, layout: $detailLayout, added: added(.widget(detail.name)),
                                                canAdd: allowsAdding, addGeneration: generation(.widget(detail.name)),
                                                add: { addWidget(detail, layout: detailLayout) })
                                // Centred in the window like the iPadOS detail, scrolling only when it must.
                                .frame(minHeight: viewport.size.height * 0.9, alignment: .center)
                        }
                    }
                    .background(GalleryPagerKeys(step: stepDetailLayout))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    gallery
                        .background(GalleryTileKeys(tileFocused: focusedTile != nil, key: tileKey, directAdd: directAdd))
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .bottom) {
            if let actionError {
                Text(actionError)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .dockGlass(.regular, in: Capsule())
                    .padding(.bottom, 16)
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .frame(minWidth: 680, idealWidth: 860, maxWidth: 1040, minHeight: 520, idealHeight: 640, maxHeight: 820)
        .background(DockDesign.page)
        .task(id: refreshID) {
            #if DEBUG
            if let previewScan = preview?.scan { scan = previewScan; loading = false; return }
            #endif
            loading = true; scan = nil
            let result = await InstalledAppCatalog.scan()
            guard !Task.isCancelled else { return }
            scan = result; loading = false
        }
        .onAppear(perform: applyPreviewState)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in refreshID = UUID() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshID = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshID = UUID() }
        .onChange(of: query) { _ in selected = 0; keyboardNavigation = false; focusedTile = nil }
        .onChange(of: tab) { _ in selected = 0; keyboardNavigation = false }
        .onChange(of: capabilityFilter) { _ in selected = 0; keyboardNavigation = false }
        .onExitCommand(perform: escape)
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        VStack(spacing: 12) {
            if let detail {
                HStack {
                    Button(action: closeDetail) {
                        Label("Back", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(GalleryGlassButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Back to \(tab.title)")
                    .help("Back to the gallery (Esc)")
                    Spacer()
                    doneButton
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(detail.name)
            } else {
                ZStack {
                    GallerySearchPill(placeholder: tab.searchPlaceholder, text: $query,
                                      move: moveSelection, choose: performSelected, cancel: escape,
                                      focusOnAppear: !returningFocus, tab: focusTiles,
                                      didBeginEditing: { focusedTile = nil })
                        .frame(maxWidth: WidgetGalleryMetrics.searchMaximumWidth)
                        .padding(.horizontal, 64)
                    HStack {
                        if tab == .widgets { filterMenu }
                        Spacer()
                        doneButton
                    }
                }
                GallerySegmentedControl(items: tabs.map { ($0, $0.title) }, selection: $tab, accessibilityLabel: "Item type")
                if tab == .widgets && capabilityFilter != .all {
                    HStack(spacing: 6) {
                        Text(capabilityFilter.rawValue).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Button { capabilityFilter = .all } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show all widgets")
                    }
                }
                if !allowsAdding {
                    Text("Choose a Dock to add items.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var doneButton: some View {
        Button("Done", action: close)
            .buttonStyle(GalleryGlassButtonStyle())
            .help("Close")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Widget capabilities", selection: $capabilityFilter) {
                ForEach(WidgetDiscoveryFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: capabilityFilter == .all ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(capabilityFilter == .all ? Color.primary : DockDesign.accent)
        }
        .menuStyle(.borderlessButton)
        .tint(capabilityFilter == .all ? Color.primary : DockDesign.accent)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: WidgetGalleryMetrics.controlHeight, height: WidgetGalleryMetrics.controlHeight)
        .dockGlass(.regular, in: Circle())
        .accessibilityLabel("Widget capabilities")
        .accessibilityValue(capabilityFilter.rawValue)
        .help("Filter widgets by what they use")
    }

    // MARK: Gallery

    private var gallery: some View {
        ScrollViewReader { proxy in
            DockScrollView {
                VStack(alignment: .leading, spacing: WidgetGalleryMetrics.sectionSpacing) {
                    switch tab {
                    case .widgets: widgetsContent
                    case .apps: appsContent
                    case .more: moreContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, WidgetGalleryMetrics.pageInset)
                .padding(.top, 6)
                .padding(.bottom, 28)
                .id("content-top")
            }
            .galleryContentWidth($contentWidth)
            .onChange(of: selected) { value in
                if navigationEntries.indices.contains(value) { proxy.scrollTo(navigationEntries[value].id, anchor: .center) }
            }
            .onChange(of: tab) { _ in proxy.scrollTo("content-top", anchor: .top) }
            .onChange(of: focusedTile) { id in
                guard let id else { return }
                DockDesign.Motion.perform(DockDesign.Motion.appear, reduceMotion: accessibility.reduceMotion) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder private var widgetsContent: some View {
        if showsSuggested {
            VStack(alignment: .leading, spacing: 12) {
                GallerySectionTitle(title: "Suggested")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth(columns: heroColumns)), spacing: WidgetGalleryMetrics.gridSpacing, alignment: .top), count: heroColumns),
                          alignment: .leading, spacing: 20) {
                    ForEach(suggestions.prefix(heroCount)) { widget in
                        widgetTile(widget, id: "suggested:" + widget.name, style: .hero, width: tileWidth(columns: heroColumns))
                    }
                }
            }
        }
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: 12) {
                GallerySectionTitle(title: section.category.rawValue)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth(columns: columns)), spacing: WidgetGalleryMetrics.gridSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: 20) {
                    ForEach(section.widgets) { widget in
                        widgetTile(widget, id: "widget:" + widget.name, style: .grid, width: tileWidth(columns: columns))
                    }
                }
            }
        }
        if sections.isEmpty {
            GalleryEmptyState(title: "No Widgets Found",
                              detail: capabilityFilter == .all ? "Try another search." : "Try another search or show all widgets.") {
                crossTabSuggestions(excluding: .widgets)
            }
        } else {
            alsoFound(excluding: .widgets)
        }
    }

    /// Below results: the other segments that also match the search.
    @ViewBuilder private func alsoFound(excluding current: AddLibraryTab) -> some View {
        if !searchText.isEmpty && tabs.contains(where: { $0 != current && !entries(for: $0).isEmpty }) {
            HStack(spacing: 10) {
                Text("Also found").font(.system(size: 12)).foregroundStyle(.secondary)
                crossTabSuggestions(excluding: current)
            }
        }
    }

    private func widgetTile(_ widget: WidgetDefinition, id: String, style: WidgetGalleryTile.Style, width: CGFloat) -> some View {
        let item = DockItem.widget(widget.name)
        let isAdded = added(item)
        return WidgetGalleryTile(widget: widget, layout: WidgetGalleryModel.defaultLayout(for: widget.name), width: width, style: style,
                                 added: isAdded, selected: isSelected(id), focused: isFocused(id), addGeneration: generation(item),
                                 open: { openDetail(widget) },
                                 addDefault: allowsAdding ? { addWidget(widget, layout: nil) } : nil)
            // Keyboard route: Tab or the arrows reach the tile, Return/Space show sizes,
            // Command-Return adds (GalleryTileKeys and WidgetGalleryKeymap).
            .galleryFocusable()
            .focused($focusedTile, equals: id)
            .onMoveCommand { moveFocus(from: id, direction: $0) }
            .id(id)
            .contextMenu {
                if allowsAdding {
                    ForEach(WidgetGalleryModel.layoutOptions(for: widget.name)) { option in
                        Button((isAdded ? "Add Another · " : "Add · ") + option.title) { addWidget(widget, layout: option.layout) }
                    }
                    Divider()
                }
                Button("Show Sizes…") { openDetail(widget) }
            }
    }

    @ViewBuilder private var appsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Finding applications…").font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 28)
            }
            if let scan, scan.unreadableLocations > 0 {
                HStack {
                    Label(scan.applications.isEmpty ? "Applications couldn’t be loaded." : "Some application locations couldn’t be loaded.",
                          systemImage: "exclamationmark.circle")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { refreshID = UUID() }.buttonStyle(GalleryGlassButtonStyle())
                }
            }
            if !applications.isEmpty {
                WidgetGalleryAppList {
                    ForEach(Array(applications.enumerated()), id: \.element.id) { index, entry in
                        let item = entry.application.dockItem
                        WidgetGalleryAppRow(entry: entry, added: added(item), selected: isSelected(entry.id), enabled: allowsAdding,
                                            addGeneration: generation(item)) { perform(Entry(id: entry.id, kind: .application(entry))) }
                            .id(entry.id)
                        if index < applications.count - 1 { WidgetGalleryRowSeparator() }
                    }
                }
            } else if !loading && (scan?.unreadableLocations ?? 0) == 0 {
                GalleryEmptyState(title: searchText.isEmpty ? "No Applications Found" : "No Apps Found",
                                  detail: searchText.isEmpty ? "Choose an application from another location." : "Try another search.") {
                    crossTabSuggestions(excluding: .apps)
                }
            }
            if !applications.isEmpty { alsoFound(excluding: .apps) }
            HStack(spacing: 10) {
                if searchText.isEmpty {
                    Button("Choose Application…") { guard allowsAdding else { return }; close(); browse("Choose Application…") }
                        .buttonStyle(GalleryGlassButtonStyle())
                        .disabled(!allowsAdding)
                }
                Spacer()
                Button { refreshID = UUID() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(GalleryGlassButtonStyle())
                    .disabled(loading)
                    .help("Scan application folders again")
            }
            Text(profile.kind == .custom ? "Add widgets again to create separate instances." : "Click an app to add it.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var moreContent: some View {
        if moreEntries.isEmpty {
            GalleryEmptyState(title: "No Results", detail: "Try another search.") { crossTabSuggestions(excluding: .more) }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                GallerySectionTitle(title: "Spacers and Locations")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth(columns: columns)), spacing: WidgetGalleryMetrics.gridSpacing, alignment: .top), count: columns),
                          alignment: .leading, spacing: 20) {
                    ForEach(moreEntries) { entry in
                        WidgetGalleryMoreTile(entry: entry, width: tileWidth(columns: columns), selected: isSelected(entry.id), enabled: allowsAdding) {
                            perform(Entry(id: entry.id, kind: .more(entry)))
                        }
                        .id(entry.id)
                    }
                }
            }
            alsoFound(excluding: .more)
        }
    }

    /// When the current segment has no match, offer the segments that do.
    @ViewBuilder private func crossTabSuggestions(excluding current: AddLibraryTab) -> some View {
        if !searchText.isEmpty {
            HStack(spacing: 8) {
                ForEach(tabs.filter { $0 != current }) { other in
                    let count = entries(for: other).count
                    if count > 0 {
                        Button("\(count) in \(other.title)") {
                            DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: accessibility.reduceMotion) { tab = other }
                        }
                        .buttonStyle(GalleryGlassButtonStyle())
                    }
                }
            }
        }
    }

    // MARK: Actions

    /// `origin` is the focused tile when the keyboard opened the detail; focus returns there.
    private func openDetail(_ widget: WidgetDefinition, from origin: String? = nil) {
        detailOrigin = origin
        DockDesign.Motion.perform(DockDesign.Motion.appear, reduceMotion: accessibility.reduceMotion) {
            detailLayout = WidgetGalleryModel.defaultLayout(for: widget.name)
            detail = widget
        }
    }
    private func closeDetail() {
        let origin = detailOrigin
        detailOrigin = nil
        // Keep the reappearing search field from taking focus back from the tile.
        if origin != nil { returningFocus = true }
        DockDesign.Motion.perform(DockDesign.Motion.appear, reduceMotion: accessibility.reduceMotion) { detail = nil }
        guard let origin else { return }
        // The tile exists again only after the gallery is back in the hierarchy.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            focusedTile = origin
            returningFocus = false
        }
    }

    /// Return, Space or Command-Return on the focused widget tile.
    private func tileKey(_ key: WidgetGalleryKey, command: Bool) {
        guard detail == nil, let id = focusedTile, let entry = navigationEntries.first(where: { $0.id == id }),
              case .widget(let widget) = entry.kind else { return }
        switch WidgetGalleryKeymap.action(for: key, command: command, context: .tile, canAdd: allowsAdding, hasQuery: !query.isEmpty) {
        case .showSizes: openDetail(widget, from: id)
        case .addDefault: addWidget(widget, layout: nil)
        default: break
        }
    }
    /// Command-Return in the gallery: adds the focused tile's default size, otherwise the
    /// search field's highlighted result, exactly like Return there.
    private func directAdd() {
        guard detail == nil else { return }
        if focusedTile != nil { tileKey(.returnKey, command: true); return }
        guard WidgetGalleryKeymap.action(for: .returnKey, command: true, context: .searchResults, canAdd: allowsAdding) == .addDefault,
              navigationEntries.indices.contains(selected) else { return }
        perform(navigationEntries[selected])
    }
    /// Tab from the search field lands on the highlighted widget tile, or the first one.
    private func focusTiles() -> Bool {
        guard detail == nil, tab == .widgets, !navigationEntries.isEmpty else { return false }
        let index = keyboardNavigation && navigationEntries.indices.contains(selected) ? selected : 0
        keyboardNavigation = false
        focusedTile = navigationEntries[index].id
        return true
    }
    private func moveFocus(from id: String, direction: MoveCommandDirection) {
        guard let index = navigationEntries.firstIndex(where: { $0.id == id }) else { return }
        let move: WidgetGalleryMoveDirection
        switch direction {
        case .left: move = .left
        case .right: move = .right
        case .up: move = .up
        case .down: move = .down
        @unknown default: return
        }
        let target = WidgetGalleryModel.movedIndex(from: index, direction: move, columns: columns, count: navigationEntries.count)
        focusedTile = navigationEntries[target].id
    }
    private func stepDetailLayout(_ offset: Int) {
        guard let detail else { return }
        let layouts = WidgetGalleryModel.layoutOptions(for: detail.name).map(\.layout)
        guard let index = layouts.firstIndex(of: detailLayout), layouts.indices.contains(index + offset) else { return }
        DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: accessibility.reduceMotion) { detailLayout = layouts[index + offset] }
    }

    private func addWidget(_ widget: WidgetDefinition, layout: WidgetLayout?) {
        guard allowsAdding else { return }
        let item = WidgetGalleryModel.item(kind: widget.name, layout: layout)
        commit(item)
    }

    private func commit(_ item: DockItem) {
        add(item)
        let key = WidgetGalleryModel.identity(item)
        DockDesign.Motion.perform(DockDesign.Motion.appear, reduceMotion: accessibility.reduceMotion) {
            recentlyAdded.insert(key)
            actionError = nil
        }
        addGenerations[key, default: 0] += 1
    }

    private func perform(_ entry: Entry) {
        guard allowsAdding else { return }
        switch entry.kind {
        case .widget(let widget):
            addWidget(widget, layout: nil)
        case .application(let application):
            let item = application.application.dockItem
            guard WidgetDiscovery.canAdd(item, alreadyAdded: added(item)) else { return }
            if let url = item.url, InstalledAppCatalog.validatedApplication(at: url) == nil {
                actionError = "This application is no longer available. Refreshing applications…"; refreshID = UUID(); return
            }
            commit(item)
        case .more(let more):
            if var item = more.item {
                item.id = UUID()
                add(item); actionError = nil
            } else if let name = more.browseAction { close(); browse(name) }
        }
    }

    private func moveSelection(_ offset: Int) {
        keyboardNavigation = true
        selected = min(max(0, navigationEntries.count - 1), max(0, selected + offset))
    }
    /// Return in the search field: adds the highlighted result's default size (the detail's
    /// selected size while it is open), as it always has.
    private func performSelected() {
        let context: WidgetGalleryKeyContext = detail == nil ? .searchResults : .detail
        switch WidgetGalleryKeymap.action(for: .returnKey, context: context, canAdd: allowsAdding) {
        case .addSelectedSize: if let detail { addWidget(detail, layout: detailLayout) }
        case .addDefault: if navigationEntries.indices.contains(selected) { perform(navigationEntries[selected]) }
        default: break
        }
    }
    /// Escape leaves the detail first, then clears the search, then closes.
    private func escape() {
        switch WidgetGalleryKeymap.escape(detailOpen: detail != nil, hasQuery: !query.isEmpty) {
        case .closeDetail: closeDetail()
        case .clearSearch: query = ""
        default: close()
        }
    }

    private func applyPreviewState() {
        #if DEBUG
        guard let preview else { return }
        recentlyAdded.formUnion(preview.recentlyAdded)
        if let name = preview.detailFamily, let widget = WidgetRegistry.definition(named: name) {
            detail = widget
            detailLayout = preview.detailLayout ?? WidgetGalleryModel.defaultLayout(for: name)
        }
        #endif
    }
}
