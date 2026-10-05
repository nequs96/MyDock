import AppKit
import SwiftUI

struct CommandLibrary: View {
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
    @State private var query = ""
    @State private var category = "All"
    @State private var apps: [DockItem] = []
    @State private var selected = 0
    @State private var recentlyAdded = Set<String>()

    init(store: ProfileStore, profile: DockProfile, commandMode: Bool = false, allowsAdding: Bool = true,
         initialQuery: String = "", initialCategory: String = "All",
         add: @escaping (DockItem) -> Void, switchProfile: @escaping (UUID) -> Void,
         newDock: @escaping () -> Void, settings: @escaping () -> Void,
         browse: @escaping (String) -> Void, close: @escaping () -> Void) {
        self.store = store; self.profile = profile; self.commandMode = commandMode; self.allowsAdding = allowsAdding
        self.add = add; self.switchProfile = switchProfile; self.newDock = newDock
        self.settings = settings; self.browse = browse; self.close = close
        _query = State(initialValue: initialQuery)
        _category = State(initialValue: initialCategory)
    }

    private struct Entry: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        var item: DockItem?
        var enabled = true
        var action: () -> Void
        /// Saved-content results only: a section header, the owning Dock and an optional secondary action.
        var section: String? = nil
        var trailing: String? = nil
        var warning = false
        var secondary: (label: String, symbol: String, run: () -> Void)? = nil
    }
    private var entries: [Entry] { commandEntries + savedEntries }
    /// Explicitly saved snippets, links and shelf files from every Dock. Absent unless the query matches something.
    private var savedEntries: [Entry] {
        guard commandMode else { return [] }
        return SavedCollectionSearch.results(in: store.state.profiles, query: query).map(savedEntry)
    }
    private func savedEntry(_ saved: SavedCollectionResult) -> Entry {
        let native = AppRuntimeEnvironment.allowsNativeEffects
        var entry = Entry(id: "saved-" + saved.id, title: saved.title, detail: saved.detail, symbol: saved.kind.symbol, action: {},
                          section: "Saved", trailing: saved.dockName)
        switch saved.kind {
        case .snippet:
            entry.action = { if let text = saved.snippetText, copyUtilityText(text) { close() } }
        case .link:
            guard let url = saved.linkURL else { return entry }
            entry.action = { guard native, NSWorkspace.shared.open(url) else { return }; close() }
            entry.secondary = ("Copy Link", "doc.on.doc", { if copyUtilityText(url.absoluteString) { close() } })
        case .file:
            guard let url = saved.fileURL else { return entry }
            if saved.isMissing {
                entry.warning = true
                entry.detail = "Missing · Return to Locate…"
                entry.action = {
                    guard native else { return }
                    close()
                    let target = saved
                    Task { @MainActor [store] in SavedCollectionActions.locate(target, store: store) }
                }
            } else {
                entry.action = { guard native, NSWorkspace.shared.open(url) else { return }; close() }
                entry.secondary = ("Reveal in Finder", "folder", { guard native else { return }; NSWorkspace.shared.activateFileViewerSelecting([url]); close() })
            }
        }
        return entry
    }
    private var commandEntries: [Entry] {
        var result: [Entry] = []
        if commandMode {
            result += store.state.profiles.map { p in
                Entry(id: p.id.uuidString, title: "Switch to " + p.name, detail: "Dock", symbol: "dock.rectangle", action: { switchProfile(p.id); close() })
            }
            result += [Entry(id: "new", title: "Create New Dock", detail: "⌘N", symbol: "plus", action: { close(); newDock() }),
                       Entry(id: "settings", title: "Open Settings", detail: "⌘,", symbol: "gearshape", action: { close(); settings() })]
        }
        if allowsAdding && (category == "All" || category == "Apps") {
            result += apps.map { item in
                Entry(id: WidgetDiscovery.applicationKey(item) ?? item.id.uuidString, title: item.displayName,
                      detail: applicationAlreadyAdded(item) ? "Application · Already added" : "Application · " + (item.url?.deletingLastPathComponent().path ?? ""),
                      symbol: "app", item: item, enabled: !applicationAlreadyAdded(item),
                      action: { guard !applicationAlreadyAdded(item) else { return }; if let key = WidgetDiscovery.applicationKey(item) { recentlyAdded.insert(key) }; add(item); close() })
            }
        }
        if allowsAdding && profile.kind == .custom && (category == "All" || category == "Widgets") {
            result += WidgetRegistry.all.map { widget in
                let item = DockItem.widget(widget.name)
                return Entry(id: widget.name, title: (profile.items.contains { $0.widgetKind == widget.name } ? "Add another " : "Add ") + widget.name, detail: widget.description, symbol: widget.symbol, item: item, action: { add(item); close() })
            }
        }
        if allowsAdding && (category == "All" || category == "System") {
            result += SpacerKind.allCases.map { kind in
                Entry(id: kind.rawValue, title: kind.title + " spacer", detail: "Separate groups of items", symbol: "rectangle.split.2x1", action: { add(.spacer(kind)); close() })
            }
            for name in profile.kind == .custom ? ["Choose Application…", "Folder…", "File…", "Link…"] : ["Choose Application…"] {
                result.append(Entry(id: name, title: name, detail: "Browse", symbol: "plus", action: { close(); browse(name) }))
            }
        }
        return result.filter { entry in
            if let kind = entry.item?.widgetKind, let definition = WidgetRegistry.definition(named: kind) {
                return WidgetDiscovery.matches(definition, query: query) || entry.title.localizedStandardContains(query)
            }
            return query.isEmpty || (entry.title + " " + entry.detail).localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                LibrarySearchField(placeholder: commandMode ? "Search MyDock…" : (profile.kind == .custom ? "Search apps, widgets, and actions…" : "Search apps and spacers…"),
                                   text: $query, move: { offset in selected = min(max(0, entries.count - 1), max(0, selected + offset)) },
                                   choose: performSelected, cancel: close,
                                   secondary: { if entries.indices.contains(selected), let run = entries[selected].secondary?.run { run() } }).frame(height: 24)
                Button(action: close) { Image(systemName: "xmark").frame(width: DockDesign.controlHeight, height: DockDesign.controlHeight).contentShape(Rectangle()) }.buttonStyle(.plain).help("Close").accessibilityLabel("Close library")
            }.padding(24)
            if !commandMode {
                HStack(spacing: 16) {
                    Text("Add to Dock").font(DockDesign.sectionTitle)
                    Spacer()
                    Picker("Category", selection: $category) {
                        ForEach(profile.kind == .custom ? ["All", "Apps", "Widgets", "System"] : ["All", "Apps", "System"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 280)
                }.padding(.horizontal, 24).padding(.bottom, 16)
            }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if entries.isEmpty {
                            Text(profile.kind == .custom ? "No matches. Try an app or widget name." : "No matches. Try an app name or spacer.").foregroundStyle(.secondary).padding(32)
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if let section = entry.section, index == 0 || entries[index - 1].section != section {
                                Text(section).font(DockDesign.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 10)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            Button(action: entry.action) {
                                HStack(spacing: 12) {
                                    if let item = entry.item, item.type == .application {
                                        Image(nsImage: AppLauncher.icon(for: item, size: 32)).resizable().scaledToFit().frame(width: 32, height: 32)
                                    } else { Image(systemName: entry.warning ? "exclamationmark.triangle.fill" : entry.symbol).frame(width: 32).foregroundStyle(entry.warning ? Color.orange : Color.secondary) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(.system(size: 13, weight: .medium))
                                        Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let trailing = entry.trailing {
                                        Text(trailing).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    if index == selected, let secondary = entry.secondary {
                                        Text("⌥↩ " + secondary.label).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
                                    }
                                    if let item = entry.item, item.type == .widget {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            WidgetCardPreview(kind: item.widgetKind ?? "", width: 144, displayScale: 0.7)
                                                .frame(width: 108, height: 40).allowsHitTesting(false).accessibilityHidden(true)
                                            Text("Example").font(.system(size: 11)).foregroundStyle(.secondary)
                                                .accessibilityLabel("Example preview for \(entry.title)")
                                        }
                                    }
                                    if index == selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(.tertiary) }
                                }.padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(index == selected ? DockDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!entry.enabled).id(entry.id)
                                .contextMenu {
                                    if let secondary = entry.secondary { Button(secondary.label, action: secondary.run) }
                                    if let item = entry.item, item.type == .widget {
                                        ForEach(WidgetPresentationCatalog.options(for: item.widgetKind ?? item.title)) { option in
                                            Button((profile.items.contains { $0.widgetKind == item.widgetKind } ? "Add another · " : "Add · ") + option.title) {
                                                var configured = item
                                                configured.widgetConfiguration?.widgetLayout = option.layout
                                                add(configured); close()
                                            }
                                        }
                                    }
                                }
                        }
                    }.padding(12)
                }.onChange(of: selected) { value in
                    if entries.indices.contains(value) { proxy.scrollTo(entries[value].id) }
                }
            }
            Divider()
            HStack {
                Text("↑ ↓ to navigate").font(DockDesign.caption)
                Spacer()
                Text("Return to choose · Esc to close").font(DockDesign.caption)
            }.foregroundStyle(.tertiary).padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 580, height: 540).background(DockDesign.page)
            .task { apps = await InstalledAppCatalog.load() }
            .onChange(of: query) { _ in selected = 0 }
            .onChange(of: category) { _ in selected = 0 }
            .onChange(of: entries.count) { count in selected = min(selected, max(0, count - 1)) }
            .onMoveCommand { direction in
                if direction == .down { selected = min(max(0, entries.count - 1), selected + 1) }
                if direction == .up { selected = max(0, selected - 1) }
            }
            .onExitCommand(perform: close)
    }
    private func applicationAlreadyAdded(_ item: DockItem) -> Bool {
        WidgetDiscovery.containsApplication(item, in: profile.items)
            || WidgetDiscovery.applicationKey(item).map { recentlyAdded.contains($0) } == true
    }
    private func performSelected() { if entries.indices.contains(selected), entries[selected].enabled { entries[selected].action() } }
}



@MainActor
enum SavedCollectionActions {
    /// Reuses the File Shelf repair rules: the entry keeps its identity and a duplicate target is refused.
    static func locate(_ saved: SavedCollectionResult, store: ProfileStore) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let panel = NSOpenPanel()
        panel.title = "Locate \(saved.title)"; panel.prompt = "Use This File"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        store.updateWidgetConfiguration(itemID: saved.itemID, in: saved.profileID) { configuration in
            if case let .relocated(updated) = FileShelfPolicy.relocating(saved.entryID, to: chosen, in: configuration.shelfFiles) {
                configuration.shelfFiles = updated
            }
        }
    }
}
