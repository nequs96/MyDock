import AppKit
import SwiftUI

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
    @State private var category: String
    @State private var scan: InstalledAppScan?
    @State private var loading = true
    @State private var refreshID = UUID()
    @State private var selected = 0
    @State private var keyboardNavigation = false
    @State private var recentlyAdded: Set<String> = []
    @State private var actionError: String?
    @State private var capabilityFilter: WidgetDiscoveryFilter = .all

    init(store: ProfileStore, profile: DockProfile, commandMode: Bool = false, allowsAdding: Bool = true,
         initialQuery: String = "", initialCategory: String = "All",
         add: @escaping (DockItem) -> Void, switchProfile: @escaping (UUID) -> Void,
         newDock: @escaping () -> Void, settings: @escaping () -> Void,
         browse: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.store = store; self.profile = profile; self.commandMode = commandMode; self.allowsAdding = allowsAdding
        self.add = add; self.switchProfile = switchProfile; self.newDock = newDock
        self.settings = settings; self.browse = browse; self.close = close
        _query = State(initialValue: initialQuery)
        _category = State(initialValue: initialCategory == "Apps" ? "Applications" : initialCategory)
    }

    private struct Entry: Identifiable {
        var id: String
        var title: String
        var detail: String
        var symbol: String
        var item: DockItem?
        var application: InstalledApplication?
        var browseAction: String?
    }
    private var categories: [(String, String)] {
        profile.kind == .custom ? [("All", "square.grid.2x2"), ("Applications", "app.dashed"), ("Widgets", "rectangle.3.group"), ("System", "slider.horizontal.3")]
            : [("All", "square.grid.2x2"), ("Applications", "app.dashed"), ("System", "slider.horizontal.3")]
    }
    private var searchText: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func matches(_ text: String) -> Bool { searchText.isEmpty || text.localizedStandardContains(searchText) }
    private var widgets: [WidgetDefinition] {
        guard profile.kind == .custom, ["All", "Widgets"].contains(category) else { return [] }
        return WidgetRegistry.all.filter { capabilityFilter.includes($0) && WidgetDiscovery.matches($0, query: searchText) }
    }
    private var applications: [Entry] {
        guard ["All", "Applications"].contains(category) else { return [] }
        let apps = scan?.applications ?? []
        return apps.filter { matches($0.name) }.map { app in
            let ambiguous = apps.filter { $0.name == app.name }.count > 1
            return Entry(id: app.id, title: app.name, detail: ambiguous ? "Version \(app.version) · \(app.url.deletingLastPathComponent().lastPathComponent)" : "",
                         symbol: "app", item: app.dockItem, application: app)
        }
    }
    private var systemEntries: [Entry] {
        guard ["All", "System"].contains(category) else { return [] }
        var result = SpacerKind.allCases.map { kind in
            Entry(id: "spacer:" + kind.rawValue, title: kind.title, detail: "Give a group of items room to breathe.", symbol: "rectangle.split.2x1", item: .spacer(kind))
        }
        for (name, symbol, detail) in [("Choose Application…", "app", "Add an app from another location."), ("Folder…", "folder", "Keep a folder within reach."), ("File…", "doc", "Open a document from your Dock."), ("Link…", "globe", "Add a website or URL.")] {
            if profile.kind == .native && name != "Choose Application…" { continue }
            result.append(Entry(id: name, title: name, detail: detail, symbol: symbol, browseAction: name))
        }
        return result.filter { matches($0.title + " " + $0.detail) }
    }
    private var navigationEntries: [Entry] {
        WidgetCategory.allCases.flatMap { group in widgets.filter { $0.category == group } }.map { Entry(id: "widget:" + $0.name, title: $0.name, detail: $0.description, symbol: $0.symbol, item: .widget($0.name)) } + applications + systemEntries
    }
    private func identity(_ item: DockItem) -> String {
        switch item.type {
        case .application: "app:" + (WidgetDiscovery.applicationKey(item) ?? item.id.uuidString)
        case .widget: "widget:" + (item.widgetKind ?? item.title)
        default: item.id.uuidString
        }
    }
    private func added(_ entry: Entry) -> Bool {
        guard let item = entry.item, item.type == .widget || item.type == .application else { return false }
        return recentlyAdded.contains(identity(item)) || profile.items.contains { identity($0) == identity(item) }
    }
    private func isSelected(_ id: String) -> Bool { keyboardNavigation && navigationEntries.indices.contains(selected) && navigationEntries[selected].id == id }

    var body: some View {
        Group {
            if commandMode {
                CommandLibrary(store: store, profile: profile, commandMode: true, allowsAdding: allowsAdding,
                               add: add, switchProfile: switchProfile, newDock: newDock, settings: settings, browse: browse, close: close)
            } else { browser }
        }
    }
    private var browser: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 176)
            Divider()
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(searchText.isEmpty ? category == "All" ? "Add Item" : category : "Search Results").font(.system(size: 17, weight: .semibold))
                        Text("Add to \(profile.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Done", action: close).controlSize(.small)
                }.padding(.horizontal, 22).padding(.vertical, 18)
                if profile.kind == .custom && ["All", "Widgets"].contains(category) {
                    HStack {
                        Picker("Widget capabilities", selection: $capabilityFilter) {
                            ForEach(WidgetDiscoveryFilter.allCases) { Text($0.rawValue).tag($0) }
                        }.frame(maxWidth: 250)
                        Spacer()
                        Text("Permissions may depend on the action or setup you choose.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.horizontal, 22).padding(.bottom, 12)
                }
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if navigationEntries.isEmpty && scan?.unreadableLocations == 0 && !(loading && ["All", "Applications"].contains(category)) {
                                emptyState(title: category == "Applications" && searchText.isEmpty ? "No applications found" : "No items found", detail: category == "Applications" && searchText.isEmpty ? "Choose an application from another location." : "Try another search, category or widget filter.", symbol: "magnifyingglass")
                            }
                            if !widgets.isEmpty {
                                ForEach(WidgetCategory.allCases, id: \.rawValue) { group in
                                    let members = widgets.filter { $0.category == group }
                                    if !members.isEmpty {
                                        VStack(alignment: .leading, spacing: 12) {
                                            sectionTitle(group.rawValue)
                                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], alignment: .leading, spacing: 16) {
                                                ForEach(members) { widget in widgetTile(widget) }
                                            }
                                        }
                                    }
                                }
                            }
                            if ["All", "Applications"].contains(category) { appSection }
                            if !systemEntries.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    if category == "All" { sectionTitle("System") }
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
                                        ForEach(systemEntries) { systemTile($0) }
                                    }
                                }
                            }
                        }.padding(22).id("content-top")
                    }.onChange(of: selected) { value in
                        if navigationEntries.indices.contains(value) { proxy.scrollTo(navigationEntries[value].id, anchor: .center) }
                    }.onChange(of: category) { _ in proxy.scrollTo("content-top", anchor: .top) }
                }
                if let actionError { Text(actionError).font(.caption).foregroundStyle(.secondary).padding(10) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 740, idealWidth: 820, maxWidth: 1040, minHeight: 500, idealHeight: 560, maxHeight: 760)
        .background(DockDesign.page)
        .task(id: refreshID) {
            loading = true; scan = nil
            let result = await InstalledAppCatalog.scan()
            guard !Task.isCancelled else { return }
            scan = result; loading = false
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in refreshID = UUID() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in refreshID = UUID() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshID = UUID() }
        .onChange(of: query) { _ in selected = 0; keyboardNavigation = false }
        .onChange(of: category) { _ in selected = 0; keyboardNavigation = false }
        .onChange(of: capabilityFilter) { _ in selected = 0; keyboardNavigation = false }
        .onExitCommand(perform: escape)
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                LibrarySearchField(placeholder: "Search", text: $query, move: moveSelection, choose: performSelected, cancel: escape, compact: true)
                    .frame(height: 22)
            }.padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            VStack(spacing: 3) {
                ForEach(categories, id: \.0) { name, symbol in
                    Button { category = name } label: {
                        Label(name, systemImage: symbol).font(.system(size: 13, weight: category == name ? .medium : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 9).padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(category == name ? Color.white : Color.primary)
                        .background(category == name ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityValue(category == name ? "Selected" : "")
                }
            }
            Spacer()
            Text(profile.kind == .custom ? "Add widgets again to create separate instances." : "Click + to add an item.").font(.caption).foregroundStyle(.secondary)
            Button { refreshID = UUID() } label: { Label("Refresh Applications", systemImage: "arrow.clockwise") }
                .buttonStyle(.borderless).font(.caption).disabled(loading)
        }.padding(12).background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 13, weight: .semibold)) }
    private func widgetTile(_ widget: WidgetDefinition) -> some View {
        let entry = Entry(id: "widget:" + widget.name, title: widget.name, detail: widget.description, symbol: widget.symbol, item: .widget(widget.name))
        return VStack(alignment: .leading, spacing: 9) {
            WidgetCardPreview(kind: widget.name, width: CGFloat(WidgetPresentationCatalog.width(for: widget.name, layout: WidgetPresentationCatalog.defaultLayout(for: widget.name))), displayScale: 1.1)
                .frame(maxWidth: .infinity).frame(height: 78).accessibilityHidden(true)
            Text("Example").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Example preview for \(widget.name)")
            itemCaption(entry)
            if !WidgetDiscovery.setupSummary(widget).isEmpty {
                Text(WidgetDiscovery.setupSummary(widget)).font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(widget.description).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
        }.padding(10).background(isSelected(entry.id) ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .id(entry.id)
            .contextMenu {
                ForEach(WidgetPresentationCatalog.options(for: widget.name)) { option in
                    Button((added(entry) ? "Add Another · " : "Add · ") + option.title) {
                        var item = DockItem.widget(widget.name); item.widgetConfiguration?.widgetLayout = option.layout
                        add(item); recentlyAdded.insert(identity(item))
                    }
                }
            }
    }
    private func systemTile(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if entry.item?.type == .spacer {
                    ForEach(0..<3) { _ in RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 30, height: 30) }
                    Spacer().frame(width: entry.title.contains("Small") ? 8 : 22)
                    RoundedRectangle(cornerRadius: 7).fill(.quaternary).frame(width: 30, height: 30)
                } else { Image(systemName: entry.symbol).font(.system(size: 30, weight: .light)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity).frame(height: 78).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 9)).accessibilityHidden(true)
            itemCaption(entry)
            Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(height: 30, alignment: .topLeading)
        }.padding(10).background(isSelected(entry.id) ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8)).id(entry.id)
    }
    private func itemCaption(_ entry: Entry) -> some View {
        HStack(spacing: 6) {
            Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 2)
            if added(entry) { Text("Added").font(.caption2).foregroundStyle(.secondary) }
            addButton(entry)
        }
    }
    private func addButton(_ entry: Entry) -> some View {
        let repeatedWidget = added(entry) && entry.item?.type == .widget
        return Button { perform(entry) } label: {
            if repeatedWidget { Text("Add another").font(.caption).foregroundStyle(Color.accentColor) }
            else if added(entry) { Image(systemName: "checkmark").foregroundStyle(.secondary) }
            else { Image(systemName: entry.browseAction == nil ? "plus.circle.fill" : "plus.circle").foregroundStyle(Color.accentColor) }
        }.buttonStyle(.borderless).font(.system(size: 17)).frame(minWidth: 26, minHeight: 26)
            .disabled(added(entry) && !repeatedWidget).help(repeatedWidget ? "Add another \(entry.title) with its own settings" : added(entry) ? "Added to this Dock" : "Add \(entry.title)")
            .accessibilityLabel(repeatedWidget ? "Add another \(entry.title)" : added(entry) ? "\(entry.title), Added" : "Add \(entry.title)")
    }
    private var appSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if category == "All" && !applications.isEmpty { sectionTitle("Applications") }
            if loading { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Finding applications…").font(.callout).foregroundStyle(.secondary) }.padding(.vertical, 24) }
            if let scan, scan.unreadableLocations > 0 {
                HStack {
                    Label(scan.applications.isEmpty ? "Applications couldn’t be loaded." : "Some application locations couldn’t be loaded.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") { refreshID = UUID() }.controlSize(.small)
                }
            }
            LazyVStack(spacing: 0) {
                ForEach(applications) { entry in
                    HStack(spacing: 10) {
                        if let app = entry.application { InstalledApplicationIcon(application: app).accessibilityHidden(true) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).font(.system(size: 13)).lineLimit(2)
                            if !entry.detail.isEmpty { Text(entry.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer()
                        if added(entry) { Text("Added").font(.caption).foregroundStyle(.secondary) }
                        addButton(entry)
                    }.padding(.horizontal, 8).padding(.vertical, 6)
                        .background(isSelected(entry.id) ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6)).id(entry.id)
                        .help(entry.application?.url.path ?? entry.title)
                    Divider().padding(.leading, 48)
                }
            }
            if category == "Applications", searchText.isEmpty {
                Button("Choose Application…") { close(); browse("Choose Application…") }.buttonStyle(.borderless).font(.callout).padding(.top, 6)
            }
        }
    }
    private func emptyState(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 70)
    }
    private func perform(_ entry: Entry) {
        if let item = entry.item, !WidgetDiscovery.canAdd(item, alreadyAdded: added(entry)) { return }
        if var item = entry.item {
            if item.type == .widget { item.id = UUID() }
            if item.type == .application, let url = item.url, InstalledAppCatalog.validatedApplication(at: url) == nil {
                actionError = "This application is no longer available. Refreshing applications…"; refreshID = UUID(); return
            }
            add(item); recentlyAdded.insert(identity(item)); actionError = nil
        } else if let name = entry.browseAction { close(); browse(name) }
    }
    private func moveSelection(_ offset: Int) { keyboardNavigation = true; selected = min(max(0, navigationEntries.count - 1), max(0, selected + offset)) }
    private func performSelected() { if navigationEntries.indices.contains(selected) { perform(navigationEntries[selected]) } }
    private func escape() { if !query.isEmpty { query = "" } else { close() } }
}

private struct InstalledApplicationIcon: View {
    var application: InstalledApplication
    @State private var icon: NSImage?
    var body: some View {
        Group {
            if let icon { Image(nsImage: icon).resizable().scaledToFit() }
            else { Image(systemName: "app.fill").font(.system(size: 24)).foregroundStyle(.secondary) }
        }.frame(width: 30, height: 30)
            .task(id: application.id) {
                let url = application.url
                let worker = Task.detached(priority: .utility) { InstalledApplicationIconLoader.load(at: url) }
                let data = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }
                icon = data.flatMap(NSImage.init(data:))
            }
    }
}
