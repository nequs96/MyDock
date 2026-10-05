import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    @DockAccessibilityStyle() var accessibility
    var embeddedInWorkspace = false
    var sidebarVisible = true
    @ObservedObject var shortcutBindings = DockShortcutStore.shared
    @ObservedObject var shortcutController = GlobalShortcutController.shared
    private let initialPage: MyDockSettingsPage?
    @State var selectedPage: MyDockSettingsPage
    @State private var settingsSearch = ""
    @State var appearanceProfileID: UUID?
    @State var previousAppearance: SettingsAppearanceEditing.Undo?
    @State var appearanceScopeMessage: String?
    @State var diagnosticsPreview: DiagnosticsPreviewPayload?
    @State var editingAppearanceContinuously = false
    @State var editingShortcutProfile: DockProfile?
    @State var backupMessage: String?
    @State var includePersonalBackupData = true
    @State var dockExportRequest: PortableDockExportRequest?
    @State var dockImportPreview: PortableDockImportPreview?
    @State var diagnosticsMessage: String?
    @State var advancedExpanded = false
    @State var marketConnectionExpanded = false
    @State var copilotConnectionExpanded = false
    @State var marketAPIKeyDraft = ""
    @State var marketAPIKeySaved = false
    @State var marketAPIKeyMessage: String?
    @State var copilotUsernameDraft = ""
    @State var copilotTokenDraft = ""
    @State var copilotCredentialsSaved = false
    @State var copilotCredentialsMessage: String?
    @State var permissionRows: [PermissionOverviewRow] = []
    @State var screenCaptureMessage: String?
    @State var windowPreviewMessage: String?
    @State var nativeProfileSwitchMessage: String?
    @State var nativeProfileSwitchFailedID: UUID?
    @State var nativeProfileSwitchTargetID: UUID?
    @State var isApplyingNativeProfile = false
    @ObservedObject var nativeDockAutoSave = NativeDockAutoSaveMonitor.shared
    @ObservedObject var nativeDockVisibility = NativeDockAutoHideController.shared
    @ObservedObject private var nativeDock = NativeDockController.shared

    init(store: ProfileStore, initialPage: MyDockSettingsPage? = nil,
         embeddedInWorkspace: Bool = false, sidebarVisible: Bool = true) {
        self.store = store
        self.initialPage = initialPage
        self.embeddedInWorkspace = embeddedInWorkspace
        self.sidebarVisible = sidebarVisible
        _selectedPage = State(initialValue: initialPage ?? store.state.settings.lastSettingsPage)
        _appearanceProfileID = State(initialValue: store.activeCustomProfile?.id)
    }

    private var visiblePages: [MyDockSettingsPage] {
        SettingsSearchCatalog.pages(matching: settingsSearch)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let message = nativeDock.recoveryError {
                HStack {
                    Label("macOS Dock recovery required: " + message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Restore Previous Dock") { Task { try? await nativeDock.recoverInterruptedTransaction() } }.disabled(!store.allowsSystemChanges)
                        .disabled(nativeDock.health == .recovering)
                }
                .padding(12).background(Color.orange.opacity(0.12))
            }
            if store.hasUnpersistedChanges || store.persistenceError != nil {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(store.hasUnpersistedChanges ? "Changes not saved" : "MyDock data needs attention",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.weight(.semibold)).foregroundStyle(.orange)
                        Text(store.persistenceError ?? "MyDock has changes waiting to be saved.")
                            .font(.caption).textSelection(.enabled)
                    }
                    Spacer(minLength: 8)
                    Button("Retry Save") { store.commit() }
                        .controlSize(.small)
                        .disabled(!store.canRetryPersistence || !store.hasUnpersistedChanges)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.orange.opacity(0.09))
                Divider()
            }
            if !sidebarVisible {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings").font(.system(size: 16, weight: .semibold))
                    // Keep every section visible, wrapping on narrow windows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 180), spacing: 3, alignment: .leading)], alignment: .leading, spacing: 3) {
                            ForEach(MyDockSettingsPage.allCases) { page in
                                Button { selectedPage = page } label: {
                                    SettingsSidebarLabel(page: page)
                                        .font(.system(size: 11.5, weight: selectedPage == page ? .semibold : .medium))
                                        .foregroundStyle(selectedPage == page ? Color.primary : Color.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(selectedPage == page ? DockDesign.control : .clear, in: RoundedRectangle(cornerRadius: 8))
                                }.buttonStyle(.plain)
                                    .accessibilityAddTraits(selectedPage == page ? .isSelected : [])
                            }
                    }
                }.padding(.horizontal, 24).padding(.vertical, 8)
                Divider()
            }
            HStack(spacing: 0) {
                if sidebarVisible {
                    VStack(alignment: .leading, spacing: 0) {
                        DockSidebarHeader(title: "Settings", symbol: "gearshape") { EmptyView() }
                        DockSearchField(placeholder: "Search Settings", text: $settingsSearch)
                            .padding(.horizontal, 16).padding(.bottom, 2)
                        DockScrollView {
                            VStack(spacing: 2) {
                                ForEach(["Your Dock", "App", "Connections"], id: \.self) { group in
                                    let pages = visiblePages.filter { page in
                                        switch group {
                                        case "Your Dock": [.dock, .appearance, .behavior].contains(page)
                                        case "App": [.general, .shortcuts].contains(page)
                                        default: [.integrations, .permissions].contains(page)
                                        }
                                    }
                                    if !pages.isEmpty {
                                        SidebarSectionTitle(title: group).frame(maxWidth: .infinity, alignment: .leading)
                                        ForEach(pages) { page in
                                            SidebarRow(selected: selectedPage == page) {
                                                SettingsSidebarLabel(page: page)
                                            } action: { selectedPage = page; settingsSearch = "" }
                                        }
                                    }
                                }
                                if visiblePages.isEmpty {
                                    Text("No matching settings").font(DockDesign.caption)
                                        .foregroundStyle(.secondary).padding(16)
                                }
                            }.padding(.horizontal, 12)
                        }
                    }.frame(width: DockDesign.sidebarWidth).background(DockSidebarBackground())
                    Rectangle().fill(DockDesign.hairline).frame(width: 1)
                }
            ScrollViewReader { settingsProxy in
            if !settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsSearchResults(query: settingsSearch) { result in
                    selectedPage = result.page
                    settingsSearch = ""
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        settingsProxy.scrollTo(result.section, anchor: .top)
                    }
                }
            } else if selectedPage == .dock {
                dockPage
            } else if selectedPage == .appearance {
                appearancePage
            } else if selectedPage == .behavior {
                behaviorPage
            } else if selectedPage == .general {
                generalPage
            } else if selectedPage == .shortcuts {
                shortcutsPage
            } else if selectedPage == .permissions {
                permissionsPage
            } else if selectedPage == .integrations {
                integrationsPage
            }
            }
        }
        }
        .frame(minHeight: 520)
        .background(DockDesign.page)
        .font(.system(size: 13))
        .tint(DockDesign.accent)
        .onAppear {
            if let initialPage { persistSettingsPage(initialPage) }
        }
        .onChange(of: appearanceProfileID) { _ in
            previousAppearance = nil
            editingAppearanceContinuously = false
        }
        .onChange(of: store.customProfiles.map(\.id)) { ids in
            if let id = appearanceProfileID, !ids.contains(id) {
                appearanceProfileID = nil
                editingAppearanceContinuously = false
                appearanceScopeMessage = "The selected Dock was removed. Editing app defaults now."
            }
        }
        .sheet(item: $diagnosticsPreview) { payload in
            DiagnosticsPreviewSheet(payload: payload) { diagnosticsPreview = nil } saved: {
                diagnosticsMessage = "Saved the reviewed redacted diagnostics."
                diagnosticsPreview = nil
            }
        }
        .sheet(item: $dockExportRequest) { request in
            PortableDockExportSheet(profiles: request.profiles, selectedID: request.selectedID,
                                    includePersonalData: request.includePersonalData,
                                    close: { dockExportRequest = nil },
                                    exported: { message in backupMessage = message; dockExportRequest = nil })
        }
        .sheet(item: $dockImportPreview) { preview in
            PortableDockImportSheet(preview: preview, add: { addImportedDock(preview) }, cancel: { dockImportPreview = nil })
        }
        .onChange(of: selectedPage) { page in persistSettingsPage(page) }
        .onChange(of: store.state.settings.lastSettingsPage) { selectedPage = $0 }
        .sheet(item: $editingShortcutProfile) { profile in
            KeyboardShortcutEditor(profileID: profile.id,
                                   profileName: profile.name,
                                   bindings: shortcutBindings,
                                   controller: shortcutController) {
                editingShortcutProfile = nil
            }
        }
    }

    private func persistSettingsPage(_ page: MyDockSettingsPage) {
        guard store.state.settings.lastSettingsPage != page else { return }
        store.updateSettings { $0.lastSettingsPage = page }
    }
}
