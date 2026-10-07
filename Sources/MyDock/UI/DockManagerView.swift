import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DockManagerView: View {
    @ObservedObject var store: ProfileStore
    var onContinueSetup: () -> Void = {}
    var isVisible = true
    var sidebarVisible = true
    var showsSettings = false
    var openSettings: () -> Void = {}
    var openDocks: () -> Void = {}
    @State private var selectedProfileID: UUID?
    @ObservedObject private var edits: ProfileEditSessionCoordinator
    private var draftSession: DockProfileDraft? {
        get { selectedProfileID.flatMap { edits.drafts[$0] } }
        nonmutating set { if let id = selectedProfileID { edits.set(newValue, for: id) } }
    }

    init(store: ProfileStore, onContinueSetup: @escaping () -> Void = {}, isVisible: Bool = true, sidebarVisible: Bool = true, showsSettings: Bool = false, openSettings: @escaping () -> Void = {}, openDocks: @escaping () -> Void = {}, initialInspector: Bool = false, initialSelection: Set<UUID> = []) {
        self.store = store
        _selectedProfileID = State(initialValue: DockProfileStatus.preferredWorkspaceProfileID(profiles: store.state.profiles, settings: store.state.settings))
        self.edits = store.editSessions
        self.onContinueSetup = onContinueSetup
        self.isVisible = isVisible
        self.sidebarVisible = sidebarVisible
        self.showsSettings = showsSettings
        self.openSettings = openSettings
        self.openDocks = openDocks
        _showingDockInspector = State(initialValue: initialInspector)
        _selectedItemIDs = State(initialValue: initialSelection)
    }
    @State private var pendingProfileSelectionID: UUID?
    @State private var showingUnsavedProfileChanges = false
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var selectionAnchorID: UUID?
    @State private var emptyDropActive = false
    @State private var selectionCursorID: UUID?
    @State private var showingPresets = false
    @State private var resolvedPreset: DockProfile?
    @State private var presetResolutionNotes: [String] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var dockOperationMessage: String?
    @State private var shortcutProfile: DockProfile?
    @State private var renamingProfile = false
    @State private var renameText = ""
    @FocusState private var profileNameFocused: Bool
    @State private var workspaceSize = CGSize(width: 1160, height: 760)
    @State private var profileSearch = ""
    @State private var dropTargetID: UUID?
    @State private var isEndDropTarget = false
    @State private var configurationTarget: DockConfigurationTarget?
    @State private var confirmingProfileDeletion = false
    @State private var profileToDelete: UUID?
    @State private var libraryMode: DockLibraryMode?
    @State private var showingActiveStatus = false
    @State private var showingDockInspector = false
    @State private var showingCreation = false
    @State private var creationName = "New Dock"
    @State private var creationSource = "Empty"
    @State private var creationKind: DockProfileKind = .custom
    @State private var confirmingClear = false
    @State private var workspaceStart: WorkspaceStartRequest?
    @State private var dockExport: PortableDockExportRequest?
    @State private var dockImport: PortableDockImportPreview?
    private var saveStatus: String? { selectedProfileID.flatMap { edits.saveFeedback[$0] } }
    @Environment(\.undoManager) private var undoManager

    private var selectedProfile: DockProfile? {
        if let draftSession, draftSession.profile.id == selectedProfileID {
            return draftSession.profile
        }
        return store.state.profiles.first(where: { $0.id == selectedProfileID })
    }

    private var hasUnsavedProfileChanges: Bool { draftSession?.isDirty == true }
    private var draftCanBeSaved: Bool {
        guard let draft = draftSession, draft.isDirty else { return true }
        return !draft.profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                profileSidebar
                Rectangle().fill(DockDesign.hairline).frame(width: 1)
            }
            Group {
                if showsSettings { SettingsView(store: store, embeddedInWorkspace: true, sidebarVisible: false) }
                else if let profile = selectedProfile { editor(for: profile) }
                else {
                    VStack(spacing: 16) {
                        EmptyStateView(title: "Choose a Dock", symbol: "dock.rectangle",
                                       detail: "Create a profile to arrange your apps and widgets.")
                            .frame(maxHeight: 200)
                        Button("Create Dock") { prepareCreation() }
                            .buttonStyle(DockButtonStyle(primary: true))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 520)
        .background(DockDesign.page)
        .background(GeometryReader { geometry in
            Color.clear.onAppear { workspaceSize = geometry.size }
                .onChange(of: geometry.size) { workspaceSize = $0 }
        })
        .tint(DockDesign.accent)
        .overlay(alignment: .top) {
            if store.hasUnpersistedChanges {
                HStack(alignment: .top, spacing: 10) {
                    Label(store.persistenceError ?? "Changes are waiting to be saved.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    Button("Retry Save") { store.commit() }
                        .controlSize(.small)
                        .disabled(!store.canRetryPersistence)
                }
                .padding(11)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
                .padding(12)
                .zIndex(20)
            }
        }
        .onAppear {
            if selectedProfileID == nil {
                switchToProfile(DockProfileStatus.preferredWorkspaceProfileID(profiles: store.state.profiles, settings: store.state.settings))
            } else {
                loadDraftSession()
            }
        }
        .onChange(of: selectedProfileID) { _ in
            showingDockInspector = false
            clearItemSelection()
        }
        .onReceive(store.$state) { state in
            if let selectedProfileID, !state.profiles.contains(where: { $0.id == selectedProfileID }) {
                switchToProfile(DockProfileStatus.preferredWorkspaceProfileID(profiles: state.profiles, settings: state.settings))
                return
            }
            guard draftSession?.isDirty != true,
                  let selectedProfileID,
                  let profile = state.profiles.first(where: { $0.id == selectedProfileID }) else { return }
            edits.load(profile)
        }
        .confirmationDialog("Delete this Dock profile?", isPresented: $confirmingProfileDeletion, titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) {
                guard let id = profileToDelete ?? selectedProfileID else { return }
                store.deleteProfile(id)
                edits.set(nil, for: id)
                profileToDelete = nil
                switchToProfile(store.state.profiles.first?.id)
            }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The profile will be removed from your library. Other profiles are kept.") }
        .sheet(item: $configurationTarget) { target in
            if target.item.type == .widget {
                WidgetConfigurationSheet(store: store, item: target.item, profileID: target.profileID,
                                         maximumHeight: workspaceSize.height - DockDesign.Space.section * 2)
            } else {
                // The live item, so the inspector shows (and edits) a Replace or Locate repair at once.
                let live = selectedProfile?.items.first { $0.id == target.item.id } ?? target.item
                DockItemInspector(item: live, update: { replacement in
                    updateDraft { draft in
                        if let index = draft.items.firstIndex(where: { $0.id == target.item.id }) { draft.items[index] = replacement }
                    }
                }, replace: { replaceItem(live) }, close: { configurationTarget = nil })
            }
        }
        .sheet(item: $libraryMode) { mode in
            Group {
                let profile = selectedProfile ?? DockProfile(name: "New Dock", kind: .custom)
                AddLibrary(store: store, profile: profile, commandMode: mode == .command, allowsAdding: selectedProfile != nil,
                           add: { appendDraftItem($0, to: profile.id) },
                           switchProfile: { requestProfileSelection($0); openDocks() },
                           newDock: { prepareCreation() }, settings: openSettings,
                           browse: { name in
                               switch name {
                               case "Folder…": pickFiles(profile, foldersOnly: true)
                               case "File…": pickFiles(profile, foldersOnly: false)
                               case "Link…": prepareLinkEditor()
                               default: pickApplications(profile)
                               }
                           }, close: { libraryMode = nil })
            }
            .environment(\.workspaceStartHandler, WorkspaceStartHandler { beginWorkspaceStart($0) })
        }
        .sheet(isPresented: $showingCreation) { creationSheet }
        .sheet(item: $workspaceStart) { request in
            WorkspaceStartSheet(request: request, launcher: SystemWorkspaceLauncher(),
                                switchToDock: { useProfile(request.profile) },
                                locate: { locateWorkspaceItem($0, in: request.profile.id) },
                                close: { workspaceStart = nil })
        }
        .sheet(item: $dockExport) { request in
            PortableDockExportSheet(profiles: request.profiles, selectedID: request.selectedID,
                                    includePersonalData: request.includePersonalData,
                                    close: { dockExport = nil }, exported: { _ in dockExport = nil })
        }
        .sheet(item: $dockImport) { preview in
            PortableDockImportSheet(preview: preview, add: { addImportedDock(preview) }, cancel: { dockImport = nil })
        }
        .confirmationDialog("Remove all items from this Dock?", isPresented: $confirmingClear) {
            Button("Remove All Items", role: .destructive) { updateDraft { $0.items.removeAll() } }
        } message: { Text("You can undo this change.") }
        .background {
            Group {
                Button("Search MyDock") { libraryMode = .command }.keyboardShortcut("k")
                Button("New Dock") { prepareCreation() }.keyboardShortcut("n")
                Button("Settings", action: openSettings).keyboardShortcut(",")
                Button("Duplicate") {
                    if let item = selectedProfile?.items.first(where: { selectedItemIDs.contains($0.id) }) { duplicateItem(item) }
                    else if let profile = selectedProfile { duplicateProfile(profile) }
                }.keyboardShortcut("d")
            }.hidden()
        }
        .sheet(isPresented: $showingPresets) { presetPicker }
        .sheet(isPresented: $showingLinkEditor) { linkEditor }
        .sheet(item: $shortcutProfile) { profile in
            KeyboardShortcutEditor(profileID: profile.id,
                                   profileName: profile.name,
                                   bindings: DockShortcutStore.shared,
                                   controller: GlobalShortcutController.shared) {
                shortcutProfile = nil
            }
        }
        .alert("MyDock data", isPresented: Binding(get: { store.persistenceError != nil || store.persistenceWarning != nil }, set: { if !$0 { store.dismissPersistenceNotice() } })) {
            Button("OK", role: .cancel) { }
        } message: { Text(store.persistenceError ?? store.persistenceWarning ?? "") }
        .alert("MyDock", isPresented: Binding(get: { dockOperationMessage != nil }, set: { if !$0 { dockOperationMessage = nil } })) {
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

    private var profileSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            DockSidebarHeader(title: "MyDock", symbol: "dock.rectangle") { EmptyView() }
            if store.state.profiles.count > 8 {
                DockSearchField(placeholder: "Find a Dock", text: $profileSearch).padding(.horizontal, 16)
            }
            SidebarSectionTitle(title: "Docks")
            DockScrollView {
                VStack(spacing: 2) {
                    ForEach(store.state.profiles.filter { profileSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(profileSearch) }) { sidebarProfile($0) }
                }.padding(.horizontal, 12)
            }
            VStack(spacing: 4) {
                SidebarRow { Label("New Dock", systemImage: "plus") } action: { prepareCreation() }
                    .contextMenu {
                        Button("New macOS Dock") { prepareCreation(kind: .native) }
                        Button("Import Current macOS Dock") { prepareCreation(kind: .native, source: "Current macOS Dock") }
                    }
                SidebarRow { Label("Presets", systemImage: "square.grid.2x2") } action: { showingPresets = true }
                SidebarRow(selected: showsSettings) { Label("Settings", systemImage: "gearshape") } action: { openSettings() }
                if !store.state.settings.onboardingComplete {
                    SidebarRow { Label("Finish setup", systemImage: "checkmark.circle") } action: { onContinueSetup() }
                }
            }.padding(12)
        }.frame(width: DockDesign.sidebarWidth).background(DockSidebarBackground())
    }

    private func sidebarProfile(_ profile: DockProfile) -> some View {
        SidebarRow(selected: !showsSettings && selectedProfileID == profile.id) {
            HStack(spacing: 10) {
                Circle().fill((DockProfileColor(rawValue: profile.color) ?? .blue).displayColor)
                    .frame(width: 6, height: 6).accessibilityHidden(true)
                Text(profile.name).font(DockDesign.body).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if isActive(profile) {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .accessibilityLabel(profile.kind == .native ? "Applied macOS layout" : "Active Dock")
                }
                if profile.kind == .native { Image(systemName: "macwindow").font(.system(size: 11)).foregroundStyle(.tertiary).help("Saved macOS Dock") }
            }
        } action: { requestProfileSelection(profile.id); openDocks() }
        .help(profile.name)
        .accessibilityLabel(sidebarAccessibilityLabel(for: profile))
        .contextMenu {
            Button(profile.kind == .native ? "Apply to macOS Dock" : "Activate") { useProfile(profile) }
            Button("Rename…") { requestProfileSelection(profile.id); openDocks(); if selectedProfileID == profile.id { beginRename(profile) } }
            Button("Export Dock…") { exportProfile(profile) }
            Button("Duplicate") { duplicateProfile(profile); openDocks() }
            Button("Save as Personal Preset") { store.personalPresets.record(profile, reason: "Personal preset") }
            Button("Delete Dock…", role: .destructive) { profileToDelete = profile.id; confirmingProfileDeletion = true }
        }
    }

    private func sidebarAccessibilityLabel(for profile: DockProfile) -> String {
        let status = DockProfileStatus(profile: profile, settings: store.state.settings)
        let kind = profile.kind == .native ? "Saved macOS Dock layout" : "Custom Dock"
        return status.isCurrent ? "\(profile.name), \(kind), \(status.label)" : "\(profile.name), \(kind)"
    }

    private func editor(for profile: DockProfile) -> some View {
        let status = DockProfileStatus(profile: profile, settings: store.state.settings)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if profile.kind == .native { Text("macOS Dock").font(DockDesign.caption).foregroundStyle(.secondary) }
                Spacer()
                if let saveStatus {
                    if saveStatus.hasPrefix("Couldn’t") { Button(saveStatus) { scheduleAutosave() }.buttonStyle(.plain).foregroundStyle(.orange) }
                    else { Text(saveStatus).font(DockDesign.caption).foregroundStyle(.secondary) }
                }
                if isActive(profile) {
                    Button { showingActiveStatus.toggle() } label: {
                        HStack(spacing: 6) { Circle().fill(status.showsActiveIndicator ? Color.green : Color.secondary).frame(width: 6, height: 6); Text(status.label).font(DockDesign.caption) }
                    }.buttonStyle(.plain).foregroundStyle(.secondary).help(profile.kind == .native ? "Applied macOS Dock layout" : "Active Dock")
                        .popover(isPresented: $showingActiveStatus) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(profile.kind == .native ? "Applied to macOS Dock" : "Active on this Mac").font(DockDesign.sectionTitle)
                                Text(status.workspaceCaption(for: profile.kind, setupMode: store.state.settings.setupMode)).font(DockDesign.caption).foregroundStyle(.secondary)
                                if status == .applied(hidden: true) { Text("The macOS Dock is hidden in replacement mode.").font(DockDesign.caption).foregroundStyle(.secondary) }
                                if profile.kind == .custom {
                                    Button("Deactivate") { showingActiveStatus = false; store.setActiveCustomProfile(nil) }
                                }
                            }.padding(20)
                        }
                } else {
                    Button(DockProfileStatus.actionTitle(for: profile.kind)) { useProfile(profile) }.buttonStyle(DockButtonStyle()).disabled(!draftCanBeSaved)
                        .help(DockProfileStatus.actionHelp(for: profile.kind))
                }
                profileActions(for: profile)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            GeometryReader { geometry in
                DockScrollView {
                VStack(spacing: geometry.size.height < 600 ? 16 : 24) {
                    Spacer(minLength: 16)
                    VStack(spacing: 8) {
                        if renamingProfile {
                            TextField("Dock name", text: $renameText)
                                .font(DockDesign.title).textFieldStyle(.plain).multilineTextAlignment(.center)
                                .focused($profileNameFocused).frame(maxWidth: 440)
                                .accessibilityIdentifier("manager.profile.name")
                                .id(profile.id)
                                .onChange(of: renameText) { value in
                                    if renamingProfile { updateProfileName(value) }
                                }
                                .onSubmit {
                                    updateProfileName(renameText)
                                    if saveDraft() { renamingProfile = false }
                                }
                        } else {
                            Text(profile.name).font(DockDesign.title).lineLimit(2).truncationMode(.tail).multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                                .onTapGesture(count: 2) { beginRename(profile) }
                                .accessibilityAction(named: "Rename Dock") { beginRename(profile) }
                                .help(profile.name + " · Double-click to rename")
                                .accessibilityLabel(profile.name)
                        }
                        Text(status.workspaceCaption(for: profile.kind, setupMode: store.state.settings.setupMode))
                            .font(DockDesign.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    if profile.items.isEmpty {
                        GalleryEmptyState(title: "Your Dock is empty",
                                          detail: profile.kind == .native ? "Add apps to save a macOS Dock layout." : "Add the apps and widgets you want available here.",
                                          symbol: "dock.rectangle", compact: true)
                            .frame(maxWidth: 480).frame(height: 120)
                            .background(emptyDropActive ? DockDesign.accent.opacity(0.05) : Color.clear,
                                        in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
                            .overlay {
                                DockCanvasDragSurface(profileID: profile.id, items: [], frames: [:], selection: [],
                                                      select: { _, _, _ in }, hover: { _, active in emptyDropActive = active }, lift: { _ in },
                                                      drop: { values, _ in
                                    emptyDropActive = false
                                    let urls = values.compactMap { if case .url(let url) = $0 { return url }; return nil }
                                    return insertDroppedURLs(urls, before: nil, into: profile)
                                })
                            }
                    } else {
                        DockCanvas(store: store, profile: profile, selection: $selectedItemIDs, cursor: selectionCursorID,
                                   select: { selectItem($0, commandPressed: $1, shiftPressed: $2) },
                                   move: { ids, before in guard selectedProfileID == profile.id else { return }; updateDraft { $0.items = DockItemOrderingPolicy.moving($0.items, ids: ids, before: before) } },
                                   configure: { configureItem($0) }, remove: { removeItem($0.id, from: profile.id) },
                                   replace: { replaceItem($0) }, duplicate: { duplicateItem($0) },
                                   addURLs: { urls, before in _ = insertDroppedURLs(urls, before: before, into: profile) })
                    }
                    HStack(spacing: 12) {
                        Button { libraryMode = .add } label: { Label("Add Item", systemImage: "plus") }
                            .buttonStyle(DockButtonStyle()).accessibilityIdentifier("manager.add-item")
                        Button { showingDockInspector.toggle(); clearItemSelection() } label: { Image(systemName: "slider.horizontal.3") }
                            .buttonStyle(DockButtonStyle(icon: true))
                            .help(profile.kind == .custom ? "Edit Dock appearance" : "Dock options")
                            .accessibilityLabel(profile.kind == .custom ? "Edit Dock appearance" : "Dock options")
                    }
                    if showingDockInspector || !selectedItemIDs.isEmpty {
                        workspaceInspector(profile).frame(maxWidth: min(480, geometry.size.width - 48))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Spacer(minLength: 16)
                    Text("Drag to arrange · Click to edit · ⌘K to search").font(.system(size: 11)).foregroundStyle(.tertiary)
                        .padding(.bottom, 20)
                }.frame(maxWidth: .infinity).frame(minHeight: geometry.size.height)
                    .background(RadialGradient(colors: [(DockProfileColor(rawValue: profile.color) ?? .blue).displayColor.opacity(0.045), .clear], center: .center, startRadius: 0, endRadius: 400))
                }
            }
        }
        .animation(reduceMotion ? nil : DockDesign.Motion.disclosure, value: showingDockInspector)
        .animation(reduceMotion ? nil : DockDesign.Motion.disclosure, value: selectedItemIDs.isEmpty)
        .onMoveCommand { direction in
            guard !renamingProfile, !profile.items.isEmpty else { return }
            navigateSelection(in: profile, forward: direction == .right || direction == .down, extending: false)
        }
        .onDeleteCommand { if !renamingProfile { removeSelectedItems(from: profile) } }
        .background {
            Group {
                Button("Configure selected item") { if selectedItemIDs.count == 1, let item = profile.items.first(where: { selectedItemIDs.contains($0.id) }) { configureItem(item) } }.keyboardShortcut(.return, modifiers: [])
                Button("Extend selection left") { navigateSelection(in: profile, forward: false, extending: true) }.keyboardShortcut(.leftArrow, modifiers: .shift)
                Button("Extend selection right") { navigateSelection(in: profile, forward: true, extending: true) }.keyboardShortcut(.rightArrow, modifiers: .shift)
                Button("Move left") { moveSelection(.left, in: profile) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Move right") { moveSelection(.right, in: profile) }.keyboardShortcut(.rightArrow, modifiers: .command)
            }.hidden()
        }
    }

    @ViewBuilder private func workspaceInspector(_ profile: DockProfile) -> some View {
        if let item = profile.items.first(where: { selectedItemIDs.contains($0.id) }) {
            VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedItemIDs.count > 1 ? "\(selectedItemIDs.count) items selected" : item.displayName).font(DockDesign.sectionTitle)
                        .lineLimit(1).truncationMode(.middle).help(selectedItemIDs.count > 1 ? "" : item.displayName)
                    Text(AppLauncher.isMissingTarget(item) ? "Saved location missing. Choose Replace to reconnect." : "⌘← / ⌘→ to move · ⌘D to duplicate · Delete to remove")
                        .font(.system(size: 11)).foregroundStyle(AppLauncher.isMissingTarget(item) ? Color.orange : Color.secondary)
                }
                Spacer()
                if selectedItemIDs.count == 1 { Button("Configure") { configureItem(item) } }
                if selectedItemIDs.count == 1, AppLauncher.isMissingTarget(item), [.application, .file, .folder].contains(item.type) {
                    Button("Replace…") { replaceItem(item) }
                }
                Button { moveSelection(.left, in: profile) } label: { Image(systemName: "arrow.left") }
                    .disabled(!canMoveSelection(.left, in: profile)).help("Move earlier (⌘←)").accessibilityLabel("Move earlier")
                Button { moveSelection(.right, in: profile) } label: { Image(systemName: "arrow.right") }
                    .disabled(!canMoveSelection(.right, in: profile)).help("Move later (⌘→)").accessibilityLabel("Move later")
                if selectedItemIDs.count == 1 {
                    Button { duplicateItem(item) } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate (⌘D)").accessibilityLabel("Duplicate item")
                }
                Button { removeSelectedItems(from: profile) } label: { Image(systemName: "trash") }
                    .help("Remove from Dock (Delete)").accessibilityLabel(selectedItemIDs.count > 1 ? "Remove selected items" : "Remove item")
                Button { clearItemSelection() } label: { Image(systemName: "xmark").frame(width: DockDesign.controlHeight, height: DockDesign.controlHeight).contentShape(Rectangle()) }.buttonStyle(.plain).help("Close inspector").accessibilityLabel("Close inspector")
            }
            if item.type == .widget && selectedItemIDs.count == 1 {
                SettingsControlRow(title: "Layout") {
                    Picker("Layout", selection: Binding(get: { WidgetPresentationCatalog.resolvedLayout(for: item.widgetKind ?? item.title, configuration: item.widgetConfiguration ?? WidgetConfiguration(), compactDefault: store.effectiveSettings(for: profile).customDockWidgetStyle == .compact) }, set: { value in
                        updateDraft { draft in
                            if let index = draft.items.firstIndex(where: { $0.id == item.id }) { draft.items[index].widgetConfiguration?.widgetLayout = value }
                        }
                    })) {
                        ForEach(WidgetPresentationCatalog.options(for: item.widgetKind ?? item.title)) { Text($0.title).tag($0.layout) }
                    }
                }
            }
            }.padding(16).background(DockDesign.card, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
        } else {
            DockAppearanceInspector(store: store, profile: profile, close: { showingDockInspector = false },
                                    workspace: DockWorkspaceSection(profile: profile,
                                                                    setIncluded: { id, included in updateDraft { $0.setWorkspaceItem(id, included: included) } },
                                                                    start: { beginWorkspaceStart(profile.id) }))
        }
    }

    private func insertDroppedURLs(_ urls: [URL], before: UUID?, into profile: DockProfile) -> Bool {
        guard selectedProfileID == profile.id else { return false }
        if profile.kind == .native && urls.contains(where: { $0.pathExtension != "app" }) {
            dockOperationMessage = "macOS Dock layouts support apps and spacers. Use a custom Dock for files, folders, links, and widgets."
        }
        let items = urls.prefix(100).compactMap { url -> DockItem? in
            if url.pathExtension == "app" { return .application(at: url) }
            guard profile.kind == .custom else { return nil }
            if !url.isFileURL { return DockLinkPolicy.validatedURL(url.absoluteString).map { .link($0, title: $0.host ?? "Link") } }
            let directory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return .file(at: url, isFolder: directory)
        }
        guard !items.isEmpty else { return false }
        updateDraft { draft in
            let index = before.flatMap { target in draft.items.firstIndex { $0.id == target } } ?? draft.items.endIndex
            draft.items.insert(contentsOf: items, at: index)
        }
        if let last = items.last { selectItem(last.id, commandPressed: false, shiftPressed: false) }
        return true
    }

    private func configureItem(_ item: DockItem) {
        guard let profileID = selectedProfileID else { return }
        if item.type == .link { prepareLinkEditor(for: item); return }
        if item.type == .widget, !saveDraft() { return }
        configurationTarget = DockConfigurationTarget(profileID: profileID, item: item)
    }

    private func replaceItem(_ item: DockItem) {
        if item.type == .link { prepareLinkEditor(for: item); return }
        guard let repaired = AppLauncher.chooseReplacement(for: item) else { return }
        updateDraft { draft in
            if let index = draft.items.firstIndex(where: { $0.id == item.id }) { draft.items[index] = repaired }
        }
    }
    private func duplicateItem(_ item: DockItem) {
        let copy = store.copyItemForDuplication(item)
        updateDraft { draft in
            if let index = draft.items.firstIndex(where: { $0.id == item.id }) { draft.items.insert(copy, at: index + 1) }
        }
    }

    private var creationSheet: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Create Dock").font(.system(size: 22, weight: .semibold))
            TextField("Name", text: $creationName)
            Picker("Type", selection: $creationKind) {
                Text("Custom Dock").tag(DockProfileKind.custom)
                Text("macOS Dock layout").tag(DockProfileKind.native)
            }.onChange(of: creationKind) { kind in
                if creationSource == "Preset" && kind == .native || creationSource == "This Dock" && selectedProfile?.kind != kind { creationSource = "Empty" }
            }
            Picker("Start with", selection: $creationSource) {
                Text("Empty").tag("Empty")
                if selectedProfile?.kind == creationKind { Text("This Dock").tag("This Dock") }
                Text("Current macOS Dock").tag("Current macOS Dock")
                if creationKind == .custom { Text("Preset").tag("Preset") }
            }
            HStack {
                Button("Cancel") { showingCreation = false }
                Spacer()
                Button("Create") {
                    guard saveDraft() else { return }
                    if creationSource == "Preset" { showingCreation = false; showingPresets = true; return }
                    do {
                        let items = creationSource == "This Dock" ? (selectedProfile?.items ?? []) : creationSource == "Current macOS Dock" ? try NativeDockController.shared.readCurrentItems() : []
                        var profile = DockProfile(name: creationName.trimmingCharacters(in: .whitespacesAndNewlines), kind: creationKind, items: items)
                        if creationSource == "This Dock", let source = selectedProfile {
                            profile.color = source.color
                            profile.appearance = source.appearance
                            profile.items = source.items.map { store.copyItemForDuplication($0) }
                            profile.workspace = source.workspace?.remapped(from: source.items, to: profile.items)
                        }
                        let id = try store.createProfile(profile)
                        requestProfileSelection(id); openDocks(); showingCreation = false
                    } catch { dockOperationMessage = error.localizedDescription }
                }.buttonStyle(DockButtonStyle(primary: true)).disabled(creationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 400).background(DockDesign.page)
    }

    private func exportProfile(_ profile: DockProfile) {
        do {
            let current = try edits.save(profile.id) ?? profile
            dockExport = PortableDockExportRequest(profiles: [current], selectedID: current.id, includePersonalData: false)
        } catch { dockOperationMessage = error.localizedDescription }
    }

    private func importDock() {
        do {
            if let preview = try PortableDockPanels.chooseImport(existingNames: store.state.profiles.map(\.name)) { dockImport = preview }
        } catch { dockOperationMessage = error.localizedDescription }
    }

    private func addImportedDock(_ preview: PortableDockImportPreview) {
        dockImport = nil
        do {
            let id = try PortableDockPackage.importAsNew(preview, into: store)
            requestProfileSelection(id); openDocks()
        } catch { dockOperationMessage = error.localizedDescription }
    }

    private func beginWorkspaceStart(_ profileID: UUID) {
        let profile = selectedProfileID == profileID ? selectedProfile : store.state.profiles.first(where: { $0.id == profileID })
        guard let profile, profile.hasWorkspace else { return }
        workspaceStart = WorkspaceStartRequest(profile: profile, isCurrentDock: isActive(profile), canLocate: selectedProfileID == profileID)
    }

    /// Reuses the existing Locate… repair on the edited Dock; the repaired item keeps its identity.
    private func locateWorkspaceItem(_ item: DockItem, in profileID: UUID) -> DockItem? {
        guard selectedProfileID == profileID, item.type != .link,
              let repaired = AppLauncher.chooseReplacement(for: item) else { return nil }
        updateDraft { draft in
            if let index = draft.items.firstIndex(where: { $0.id == item.id }) { draft.items[index] = repaired }
        }
        return repaired
    }

    private func duplicateProfile(_ profile: DockProfile) {
        guard saveDraft() else { return }
        do {
            let id = try store.duplicateProfile(profile.id)
            guard let copy = store.state.profiles.first(where: { $0.id == id }) else { return }
            switchToProfile(copy.id); beginRename(copy)
        } catch { dockOperationMessage = error.localizedDescription }
    }

    private func beginRename(_ profile: DockProfile) {
        renameText = selectedProfile?.id == profile.id ? selectedProfile?.name ?? profile.name : profile.name
        renamingProfile = true
        profileNameFocused = true
    }

    private func updateProfileName(_ name: String) { updateDraft { $0.name = name } }
    private func isActive(_ profile: DockProfile) -> Bool {
        DockProfileStatus(profile: profile, settings: store.state.settings).isCurrent
    }

    private func profileActions(for profile: DockProfile) -> some View {
        Menu {
            if hasUnsavedProfileChanges { Button("Retry Save") { _ = saveDraft() }; Button("Discard Unsaved Changes", role: .destructive) { discardDraft() } }
            Button("Undo") { undoManager?.undo() }.disabled(!(undoManager?.canUndo ?? false))
            Button("Redo") { undoManager?.redo() }.disabled(!(undoManager?.canRedo ?? false))
            Divider()
            Button("Rename…") { beginRename(profile) }
            if profile.kind == .custom {
                Button("Save as Personal Preset") { store.personalPresets.record(profile, reason: "Personal preset") }
            }
            Button("Export Dock…") { exportProfile(profile) }
            Button("Import Dock…") { importDock() }
            if profile.hasWorkspace { Button("Start Workspace…") { beginWorkspaceStart(profile.id) } }
            Button("Duplicate") { duplicateProfile(profile) }
            Button("Keyboard Shortcut…") { shortcutProfile = profile }
            Menu("Profile Color") {
                ForEach(DockProfileColor.allCases) { color in
                    Button { updateDraft { $0.color = color.rawValue } } label: {
                        Label(color.title, systemImage: profile.color == color.rawValue ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            }
            if profile.kind == .native { Button("Replace with Current Dock…") { replaceFromCurrentDock(profile) } }
            Divider()
            Button("Remove All Items…", role: .destructive) { confirmingClear = true }
            Button("Delete Dock…", role: .destructive) { profileToDelete = profile.id; confirmingProfileDeletion = true }
        } label: { Image(systemName: "ellipsis") }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().frame(width: 30, height: 30)
            .background(DockDesign.hover, in: RoundedRectangle(cornerRadius: DockDesign.Radius.control))
            .tint(Color.secondary).help("More").accessibilityLabel("Profile actions")
    }

    private func requestProfileSelection(_ id: UUID?) {
        guard id != selectedProfileID else { return }
        if hasUnsavedProfileChanges && !saveDraft() {
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
        renamingProfile = false
        profileNameFocused = false
        withAnimation(reduceMotion ? nil : DockDesign.Motion.transform) { selectedProfileID = id }
        clearItemSelection()
        loadDraftSession()
    }

    private func loadDraftSession() {
        guard let selectedProfileID,
              let profile = store.state.profiles.first(where: { $0.id == selectedProfileID }) else {
            draftSession = nil
            return
        }
        edits.load(profile)
    }

    private func updateDraft(_ change: (inout DockProfile) -> Void) {
        guard var session = draftSession, session.profile.id == selectedProfileID else { return }
        let before = session.profile
        session.update(change)
        draftSession = session
        if session.profile != before {
            registerUndo(before, replacing: session.profile)
            scheduleAutosave()
        }
    }

    private func registerUndo(_ before: DockProfile, replacing after: DockProfile) {
        undoManager?.registerUndo(withTarget: edits) { coordinator in
            do {
                let current = try coordinator.restore(before, replacing: after)
                let restored = coordinator.drafts[before.id]?.profile ?? before
                registerUndo(current, replacing: restored)
                coordinator.autosave(before.id)
            } catch { dockOperationMessage = error.localizedDescription }
        }
        undoManager?.setActionName("Edit Dock")
    }

    private func scheduleAutosave(profileID: UUID? = nil) {
        if let id = profileID ?? selectedProfileID { edits.autosave(id) }
    }

    @discardableResult
    private func saveDraft() -> Bool {
        guard let id = selectedProfileID else { return true }
        do { try edits.save(id); return true }
        catch let error as ProfileDraftMergeError {
            let alert = NSAlert()
            alert.messageText = "Your draft needs review"
            alert.informativeText = error.localizedDescription + " You can keep this draft as a separate profile, reload the latest saved profile, or continue editing."
            alert.addButton(withTitle: "Continue Editing")
            alert.addButton(withTitle: "Save Draft as New Profile")
            alert.addButton(withTitle: "Reload Latest")
            switch alert.runModal() {
            case .alertSecondButtonReturn:
                guard let draft = edits.drafts[id] else { return false }
                do {
                    let newID = try store.createProfile(ProfileSanitizer.newIdentity(draft.profile))
                    edits.discard(id)
                    switchToProfile(newID)
                } catch { dockOperationMessage = error.localizedDescription }
            case .alertThirdButtonReturn: edits.discard(id)
            default: break
            }
            return false
        }
        catch { dockOperationMessage = error.localizedDescription; return false }
    }

    private func discardDraft() {
        if let id = selectedProfileID { edits.discard(id) }
    }

    private func appendDraftItem(_ item: DockItem, to profileID: UUID?) {
        guard let profileID else { return }
        if draftSession?.profile.id != profileID {
            requestProfileSelection(profileID)
            return
        }
        updateDraft { $0.items.append(item) }
        selectItem(item.id, commandPressed: false, shiftPressed: false)
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
                    .buttonStyle(DockButtonStyle(primary: true))
                    .disabled(DockLinkPolicy.validatedURL(linkAddress) == nil)
            }
        }
        .textFieldStyle(DockTextFieldStyle()).padding(24).frame(width: 420).background(DockDesign.page)
    }

    private var presetPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(resolvedPreset == nil ? "Dock Presets" : "Preview your new Dock").font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Cancel") { resolvedPreset = nil; showingPresets = false }
            }
            if let profile = resolvedPreset {
                DockScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        TextField("Name", text: Binding(get: { resolvedPreset?.name ?? "" }, set: { resolvedPreset?.name = $0 }))
                            .textFieldStyle(DockTextFieldStyle())
                        DockLayoutPreview(store: store, profile: profile, fitsByScale: true)
                        Text("Start with these installed apps. Replace or remove any item before creating your Dock.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !presetResolutionNotes.isEmpty {
                            Text(presetResolutionNotes.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(profile.items) { item in
                                HStack {
                                    Text(item.displayName)
                                    Spacer()
                                    if item.type == .application {
                                        Button("Choose Application…") { substitutePresetApp(item.id) }
                                    }
                                    Button("Remove") { resolvedPreset?.items.removeAll { $0.id == item.id } }
                                }
                            }
                        }
                    }
                }
                HStack {
                    Button("Back") { resolvedPreset = nil }
                    Button("Add Application…") { addPresetApp() }
                    Spacer()
                    Button("Create Dock") {
                        guard saveDraft() else { return }
                        do {
                            let id = try store.createProfile(profile)
                            requestProfileSelection(id)
                            resolvedPreset = nil
                            showingPresets = false
                        } catch { dockOperationMessage = error.localizedDescription }
                    }.buttonStyle(DockButtonStyle(primary: true)).disabled(profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("Preview a complete profile before adding it. Every item and appearance stays editable.")
                    .foregroundStyle(.secondary)
                DockScrollView {
                    PersonalPresetPicker(store: store, library: store.personalPresets) { resolvedPreset = $0; presetResolutionNotes = [] }
                        .padding(.bottom, 16)
                    VStack(spacing: 8) {
                        ForEach(DockStarterPreset.allCases) { preset in
                            Button {
                                let resolution = preset.resolve()
                                presetResolutionNotes = resolution.notes
                                var profile = DockProfile(name: preset.title, kind: .custom, color: preset.color.rawValue, items: resolution.items)
                                profile.appearance = preset.appearance(basedOn: store.state.settings)
                                resolvedPreset = profile
                            } label: {
                                PresetLibraryTile(preset: preset)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(maxHeight: 480)
                Text("Widget previews use sample data.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(24).frame(width: 660, height: min(650, max(480, workspaceSize.height - 48)))
            .background(DockDesign.page).font(.system(size: 13))
    }

    private func substitutePresetApp(_ itemID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let index = resolvedPreset?.items.firstIndex(where: { $0.id == itemID }) else { return }
        var item = DockItem.application(at: url)
        item.id = itemID
        resolvedPreset?.items[index] = item
    }

    private func addPresetApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let apps = panel.urls.prefix(100).map { DockItem.application(at: $0) }
        resolvedPreset?.items.append(contentsOf: apps)
    }

    private func prepareCreation(kind: DockProfileKind? = nil, source: String = "Empty") {
        creationKind = kind ?? (store.state.settings.setupMode == .nativeOnly ? .native : .custom)
        creationName = source == "Current macOS Dock" ? "Current Dock" : "New Dock"
        creationSource = source
        showingCreation = true
    }

    private func navigateSelection(in profile: DockProfile, forward: Bool, extending: Bool) {
        guard !renamingProfile,
              let next = DockItemSelectionPolicy.next(in: profile.items.map(\.id), selected: selectedItemIDs,
                                                     cursor: selectionCursorID, forward: forward) else { return }
        if extending && selectionAnchorID == nil {
            selectionAnchorID = selectionCursorID ?? profile.items.first(where: { selectedItemIDs.contains($0.id) })?.id ?? next
        }
        selectItem(next, commandPressed: false, shiftPressed: extending)
    }

    private func clearItemSelection() {
        selectedItemIDs.removeAll()
        selectionAnchorID = nil
        selectionCursorID = nil
    }

    private func selectItem(_ id: UUID, commandPressed: Bool, shiftPressed: Bool) {
        guard let profile = selectedProfile else { return }
        selectionCursorID = id
        if shiftPressed, let anchorID = selectionAnchorID {
            let range = DockItemSelectionPolicy.range(in: profile.items.map(\.id), from: anchorID, to: id)
            if !range.isEmpty {
                selectedItemIDs = range
                return
            }
        }
        if commandPressed {
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
        if selectionCursorID == id { selectionCursorID = nil }
    }

    private func removeSelectedItems(from profile: DockProfile) {
        let itemIDs = selectedItemIDs
        updateDraft { $0.items.removeAll { itemIDs.contains($0.id) } }
        clearItemSelection()
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
        guard store.allowsSystemChanges else { dockOperationMessage = "Native Dock changes are disabled in the visual preview."; return }
        guard saveDraft() else { return }
        let profileToApply = store.state.profiles.first(where: { $0.id == profile.id }) ?? profile
        Task { @MainActor in
            do {
                try await NativeDockController.shared.apply(profileToApply)
                store.recordAppliedNativeProfile(profileToApply.id)
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

    private func replaceFromCurrentDock(_ profile: DockProfile) {
        do {
            let importedItems = try NativeDockController.shared.readCurrentItems()
            updateDraft { $0.items = importedItems }
        } catch {
            dockOperationMessage = "Could not read the current macOS Dock. Your profile was not changed. \(error.localizedDescription)"
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

enum DockLibraryMode: String, Identifiable {
    case add, command
    var id: String { rawValue }
}

private struct DockConfigurationTarget: Identifiable {
    let profileID: UUID
    let item: DockItem
    var id: UUID { item.id }
}
