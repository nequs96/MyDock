import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DockManagerView: View {
    @ObservedObject var store: ProfileStore
    var onContinueSetup: () -> Void = {}
    @State private var selectedProfileID: UUID?
    @State private var draftSession: DockProfileDraft?
    @State private var pendingProfileSelectionID: UUID?
    @State private var showingUnsavedProfileChanges = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var isSelectingItems = false
    @State private var showingWidgetPicker = false
    @State private var showingLinkEditor = false
    @State private var linkTitle = ""
    @State private var linkAddress = "https://"
    @State private var linkIconSelection = ""
    @State private var linkFaviconData: Data?
    @State private var faviconMessage: String?
    @State private var isFetchingFavicon = false
    @State private var faviconRequestID = UUID()
    @State private var faviconFetchTask: Task<Void, Never>?
    @State private var editingLinkItemID: UUID?
    @State private var searchText = ""
    @State private var dockOperationMessage: String?
    @State private var shortcutProfileID: UUID?
    @State private var showingShortcutEditor = false

    private var selectedProfile: DockProfile? {
        guard let committedProfile = store.state.profiles.first(where: { $0.id == selectedProfileID }) else { return nil }
        if let draftSession, draftSession.profile.id == selectedProfileID {
            return draftSession.profile
        }
        return committedProfile
    }

    private var hasUnsavedProfileChanges: Bool { draftSession?.isDirty == true }
    private var draftCanBeSaved: Bool {
        guard let draft = draftSession, draft.isDirty else { return true }
        return !draft.profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { selectedProfileID }, set: { requestProfileSelection($0) })) {
                Section("macOS Dock") {
                    ForEach(store.nativeProfiles) { profile in
                        Label(profile.name, systemImage: "dock.rectangle").tag(profile.id)
                    }
                }
                Section("Custom Dock") {
                    ForEach(store.customProfiles) { profile in
                        Label(profile.name, systemImage: "rectangle.bottomthird.inset.filled").tag(profile.id)
                    }
                }
            }
            .navigationTitle("Saved Docks")
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("New macOS Dock") { select(store.createProfile(kind: .native)) }
                        Button("New Custom Dock") { select(store.createProfile(kind: .custom)) }
                        Divider()
                        Button("Create from Current Dock…") { createFromCurrentDock() }
                        Button("Start Empty") { select(store.createProfile(kind: .native)) }
                    } label: { Image(systemName: "plus") }
                    .help("New profile")
                }
            }
        } detail: {
            if let profile = selectedProfile {
                editor(for: profile)
            } else {
                EmptyStateView(title: "Choose a Dock", symbol: "dock.rectangle", detail: "Create a macOS Dock profile or a Custom Dock to get started.")
            }
        }
        .frame(minWidth: 800, minHeight: 520)
        .onAppear {
            if selectedProfileID == nil {
                switchToProfile(store.state.settings.activeCustomProfileID ?? store.state.settings.activeNativeProfileID ?? store.state.profiles.first?.id)
            } else {
                loadDraftSession()
            }
        }
        .onChange(of: selectedProfileID) { _ in
            selectedItemIDs.removeAll()
            selectionAnchorID = nil
            isSelectingItems = false
        }
        .onReceive(store.$state) { state in
            guard draftSession?.isDirty != true,
                  let selectedProfileID,
                  let profile = state.profiles.first(where: { $0.id == selectedProfileID }) else { return }
            draftSession = DockProfileDraft(profile: profile)
        }
        .sheet(isPresented: $showingWidgetPicker) { widgetPicker }
        .sheet(isPresented: $showingLinkEditor) { linkEditor }
        .sheet(isPresented: $showingShortcutEditor) {
            if let shortcutProfileID,
               let profile = store.state.profiles.first(where: { $0.id == shortcutProfileID }) {
                KeyboardShortcutEditor(profileID: profile.id,
                                       profileName: profile.name,
                                       bindings: DockShortcutStore.shared,
                                       controller: GlobalShortcutController.shared) {
                    showingShortcutEditor = false
                }
            }
        }
        .alert("MyDock data", isPresented: Binding(get: { store.persistenceError != nil || store.persistenceWarning != nil }, set: { if !$0 { store.dismissPersistenceNotice() } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(store.persistenceError ?? store.persistenceWarning ?? "") }
        .alert("macOS Dock", isPresented: Binding(get: { dockOperationMessage != nil }, set: { if !$0 { dockOperationMessage = nil } })) {
            Button("OK", role: .cancel) { dockOperationMessage = nil }
        } message: { Text(dockOperationMessage ?? "") }
        .confirmationDialog("Unsaved Dock Changes", isPresented: $showingUnsavedProfileChanges, titleVisibility: .visible) {
            Button("Save Changes") { completePendingProfileSwitch(saveChanges: true) }
            Button("Discard Changes", role: .destructive) { completePendingProfileSwitch(saveChanges: false) }
            Button("Cancel", role: .cancel) { pendingProfileSelectionID = nil }
        } message: {
            Text("Save or discard your edits to \(draftSession?.profile.name ?? "this Dock") before switching profiles.")
        }
    }

    private func editor(for profile: DockProfile) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Dock name", text: Binding(get: { profile.name }, set: { name in
                    updateDraft { $0.name = name }
                }))
                    .font(.title2.weight(.semibold)).textFieldStyle(.plain).frame(maxWidth: 300)
                Text(profile.kind.title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.state.settings.onboardingComplete {
                    Button("Continue Setup…", action: onContinueSetup).buttonStyle(.borderedProminent)
                }
                Menu("Profile Actions") {
                    Button("Duplicate") {
                        guard saveDraft() else { return }
                        store.duplicateProfile(profile.id)
                    }
                    Button("Keyboard Shortcut…") {
                        shortcutProfileID = profile.id
                        showingShortcutEditor = true
                    }
                    Menu("Profile Color") {
                        ForEach(DockProfileColor.allCases) { color in
                            Button {
                                updateDraft { $0.color = color.rawValue }
                            } label: {
                                Label(color.title, systemImage: profile.color == color.rawValue ? "checkmark.circle.fill" : "circle.fill")
                            }
                        }
                    }
                    Button("Replace with Current Dock…") { replaceFromCurrentDock(profile) }
                    Divider()
                    Button("Delete Profile…", role: .destructive) {
                        guard saveDraft() else { return }
                        store.deleteProfile(profile.id)
                        switchToProfile(nil)
                    }
                }
                Button("Use This Profile") { useProfile(profile) }.buttonStyle(.borderedProminent)
                    .disabled(!draftCanBeSaved)
            }
            .padding(22)
            Divider()
            HStack(spacing: 8) {
                Text("Preview").font(.headline)
                Spacer()
                Button(isSelectingItems ? "Done Selecting" : "Select Items") {
                    isSelectingItems.toggle()
                    if !isSelectingItems {
                        selectedItemIDs.removeAll()
                        selectionAnchorID = nil
                    }
                }
                .buttonStyle(.bordered)
                addMenu(for: profile)
                if !selectedItemIDs.isEmpty {
                    Button("Clear Selection") {
                        selectedItemIDs.removeAll()
                        selectionAnchorID = nil
                    }.buttonStyle(.bordered)
                    Button { moveSelection(.left, in: profile) } label: { Image(systemName: "arrow.left") }
                        .help("Move selected items left").accessibilityLabel("Move selected items left")
                        .disabled(!canMoveSelection(.left, in: profile))
                    Button { moveSelection(.right, in: profile) } label: { Image(systemName: "arrow.right") }
                        .help("Move selected items right").accessibilityLabel("Move selected items right")
                        .disabled(!canMoveSelection(.right, in: profile))
                    Button("Delete \(selectedItemIDs.count) Selected", role: .destructive) {
                        removeSelectedItems(from: profile)
                    }.buttonStyle(.bordered)
                }
                if hasUnsavedProfileChanges {
                    Button("Discard Changes") { discardDraft() }.buttonStyle(.bordered)
                }
                Button("Save Changes") { _ = saveDraft() }
                    .buttonStyle(.bordered).disabled(!hasUnsavedProfileChanges || !draftCanBeSaved)
                if profile.kind == .native {
                    Button("Apply Changes") { applyNativeProfile(profile) }
                        .buttonStyle(.borderedProminent).disabled(!draftCanBeSaved)
                }
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(profile.items) { item in
                DockManagerItemView(item: item, isSelected: selectedItemIDs.contains(item.id),
                                            isSelectionMode: isSelectingItems,
                                            remove: { removeItem(item.id, from: profile.id) },
                                            editLink: { prepareLinkEditor(for: item) },
                                            updateFolderIcon: { color, letter, number in
                                                updateDraft { draft in
                                                    guard let index = draft.items.firstIndex(where: { $0.id == item.id }) else { return }
                                                    draft.items[index].folderIconColor = color
                                                    draft.items[index].folderIconLetter = letter
                                                    draft.items[index].folderIconNumber = number
                                                }
                                            },
                                            select: { commandPressed, shiftPressed in
                                                selectItem(item.id, commandPressed: commandPressed, shiftPressed: shiftPressed)
                                            })
                        .draggable(item.id.uuidString)
                        .dropDestination(for: String.self) { values, _ in
                            guard let raw = values.first, let draggedID = UUID(uuidString: raw) else { return false }
                            updateDraft { draft in
                                guard draggedID != item.id,
                                      let sourceIndex = draft.items.firstIndex(where: { $0.id == draggedID }),
                                      let targetIndex = draft.items.firstIndex(where: { $0.id == item.id }) else { return }
                                let movedItem = draft.items.remove(at: sourceIndex)
                                let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
                                draft.items.insert(movedItem, at: adjustedTarget)
                            }
                            return true
                        }
                    }
                    if profile.items.isEmpty {
                        EmptyStateView(title: "No items yet", symbol: "plus.app", detail: "Use Add to put apps, files, spacers, or widgets in this Dock.")
                            .frame(width: 320, height: 180)
                    }
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Spacer(minLength: 0)
            HStack {
                Label(managerInteractionHint,
                      systemImage: isSelectingItems ? "checkmark.circle" : "hand.draw")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(profile.items.count) items").font(.caption).foregroundStyle(.secondary)
            }.padding(16).background(.bar)
        }
    }

    private var managerInteractionHint: String {
        guard isSelectingItems else { return "Drag items to reorder" }
        return selectedItemIDs.isEmpty
            ? "Click items or Shift-click a range to select"
            : "Click selected items again to deselect; move the selection together"
    }

    private func requestProfileSelection(_ id: UUID?) {
        guard id != selectedProfileID else { return }
        if hasUnsavedProfileChanges {
            pendingProfileSelectionID = id
            showingUnsavedProfileChanges = true
        } else {
            switchToProfile(id)
        }
    }

    private func completePendingProfileSwitch(saveChanges: Bool) {
        let targetID = pendingProfileSelectionID
        pendingProfileSelectionID = nil
        if saveChanges {
            guard saveDraft() else { return }
        } else {
            discardDraft()
        }
        switchToProfile(targetID)
    }

    private func switchToProfile(_ id: UUID?) {
        selectedProfileID = id
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
        isSelectingItems = false
        loadDraftSession()
    }

    private func loadDraftSession() {
        guard let selectedProfileID,
              let profile = store.state.profiles.first(where: { $0.id == selectedProfileID }) else {
            draftSession = nil
            return
        }
        draftSession = DockProfileDraft(profile: profile)
    }

    private func updateDraft(_ change: (inout DockProfile) -> Void) {
        guard var session = draftSession, session.profile.id == selectedProfileID else { return }
        session.update(change)
        draftSession = session
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard var session = draftSession, session.isDirty else { return true }
        var updatedProfile = session.profile
        updatedProfile.name = updatedProfile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !updatedProfile.name.isEmpty else {
            dockOperationMessage = "A Dock profile needs a name before it can be saved or applied."
            return false
        }
        store.replaceProfile(updatedProfile)
        session.markSaved(updatedProfile)
        draftSession = session
        return true
    }

    private func discardDraft() {
        guard var session = draftSession else { return }
        session.discard()
        draftSession = session
    }

    private func appendDraftItem(_ item: DockItem, to profileID: UUID?) {
        guard let profileID else { return }
        if draftSession?.profile.id != profileID {
            requestProfileSelection(profileID)
            return
        }
        updateDraft { $0.items.append(item) }
    }

    private func canMoveSelection(_ direction: DockItemMoveDirection, in profile: DockProfile) -> Bool {
        let indices = profile.items.indices.filter { selectedItemIDs.contains(profile.items[$0].id) }
        guard let first = indices.first, let last = indices.last else { return false }
        switch direction {
        case .left:
            return first > profile.items.startIndex && !selectedItemIDs.contains(profile.items[first - 1].id)
        case .right:
            return last < profile.items.index(before: profile.items.endIndex)
                && !selectedItemIDs.contains(profile.items[last + 1].id)
        }
    }

    private func moveSelection(_ direction: DockItemMoveDirection, in profile: DockProfile) {
        let itemIDs = selectedItemIDs
        updateDraft { $0.items = DockItemOrderingPolicy.moving($0.items, ids: itemIDs, direction: direction) }
    }

    @ViewBuilder private func addMenu(for profile: DockProfile) -> some View {
        Menu {
            Button("Apps…") { pickApplications(profile) }
            if profile.kind == .custom {
                Button("Folders…") { pickFiles(profile, foldersOnly: true) }
                Button("Files…") { pickFiles(profile, foldersOnly: false) }
                Button("Link…") { prepareLinkEditor() }
                Button("Widget…") { showingWidgetPicker = true }
            }
            Menu("Spacer") {
                    Button("Small spacer") { appendDraftItem(.spacer(.small), to: profile.id) }
                    Button("Regular spacer") { appendDraftItem(.spacer(.regular), to: profile.id) }
            }
        } label: { Label("Add", systemImage: "plus") }
    }

    private var widgetPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Widget Library").font(.title2.bold()); Spacer(); Button("Done") { showingWidgetPicker = false } }
            TextField("Search widgets", text: $searchText).textFieldStyle(.roundedBorder)
            List(WidgetRegistry.all.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }) { widget in
                Button {
                    appendDraftItem(.widget(widget.name), to: selectedProfileID)
                    showingWidgetPicker = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: widget.symbol).font(.title2).frame(width: 34)
                        VStack(alignment: .leading) { Text(widget.name); Text(widget.description).font(.caption).foregroundStyle(.secondary) }
                        Spacer(); Text(widget.category.rawValue).font(.caption2).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .padding(20).frame(width: 500, height: 520)
    }

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(editingLinkItemID == nil ? "Add Link" : "Edit Link").font(.title2.bold())
            TextField("Name", text: $linkTitle)
            TextField("https://example.com", text: $linkAddress)
                .onChange(of: linkAddress) { _ in
                    faviconFetchTask?.cancel()
                    faviconFetchTask = nil
                    faviconRequestID = UUID()
                    isFetchingFavicon = false
                    faviconMessage = nil
                }
            if DockLinkPolicy.validatedURL(linkAddress) == nil {
                Text("Enter a valid HTTP or HTTPS address.")
                    .font(.caption).foregroundStyle(.red)
            }
            Picker("Icon", selection: $linkIconSelection) {
                Text("Default").tag("")
                ForEach(DockLinkIcon.allCases) { icon in
                    Label(icon.title, systemImage: icon.rawValue).tag(icon.rawValue)
                }
            }
            HStack(spacing: 10) {
                Button {
                    fetchSiteIcon()
                } label: {
                    if isFetchingFavicon {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(linkFaviconData == nil ? "Fetch Site Icon" : "Refresh Site Icon", systemImage: "globe")
                    }
                }
                .disabled(isFetchingFavicon || DockLinkPolicy.validatedURL(linkAddress) == nil)
                if let linkFaviconData, let image = NSImage(data: linkFaviconData) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 24, height: 24)
                        .accessibilityLabel("Saved site icon preview")
                }
            }
            if linkFaviconData != nil {
                Button("Remove Site Icon", role: .destructive) {
                    linkFaviconData = nil
                    faviconMessage = nil
                }
                .font(.caption)
            }
            Text("Fetching contacts the site's HTTPS favicon endpoint. The optimized icon is stored locally.")
                .font(.caption2).foregroundStyle(.secondary)
            if let faviconMessage {
                Text(faviconMessage).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { showingLinkEditor = false }
                Button(editingLinkItemID == nil ? "Add" : "Save") { saveLink() }
                    .buttonStyle(.borderedProminent)
                    .disabled(DockLinkPolicy.validatedURL(linkAddress) == nil)
            }
        }
        .textFieldStyle(.roundedBorder).padding(24).frame(width: 420)
    }

    private func select(_ id: UUID) { requestProfileSelection(id) }

    private func selectItem(_ id: UUID, commandPressed: Bool, shiftPressed: Bool) {
        guard let profile = selectedProfile else { return }
        if shiftPressed, let anchorID = selectionAnchorID {
            let range = DockItemSelectionPolicy.range(in: profile.items.map(\.id), from: anchorID, to: id)
            if !range.isEmpty {
                selectedItemIDs = range
                isSelectingItems = true
                return
            }
        }
        if isSelectingItems || commandPressed {
            if commandPressed { isSelectingItems = true }
            if !selectedItemIDs.insert(id).inserted { selectedItemIDs.remove(id) }
            selectionAnchorID = id
        } else {
            selectedItemIDs = [id]
            selectionAnchorID = id
        }
    }

    private func removeItem(_ id: UUID, from profileID: UUID) {
        updateDraft { $0.items.removeAll { $0.id == id } }
        selectedItemIDs.remove(id)
        if selectionAnchorID == id { selectionAnchorID = nil }
    }

    private func removeSelectedItems(from profile: DockProfile) {
        let itemIDs = selectedItemIDs
        updateDraft { $0.items.removeAll { itemIDs.contains($0.id) } }
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
    }

    private func useProfile(_ profile: DockProfile) {
        guard saveDraft() else { return }
        if profile.kind == .custom {
            store.activate(profile.id)
        } else {
            applyNativeProfile(profile)
        }
    }

    private func applyNativeProfile(_ profile: DockProfile) {
        guard saveDraft() else { return }
        let profileToApply = store.state.profiles.first(where: { $0.id == profile.id }) ?? profile
        Task { @MainActor in
            do {
                try await NativeDockController.shared.apply(profileToApply)
                store.activate(profileToApply.id)
                dockOperationMessage = "Applied \(profileToApply.name)."
            } catch {
                dockOperationMessage = error.localizedDescription
            }
        }
    }

    private func pickApplications(_ profile: DockProfile) {
        let panel = NSOpenPanel()
        panel.title = "Add Applications"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            panel.urls.forEach { appendDraftItem(.application(at: $0), to: profile.id) }
        }
    }

    private func pickFiles(_ profile: DockProfile, foldersOnly: Bool) {
        let panel = NSOpenPanel()
        panel.title = foldersOnly ? "Add Folders" : "Add Files"
        panel.prompt = "Add"
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = foldersOnly
        panel.canChooseFiles = !foldersOnly
        if panel.runModal() == .OK {
            panel.urls.forEach { appendDraftItem(.file(at: $0, isFolder: foldersOnly), to: profile.id) }
        }
    }

    private func prepareLinkEditor(for item: DockItem? = nil) {
        editingLinkItemID = item?.id
        linkTitle = item?.title ?? ""
        linkAddress = item?.url?.absoluteString ?? "https://"
        linkIconSelection = item?.linkIcon?.rawValue ?? ""
        linkFaviconData = item?.linkFaviconData
        faviconMessage = nil
        isFetchingFavicon = false
        faviconFetchTask?.cancel()
        faviconFetchTask = nil
        faviconRequestID = UUID()
        showingLinkEditor = true
    }

    private func fetchSiteIcon() {
        guard let destination = DockLinkPolicy.validatedURL(linkAddress) else { return }
        let requestID = UUID()
        faviconRequestID = requestID
        isFetchingFavicon = true
        faviconMessage = nil
        faviconFetchTask = Task { @MainActor in
            let data = await SiteFaviconFetcher.fetchIconData(for: destination)
            guard faviconRequestID == requestID else { return }
            faviconFetchTask = nil
            isFetchingFavicon = false
            if let data {
                linkFaviconData = data
                linkIconSelection = ""
                faviconMessage = "Site icon saved."
            } else {
                faviconMessage = "No safe HTTPS favicon was available for this site."
            }
        }
    }

    private func saveLink() {
        guard let url = DockLinkPolicy.validatedURL(linkAddress) else { return }
        let icon = DockLinkIcon(rawValue: linkIconSelection)
        if let editingLinkItemID {
            updateDraft { draft in
                guard let index = draft.items.firstIndex(where: { $0.id == editingLinkItemID }) else { return }
                draft.items[index].url = url
                let trimmedTitle = linkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.items[index].title = trimmedTitle.isEmpty ? (url.host ?? url.absoluteString) : trimmedTitle
                draft.items[index].linkIcon = icon
                draft.items[index].linkFaviconData = linkFaviconData
            }
        } else {
            var item = DockItem.link(url,
                                     title: linkTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                                     icon: icon)
            item.linkFaviconData = linkFaviconData
            appendDraftItem(item, to: selectedProfileID)
        }
        linkTitle = ""
        linkAddress = "https://"
        linkIconSelection = ""
        linkFaviconData = nil
        faviconMessage = nil
        isFetchingFavicon = false
        faviconFetchTask?.cancel()
        faviconFetchTask = nil
        faviconRequestID = UUID()
        editingLinkItemID = nil
        showingLinkEditor = false
    }

    private func createFromCurrentDock() {
        let id = store.createProfile(kind: .native, name: "Current Dock")
        requestProfileSelection(id)
        if let profile = store.state.profiles.first(where: { $0.id == id }) {
            store.replaceItems(NativeDockController.shared.readCurrentItems(), in: profile.id)
        }
    }

    private func replaceFromCurrentDock(_ profile: DockProfile) {
        let importedItems = NativeDockController.shared.readCurrentItems()
        updateDraft { $0.items = importedItems }
    }
}

private struct DockManagerItemView: View {
    var item: DockItem
    var isSelected: Bool
    var isSelectionMode: Bool
    var remove: () -> Void
    var editLink: () -> Void
    var updateFolderIcon: (DockProfileColor?, String?, String?) -> Void
    var select: (Bool, Bool) -> Void
    @State private var isFolderIconEditorPresented = false
    @State private var folderColorSelection = ""
    @State private var folderLetterDraft = ""
    @State private var folderNumberDraft = ""

    var body: some View {
        VStack(spacing: 8) {
            if item.type == .spacer {
                RoundedRectangle(cornerRadius: 3).fill(.secondary.opacity(0.35)).frame(width: item.spacerKind == .small ? 12 : 25, height: 70)
            } else if item.type == .folder && item.hasCustomFolderIcon {
                DockFolderIconView(item: item, size: 58)
            } else {
                Image(nsImage: AppLauncher.icon(for: item, size: 54)).resizable().scaledToFit().frame(width: 58, height: 58)
            }
            Text(item.title).font(.caption).lineLimit(1).frame(width: 86)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color(nsColor: .quaternaryLabelColor).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2))
        .overlay(alignment: .bottomTrailing) {
            if AppLauncher.isMissingTarget(item) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(5)
                    .help("Saved location is unavailable")
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(5)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            let modifiers = NSApplication.shared.currentEvent?.modifierFlags ?? []
            select(modifiers.contains(.command), modifiers.contains(.shift))
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(AppLauncher.isMissingTarget(item)
            ? "Saved location is unavailable. Re-add the item from its current location."
            : (isSelectionMode ? "Click to toggle selection." : "Click to select; use Select Items for multi-select."))
        .contextMenu {
            if item.type == .link {
                Button("Edit Link…", systemImage: "pencil") { editLink() }
            }
            if item.type == .file, let fileURL = item.url {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
                Button("Open Containing Folder") { NSWorkspace.shared.open(fileURL.deletingLastPathComponent()) }
            }
            if item.type == .folder {
                Button("Customize Folder Icon…", systemImage: "folder.badge.gearshape") {
                    folderColorSelection = item.folderIconColor?.rawValue ?? ""
                    folderLetterDraft = item.folderIconLetter ?? ""
                    folderNumberDraft = item.folderIconNumber ?? ""
                    isFolderIconEditorPresented = true
                }
                Button("Reset Icon") { updateFolderIcon(nil, nil, nil) }
                    .disabled(!item.hasCustomFolderIcon)
            }
            Button("Remove", role: .destructive, action: remove)
        }
        .popover(isPresented: $isFolderIconEditorPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Folder Icon").font(.headline)
                Picker("Color", selection: $folderColorSelection) {
                    Text("Default").tag("")
                    ForEach(DockProfileColor.allCases) { color in
                        Text(color.title).tag(color.rawValue)
                    }
                }
                TextField("Optional single letter", text: $folderLetterDraft)
                    .onChange(of: folderLetterDraft) { value in
                        let normalized = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
                        if normalized != value { folderLetterDraft = normalized }
                    }
                TextField("Optional number", text: $folderNumberDraft)
                    .onChange(of: folderNumberDraft) { value in
                        let normalized = String(value.filter(\.isNumber).prefix(3))
                        if normalized != value { folderNumberDraft = normalized }
                    }
                HStack {
                    Button("Reset Icon") {
                        updateFolderIcon(nil, nil, nil)
                        isFolderIconEditorPresented = false
                    }
                    Spacer()
                    Button("Done") {
                        updateFolderIcon(DockProfileColor(rawValue: folderColorSelection),
                                         folderLetterDraft.isEmpty ? nil : folderLetterDraft,
                                         folderNumberDraft.isEmpty ? nil : folderNumberDraft)
                        isFolderIconEditorPresented = false
                    }.buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .frame(width: 240)
        }
    }
}

private struct EmptyStateView: View {
    var title: String
    var symbol: String
    var detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
