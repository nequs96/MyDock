import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    private var latest: String {
        switch kind {
        case "File Shelf": configuration.shelfFiles.last?.url.lastPathComponent ?? "Drop files here"
        case "Text Snippets": configuration.textSnippets.last?.title ?? "Save a snippet"
        default: configuration.quickLinks.last?.title ?? "Add a website"
        }
    }
    var body: some View {
        VStack(alignment: width <= 54 ? .center : .leading, spacing: 3) {
            HStack(spacing: 5) {
                WidgetIcon(kind: kind, size: 16)
                MetricText(value: "\(count)", unit: width <= 54 ? "" : kind == "File Shelf" ? "files" : kind == "Text Snippets" ? "snippets" : "links", size: 21)
            }
            if layout == .wide { Text(latest).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(.horizontal, 9).frame(width: width, height: 54)
            .accessibilityElement(children: .ignore).accessibilityLabel("\(kind), \(count) saved items")
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
    @ViewBuilder var content: Content
    @State private var targeted = false
    var body: some View {
        content.contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 2).allowsHitTesting(false))
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

struct FileShelfView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var message: String?
    @State private var undoPending: RemovedEntries<ShelfFile>?
    private var entries: [ShelfFile] { item.widgetConfiguration?.shelfFiles ?? [] }
    private var availableURLs: [URL] { entries.map(\.resolvedURL).filter { FileManager.default.fileExists(atPath: $0.path) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FileShelfDropSurface(store: store, item: item, profileID: profileID) {
                VStack(spacing: 7) {
                    WidgetEmblem(kind: "File Shelf", size: 34)
                    Text("Drop files to keep them close").font(.system(size: 14, weight: .medium))
                    Text("Or drop onto the File Shelf in your Dock.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button("Add Files…", action: chooseFiles).disabled(entries.count >= FileShelfPolicy.capacity)
                Spacer()
                Text("\(entries.count) / \(FileShelfPolicy.capacity)").font(.caption).foregroundStyle(.secondary)
                if entries.count > availableURLs.count { Button("Retry") { retryUnavailable() }.help("Check again, for example after reconnecting a drive") }
                Button("Copy All") { copy(availableURLs) }.disabled(availableURLs.isEmpty)
            }
            if !entries.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { entry in fileRow(entry) }
                    }
                }.frame(maxHeight: 240)
                HStack {
                    AirDropShareButton(urls: availableURLs, title: "Share / AirDrop…").frame(height: 30)
                        .disabled(!AppRuntimeEnvironment.allowsNativeEffects)
                    Button("Clear Shelf") {
                        let pending = RemovedEntries.capture(Set(entries.map(\.id)), from: entries, message: "Shelf cleared. Original files are unchanged.")
                        if case .accepted = store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: { $0.shelfFiles = [] }) { undoPending = pending; message = nil }
                    }
                }
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.shelfFiles, capacity: FileShelfPolicy.capacity) }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary).accessibilityLabel(message) }
            if !AppRuntimeEnvironment.allowsNativeEffects { Text(utilityIsolatedActionMessage).font(.caption).foregroundStyle(.secondary) }
            Text("Saved as references, not copies. Copy files here, then use ⌘V in Finder to paste them elsewhere. Removing a shelf item leaves the original file in place.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func fileRow(_ entry: ShelfFile) -> some View {
        let url = entry.resolvedURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        return HStack(spacing: 10) {
            Image(systemName: exists ? "doc" : "exclamationmark.triangle").foregroundStyle(exists ? Color.accentColor : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(exists ? url.deletingLastPathComponent().abbreviatingWithTildeInPath : "Original unavailable · moved or deleted")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !exists { Button("Locate…") { locate(entry) }.accessibilityLabel("Locate \(url.lastPathComponent)") }
            Button { copy([url]) } label: { Image(systemName: "doc.on.doc") }.disabled(!exists).accessibilityLabel("Copy \(url.lastPathComponent)")
            Button { remove(entry.id) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove \(url.lastPathComponent) from shelf")
        }.padding(.vertical, 9)
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
        panel.title = "Locate \(entry.resolvedURL.lastPathComponent)"; panel.prompt = "Use This File"
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        switch FileShelfPolicy.relocating(entry.id, to: chosen, in: entries) {
        case .relocated:
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
                if case let .relocated(updated) = FileShelfPolicy.relocating(entry.id, to: chosen, in: $0.shelfFiles) { $0.shelfFiles = updated }
            }
            message = "Shelf item now points to \(chosen.lastPathComponent)."
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
        VStack(alignment: .leading, spacing: 14) {
            Text("Reusable words, one click away.").font(.system(size: 17, weight: .semibold))
            utilityDraftNotice(kind: "snippet", retained: retainedDraft != nil, waitingToResume: waitingToResume,
                               error: drafts.errorMessage, resume: resumeDraft, discard: discardDraft, retry: { _ = drafts.flush() })
            TextField("Snippet name (optional)", text: $title).accessibilityLabel("Snippet name").disabled(waitingToResume)
            TextEditor(text: $text)
                .frame(height: 90).padding(6).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 8)).accessibilityLabel("Snippet text")
                .disabled(waitingToResume)
            HStack {
                Button("Use Clipboard") {
                    guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                    if let value = NSPasteboard.general.string(forType: .string), !value.isEmpty { text = value; message = nil }
                    else { message = "The clipboard has no text to save." }
                }.disabled(waitingToResume)
                Spacer()
                Button(editingID == nil ? "Save Snippet" : "Save Changes", action: save)
                    .disabled(waitingToResume || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (editingID == nil && entries.count >= 50))
            }
            if !entries.isEmpty {
                TextField("Search saved snippets", text: $savedSearch).accessibilityLabel("Search saved snippet names and text")
            }
            if entries.isEmpty { collectionEmpty("No snippets yet", detail: "Save an email reply, address, command or any text you reuse.") }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(visibleEntries) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(entry.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Button("Copy") { message = copyUtilityText(entry.text) ? "Copied \(entry.title). Paste with ⌘V." : utilityCopyFailureMessage }
                                    Button { editingID = entry.id; title = entry.title; text = entry.text } label: { Image(systemName: "pencil") }.accessibilityLabel("Edit \(entry.title)").disabled(hasInput || waitingToResume)
                                    Button { removeSnippet(entry) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove \(entry.title)").disabled(editingID == entry.id)
                                }
                                Text(entry.text).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
                            }.padding(12).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }.frame(maxHeight: 230)
                if visibleEntries.isEmpty { Text("No saved snippets match. Your draft is separate from this search.").font(.caption).foregroundStyle(.secondary) }
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.textSnippets, capacity: 50) }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Text(entries.count >= 50 ? "Snippet collection full. Remove one to add another." : "Saved locally. Clipboard text is read only when you click Use Clipboard.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { draftLoaded = retainedDraft == nil }
        .onChange(of: title) { _ in retainDraft() }
        .onChange(of: text) { _ in retainDraft() }
        .onChange(of: editingID) { _ in retainDraft() }
        .onDisappear { retainDraft(); _ = drafts.flush() }
    }
    private func save() {
        guard !waitingToResume else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = TextSnippet(id: editingID ?? UUID(), title: name.isEmpty ? String(text.prefix(40)).replacingOccurrences(of: "\n", with: " ") : name, text: text)
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
        let pending = RemovedEntries.capture([entry.id], from: entries, message: "Removed \(entry.title).")
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
        VStack(alignment: .leading, spacing: 14) {
            utilityDraftNotice(kind: "link", retained: retainedDraft != nil, waitingToResume: waitingToResume,
                               error: drafts.errorMessage, resume: resumeDraft, discard: discardDraft, retry: { _ = drafts.flush() })
            TextField("Website name (optional)", text: $title).accessibilityLabel("Website name").disabled(waitingToResume)
            TextField("https://example.com", text: $address).onSubmit(save).accessibilityLabel("Website URL").disabled(waitingToResume)
            HStack {
                Button("Use Clipboard") {
                    guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                    if let value = NSPasteboard.general.string(forType: .string), DockLinkPolicy.validatedURL(value) != nil { address = value; message = nil }
                    else { message = "Copy a complete HTTP or HTTPS link first." }
                }.disabled(waitingToResume)
                Spacer()
                Button(editingID == nil ? "Save Link" : "Save Changes", action: save).disabled(waitingToResume || address.isEmpty || (editingID == nil && entries.count >= 50))
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.quickLinks, capacity: 50) }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if entries.isEmpty { collectionEmpty("Your own little launchpad", detail: "Keep project pages, reading and everyday websites together.") }
            else {
                TextField("Search saved links", text: $query).accessibilityLabel("Search saved links")
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filtered) { entry in
                            HStack(spacing: 10) {
                                Button {
                                    guard AppRuntimeEnvironment.allowsNativeEffects else { message = utilityIsolatedActionMessage; return }
                                    if !NSWorkspace.shared.open(entry.url) { message = "This link could not be opened." }
                                } label: {
                                    HStack(spacing: 9) {
                                        Image(systemName: "globe").foregroundStyle(.tint)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(entry.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                            Text(entry.url.host ?? entry.url.absoluteString).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel("Open \(entry.title)")
                                Button { message = copyUtilityText(entry.url.absoluteString) ? "Link copied." : utilityCopyFailureMessage } label: { Image(systemName: "doc.on.doc") }.accessibilityLabel("Copy \(entry.title) URL")
                                Button { editingID = entry.id; title = entry.title; address = entry.url.absoluteString } label: { Image(systemName: "pencil") }.accessibilityLabel("Edit \(entry.title)").disabled(hasInput || waitingToResume)
                                Button { removeLink(entry) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove \(entry.title)").disabled(editingID == entry.id)
                            }.padding(12).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 10))
                        }
                        if filtered.isEmpty { Text("No matching links.").font(.caption).foregroundStyle(.secondary) }
                    }
                }.frame(maxHeight: 260)
            }
            Text(entries.count >= 50 ? "Link collection full. Remove one to add another." : "Saved locally with this Dock. Click a link to open it in your default browser.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { draftLoaded = retainedDraft == nil }
        .onChange(of: title) { _ in retainDraft() }
        .onChange(of: address) { _ in retainDraft() }
        .onChange(of: editingID) { _ in retainDraft() }
        .onDisappear { retainDraft(); _ = drafts.flush() }
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

private func utilityDraftNotice(kind: String, retained: Bool, waitingToResume: Bool, error: String?,
                                resume: @escaping () -> Void, discard: @escaping () -> Void,
                                retry: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        if retained {
            Text(waitingToResume ? "An unfinished \(kind) is available." : "Your unfinished \(kind) is kept separately from saved items.").font(.caption)
            HStack {
                if waitingToResume { Button("Resume Draft", action: resume) }
                Button("Discard Draft", role: .destructive, action: discard)
            }
        }
        if let error {
            Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            Button("Retry Draft Save", action: retry)
        }
    }
}

private func collectionEmpty(_ title: String, detail: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.system(size: 14, weight: .medium))
        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 12))
}

private let utilityIsolatedActionMessage = "Native file, clipboard, sharing, and screen-sampling actions are disabled in this isolated session."
private var utilityCopyFailureMessage: String { AppRuntimeEnvironment.allowsNativeEffects ? "This text could not be copied." : utilityIsolatedActionMessage }

@discardableResult
private func copyUtilityText(_ value: String) -> Bool {
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
        VStack(alignment: .leading, spacing: 16) {
            Picker("Convert", selection: $category) { ForEach(ConversionCategory.allCases) { Text($0.title).tag($0) } }
            TextField("Value", text: Binding(get: { input }, set: { input = String($0.prefix(100)); copied = false })).accessibilityLabel("Value to convert")
            HStack(spacing: 10) {
                Picker("From", selection: $fromID) { ForEach(category.units) { Text($0.title).tag($0.id) } }.frame(maxWidth: .infinity)
                Button {
                    let previous = fromID; fromID = toID; toID = previous; copied = false
                } label: { Image(systemName: "arrow.left.arrow.right") }.accessibilityLabel("Swap conversion units")
                Picker("To", selection: $toID) { ForEach(category.units) { Text($0.title).tag($0.id) } }.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(resultText).font(.system(size: 32, weight: .semibold)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.6)
                    Text(to.symbol).foregroundStyle(.secondary)
                }
                Text(result == nil ? "Enter a finite number to convert." : "\(input) \(from.symbol) = \(resultText) \(to.symbol)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Text("Rounded to 6 significant digits. " + (category == .data ? "kB / MB / GB are decimal. KiB / MiB / GiB are binary." : category == .volume ? "Gallon and cup use US measures." : "Updates as you type."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(copied ? "Copied" : "Copy Result") { copied = copyUtilityText(resultText) }.disabled(result == nil)
            }
            if !AppRuntimeEnvironment.allowsNativeEffects { Text(utilityIsolatedActionMessage).font(.caption).foregroundStyle(.secondary) }
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
    private var palette: [String] { item.widgetConfiguration?.savedColors ?? [] }
    private var rgb: NSColor { NSColor(color).usingColorSpace(.sRGB) ?? .black }
    private var hex: String { HexColor.string(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent) }
    private var rgbText: String { "rgb(\(Int((rgb.redComponent * 255).rounded())), \(Int((rgb.greenComponent * 255).rounded())), \(Int((rgb.blueComponent * 255).rounded())))" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ColorPicker("Color", selection: $color, supportsOpacity: false)
                Spacer()
                Button(sampling ? "Picking…" : "Pick from Screen") {
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
                }.disabled(sampling)
            }
            RoundedRectangle(cornerRadius: 14).fill(color).frame(height: 88)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)).accessibilityLabel("Selected color \(hex)")
            HStack {
                TextField("#RRGGBB", text: Binding(get: { hexDraft }, set: { hexDraft = String($0.prefix(7)); message = nil })).onSubmit(applyHex).accessibilityLabel("HEX color")
                Button("Apply to Preview", action: applyHex)
                Button("Copy HEX") { message = copyUtilityText(hex) ? "HEX copied." : utilityCopyFailureMessage }
            }
            HStack {
                Text(rgbText).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                Spacer()
                Button("Copy RGB") { message = copyUtilityText(rgbText) ? "RGB copied." : utilityCopyFailureMessage }
            }
            Text("Apply updates the selected color preview. Save Color adds that color to this widget’s saved palette.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text("Saved palette").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(palette.count) / 24").font(.caption).foregroundStyle(.secondary)
                Button("Save Color") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { if !$0.savedColors.contains(hex) && $0.savedColors.count < 24 { $0.savedColors.append(hex) } }
                }.disabled(palette.contains(hex) || palette.count >= 24)
            }
            if palette.isEmpty { Text("Save colors you use often. Right-click a saved color to copy or remove it.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(palette, id: \.self) { value in
                        Button { select(value) } label: {
                            RoundedRectangle(cornerRadius: 8).fill(paletteColor(value)).frame(height: 38)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
                        }.buttonStyle(.plain).help(value).accessibilityLabel("Select color \(value)")
                            .accessibilityAddTraits(value.caseInsensitiveCompare(hex) == .orderedSame ? .isSelected : [])
                            .contextMenu {
                                Button("Copy HEX") { message = copyUtilityText(value) ? "HEX copied." : utilityCopyFailureMessage }
                                Button("Remove Color") { store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.savedColors.removeAll { $0 == value } } }
                            }
                    }
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
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
