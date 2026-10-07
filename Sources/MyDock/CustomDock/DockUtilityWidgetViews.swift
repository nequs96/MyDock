import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Pure labels for the saved-collection faces (File Shelf, Text Snippets, Quick Links).
enum SavedCollectionFacePresentation {
    /// The family's short name, used on narrow side-Dock faces.
    static func shortName(kind: String) -> String {
        switch kind {
        case "File Shelf": "Shelf"
        case "Text Snippets": "Snippets"
        default: "Links"
        }
    }
    /// What an empty collection invites on wide faces.
    static func emptyHint(kind: String) -> String {
        switch kind {
        case "File Shelf": "Drop files here"
        case "Text Snippets": "Save a snippet"
        default: "Add a website"
        }
    }
    /// The label line: the short name when narrow, the most recent item when wide, otherwise a short noun.
    /// A collection with entries but no showable name (Text Snippets) reads "Saved", never the empty-state hint.
    static func label(kind: String, latest: String?, layout: WidgetLayout, narrow: Bool, count: Int = 0) -> String {
        if narrow { return shortName(kind: kind) }
        if layout == .wide {
            return latest.flatMap { $0.isEmpty ? nil : $0 } ?? (count > 0 ? (kind == "File Shelf" ? "Shelf" : "Saved") : emptyHint(kind: kind))
        }
        return kind == "File Shelf" ? "Shelf" : "Saved"
    }
    /// The value with its unit, e.g. "2 snippets"; never a bare number.
    static func valueText(kind: String, count: Int) -> String { "\(count) " + SavedCollectionUnit.text(kind: kind, count: count) }
    /// The most recent entry's name for the wide label. Text Snippets hold private text (older unnamed snippets
    /// carry the start of their text as a name), so the Dock face only ever shows their count.
    static func latest(kind: String, configuration: WidgetConfiguration) -> String? {
        switch kind {
        case "File Shelf": configuration.shelfFiles.last?.url.lastPathComponent
        case "Text Snippets": nil
        default: configuration.quickLinks.last?.title
        }
    }
}

extension TextSnippet {
    /// The name shown in the popout: the user's name, or for an unnamed snippet a one-line preview of its text.
    var displayTitle: String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? SavedCollectionSearch.oneLinePreview(text, limit: 40) : name
    }
}

/// The saved-collection module: the count with its unit ("2 snippets") and one short label.
struct SavedCollectionDockFace: View {
    var item: DockItem
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var count: Int {
        switch kind {
        case "File Shelf": configuration.shelfFiles.count
        case "Text Snippets": configuration.textSnippets.count
        default: configuration.quickLinks.count
        }
    }
    private var latest: String? { SavedCollectionFacePresentation.latest(kind: kind, configuration: configuration) }
    var body: some View {
        let narrow = WidgetModuleMetrics.isNarrow(width)
        ModuleStack(kind: kind, label: SavedCollectionFacePresentation.label(kind: kind, latest: latest, layout: layout, narrow: narrow, count: count),
                    value: "\(count)", unit: SavedCollectionUnit.text(kind: kind, count: count),
                    valueColor: count == 0 ? .secondary : .primary, keepsLeading: !narrow)
            .moduleInsets()
            .frame(width: width, height: 54)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(kind)
            .accessibilityValue(SavedCollectionFacePresentation.valueText(kind: kind, count: count) + (latest.map { ", latest \($0)" } ?? ""))
    }
}

struct FileShelfWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(FileShelfDropSurface(store: store, item: item, profileID: profileID) { SavedCollectionDockFace(item: item) })
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(FileShelfView(store: store, item: item, profileID: profileID))
    }
}

struct FileShelfDropSurface<Content: View>: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    var radius: CGFloat? = nil
    @ViewBuilder var content: Content
    @Environment(\.dockModuleRadius) private var moduleRadius
    @State private var targeted = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? moduleRadius, style: .continuous)
        content.contentShape(Rectangle())
            .overlay(shape.fill(DockDesign.accent.opacity(targeted ? 0.12 : 0)).allowsHitTesting(false))
            .overlay(shape.strokeBorder(targeted ? DockDesign.accent : .clear, lineWidth: 2).allowsHitTesting(false))
            .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { providers in
                guard AppRuntimeEnvironment.allowsNativeEffects else { return false }
                let compatible = providers.prefix(FileShelfPolicy.capacity).filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
                guard !compatible.isEmpty else { return false }
                AirDropDroppedItemLoader.load(compatible.map { ($0, UTType.fileURL.identifier) }) { urls in
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.shelfFiles = FileShelfPolicy.adding(urls, to: $0.shelfFiles) }
                }
                return true
            }
            .help("Drop files here to keep them in your shelf")
    }
}

/// One shelf entry's resolved location and whether its original is there. Resolving a bookmark and checking the
/// file can block on a slow or disconnected volume, so the shelf does it off the main thread once per change.
struct ShelfFileAvailability: Equatable, Sendable {
    var url: URL
    var exists: Bool

    static func resolve(_ entries: [ShelfFile],
                        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [UUID: ShelfFileAvailability] {
        var result: [UUID: ShelfFileAvailability] = [:]
        for entry in entries where result[entry.id] == nil {
            let url = entry.resolvedURL
            result[entry.id] = ShelfFileAvailability(url: url, exists: fileExists(url))
        }
        return result
    }
}

struct FileShelfView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var message: String?
    @State private var undoPending: RemovedEntries<ShelfFile>?
    @State private var availability: [UUID: ShelfFileAvailability] = [:]
    /// Bumped by Retry and Locate so the shelf checks its files again without any change to the entries.
    @State private var availabilityRequest = 0
    private var entries: [ShelfFile] { item.widgetConfiguration?.shelfFiles ?? [] }
    /// Until the first check finishes an entry reads as its stored location and as present, so nothing flashes as missing.
    private func shelfState(_ entry: ShelfFile) -> ShelfFileAvailability {
        availability[entry.id] ?? ShelfFileAvailability(url: entry.url, exists: true)
    }
    private var availableURLs: [URL] { entries.compactMap { entry -> URL? in let resolved = shelfState(entry); return resolved.exists ? resolved.url : nil } }
    /// Separators start at the file name, past its glyph.
    private static let rowSeparatorInset = DockDesign.Grouped.separatorInset
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            FileShelfDropSurface(store: store, item: item, profileID: profileID, radius: DockDesign.Grouped.radius) {
                WidgetPopoutDropArea(minHeight: 92) {
                    VStack(spacing: 5) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .regular)).foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text("Drop files to keep them close").font(.system(size: 13, weight: .medium))
                        Text("Or drop onto the File Shelf in your Dock.").font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                WidgetPopoutSectionHeader("Files · \(entries.count) of \(FileShelfPolicy.capacity)") {
                    HStack(spacing: 12) {
                        if entries.count > availableURLs.count {
                            Button("Retry") { retryUnavailable() }.help("Check again, for example after reconnecting a drive")
                        }
                        Button("Copy All") { copy(availableURLs) }.disabled(availableURLs.isEmpty)
                        Button("Add Files…", action: chooseFiles).disabled(entries.count >= FileShelfPolicy.capacity)
                    }
                }
                if entries.isEmpty {
                    GroupedSection {
                        GroupedRow("No files yet", subtitle: "Files stay where they are; the shelf keeps a reference.", symbol: "tray", color: .gray)
                    }
                } else {
                    if entries.count > 6 {
                        DockScrollView { fileList }.frame(height: 270)
                    } else {
                        fileList
                    }
                    HStack(spacing: 10) {
                        AirDropShareButton(urls: availableURLs, title: "Share / AirDrop…").frame(height: 30).fixedSize()
                            .disabled(!AppRuntimeEnvironment.allowsNativeEffects)
                        Spacer()
                        Button("Clear Shelf") {
                            let pending = RemovedEntries.capture(Set(entries.map(\.id)), from: entries, message: "Shelf cleared. Original files are unchanged.")
                            if case .accepted = store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: { $0.shelfFiles = [] }) { undoPending = pending; message = nil }
                        }
                        .buttonStyle(.borderless).foregroundStyle(Color(nsColor: .systemRed))
                    }
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                }
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.shelfFiles, capacity: FileShelfPolicy.capacity) }
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            if let message { WidgetPopoutCaption(message).accessibilityLabel(message) }
            if !AppRuntimeEnvironment.allowsNativeEffects { WidgetPopoutCaption(utilityIsolatedActionMessage) }
            WidgetPopoutCaption("Removing an item leaves the original file in place.")
                .help("The shelf keeps references, not copies. Copy files here, then paste them in Finder with ⌘V.")
        }
        .task(id: ShelfAvailabilityKey(entries: entries, request: availabilityRequest)) {
            let current = entries
            let resolved = await Task.detached(priority: .userInitiated) { ShelfFileAvailability.resolve(current) }.value
            guard !Task.isCancelled else { return }
            availability = resolved
        }
    }
    private struct ShelfAvailabilityKey: Equatable {
        var entries: [ShelfFile]
        var request: Int
    }
    private var fileList: some View {
        GroupedSection(separatorInset: Self.rowSeparatorInset) {
            ForEach(entries) { entry in fileRow(entry) }
        }
    }
    private func fileRow(_ entry: ShelfFile) -> some View {
        let resolved = shelfState(entry)
        let url = resolved.url
        let exists = resolved.exists
        return WidgetPopoutRow {
            HStack(spacing: DockDesign.Grouped.glyphSpacing) {
                GroupedRowGlyph(symbol: exists ? "doc.fill" : "exclamationmark.triangle.fill", color: exists ? .gray : .orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent).font(DockDesign.Grouped.titleFont).lineLimit(1)
                    Text(exists ? url.deletingLastPathComponent().abbreviatingWithTildeInPath : "Original unavailable · moved or deleted")
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !exists {
                    Button("Locate…") { locate(entry) }.buttonStyle(.borderless).controlSize(.small)
                        .accessibilityLabel("Locate \(url.lastPathComponent)")
                }
                WidgetRowIconButton(symbol: "doc.on.doc", label: "Copy \(url.lastPathComponent)") { copy([url]) }.disabled(!exists)
                WidgetRowIconButton(symbol: "minus.circle", label: "Remove \(url.lastPathComponent) from shelf") { remove(entry.id) }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Open") {
                guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                if !NSWorkspace.shared.open(url) { message = "This file could not be opened." }
            }.disabled(!exists)
            Button("Reveal in Finder") {
                guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }.disabled(!exists)
            Button("Copy File") { copy([url]) }.disabled(!exists)
            if !exists { Button("Locate…") { locate(entry) }; Button("Retry") { retryUnavailable() } }
            Button("Remove from Shelf") { remove(entry.id) }
        }
        .onDrag { AppRuntimeEnvironment.allowsNativeEffects && exists ? NSItemProvider(contentsOf: url) ?? NSItemProvider() : NSItemProvider() }
    }
    private func chooseFiles() {
        guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
        let panel = NSOpenPanel()
        panel.title = "Add to File Shelf"; panel.prompt = "Keep in Shelf"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.shelfFiles = FileShelfPolicy.adding(panel.urls, to: $0.shelfFiles) }
        message = nil
    }
    private func locate(_ entry: ShelfFile) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
        let panel = NSOpenPanel()
        panel.title = "Locate \(shelfState(entry).url.lastPathComponent)"; panel.prompt = "Use This File"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        switch FileShelfPolicy.relocating(entry.id, to: chosen, in: entries) {
        case .relocated:
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
                if case let .relocated(updated) = FileShelfPolicy.relocating(entry.id, to: chosen, in: $0.shelfFiles) { $0.shelfFiles = updated }
            }
            message = "Shelf item now points to \(chosen.lastPathComponent)."
            availabilityRequest += 1
        case let .duplicate(name): message = "\(name) is already on this shelf, so the missing item was left unchanged. Remove it or choose a different file."
        case .notFound: message = "That file could not be found. The shelf item was left unchanged."
        case .notFileURL: message = "Choose a file on this Mac. The shelf item was left unchanged."
        }
    }
    private func retryUnavailable() {
        if FileShelfPolicy.refreshingStaleBookmarks(entries) != nil {
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { if let updated = FileShelfPolicy.refreshingStaleBookmarks($0.shelfFiles) { $0.shelfFiles = updated } }
        }
        let missing = entries.filter { !FileShelfPolicy.isAvailable($0) }.count
        availabilityRequest += 1
        message = missing == 0 ? "All shelf items are available." : "\(missing) shelf item\(missing == 1 ? "" : "s") still unavailable. Reconnect the drive or use Locate…"
    }
    private func remove(_ id: UUID) {
        let pending = RemovedEntries.capture([id], from: entries, message: "Removed from the shelf. The original file was not deleted.")
        if case .accepted = store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: { $0.shelfFiles.removeAll { $0.id == id } }) { undoPending = pending }
        message = nil
    }
    private func copy(_ urls: [URL]) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        message = copied ? "\(urls.count == 1 ? "File" : "Files") copied. Paste into Finder with ⌘V." : "These files could not be copied."
    }
}

struct SavedCollectionWidgetProvider: DockWidgetProvider {
    var kind: String
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(SavedCollectionDockFace(item: item)) }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        if kind == "Text Snippets" { return AnyView(TextSnippetsView(store: store, item: item, profileID: profileID)) }
        return AnyView(QuickLinksView(store: store, item: item, profileID: profileID))
    }
}

struct TextSnippetsView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var drafts: DockUtilityDraftStore
    var item: DockItem
    var profileID: UUID
    @State private var savedSearch = ""
    @State private var title = ""
    @State private var text = ""
    @State private var message: String?
    @State private var editingID: UUID?
    @State private var draftLoaded = false
    @State private var undoPending: RemovedEntries<TextSnippet>?
    /// The saved snippets lead; the editor sits behind a disclosure that opens with no snippets, for editing and for a draft.
    @State private var editorExpanded = false
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @Environment(\.widgetPopoutContext) private var popoutContext
    private var inSheet: Bool { WidgetPopoutContext.resolve(explicit: popoutContext, showsHero: showsHero) == .sheet }
    init(store: ProfileStore, item: DockItem, profileID: UUID) {
        self.store = store; self.item = item; self.profileID = profileID
        self.drafts = store.utilityDrafts
    }
    private var retainedDraft: DockUtilityFormDraft? { drafts.draft(itemID: item.id, in: profileID, kind: .snippet) }
    private var waitingToResume: Bool { !draftLoaded && retainedDraft != nil }
    private var hasInput: Bool { editingID != nil || !title.isEmpty || !text.isEmpty }
    private var entries: [TextSnippet] { item.widgetConfiguration?.textSnippets ?? [] }
    private var visibleEntries: [TextSnippet] {
        SavedSnippetSearch.results(entries, query: savedSearch)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            utilityDraftNotice(kind: "snippet", retained: retainedDraft != nil, waitingToResume: waitingToResume,
                               error: drafts.errorMessage, resume: resumeDraft, discard: discardDraft, retry: { _ = drafts.flush() })
            if entries.isEmpty {
                GroupedSection {
                    GroupedRow("No snippets yet", subtitle: "Save an email reply, address, command or any text you reuse.", symbol: "doc.on.clipboard", color: .gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search saved snippets", text: $savedSearch).accessibilityLabel("Search saved snippet names and text")
                    WidgetPopoutSectionHeader("Saved · \(entries.count) of 50")
                    if visibleEntries.isEmpty {
                        WidgetPopoutCaption("No saved snippets match. Your draft is separate from this search.")
                    } else if visibleEntries.count > 4 {
                        DockScrollView { snippetList }.frame(height: 260)
                    } else {
                        snippetList
                    }
                }
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.textSnippets, capacity: 50) }
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            WidgetPopoutSettingsDisclosure(editingID == nil ? "New Snippet" : "Edit Snippet", isExpanded: $editorExpanded) {
                editor
            }
            if let message { WidgetPopoutCaption(message) }
            WidgetPopoutCaption(entries.count >= 50 ? "Snippet collection full. Remove one to add another." : "Saved locally. Clipboard text is read only when you click Use Clipboard.")
        }
        .onAppear {
            draftLoaded = retainedDraft == nil
            if entries.isEmpty || retainedDraft != nil { editorExpanded = true }
        }
        .onChange(of: title) { _ in retainDraft() }
        .onChange(of: text) { _ in retainDraft() }
        .onChange(of: editingID) { _ in retainDraft() }
        .onDisappear { retainDraft(); _ = drafts.flush() }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            // In the Dock popout the disclosure names the form; in the settings sheet the section does.
            GroupedSection(inSheet ? (editingID == nil ? "New Snippet" : "Edit Snippet") : nil,
                           separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                WidgetPopoutRow {
                    TextField("Snippet name (optional)", text: $title).textFieldStyle(.plain).font(DockDesign.Grouped.titleFont)
                        .accessibilityLabel("Snippet name").disabled(waitingToResume)
                }
                WidgetPopoutRow(verticalPadding: 4) {
                    TextEditor(text: $text)
                        .font(DockDesign.Grouped.titleFont)
                        .scrollContentBackground(.hidden)
                        .frame(height: 84)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Snippet text").font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary)
                                    .padding(.leading, 5).allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .accessibilityLabel("Snippet text")
                        .disabled(waitingToResume)
                }
            }
            HStack(spacing: 10) {
                Button("Use Clipboard") {
                    guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                    if let value = NSPasteboard.general.string(forType: .string), !value.isEmpty { text = value; message = nil }
                    else { message = "The clipboard has no text to save." }
                }
                .buttonStyle(GalleryGlassButtonStyle()).disabled(waitingToResume)
                Spacer()
                PillButton(editingID == nil ? "Save Snippet" : "Save Changes", action: save)
                    .disabled(waitingToResume || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (editingID == nil && entries.count >= 50))
            }
        }
    }
    private var snippetList: some View {
        GroupedSection(separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            ForEach(visibleEntries) { entry in
                WidgetPopoutRow {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            // An unnamed snippet shows its text only here, in the popout, never on the Dock face.
                            if !entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(entry.title).font(DockDesign.Grouped.titleFont.weight(.semibold)).lineLimit(1)
                            }
                            Text(entry.text).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Copy") { message = copyUtilityText(entry.text) ? "Copied \(entry.displayTitle). Paste with ⌘V." : utilityCopyFailureMessage }
                            .buttonStyle(.borderless).controlSize(.small)
                            .accessibilityLabel("Copy \(entry.displayTitle)")
                        WidgetRowIconButton(symbol: "pencil", label: "Edit \(entry.displayTitle)") {
                            editingID = entry.id; title = entry.title; text = entry.text; editorExpanded = true
                        }
                            .disabled(hasInput || waitingToResume)
                        WidgetRowIconButton(symbol: "minus.circle", label: "Remove \(entry.displayTitle)") { removeSnippet(entry) }
                            .disabled(editingID == entry.id)
                    }
                }
            }
        }
    }
    private func save() {
        guard !waitingToResume else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // A blank name stays blank: the snippet's text is never turned into a visible name.
        let entry = TextSnippet(id: editingID ?? UUID(), title: name, text: text)
        do {
            try drafts.update(DockUtilityFormDraft(editingID: editingID, title: title, body: text), itemID: item.id, in: profileID, kind: .snippet)
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { config in
                if let index = config.textSnippets.firstIndex(where: { $0.id == entry.id }) { config.textSnippets[index] = entry }
                else if editingID == nil && config.textSnippets.count < 50 { config.textSnippets.append(entry) }
            }
            let saved = store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id }?.widgetConfiguration?.textSnippets.contains(entry) == true
            guard saved else { message = "This snippet is no longer available or the collection is full. Your draft was kept."; return }
            guard drafts.discard(itemID: item.id, in: profileID, kind: .snippet) else { message = "Snippet saved. The unfinished draft could not be removed; retry discarding it."; return }
            reset()
        } catch {
            message = "Could not save this snippet. Your text is still here. \(error.localizedDescription)"
        }
    }
    private func removeSnippet(_ entry: TextSnippet) {
        let pending = RemovedEntries.capture([entry.id], from: entries, message: "Removed \(entry.displayTitle).")
        if case .accepted = store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: { $0.textSnippets.removeAll { $0.id == entry.id } }) { undoPending = pending }
    }
    private func retainDraft() {
        guard draftLoaded else { return }
        do { try drafts.update(DockUtilityFormDraft(editingID: editingID, title: title, body: text), itemID: item.id, in: profileID, kind: .snippet); message = nil }
        catch { message = error.localizedDescription }
    }
    private func resumeDraft() {
        guard let draft = retainedDraft else { return }
        title = draft.title; text = draft.body; editingID = draft.editingID; draftLoaded = true; message = nil
        editorExpanded = true
    }
    private func discardDraft() {
        guard drafts.discard(itemID: item.id, in: profileID, kind: .snippet) else { return }
        draftLoaded = true; reset()
    }
    private func reset() { title = ""; text = ""; editingID = nil; message = nil }
}

struct QuickLinksView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var drafts: DockUtilityDraftStore
    var item: DockItem
    var profileID: UUID
    @State private var title = ""
    @State private var address = ""
    @State private var query = ""
    @State private var message: String?
    @State private var editingID: UUID?
    @State private var draftLoaded = false
    @State private var undoPending: RemovedEntries<QuickLink>?
    init(store: ProfileStore, item: DockItem, profileID: UUID) {
        self.store = store; self.item = item; self.profileID = profileID
        self.drafts = store.utilityDrafts
    }
    private var retainedDraft: DockUtilityFormDraft? { drafts.draft(itemID: item.id, in: profileID, kind: .link) }
    private var waitingToResume: Bool { !draftLoaded && retainedDraft != nil }
    private var hasInput: Bool { editingID != nil || !title.isEmpty || !address.isEmpty }
    private var entries: [QuickLink] { item.widgetConfiguration?.quickLinks ?? [] }
    private var filtered: [QuickLink] { entries.filter { query.isEmpty || ($0.title + " " + $0.url.absoluteString).localizedStandardContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            utilityDraftNotice(kind: "link", retained: retainedDraft != nil, waitingToResume: waitingToResume,
                               error: drafts.errorMessage, resume: resumeDraft, discard: discardDraft, retry: { _ = drafts.flush() })
            if entries.isEmpty {
                GroupedSection {
                    GroupedRow("Your own little launchpad", subtitle: "Keep project pages, reading and everyday websites together.", symbol: "link", color: .gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Search saved links", text: $query).accessibilityLabel("Search saved links")
                    WidgetPopoutSectionHeader("Links · \(entries.count) of 50")
                    if filtered.isEmpty {
                        WidgetPopoutCaption("No matching links.")
                    } else if filtered.count > 6 {
                        DockScrollView { linkList }.frame(height: 280)
                    } else {
                        linkList
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                GroupedSection(editingID == nil ? "Add Link" : "Edit Link", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    WidgetPopoutRow {
                        TextField("Website name (optional)", text: $title).textFieldStyle(.plain).font(DockDesign.Grouped.titleFont)
                            .accessibilityLabel("Website name").disabled(waitingToResume)
                    }
                    WidgetPopoutRow {
                        TextField("https://example.com", text: $address).textFieldStyle(.plain).font(DockDesign.Grouped.titleFont)
                            .onSubmit(save).accessibilityLabel("Website URL").disabled(waitingToResume)
                    }
                }
                HStack(spacing: 10) {
                    Button("Use Clipboard") {
                        guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                        if let value = NSPasteboard.general.string(forType: .string), DockLinkPolicy.validatedURL(value) != nil { address = value; message = nil }
                        else { message = "Copy a complete HTTP or HTTPS link first." }
                    }
                    .buttonStyle(GalleryGlassButtonStyle()).disabled(waitingToResume)
                    Spacer()
                    PillButton(editingID == nil ? "Save Link" : "Save Changes", action: save)
                        .disabled(waitingToResume || address.isEmpty || (editingID == nil && entries.count >= 50))
                }
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.quickLinks, capacity: 50) }
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            if let message { WidgetPopoutCaption(message) }
            WidgetPopoutCaption(entries.count >= 50 ? "Link collection full. Remove one to add another." : "Saved locally with this Dock. Click a link to open it in your default browser.")
        }
        .onAppear { draftLoaded = retainedDraft == nil }
        .onChange(of: title) { _ in retainDraft() }
        .onChange(of: address) { _ in retainDraft() }
        .onChange(of: editingID) { _ in retainDraft() }
        .onDisappear { retainDraft(); _ = drafts.flush() }
    }
    private var linkList: some View {
        GroupedSection(separatorInset: DockDesign.Grouped.separatorInset) {
            ForEach(filtered) { entry in
                WidgetPopoutRow {
                    HStack(spacing: 8) {
                        Button {
                            guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                            if !NSWorkspace.shared.open(entry.url) { message = "This link could not be opened." }
                        } label: {
                            HStack(spacing: DockDesign.Grouped.glyphSpacing) {
                                GroupedRowGlyph(symbol: "globe", color: .gray)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title).font(DockDesign.Grouped.titleFont).lineLimit(1)
                                    Text(entry.url.host ?? entry.url.absoluteString).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Open \(entry.title)")
                        WidgetRowIconButton(symbol: "doc.on.doc", label: "Copy \(entry.title) URL") {
                            message = copyUtilityText(entry.url.absoluteString) ? "Link copied." : utilityCopyFailureMessage
                        }
                        WidgetRowIconButton(symbol: "pencil", label: "Edit \(entry.title)") { editingID = entry.id; title = entry.title; address = entry.url.absoluteString }
                            .disabled(hasInput || waitingToResume)
                        WidgetRowIconButton(symbol: "minus.circle", label: "Remove \(entry.title)") { removeLink(entry) }
                            .disabled(editingID == entry.id)
                    }
                }
            }
        }
    }
    private func save() {
        guard !waitingToResume else { return }
        guard editingID != nil || entries.count < 50 else { return }
        guard address.utf8.count <= 8_192, let url = DockLinkPolicy.validatedURL(address) else { message = "Enter a complete HTTP or HTTPS link."; return }
        guard !entries.contains(where: { $0.url == url && $0.id != editingID }) else { message = "This link is already saved."; return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = QuickLink(id: editingID ?? UUID(), title: String((name.isEmpty ? url.host ?? "Website" : name).prefix(100)), url: url)
        do {
            try drafts.update(DockUtilityFormDraft(editingID: editingID, title: title, body: address), itemID: item.id, in: profileID, kind: .link)
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { config in
                if let index = config.quickLinks.firstIndex(where: { $0.id == entry.id }) { config.quickLinks[index] = entry }
                else if editingID == nil && config.quickLinks.count < 50 { config.quickLinks.append(entry) }
            }
            let saved = store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id }?.widgetConfiguration?.quickLinks.contains(entry) == true
            guard saved else { message = "This link is no longer available or the collection is full. Your draft was kept."; return }
            guard drafts.discard(itemID: item.id, in: profileID, kind: .link) else { message = "Link saved. The unfinished draft could not be removed; retry discarding it."; return }
            reset()
        } catch {
            message = "Could not save this link. Your input is still here. \(error.localizedDescription)"
        }
    }
    private func removeLink(_ entry: QuickLink) {
        let pending = RemovedEntries.capture([entry.id], from: entries, message: "Removed \(entry.title).")
        if case .accepted = store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: { $0.quickLinks.removeAll { $0.id == entry.id } }) { undoPending = pending }
    }
    private func retainDraft() {
        guard draftLoaded else { return }
        do { try drafts.update(DockUtilityFormDraft(editingID: editingID, title: title, body: address), itemID: item.id, in: profileID, kind: .link); message = nil }
        catch { message = error.localizedDescription }
    }
    private func resumeDraft() {
        guard let draft = retainedDraft else { return }
        title = draft.title; address = draft.body; editingID = draft.editingID; draftLoaded = true; message = nil
    }
    private func discardDraft() {
        guard drafts.discard(itemID: item.id, in: profileID, kind: .link) else { return }
        draftLoaded = true; reset()
    }
    private func reset() { title = ""; address = ""; editingID = nil; message = nil }
}

@MainActor @ViewBuilder
private func utilityDraftNotice(kind: String, retained: Bool, waitingToResume: Bool, error: String?,
                                resume: @escaping () -> Void, discard: @escaping () -> Void,
                                retry: @escaping () -> Void) -> some View {
    if retained || error != nil {
        GroupedSection {
            if retained {
                GroupedRow(waitingToResume ? "An unfinished \(kind) is available." : "Your unfinished \(kind) is kept separately from saved items.",
                           symbol: "square.and.pencil", color: .gray) {
                    HStack(spacing: 10) {
                        if waitingToResume { Button("Resume Draft", action: resume).buttonStyle(.borderless) }
                        Button("Discard Draft", role: .destructive, action: discard).buttonStyle(.borderless)
                    }
                    .controlSize(.small)
                }
            }
            if let error {
                GroupedRow(error, symbol: "exclamationmark.triangle.fill", color: .orange) {
                    Button("Retry Draft Save", action: retry).buttonStyle(.borderless).controlSize(.small)
                }
            }
        }
    }
}

private let utilityIsolatedActionMessage = "Native file, clipboard, sharing, and screen-sampling actions are disabled in this isolated session."
var utilityCopyFailureMessage: String { AppRuntimeEnvironment.allowsNativeEffects ? "This text could not be copied." : utilityIsolatedActionMessage }

@discardableResult
func copyUtilityText(_ value: String) -> Bool {
    guard AppRuntimeEnvironment.allowsNativeEffects else { return false }
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(value, forType: .string)
}

private extension URL {
    var abbreviatingWithTildeInPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

struct UnitConverterWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(LocalWidgetDockFace(item: item)) }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(UnitConverterView()) }
}

/// The converter hero's one secondary line: where the value comes from, never the result again.
enum UnitConverterPresentation {
    static func caption(input: String, from symbol: String, hasResult: Bool) -> String {
        hasResult ? "from \(input.trimmingCharacters(in: .whitespacesAndNewlines)) \(symbol)" : "Enter a finite number to convert."
    }
}

struct UnitConverterView: View {
    @State private var category: ConversionCategory = .length
    @State private var input = "1"
    @State private var fromID = "m"
    @State private var toID = "ft"
    @State private var copied = false
    private var from: ConversionUnit { category.units.first { $0.id == fromID } ?? category.units[0] }
    private var to: ConversionUnit { category.units.first { $0.id == toID } ?? category.units[1] }
    private var result: Double? {
        // Accept the user's decimal separator, with no grouping ambiguity.
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: separator, with: ".")
        guard let number = Double(normalized) else { return nil }
        return ConversionUnit.convert(number, from: from, to: to)
    }
    private var resultText: String { result.map { ConversionResultFormatter.text($0) } ?? "—" }
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            WidgetPopoutHero(value: result == nil ? "—" : "\(resultText) \(to.symbol)",
                             caption: UnitConverterPresentation.caption(input: input, from: from.symbol, hasResult: result != nil),
                             valueColor: result == nil ? .secondary : .primary)
            VStack(alignment: .leading, spacing: 6) {
                WidgetPopoutSectionHeader("Convert") {
                    Button {
                        let previous = fromID; fromID = toID; toID = previous; copied = false
                    } label: { Label("Swap", systemImage: "arrow.up.arrow.down") }
                        .accessibilityLabel("Swap conversion units")
                }
                GroupedSection(footer: category == .data ? "kB, MB and GB are decimal; KiB, MiB and GiB are binary." : category == .volume ? "Gallon and cup use US measures." : nil,
                               separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    GroupedRow("Category") {
                        Picker("Convert", selection: $category) { ForEach(ConversionCategory.allCases) { Text($0.title).tag($0) } }
                            .labelsHidden().fixedSize().accessibilityLabel("Convert")
                    }
                    GroupedRow("Value") {
                        TextField("Value", text: Binding(get: { input }, set: { input = String($0.prefix(100)); copied = false }))
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).monospacedDigit().frame(maxWidth: 180)
                            .accessibilityLabel("Value to convert")
                    }
                    GroupedRow("From") {
                        Picker("From", selection: $fromID) { ForEach(category.units) { Text($0.title).tag($0.id) } }
                            .labelsHidden().fixedSize().accessibilityLabel("From")
                    }
                    GroupedRow("To") {
                        Picker("To", selection: $toID) { ForEach(category.units) { Text($0.title).tag($0.id) } }
                            .labelsHidden().fixedSize().accessibilityLabel("To")
                    }
                }
                .help("Results update as you type and are rounded to 6 significant digits.")
            }
            HStack {
                if !AppRuntimeEnvironment.allowsNativeEffects {
                    Text(utilityIsolatedActionMessage).font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(copied ? "Copied" : "Copy Result") { copied = copyUtilityText(resultText) }
                    .buttonStyle(GalleryGlassButtonStyle()).disabled(result == nil)
            }
            .padding(.leading, DockDesign.Grouped.rowHorizontalPadding)
        }
        .onChange(of: category) { value in fromID = value.units[0].id; toID = value.units[1].id; copied = false }
        .onChange(of: fromID) { _ in copied = false }.onChange(of: toID) { _ in copied = false }
    }
}

struct ColorPickerWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(LocalWidgetDockFace(item: item)) }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(DockColorPickerView(store: store, item: item, profileID: profileID)) }
}

struct DockColorPickerView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var color = Color(red: 0.37, green: 0.64, blue: 0.66)
    @State private var hexDraft = "#5EA3A8"
    @State private var message: String?
    @State private var sampling = false
    @State private var sampler = NSColorSampler()
    @DockAccessibilityStyle() private var accessibility
    private var palette: [String] { item.widgetConfiguration?.savedColors ?? [] }
    private var rgb: NSColor { NSColor(color).usingColorSpace(.sRGB) ?? .black }
    private var hex: String { HexColor.string(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent) }
    private var rgbText: String { "rgb(\(Int((rgb.redComponent * 255).rounded())), \(Int((rgb.greenComponent * 255).rounded())), \(Int((rgb.blueComponent * 255).rounded())))" }
    private var edge: Color { Color.primary.opacity(accessibility.contrast == .increased ? 0.55 : 0.14) }
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color).frame(width: 76, height: 76)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(edge, lineWidth: 1))
                    .accessibilityLabel("Selected color \(hex)")
                VStack(alignment: .leading, spacing: 3) {
                    Text(hex).font(.system(size: 28, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                    Text(rgbText).font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            GroupedSection(separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Color") {
                    ColorPicker("Color", selection: $color, supportsOpacity: false).labelsHidden()
                }
                GroupedRow(sampling ? "Picking…" : "Pick from Screen", role: .button) {
                    guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                    sampling = true
                    sampler.show { picked in
                        let components = picked?.usingColorSpace(.sRGB).map { ($0.redComponent, $0.greenComponent, $0.blueComponent) }
                        Task { @MainActor in
                            sampling = false
                            if let components {
                                color = Color(red: components.0, green: components.1, blue: components.2)
                                message = nil
                            }
                        }
                    }
                }
                .disabled(sampling)
                GroupedRow("HEX") {
                    HStack(spacing: 8) {
                        TextField("#RRGGBB", text: Binding(get: { hexDraft }, set: { hexDraft = String($0.prefix(7)); message = nil }))
                            .textFieldStyle(.plain).multilineTextAlignment(.trailing).font(.system(size: 13, design: .monospaced))
                            .frame(width: 90).onSubmit(applyHex).accessibilityLabel("HEX color")
                        Button("Apply", action: applyHex).buttonStyle(.borderless).accessibilityLabel("Apply to Preview")
                    }
                }
                GroupedRow("Copy") {
                    HStack(spacing: 12) {
                        Button("HEX") { message = copyUtilityText(hex) ? "HEX copied." : utilityCopyFailureMessage }
                            .accessibilityLabel("Copy HEX")
                        Button("RGB") { message = copyUtilityText(rgbText) ? "RGB copied." : utilityCopyFailureMessage }
                            .accessibilityLabel("Copy RGB")
                    }
                    .buttonStyle(.borderless)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                WidgetPopoutSectionHeader("Saved Palette · \(palette.count) of 24") {
                    Button("Save Color") {
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { if !$0.savedColors.contains(hex) && $0.savedColors.count < 24 { $0.savedColors.append(hex) } }
                    }.disabled(palette.contains(hex) || palette.count >= 24)
                }
                if palette.isEmpty {
                    WidgetPopoutCaption("Save colors you use often.")
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 8), spacing: 10) {
                        ForEach(palette, id: \.self) { value in
                            let selected = value.caseInsensitiveCompare(hex) == .orderedSame
                            Button { select(value) } label: {
                                Circle().fill(paletteColor(value)).frame(width: 34, height: 34)
                                    .overlay(Circle().strokeBorder(edge, lineWidth: 1))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selected ? DockDesign.accent : .clear, lineWidth: 2))
                                    .contentShape(Circle())
                            }.buttonStyle(.plain).help(value).accessibilityLabel("Select color \(value)")
                                .accessibilityAddTraits(selected ? .isSelected : [])
                                .contextMenu {
                                    Button("Copy HEX") { message = copyUtilityText(value) ? "HEX copied." : utilityCopyFailureMessage }
                                    Button("Remove Color") { store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.savedColors.removeAll { $0 == value } } }
                                }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
            if let message { WidgetPopoutCaption(message) }
            WidgetPopoutCaption("Right-click a saved color to copy or remove it.")
                .help("Apply updates the preview. Save Color adds it to this widget’s palette.")
        }
        .onChange(of: color) { _ in hexDraft = hex; message = nil }
        .onAppear { if let first = palette.first { select(first) }; hexDraft = hex }
    }
    private func applyHex() {
        guard HexColor.components(hexDraft) != nil else { message = "Enter a 3- or 6-digit HEX color, such as #5EA3A8."; return }
        select(hexDraft); hexDraft = hex; message = nil
    }
    private func select(_ value: String) { color = paletteColor(value) }
    private func paletteColor(_ value: String) -> Color {
        guard let c = HexColor.components(value) else { return .clear }
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
