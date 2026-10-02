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
        let action: () -> Void
    }
    private var entries: [Entry] {
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
                Entry(id: item.url?.path ?? item.id.uuidString, title: item.displayName, detail: "Application", symbol: "app", item: item, action: { add(item); close() })
            }
        }
        if allowsAdding && profile.kind == .custom && (category == "All" || category == "Widgets") {
            result += WidgetRegistry.all.map { widget in
                let item = DockItem.widget(widget.name)
                return Entry(id: widget.name, title: widget.name, detail: widget.description, symbol: widget.symbol, item: item, action: { add(item); close() })
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
        return result.filter { query.isEmpty || ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                LibrarySearchField(placeholder: commandMode ? "Search MyDock…" : (profile.kind == .custom ? "Search apps, widgets, and actions…" : "Search apps and spacers…"),
                                   text: $query, move: { offset in selected = min(max(0, entries.count - 1), max(0, selected + offset)) },
                                   choose: performSelected, cancel: close).frame(height: 24)
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
                            Button(action: entry.action) {
                                HStack(spacing: 12) {
                                    if let item = entry.item, item.type == .application {
                                        Image(nsImage: AppLauncher.icon(for: item, size: 32)).resizable().scaledToFit().frame(width: 32, height: 32)
                                    } else { Image(systemName: entry.symbol).frame(width: 32).foregroundStyle(.secondary) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(.system(size: 13, weight: .medium))
                                        Text(entry.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let item = entry.item, item.type == .widget {
                                        WidgetCardPreview(kind: item.widgetKind ?? "", width: 144, displayScale: 0.7)
                                            .frame(width: 108, height: 40).allowsHitTesting(false).accessibilityHidden(true)
                                    }
                                    if index == selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(.tertiary) }
                                }.padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(index == selected ? DockDesign.hover : .clear, in: RoundedRectangle(cornerRadius: 8))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).id(entry.id)
                                .contextMenu {
                                    if let item = entry.item, item.type == .widget {
                                        ForEach(WidgetPresentationCatalog.options(for: item.widgetKind ?? item.title)) { option in
                                            Button("Add " + option.title) {
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
    private func performSelected() { if entries.indices.contains(selected) { entries[selected].action() } }
}

