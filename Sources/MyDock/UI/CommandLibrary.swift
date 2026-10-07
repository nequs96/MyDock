import AppKit
import SwiftUI

/// The ⌘K window: switch Docks, run commands, find saved content and add items.
struct CommandLibrary: View {
    @ObservedObject var store: ProfileStore
    let profile: DockProfile
    var allowsAdding = true
    let add: (DockItem) -> Void
    let switchProfile: (UUID) -> Void
    let newDock: () -> Void
    let settings: () -> Void
    let browse: (DockBrowseAction) -> Void
    let close: () -> Void
    @State private var query = ""
    @State private var apps: [DockItem] = []
    @State private var selected = 0
    @Environment(\.workspaceStartHandler) private var workspaceStartHandler

    init(store: ProfileStore, profile: DockProfile, allowsAdding: Bool = true,
         add: @escaping (DockItem) -> Void, switchProfile: @escaping (UUID) -> Void,
         newDock: @escaping () -> Void, settings: @escaping () -> Void,
         browse: @escaping (DockBrowseAction) -> Void, close: @escaping () -> Void) {
        self.store = store; self.profile = profile; self.allowsAdding = allowsAdding
        self.add = add; self.switchProfile = switchProfile; self.newDock = newDock
        self.settings = settings; self.browse = browse; self.close = close
    }

    private struct Entry: Identifiable {
        let id: String
        let title: String
        var detail: String
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
    /// Docks and commands first, then saved content, then items to add, so a saved match is not
    /// buried under every app and widget that also matches.
    private var entries: [Entry] { matching(commandEntries) + savedEntries + matching(addEntries) }
    /// Explicitly saved snippets, links and shelf files from every Dock. Absent unless the query matches something.
    private var savedEntries: [Entry] {
        SavedCollectionSearch.results(in: store.state.profiles, query: query).map(savedEntry)
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
            entry.action = { openSaved(url, native: native) }
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
                entry.action = { openSaved(url, native: native) }
                entry.secondary = ("Reveal in Finder", "folder", { guard native else { return }; NSWorkspace.shared.activateFileViewerSelecting([url]); close() })
            }
        }
        return entry
    }
    /// Opens a saved link or file; a refused open beeps and keeps the window open.
    private func openSaved(_ url: URL, native: Bool) {
        guard native else { return }
        guard NSWorkspace.shared.open(url) else { NSSound.beep(); return }
        close()
    }
    private var commandEntries: [Entry] {
        // Other Docks come first; the Dock being edited stays last so Settings can return to it.
        let docks = store.state.profiles.filter { $0.id != profile.id } + store.state.profiles.filter { $0.id == profile.id }
        var result: [Entry] = docks.map { p in
            Entry(id: p.id.uuidString, title: "Switch to " + p.name, detail: p.id == profile.id ? "Current Dock" : "Dock",
                  symbol: "dock.rectangle", action: { switchProfile(p.id); close() })
        }
        if let workspaceStartHandler {
            result += store.state.profiles.filter(\.hasWorkspace).map { p in
                Entry(id: "workspace:" + p.id.uuidString, title: "Start Workspace: " + p.name, detail: "Workspace", symbol: "play.circle", action: { close(); workspaceStartHandler.start(p.id) })
            }
        }
        result += [Entry(id: "new", title: "Create New Dock", detail: "⌘N", symbol: "plus", action: { close(); newDock() }),
                   Entry(id: "settings", title: "Open Settings", detail: "⌘,", symbol: "gearshape", action: { close(); settings() })]
        return result
    }
    private var addEntries: [Entry] {
        var result: [Entry] = []
        if allowsAdding {
            // One key set per pass, and only apps whose text can match are resolved: each app is a
            // set lookup instead of a symlink resolution for every Dock item.
            let dockKeys = Set(profile.items.compactMap(WidgetDiscovery.applicationKey))
            result += apps.compactMap { item -> Entry? in
                let folder = item.url?.deletingLastPathComponent().path ?? ""
                guard query.isEmpty || (item.displayName + " Application · " + folder).localizedStandardContains(query)
                        || (item.displayName + " Application · Already added").localizedStandardContains(query) else { return nil }
                let key = WidgetDiscovery.applicationKey(item)
                let added = key.map { dockKeys.contains($0) } ?? false
                return Entry(id: key ?? item.id.uuidString, title: item.displayName,
                             detail: added ? "Application · Already added" : "Application · " + folder,
                             symbol: "app", item: item, enabled: !added,
                             action: { guard !added else { return }; add(item); close() })
            }
        }
        if allowsAdding && profile.kind == .custom {
            result += WidgetRegistry.all.map { widget in
                let item = DockItem.widget(widget.name)
                return Entry(id: widget.name, title: (profile.items.contains { $0.widgetKind == widget.name } ? "Add another " : "Add ") + widget.name, detail: widget.description, symbol: widget.symbol, item: item, action: { add(item); close() })
            }
        }
        if allowsAdding {
            result += SpacerKind.allCases.map { kind in
                Entry(id: kind.rawValue, title: kind.title + " spacer", detail: "Separate groups of items", symbol: "rectangle.split.2x1", action: { add(.spacer(kind)); close() })
            }
            for action in DockBrowseAction.available(for: profile.kind) {
                result.append(Entry(id: "browse:" + action.rawValue, title: action.title, detail: "Browse", symbol: "plus", action: { close(); browse(action) }))
            }
        }
        return result
    }
    private func matching(_ candidates: [Entry]) -> [Entry] {
        candidates.filter { entry in
            if let kind = entry.item?.widgetKind, let definition = WidgetRegistry.definition(named: kind) {
                return WidgetDiscovery.matches(definition, query: query) || entry.title.localizedStandardContains(query)
            }
            return query.isEmpty || (entry.title + " " + entry.detail).localizedStandardContains(query)
        }
    }

    var body: some View {
        // Built once per pass: the field, the list, the arrow keys and Return all read these rows
        // (app keys, bookmark resolution and file checks are not repeated per use).
        let rows = entries
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                LibrarySearchField(placeholder: "Search MyDock…",
                                   text: $query, move: { offset in moveSelection(by: offset, in: rows) },
                                   choose: { performSelected(in: rows) }, cancel: close,
                                   secondary: { if rows.indices.contains(selected), let run = rows[selected].secondary?.run { run() } }).frame(height: 24)
                Button(action: close) { Image(systemName: "xmark").frame(width: DockDesign.controlHeight, height: DockDesign.controlHeight).contentShape(Rectangle()) }.buttonStyle(.plain).help("Close").accessibilityLabel("Close library")
            }.padding(24)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        if rows.isEmpty {
                            GalleryEmptyState(title: "No Matches", detail: profile.kind == .custom ? "Try an app or widget name." : "Try an app name or spacer.", compact: true)
                        }
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                            if let section = entry.section, index == 0 || rows[index - 1].section != section {
                                Text(section).font(DockDesign.caption).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.top, 10)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            Button(action: entry.action) {
                                HStack(spacing: 12) {
                                    if let item = entry.item, item.type == .application {
                                        Image(nsImage: AppLauncher.icon(for: item, size: 32)).resizable().scaledToFit().frame(width: 32, height: 32)
                                    } else { Image(systemName: entry.warning ? "exclamationmark.triangle.fill" : entry.symbol).frame(width: 32).foregroundStyle(entry.warning ? DockDesign.Status.warning : Color.secondary) }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title).font(DockDesign.body.weight(.medium))
                                        Text(entry.detail).font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if let trailing = entry.trailing {
                                        Text(trailing).font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    if index == selected, let secondary = entry.secondary {
                                        Text("⌥↩ " + secondary.label).font(DockDesign.Grouped.footerFont).foregroundStyle(.tertiary).lineLimit(1)
                                            .accessibilityHidden(true)
                                    }
                                    if let item = entry.item, item.type == .widget {
                                        VStack(alignment: .trailing, spacing: 2) {
                                            WidgetCardPreview(kind: item.widgetKind ?? "", width: 144, displayScale: 0.7)
                                                .frame(width: 108, height: 40).allowsHitTesting(false).accessibilityHidden(true)
                                            Text("Example").font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                                                .accessibilityLabel("Example preview for \(entry.title)")
                                        }
                                    }
                                    if index == selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(.tertiary).accessibilityHidden(true) }
                                }.padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(index == selected ? DockDesign.hover : .clear, in: RoundedRectangle(cornerRadius: DockDesign.Radius.row))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!entry.enabled).id(entry.id)
                                .accessibilityAddTraits(index == selected ? .isSelected : [])
                                .accessibilityActions {
                                    if let secondary = entry.secondary { Button(secondary.label, action: secondary.run) }
                                }
                                .contextMenu {
                                    if let secondary = entry.secondary { Button(secondary.label, action: secondary.run) }
                                    if let item = entry.item, item.type == .widget {
                                        ForEach(WidgetPresentationCatalog.options(for: item.widgetKind ?? item.title)) { option in
                                            Button((profile.items.contains { $0.widgetKind == item.widgetKind } ? "Add another · " : "Add · ") + option.title) {
                                                var configured = item
                                                var configuration = configured.widgetConfiguration ?? WidgetConfiguration()
                                                configuration.widgetLayout = option.layout
                                                configured.widgetConfiguration = configuration
                                                add(configured); close()
                                            }
                                        }
                                    }
                                }
                        }
                    }.padding(12)
                }.onChange(of: selected) { value in
                    if rows.indices.contains(value) { proxy.scrollTo(rows[value].id) }
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
            .onChange(of: rows.count) { count in selected = min(selected, max(0, count - 1)) }
            .onMoveCommand { direction in
                if direction == .down { moveSelection(by: 1, in: rows) }
                if direction == .up { moveSelection(by: -1, in: rows) }
            }
            .onExitCommand(perform: close)
    }
    /// Focus stays in the search field, so VoiceOver hears the newly highlighted command.
    private func moveSelection(by offset: Int, in rows: [Entry]) {
        let next = min(max(0, rows.count - 1), max(0, selected + offset))
        selected = next
        guard rows.indices.contains(next) else { return }
        GalleryAnnouncement.post(rows[next].title + (rows[next].enabled ? "" : ", dimmed"))
    }
    private func performSelected(in rows: [Entry]) { if rows.indices.contains(selected), rows[selected].enabled { rows[selected].action() } }
}



@MainActor
enum SavedCollectionActions {
    /// Reuses the File Shelf repair rules: the entry keeps its identity and a duplicate target is refused.
    /// A refused or unsaved repair is reported, never shown as success.
    static func locate(_ saved: SavedCollectionResult, store: ProfileStore) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let panel = NSOpenPanel()
        panel.title = "Locate \(saved.title)"; panel.prompt = "Use This File"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        var relocation: FileShelfPolicy.RelocationResult?
        let update = store.updateWidgetConfiguration(itemID: saved.itemID, in: saved.profileID) { configuration in
            let result = FileShelfPolicy.relocating(saved.entryID, to: chosen, in: configuration.shelfFiles)
            relocation = result
            if case let .relocated(updated) = result { configuration.shelfFiles = updated }
        }
        guard let failure = locateFailure(relocation: relocation, update: update) else { return }
        let alert = NSAlert()
        alert.messageText = "Could not locate \(saved.title)"
        alert.informativeText = failure
        alert.runModal()
    }

    /// Why a Locate… repair changed nothing, or nil when the shelf now points to the chosen file.
    static func locateFailure(relocation: FileShelfPolicy.RelocationResult?, update: WidgetConfigurationUpdateResult) -> String? {
        switch relocation {
        case .duplicate(let name)?: return "\(name) is already on this shelf, so the missing item was left unchanged."
        case .notFound?: return "That file could not be found. The shelf item was left unchanged."
        case .notFileURL?: return "Choose a file on this Mac. The shelf item was left unchanged."
        case .relocated?, nil:
            switch update {
            case .accepted, .unchanged: return nil
            case .rejected(let reason): return reason
            case .missingTarget: return "This File Shelf was removed. Nothing was changed."
            }
        }
    }
}
