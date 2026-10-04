import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    @DockAccessibilityStyle() private var accessibility
    var embeddedInWorkspace = false
    var sidebarVisible = true
    @ObservedObject private var shortcutBindings = DockShortcutStore.shared
    @ObservedObject private var shortcutController = GlobalShortcutController.shared
    private let initialPage: MyDockSettingsPage?
    @State private var selectedPage: MyDockSettingsPage
    @State private var settingsSearch = ""
    @State private var advancedAppearanceExpanded = false
    @State private var appearanceProfileID: UUID?
    @State private var previousAppearance: SettingsAppearanceEditing.Undo?
    @State private var appearanceScopeMessage: String?
    @State private var diagnosticsPreview: DiagnosticsPreviewPayload?
    @State private var editingAppearanceContinuously = false
    @State private var editingShortcutProfile: DockProfile?
    @State private var backupMessage: String?
    @State private var includePersonalBackupData = true
    @State private var diagnosticsMessage: String?
    @State private var advancedExpanded = false
    @State private var marketConnectionExpanded = false
    @State private var copilotConnectionExpanded = false
    @State private var marketAPIKeyDraft = ""
    @State private var marketAPIKeySaved = false
    @State private var marketAPIKeyMessage: String?
    @State private var copilotUsernameDraft = ""
    @State private var copilotTokenDraft = ""
    @State private var copilotCredentialsSaved = false
    @State private var copilotCredentialsMessage: String?
    @State private var permissionRows: [PermissionOverviewRow] = []
    @State private var screenCaptureMessage: String?
    @State private var windowPreviewMessage: String?
    @State private var nativeProfileSwitchMessage: String?
    @State private var nativeProfileSwitchFailedID: UUID?
    @State private var nativeProfileSwitchTargetID: UUID?
    @State private var isApplyingNativeProfile = false
    @ObservedObject private var nativeDockAutoSave = NativeDockAutoSaveMonitor.shared
    @ObservedObject private var nativeDockVisibility = NativeDockAutoHideController.shared
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
            if !embeddedInWorkspace { HStack {
                Text("Settings").font(.title2.weight(.semibold))
                Spacer()
                Text("MyDock").font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            Divider() }
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
                    // The window header already names the page; only the embedded workspace needs a heading here.
                    if embeddedInWorkspace { Text("Settings").font(.system(size: 16, weight: .semibold)) }
                    // Keep every section visible, wrapping on narrow windows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 118, maximum: 180), spacing: 3, alignment: .leading)], alignment: .leading, spacing: 3) {
                            ForEach(MyDockSettingsPage.allCases) { page in
                                Button { selectedPage = page } label: {
                                    Label(page.title, systemImage: page.symbol)
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
                        Text("MyDock").font(.system(size: 11)).foregroundStyle(.secondary).padding(20)
                    }.frame(width: DockDesign.sidebarWidth).background(DockSidebarBackground())
                    Rectangle().fill(DockDesign.hairline).frame(width: 1)
                }
            ScrollViewReader { settingsProxy in
            if !settingsSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                SettingsSearchResults(query: settingsSearch) { result in
                    selectedPage = result.page
                    if result.title == "Corner roundness and tint" { advancedAppearanceExpanded = true }
                    settingsSearch = ""
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        settingsProxy.scrollTo(result.section, anchor: .top)
                    }
                }
            } else if selectedPage == .dock {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                DockSettingSection(title: "Dock setup") {
                    SettingsControlRow(title: "Mode") {
                        Picker("Mode", selection: Binding(get: { store.state.settings.setupMode }, set: { store.setSetupMode($0) })) {
                            ForEach(SetupMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                    }
                    Toggle("Show active profile name in menu bar", isOn: Binding(
                        get: { store.state.settings.showActiveProfileNameInMenuBar },
                        set: { enabled in store.updateSettings { $0.showActiveProfileNameInMenuBar = enabled } }
                    ))
                    Text("When both Docks are active, their profile names appear together beside the menu-bar icon.")
                        .font(.caption).foregroundStyle(.secondary)
                    if store.state.settings.setupMode == .customMain {
                        if store.activeCustomProfile == nil {
                            Text("Select or create a Custom Dock profile first. Apple's Dock remains available until a Custom Dock profile is active.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Apple’s Dock stays hidden when you move the pointer to the screen edge. MyDock restores your original Dock settings when you change modes or quit.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage = nativeDockVisibility.errorMessage {
                        HStack(alignment: .top, spacing: 10) {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button("Retry") {
                                let customMainRequested = store.state.settings.setupMode == .customMain
                                    && store.activeCustomProfile != nil
                                Task { @MainActor in
                                    if store.allowsSystemChanges { try? await nativeDockVisibility.setCustomDockMain(customMainRequested) }
                                }
                            }.controlSize(.small)
                        }
                    }
                    SettingsControlRow(title: "macOS Dock profile") {
                        Picker("macOS Dock profile", selection: Binding(
                            get: {
                                isApplyingNativeProfile
                                    ? nativeProfileSwitchTargetID
                                    : store.state.settings.activeNativeProfileID
                            },
                            set: { selectNativeProfile($0) }
                        )) {
                            Text("No profile").tag(Optional<UUID>.none)
                            ForEach(store.nativeProfiles) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    .disabled(isApplyingNativeProfile)
                    if isApplyingNativeProfile {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Applying \(store.nativeProfiles.first(where: { $0.id == nativeProfileSwitchTargetID })?.name ?? "macOS Dock profile")…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let nativeProfileSwitchMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(nativeProfileSwitchMessage)
                                .font(.caption)
                                .foregroundStyle(nativeProfileSwitchFailedID == nil ? Color.secondary : Color.orange)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                            if let nativeProfileSwitchFailedID {
                                Button("Retry") { selectNativeProfile(nativeProfileSwitchFailedID) }
                                    .controlSize(.small)
                                    .disabled(isApplyingNativeProfile)
                            }
                        }
                    }
                    SettingsControlRow(title: "Custom Dock profile") {
                        Picker("Custom Dock profile", selection: Binding(
                            get: { store.state.settings.activeCustomProfileID },
                            set: { store.setActiveCustomProfile($0) }
                        )) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(store.customProfiles) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    SettingsControlRow(title: "Position") {
                        Picker("Position", selection: Binding(get: { store.state.settings.customDockPosition }, set: { value in store.updateSettings { $0.customDockPosition = value } })) {
                            ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 220)
                    }
                    SettingsControlRow(title: "Display") {
                        Picker("Display", selection: Binding(get: { store.state.settings.customDockDisplayID }, set: { value in
                            store.updateSettings { $0.customDockDisplayID = value }
                        })) {
                            Text("Main display").tag(Optional<UInt32>.none)
                            ForEach(displayOptions) { option in Text(option.title).tag(Optional(option.id)) }
                            if let selectedID = store.state.settings.customDockDisplayID,
                               !displayOptions.contains(where: { $0.id == selectedID }) {
                                Text("Unavailable display (using main)").tag(Optional(selectedID))
                            }
                        }
                    }
                    if let selectedID = store.state.settings.customDockDisplayID,
                       !displayOptions.contains(where: { $0.id == selectedID }) {
                        Text("The selected display is disconnected. MyDock is showing on the main display and will return when it reconnects. Choose Main display to keep it there.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                DockSettingSection(title: "Focus filters") {
                    Text(FocusFilterAvailability.guidance())
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                DockSettingSection(title: "Native Dock switching") {
                    Toggle("Automatically save Dock changes", isOn: Binding(
                        get: { store.state.settings.automaticallySaveNativeDockChanges },
                        set: { enabled in store.updateSettings { $0.automaticallySaveNativeDockChanges = enabled } }
                    ))
                    Text("When enabled, changes you make directly in Apple's Dock update the selected macOS Dock profile. MyDock checks pinned apps and spacers every five seconds; turning this off stops the check.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.state.settings.automaticallySaveNativeDockChanges,
                       store.state.settings.activeNativeProfileID == nil {
                        Text("Select a macOS Dock profile to start automatic saving.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let message = nativeDockAutoSave.errorMessage, store.state.settings.automaticallySaveNativeDockChanges {
                        Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Toggle("Freeze desktop during Dock restart", isOn: Binding(
                        get: { store.state.settings.smoothNativeDockSwitches },
                        set: { enabled in
                            store.updateSettings { $0.smoothNativeDockSwitches = enabled }
                            screenCaptureMessage = nil
                            guard enabled else { return }
                            guard supportsScreenCaptureFreeze else {
                                screenCaptureMessage = "This visual effect requires macOS 14 or later."
                                return
                            }
                            if !CGPreflightScreenCaptureAccess() {
                                let accessRequestStarted = AppRuntimeEnvironment.allowsNativeEffects && CGRequestScreenCaptureAccess()
                                screenCaptureMessage = accessRequestStarted
                                    ? "Allow MyDock in System Settings → Privacy & Security → Screen Recording. Relaunch MyDock after granting access."
                                    : "Allow MyDock in System Settings → Privacy & Security → Screen Recording. Dock switching remains available without the effect."
                            } else {
                                screenCaptureMessage = "The desktop freeze will be used for the next native Dock switch."
                            }
                        }
                    ))
                    .disabled(!supportsScreenCaptureFreeze)
                    Text("Optional on macOS 14 and later. A one-frame image of each display stays in memory only while the Dock restarts. Without Screen Recording access, Dock switching still works without the visual effect.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let screenCaptureMessage {
                        Text(screenCaptureMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            } else if selectedPage == .appearance {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                DockSettingSection(title: "Appearance scope") {
                    SettingsControlRow(title: "Editing") {
                        Picker("Editing", selection: Binding(
                            get: { appearanceProfileID != nil },
                            set: { thisDock in
                                appearanceProfileID = thisDock ? store.activeCustomProfile?.id ?? store.customProfiles.first?.id : nil
                                appearanceScopeMessage = nil
                            })) {
                            Text("This Dock").tag(true).disabled(store.customProfiles.isEmpty)
                            Text("App defaults").tag(false)
                        }.pickerStyle(.segmented).frame(width: 240)
                    }
                    if appearanceProfileID != nil {
                        SettingsControlRow(title: "Dock") {
                            Picker("Dock to edit", selection: $appearanceProfileID) {
                                ForEach(store.customProfiles) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                    } else {
                        Text(store.customProfiles.isEmpty ? "Create a custom Dock to edit its appearance. You can edit app defaults now." : "Defaults apply to Docks that use inherited appearance. Saved Dock overrides and Dock colors stay as they are.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let appearanceScopeMessage { Text(appearanceScopeMessage).font(.caption).foregroundStyle(.secondary) }
                    if let id = appearanceProfileID {
                        Toggle("Use app defaults", isOn: Binding(
                            get: { store.customProfiles.first(where: { $0.id == id })?.appearance == nil },
                            set: { inherit in
                                rememberAppearance()
                                store.setAppearance(inherit ? nil : ProfileAppearance(settings: appearanceSettings), for: id)
                            }))
                        Text("This Dock can inherit app defaults or keep its full saved appearance. Editing a control creates a full Dock override.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if appearanceProfileID != nil {
                        Button("Reset to app defaults") {
                            guard let id = appearanceProfileID, store.customProfiles.contains(where: { $0.id == id }) else { return }
                            rememberAppearance(); store.setAppearance(nil, for: id)
                        }
                    } else {
                        Button("Reset app appearance defaults") {
                            updateAppearance { $0 = ProfileAppearance(settings: AppSettings()).applying(to: $0) }
                        }
                    }
                    if previousAppearance?.isAvailable(for: appearanceProfileID) == true {
                        Button("Undo last appearance change") { undoAppearance() }
                    }
                }
                DockSettingSection(title: "Preview") {
                    appearancePreview
                    Text("Widgets in this preview use sample data.").font(.caption).foregroundStyle(.secondary)
                }
                DockSettingSection(title: "Quick styles") {
                    Text("Choose a finish. Your Dock updates as you make changes.")
                        .font(.callout).foregroundStyle(.secondary)
                    HStack {
                        appearancePreset("Minimal", material: .solid, tint: 0.03)
                        appearancePreset("Soft frost", material: .frosted, tint: 0.06)
                        appearancePreset("Clear glass", material: .liquidGlassClear, tint: 0)
                        appearancePreset("Frosted glass", material: .liquidGlass, tint: 0.02)
                        appearancePreset("Midnight", material: .dark, tint: 0.10)
                    }
                    if let profile = appearanceProfileID.flatMap({ id in store.customProfiles.first { $0.id == id } }) {
                        SettingsControlRow(title: "Dock color") {
                            Picker("Dock color", selection: Binding(get: { DockProfileColor(rawValue: profile.color) ?? .blue }, set: { rememberAppearance(); store.setProfileColor(profile.id, to: $0) })) {
                                ForEach(DockProfileColor.allCases) { Text($0.title).tag($0) }
                            }
                        }
                    }
                }
                DockSettingSection(title: "Fine-tune appearance") {
                    SettingsControlRow(title: "Color theme") {
                        Picker("Color theme", selection: Binding(get: { appearanceSettings.customDockTheme }, set: { value in
                            updateAppearance { $0.customDockTheme = value }
                        })) {
                            ForEach(CustomDockTheme.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).frame(width: 220)
                    }
                    SettingsControlRow(title: "Appearance") {
                        Picker("Appearance", selection: Binding(get: { appearanceSettings.customDockMaterial }, set: { value in
                            updateAppearance { $0.customDockMaterial = value }
                        })) {
                            ForEach(CustomDockMaterial.allCases) { material in Text(material.title).tag(material) }
                        }
                    }
                    SettingsControlRow(title: "Widget defaults") {
                        Picker("Widget defaults", selection: Binding(get: { appearanceSettings.customDockWidgetStyle }, set: { value in
                            updateAppearance { $0.customDockWidgetStyle = value }
                        })) {
                            ForEach(CustomDockWidgetStyle.allCases) { style in Text(style.title).tag(style) }
                        }
                    }
                    if [.liquidGlass, .liquidGlassClear].contains(appearanceSettings.customDockMaterial) {
                        SettingsControlRow(title: "Glass finish") {
                            Picker("Glass finish", selection: Binding(get: { appearanceSettings.customDockMaterial }, set: { value in
                                updateAppearance { $0.customDockMaterial = value }
                            })) {
                                Text("Clear").tag(CustomDockMaterial.liquidGlassClear)
                                Text("Frosted").tag(CustomDockMaterial.liquidGlass)
                            }.pickerStyle(.segmented).frame(width: 220)
                        }
                        HStack {
                            Text("Glass opacity")
                            Spacer()
                            Text("\(Int((appearanceSettings.customDockGlassOpacity * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { appearanceSettings.customDockGlassOpacity }, set: { value in
                            updateAppearance { $0.customDockGlassOpacity = value }
                        }), in: 0...1).accessibilityLabel("Glass opacity")
                        HStack { Text("Clear"); Spacer(); Text("Opaque") }.font(.caption).foregroundStyle(.secondary)
                        Text("Keep more wallpaper visible, or give icons a quieter background. Tint strength adjusts the color separately.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Configure each widget’s layout and icon separately. Side Docks use a narrow presentation.")
                        .font(.caption).foregroundStyle(.secondary)
                    if [.liquidGlass, .liquidGlassClear].contains(appearanceSettings.customDockMaterial) && !supportsLiquidGlass {
                        Text("Liquid Glass uses the standard frosted material on macOS versions before 26.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    visualStyleControls
                }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            } else if selectedPage == .behavior {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                DockSettingSection(title: "Custom Dock behavior") {
                    Toggle("Use as desktop widget (behind windows)", isOn: Binding(get: { store.state.settings.customDockDesktopMode }, set: { value in store.updateSettings { $0.customDockDesktopMode = value } }))
                    Toggle("Automatically hide", isOn: Binding(get: { store.state.settings.automaticallyHideCustomDock }, set: { value in store.updateSettings { $0.automaticallyHideCustomDock = value } }))
                        .disabled(store.state.settings.customDockDesktopMode)
                    Toggle("Show reveal handle while hidden", isOn: Binding(
                        get: { store.state.settings.showRevealHandle },
                        set: { value in store.updateSettings { $0.showRevealHandle = value } }
                    ))
                    .disabled(!store.state.settings.automaticallyHideCustomDock || store.state.settings.customDockDesktopMode)
                    Text("Turning off the handle keeps the screen edge active so the Dock can still be revealed.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Hide when Apple Dock appears", isOn: Binding(get: { store.state.settings.hideCustomDockWhenSystemDockAppears }, set: { value in store.updateSettings { $0.hideCustomDockWhenSystemDockAppears = value } }))
                    Text("When an on-screen Apple Dock overlaps MyDock, hide MyDock until the Apple Dock retracts. This reads window position only and does not capture screen contents.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.state.settings.customDockDesktopMode {
                        Text("Desktop-widget mode stays behind application windows and is not revealed over fullscreen apps. Auto-hide is paused while this mode is on.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                DockSettingSection(title: "Apps and windows") {
                    Toggle("Show running apps", isOn: Binding(get: { store.state.settings.showRunningApps }, set: { value in store.updateSettings { $0.showRunningApps = value } }))
                    Toggle("Show minimized windows", isOn: Binding(get: { store.state.settings.showMinimizedWindows }, set: { value in store.updateSettings { $0.showMinimizedWindows = value } }))
                        .onChange(of: store.state.settings.showMinimizedWindows) { enabled in
                            if enabled { _ = WindowAccessibilityService.requestAccessPrompt() }
                        }
                    Toggle("Cache window previews", isOn: Binding(get: { store.state.settings.showWindowPreviews }, set: { value in store.updateSettings { $0.showWindowPreviews = value } }))
                        .disabled(!store.state.settings.showMinimizedWindows || !supportsScreenCaptureFreeze)
                        .onChange(of: store.state.settings.showWindowPreviews) { enabled in
                            guard enabled else { windowPreviewMessage = nil; return }
                            if !CGPreflightScreenCaptureAccess() {
                                if AppRuntimeEnvironment.allowsNativeEffects { _ = CGRequestScreenCaptureAccess() }
                                windowPreviewMessage = "Allow MyDock in System Settings → Privacy & Security → Screen Recording, then relaunch it."
                            } else {
                                windowPreviewMessage = "Visible windows will be captured while the Custom Dock is shown."
                            }
                        }
                    Text("Optional on macOS 14 and later. Unique window previews are stored locally for up to 24 hours, never uploaded, and deleted when this setting is disabled. Duplicate, expired, or unavailable previews use the app icon.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let windowPreviewMessage {
                        Text(windowPreviewMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }
                DockSettingSection(title: "Dock items") {
                    Toggle("Show Trash", isOn: Binding(get: { store.state.settings.showTrash }, set: { value in store.updateSettings { $0.showTrash = value } }))
                    Toggle("Show app badges", isOn: Binding(get: { store.state.settings.showAppBadges }, set: { value in store.updateSettings { $0.showAppBadges = value } }))
                        .disabled(!DockBadgeReader.isSupported)
                        .onChange(of: store.state.settings.showAppBadges) { enabled in
                            if enabled && !WindowAccessibilityService.isTrusted() {
                                _ = WindowAccessibilityService.requestAccessPrompt()
                            }
                        }
                    Text(DockBadgeReader.isSupported
                         ? "Reads only badge labels exposed by the Apple Dock through Accessibility. Some apps or macOS versions may not expose a label. Notification contents are never read."
                         : "App badge labels require macOS 14 or later.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if DockBadgeReader.isSupported, store.state.settings.showAppBadges,
                       !WindowAccessibilityService.isTrusted() {
                        HStack {
                            Text("Allow MyDock under Privacy & Security → Accessibility to show badge labels.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Accessibility Settings…", action: openAccessibilitySettings)
                                .controlSize(.small)
                        }
                    }
                }
                DockSettingSection(title: "Interaction") {
                    Toggle("Click focused app to minimize", isOn: Binding(get: { store.state.settings.clickFocusedAppToMinimize }, set: { value in store.updateSettings { $0.clickFocusedAppToMinimize = value } }))
                        .onChange(of: store.state.settings.clickFocusedAppToMinimize) { enabled in
                            if enabled { _ = WindowAccessibilityService.requestAccessPrompt() }
                        }
                    HStack {
                        Text(WindowAccessibilityService.isTrusted() ? "Accessibility access is enabled." : "Accessibility access is needed for window controls.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Accessibility Settings…", action: openAccessibilitySettings)
                    }
                    Toggle("Magnification", isOn: Binding(get: { store.state.settings.magnificationEnabled }, set: { value in store.updateSettings { $0.magnificationEnabled = value } }))
                }
                DockSettingSection(title: "Dock animations") {
                    Toggle("Animate Dock appearance", isOn: Binding(get: { store.state.settings.dockAnimationsEnabled }, set: { value in store.updateSettings { $0.dockAnimationsEnabled = value } }))
                    SettingsControlRow(title: "Reveal effect") {
                        Picker("Reveal effect", selection: Binding(get: { store.state.settings.dockAnimationStyle }, set: { value in store.updateSettings { $0.dockAnimationStyle = value } })) {
                            ForEach(DockAnimationStyle.allCases) { Text($0.title).tag($0) }
                        }.disabled(!store.state.settings.dockAnimationsEnabled)
                    }
                    Text("Used when the Dock appears or hides. Reduce Motion in macOS turns these effects off.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Preview animation", systemImage: "play.fill") {
                        NotificationCenter.default.post(name: CustomDockWindowController.animationPreviewNotification, object: store)
                    }.disabled(!store.state.settings.dockAnimationsEnabled || store.state.settings.setupMode == .nativeOnly || store.activeCustomProfile == nil)
                }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            } else if selectedPage == .general {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                AppLifecycleSettingsView()
                RecoveryCenterView(store: store, history: store.history)
                DockSettingSection(title: "Saved Docks") {
                    Toggle("Include personal widget data", isOn: $includePersonalBackupData)
                    Text(includePersonalBackupData
                         ? "Includes notes, checklists, snippets, shelf files, histories, timers, alarms and saved selections. Keep this file private. Credentials, permissions and cached provider readings are always excluded."
                         : "Layout only: notes, checklists, snippets, histories, timers, alarms, local calendar selections and connection assignments are removed. App, file, folder, and link locations remain in the layout. Cached provider readings are never included.")
                        .font(DockDesign.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Back Up…") { exportBackup() }
                        Button("Restore…") { importBackup() }
                    }
                    if let backupMessage { Text(backupMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                    HStack {
                        Text("macOS Dock profiles")
                        Spacer()
                        Text("\(store.nativeProfiles.count)").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Custom Dock profiles")
                        Spacer()
                        Text("\(store.customProfiles.count)").foregroundStyle(.secondary)
                    }
                }
                PrivacyHelpSection()
                DisclosureGroup("Advanced", isExpanded: $advancedExpanded) {
                DockSettingSection(title: "Diagnostics") {
                    Text("Export a redacted status report for troubleshooting. It contains app and macOS versions, item counts, appearance choices, save status, and recent event codes. It excludes profile names, app and file paths, URLs, note text, calendar content, credentials, and window images.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Export Diagnostics…") { exportDiagnostics() }
                    if let diagnosticsMessage {
                        Text(diagnosticsMessage).font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            } else if selectedPage == .shortcuts {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                    DockSettingSection(title: "Global profile shortcuts") {
                        Text("Assign a keyboard shortcut to switch to any saved macOS Dock or Custom Dock profile. Shortcuts work while MyDock is in the background, require at least two modifiers, and are stored only on this Mac.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if store.state.profiles.isEmpty {
                            Text("Create a Dock profile in Manage Docks to assign a shortcut.")
                                .font(.callout).foregroundStyle(.secondary)
                        } else {
                            ForEach(store.state.profiles) { profile in
                                SettingsShortcutRow(
                                    profile: profile,
                                    shortcut: shortcutBindings.shortcut(for: profile.id),
                                    registrationMessage: shortcutController.statusMessages[profile.id],
                                    edit: {
                                        editingShortcutProfile = profile
                                    }
                                )
                            }
                        }
                    }
                    DockSettingSection(title: "Shortcut privacy") {
                        Text("Shortcuts are excluded from profile backups because key combinations are local to this Mac. MyDock shows a warning beside any shortcut the system could not register.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            } else if selectedPage == .permissions {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                DockSettingSection(title: "Permission status") {
                    Text("MyDock asks only when you use a feature that needs access. Automation approval is managed separately for each app MyDock controls.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(permissionRows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: row.symbol).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.name).font(.system(size: 13, weight: .medium))
                                Text(row.explanation).font(DockDesign.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            HStack(spacing: 12) {
                                Label(row.summary, systemImage: row.granted ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 11)).foregroundStyle(row.granted ? Color.green : Color.secondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                if let settingsURL = row.settingsURL, let url = URL(string: settingsURL) {
                                    Link("Open Settings", destination: url).buttonStyle(DockButtonStyle())
                                        .fixedSize(horizontal: true, vertical: false)
                                }
                            }.frame(width: 230)
                        }.padding(.vertical, 8)
                        if row.id != permissionRows.last?.id { Divider() }
                    }
                    HStack {
                        Button("Refresh Status") { Task { await refreshPermissionStatuses() } }
                        Spacer()
                        Text("Refresh after changing a permission.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            .task { await refreshPermissionStatuses() }
            } else if selectedPage == .integrations {
            DockScrollView {
                VStack(alignment: .leading, spacing: 20) {
                SettingsPageHeader(page: selectedPage)
                DockSettingSection(title: "AI accounts on this Mac") {
                    Text("MyDock finds existing Codex and Claude Code accounts automatically. Sign in with the provider to connect a new account.")
                        .font(DockDesign.caption).foregroundStyle(.secondary)
                    AIAccountConnectionView(provider: .codex, allowsAccountActions: store.allowsSystemChanges)
                    AIAccountConnectionView(provider: .claude, allowsAccountActions: store.allowsSystemChanges, showsLimitsSetup: true)
                }
                ConnectionsCenterView(store: store)
                PrivacyHelpSection()
                DockSettingSection(title: "Market data") {
                    integrationSummary("Alpha Vantage", symbol: "chart.line.uptrend.xyaxis", connected: marketAPIKeySaved)
                    DisclosureGroup("Manage API key", isExpanded: $marketConnectionExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("Stock and Watchlist use Alpha Vantage's end-of-day market data. Create a personal API key on their website; free-tier request limits apply. The key is stored in this Mac's Keychain and is never included in backups.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SecureField(marketAPIKeySaved ? "Key saved in Keychain" : "Alpha Vantage API key", text: $marketAPIKeyDraft)
                        .textFieldStyle(DockTextFieldStyle())
                    HStack {
                        Button("Save Key") { saveMarketAPIKey() }
                            .disabled(marketAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove Key", role: .destructive) { removeMarketAPIKey() }
                            .disabled(!marketAPIKeySaved)
                        Spacer()
                        if let url = URL(string: "https://www.alphavantage.co/support/#api-key") {
                            Link("Get a key", destination: url)
                        }
                    }
                    }.padding(.top, 12)
                    }
                    if let marketAPIKeyMessage {
                        Text(marketAPIKeyMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                DockSettingSection(title: "GitHub Copilot usage") {
                    integrationSummary("GitHub Copilot", symbol: "sparkles", connected: copilotCredentialsSaved)
                    DisclosureGroup("Manage credentials", isExpanded: $copilotConnectionExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("Connect a personal Copilot plan to show AI-credit usage in AI Limits. MyDock uses GitHub's read-only billing endpoint. Organization or enterprise billed usage is not included. The fine-grained token needs Plan: read access; the secret stays in this Mac's Keychain and is excluded from profiles and backups.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("GitHub username", text: $copilotUsernameDraft)
                        .textFieldStyle(DockTextFieldStyle())
                        .textContentType(.username)
                        .autocorrectionDisabled()
                    SecureField(copilotCredentialsSaved ? "Replace saved fine-grained token" : "Fine-grained personal access token",
                                text: $copilotTokenDraft)
                        .textFieldStyle(DockTextFieldStyle())
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    HStack {
                        Button(copilotCredentialsSaved ? "Update Credentials" : "Save Credentials") {
                            saveCopilotCredentials()
                        }
                        .disabled(copilotTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  !GitHubCopilotUsernamePolicy.isValid(copilotUsernameDraft))
                        Button("Remove Credentials", role: .destructive) { removeCopilotCredentials() }
                            .disabled(!copilotCredentialsSaved)
                        Spacer()
                        if let url = URL(string: "https://github.com/settings/personal-access-tokens/new") {
                            Link("Create token", destination: url)
                        }
                    }
                    }.padding(.top, 12)
                    }
                    if let copilotCredentialsMessage {
                        Text(copilotCredentialsMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                updateMarketAPIKeyState()
                updateCopilotCredentialState()
            }
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

    private func integrationSummary(_ title: String, symbol: String, connected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 24)
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            Text(connected ? "Connected" : "Not connected").font(DockDesign.caption).foregroundStyle(.secondary)
        }.frame(minHeight: 32)
    }

    private func persistSettingsPage(_ page: MyDockSettingsPage) {
        guard store.state.settings.lastSettingsPage != page else { return }
        store.updateSettings { $0.lastSettingsPage = page }
    }

    private var appearancePreview: some View {
        var profile = appearanceProfileID.flatMap { id in store.customProfiles.first { $0.id == id } }
            ?? DockProfile(name: "Preview", kind: .custom, items: [.widget("Clock"), .widget("Weather"), .widget("Sticky Note")])
        profile.appearance = ProfileAppearance(settings: appearanceSettings)
        return DockLayoutPreview(store: store, profile: profile, maximumSideLength: 180, usesLiveData: false)
            .accessibilityLabel("Dock appearance preview, sample data")
    }

    private var appearanceSettings: AppSettings {
        appearanceProfileID.map { store.effectiveSettings(profileID: $0) } ?? store.state.settings
    }

    private func rememberAppearance() {
        previousAppearance = SettingsAppearanceEditing.capture(in: store, profileID: appearanceProfileID)
    }

    private func updateAppearance(immediately: Bool = false, _ change: (inout AppSettings) -> Void) {
        if !editingAppearanceContinuously { rememberAppearance() }
        SettingsAppearanceEditing.update(in: store, profileID: appearanceProfileID, immediately: immediately,
                                         recordHistory: !editingAppearanceContinuously, change: change)
    }

    private func appearanceSliderEditingChanged(_ editing: Bool) {
        if editing {
            rememberAppearance()
            if let id = appearanceProfileID, let profile = store.customProfiles.first(where: { $0.id == id }) {
                store.history.record(profile, reason: "Before appearance edit")
            }
        } else { store.flush() }
        editingAppearanceContinuously = editing
    }

    private func undoAppearance() {
        previousAppearance?.restore(in: store, editingProfileID: appearanceProfileID)
        previousAppearance = nil
    }

    private func appearancePreset(_ title: String, material: CustomDockMaterial, tint: Double) -> some View {
        let previewColor = SettingsAppearanceEditing.previewColor(profiles: store.customProfiles, profileID: appearanceProfileID)
        let backdrop: [Color] = previewColor == nil
            ? [Color(white: 0.38), Color(white: 0.62)]
            : [Color(red: 0.35, green: 0.48, blue: 0.66), Color(red: 0.66, green: 0.52, blue: 0.40)]
        var previewSettings = appearanceSettings
        previewSettings.customDockMaterial = material
        previewSettings.customDockTintStrength = tint
        previewSettings.customDockGlassOpacity = material == .liquidGlass ? 0.15 : 0
        previewSettings.customDockCornerRadius = 9
        return Button {
            updateAppearance {
                $0.customDockMaterial = material
                $0.customDockTintStrength = tint
                $0.customDockGlassOpacity = material == .liquidGlass ? 0.15 : 0
                $0.customDockCornerRadius = 22
            }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    // A visible backdrop makes the material's clarity legible.
                    LinearGradient(colors: backdrop, startPoint: .topLeading, endPoint: .bottomTrailing)
                    DockMaterialSurface(settings: previewSettings, color: previewColor?.displayColor ?? .gray).padding(3)
                    HStack(spacing: 5) {
                        ForEach(["folder.fill", "clock.fill", "calendar"], id: \.self) { symbol in
                            Image(systemName: symbol).font(.system(size: 13))
                                .foregroundStyle(material == .dark ? Color.white.opacity(0.9) : Color.primary.opacity(0.8))
                                .frame(width: 20, height: 24)
                        }
                    }
                }.frame(height: 43).clipShape(RoundedRectangle(cornerRadius: 9))
                Text(title).font(.system(size: 10, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
            }.padding(7).frame(maxWidth: .infinity)
                .background(appearanceSettings.customDockMaterial == material ? DockDesign.accent.opacity(0.06) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10)
                    .stroke(appearanceSettings.customDockMaterial == material ? DockDesign.accent : DockDesign.Outline.color(accessibility.contrast),
                            lineWidth: appearanceSettings.customDockMaterial == material ? 1.5 : DockDesign.Outline.controlWidth(accessibility.contrast)))
        }
        .buttonStyle(.plain).accessibilityLabel(title)
        .accessibilityAddTraits(appearanceSettings.customDockMaterial == material ? .isSelected : [])
    }

    private var visualStyleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            HStack {
                Text("Density")
                Spacer()
                Text(selectedDensity?.title ?? "Custom").foregroundStyle(.secondary)
            }
            Picker("Density", selection: Binding(get: { selectedDensity }, set: { preset in
                guard let preset else { return }
                updateAppearance { $0.customDockSize = preset.size; $0.customDockItemSpacing = preset.spacing }
            })) {
                if selectedDensity == nil { Text("Custom").tag(Optional<DockDensityPreset>.none) }
                ForEach(DockDensityPreset.allCases) { preset in Text(preset.title).tag(Optional(preset)) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Tile size")
                Spacer()
                Text("\(Int((appearanceSettings.customDockSize * 100).rounded()))%").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { appearanceSettings.customDockSize }, set: { value in
                updateAppearance(immediately: false) { $0.customDockSize = value }
            }), in: 0.65...1.5, onEditingChanged: appearanceSliderEditingChanged)
            HStack {
                Text("Item spacing")
                Spacer()
                Text("\(Int(appearanceSettings.customDockItemSpacing)) pt").foregroundStyle(.secondary)
            }
            Slider(value: Binding(get: { appearanceSettings.customDockItemSpacing }, set: { value in
                updateAppearance(immediately: false) { $0.customDockItemSpacing = value }
            }), in: DockAppearanceBounds.itemSpacing, step: 1, onEditingChanged: appearanceSliderEditingChanged)
            DisclosureGroup("Advanced appearance", isExpanded: $advancedAppearanceExpanded) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Corner roundness")
                        Spacer()
                        Text("\(Int(appearanceSettings.customDockCornerRadius)) pt").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { appearanceSettings.customDockCornerRadius }, set: { value in
                        updateAppearance(immediately: false) { $0.customDockCornerRadius = value }
                    }), in: DockAppearanceBounds.cornerRadius, step: 1, onEditingChanged: appearanceSliderEditingChanged)
                    HStack {
                        Text("Profile tint")
                        Spacer()
                        Text("\(Int((appearanceSettings.customDockTintStrength * 100).rounded()))%").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { appearanceSettings.customDockTintStrength }, set: { value in
                        updateAppearance(immediately: false) { $0.customDockTintStrength = value }
                    }), in: DockAppearanceBounds.tintStrength, step: 0.01, onEditingChanged: appearanceSliderEditingChanged)
                }.padding(.top, 12)
            }
            Button("Restore appearance defaults") {
                updateAppearance {
                    $0.customDockSize = 1
                    $0.customDockItemSpacing = 8
                    $0.customDockCornerRadius = 24
                    $0.customDockTintStrength = 0.08
                    $0.customDockWidgetStyle = .cards
                    $0.showWidgetLabels = true
                    $0.customDockMaterial = .frosted
                }
            }
            .font(.caption)
        }
    }

    private var selectedDensity: DockDensityPreset? {
        DockDensityPreset.allCases.first {
            abs(appearanceSettings.customDockSize - $0.size) < 0.001
                && abs(appearanceSettings.customDockItemSpacing - $0.spacing) < 0.001
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MyDock-Backup.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let profiles = includePersonalBackupData ? store.state.profiles : store.state.profiles.map { ProfileSanitizer.sanitize($0) }
            let data = try BackupManager.makeArchive(from: profiles)
            try data.write(to: url, options: .atomic)
            backupMessage = "Saved \(store.state.profiles.count) profile(s)."
            DiagnosticsService.shared.record(.backupExported)
        } catch {
            backupMessage = error.localizedDescription
            DiagnosticsService.shared.record(.backupOperationFailed)
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let report = try BackupManager.readArchive(from: url)
            try store.importProfiles(report.importedProfiles)
            var message = "Restored \(report.importedProfiles.count) profile(s)."
            if !report.missingItems.isEmpty {
                message += " Missing apps or paths: " + report.missingItems.joined(separator: "; ")
            }
            backupMessage = message
            DiagnosticsService.shared.record(.backupImported)
        } catch {
            backupMessage = error.localizedDescription
            DiagnosticsService.shared.record(.backupOperationFailed)
        }
    }

    private func exportDiagnostics() {
        do {
            diagnosticsPreview = DiagnosticsPreviewPayload(data: try DiagnosticsService.shared.reportData(for: store))
            diagnosticsMessage = nil
        } catch {
            diagnosticsMessage = "Could not prepare diagnostics: \(error.localizedDescription)"
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func refreshPermissionStatuses() async {
        let notificationSettings = AppRuntimeEnvironment.allowsNativeEffects
            ? await UNUserNotificationCenter.current().notificationSettings() : nil
        permissionRows = [
            PermissionOverviewRow(name: "Accessibility",
                                  status: WindowAccessibilityService.isTrusted() ? "Allowed — window controls are available." : "Not allowed — minimized-window controls are unavailable.",
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            PermissionOverviewRow(name: "Screen Recording",
                                  status: CGPreflightScreenCaptureAccess() ? "Allowed — the optional switch effect can capture displays." : "Not allowed — native Dock switches continue without the visual freeze.",
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            PermissionOverviewRow(name: "Notifications",
                                  status: notificationSettings.map { notificationStatus($0.authorizationStatus) } ?? "Unavailable in this isolated run.",
                                  settingsURL: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"),
            PermissionOverviewRow(name: "Calendar",
                                  status: eventStatus(EKEventStore.authorizationStatus(for: .event)),
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"),
            PermissionOverviewRow(name: "Reminders",
                                  status: eventStatus(EKEventStore.authorizationStatus(for: .reminder)),
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"),
            PermissionOverviewRow(name: "Location",
                                  status: locationStatus(CLLocationManager().authorizationStatus),
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"),
            PermissionOverviewRow(name: "Automation",
                                  status: "Per-app approval; MyDock cannot read a universal status. A prompt appears when you use Now Playing or confirm Empty Trash.",
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        ]
        DiagnosticsService.shared.record(.permissionStatusRefreshed)
    }

    private func notificationStatus(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not requested — alarms, countdowns, and hydration reminders ask when enabled."
        case .denied: "Denied — scheduled alerts will not appear."
        case .authorized, .provisional, .ephemeral: "Allowed — scheduled alerts can appear."
        @unknown default: "Status unavailable."
        }
    }

    private func eventStatus(_ status: EKAuthorizationStatus) -> String {
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return "Full access allowed." }
            if status == .writeOnly { return "Write-only access; MyDock needs read access for this widget." }
        }
        return switch status {
        case .notDetermined: "Not requested — access is requested when the widget opens."
        case .restricted: "Restricted by macOS or device policy."
        case .denied: "Denied — open System Settings to allow access."
        default: "Allowed."
        }
    }

    private func locationStatus(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "Not requested — only the Weather current-location action asks."
        case .restricted: "Restricted by macOS or device policy."
        case .denied: "Denied — city search still works without location access."
        case .authorizedAlways, .authorized: "Allowed."
        case .authorizedWhenInUse: "Allowed while using MyDock."
        @unknown default: "Status unavailable."
        }
    }

    private func updateMarketAPIKeyState() {
        do {
            marketAPIKeySaved = try MarketAPIKeyStore.read() != nil
            if marketAPIKeySaved { marketAPIKeyMessage = "The key is saved locally in Keychain." }
        } catch {
            marketAPIKeySaved = false
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    private func updateCopilotCredentialState() {
        do {
            let credentials = try GitHubCopilotCredentialStore.read()
            copilotCredentialsSaved = credentials != nil
            copilotUsernameDraft = credentials?.username ?? ""
            if copilotCredentialsSaved {
                copilotCredentialsMessage = "Personal GitHub credentials are saved in this Mac's Keychain."
            }
        } catch {
            copilotCredentialsSaved = false
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    private func saveCopilotCredentials() {
        do {
            try GitHubCopilotCredentialStore.write(username: copilotUsernameDraft, token: copilotTokenDraft)
            store.invalidateCopilotLimitReadings()
            copilotTokenDraft = ""
            copilotCredentialsSaved = true
            copilotCredentialsMessage = "Saved in Keychain. AI Limits can now read personal Copilot billing usage."
        } catch {
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    private func removeCopilotCredentials() {
        do {
            try GitHubCopilotCredentialStore.delete()
            store.invalidateCopilotLimitReadings()
            copilotTokenDraft = ""
            copilotCredentialsSaved = false
            copilotCredentialsMessage = "Removed from Keychain."
        } catch {
            copilotCredentialsMessage = error.localizedDescription
        }
    }

    private var supportsScreenCaptureFreeze: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    private var supportsLiquidGlass: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    private func saveMarketAPIKey() {
        let key = marketAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try MarketAPIKeyStore.write(key)
            marketAPIKeyDraft = ""
            marketAPIKeySaved = true
            store.widgetData.connectionsDidChange()
            marketAPIKeyMessage = "Saved in Keychain. The Stock and Watchlist widgets can use it now."
        } catch {
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    private func selectNativeProfile(_ id: UUID?) {
        guard store.allowsSystemChanges else { nativeProfileSwitchMessage = "Native Dock changes are disabled in the visual preview."; return }
        guard !isApplyingNativeProfile else { return }
        nativeProfileSwitchMessage = nil
        nativeProfileSwitchFailedID = nil
        guard let id else {
            store.updateSettings { $0.activeNativeProfileID = nil }
            return
        }
        guard let profile = store.nativeProfiles.first(where: { $0.id == id }) else {
            nativeProfileSwitchFailedID = nil
            nativeProfileSwitchMessage = "That macOS Dock profile is no longer available. Refresh the profile list and try again."
            return
        }

        isApplyingNativeProfile = true
        nativeProfileSwitchTargetID = id
        Task { @MainActor in
            defer {
                isApplyingNativeProfile = false
                nativeProfileSwitchTargetID = nil
            }
            do {
                try await NativeDockController.shared.apply(profile)
                store.recordAppliedNativeProfile(id)
                nativeProfileSwitchMessage = "Applied “\(profile.name)”."
            } catch {
                nativeProfileSwitchFailedID = id
                nativeProfileSwitchMessage = "Could not apply “\(profile.name)”: \(error.localizedDescription)"
            }
        }
    }

    private func removeMarketAPIKey() {
        do {
            try MarketAPIKeyStore.delete()
            store.widgetData.connectionsDidChange()
            marketAPIKeyDraft = ""
            marketAPIKeySaved = false
            marketAPIKeyMessage = "Removed from Keychain."
        } catch {
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    private var displayOptions: [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayOption(id: number.uint32Value, title: screen.localizedName)
        }
    }
}

private enum DockDensityPreset: String, CaseIterable, Identifiable {
    case compact
    case balanced
    case comfortable

    var id: Self { self }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .balanced: "Balanced"
        case .comfortable: "Comfortable"
        }
    }

    var size: Double {
        switch self {
        case .compact: 0.85
        case .balanced: 1
        case .comfortable: 1.1
        }
    }

    var spacing: Double {
        switch self {
        case .compact: 5
        case .balanced: 8
        case .comfortable: 10
        }
    }
}

private struct PermissionOverviewRow: Identifiable {
    var name: String
    var status: String
    var settingsURL: String?
    var id: String { name }
    var granted: Bool { status.hasPrefix("Allowed") || status.hasPrefix("Full access") }
    var summary: String {
        if granted { return "Granted" }
        if status.hasPrefix("Not requested") { return "Not requested" }
        if status.hasPrefix("Per-app") { return "Per-app" }
        return "Not granted"
    }
    var explanation: String { status.components(separatedBy: " — ").last ?? status }
    var symbol: String {
        switch name {
        case "Accessibility": "accessibility"; case "Screen Recording": "rectangle.on.rectangle"
        case "Notifications": "bell"; case "Calendar": "calendar"; case "Reminders": "checklist"
        case "Location": "location"; default: "gearshape.2"
        }
    }
}

private struct SettingsShortcutRow: View {
    var profile: DockProfile
    var shortcut: DockShortcut?
    var registrationMessage: String?
    var edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(profile.kind.title).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(shortcut?.displayString ?? "—").font(.system(size: 13, weight: .medium).monospaced())
                    .foregroundStyle(shortcut == nil ? Color.secondary : Color.primary)
                    .padding(.horizontal, 10).frame(minWidth: 80, minHeight: 28)
                    .background(DockDesign.input, in: RoundedRectangle(cornerRadius: 6))
                Button(shortcut == nil ? "Set…" : "Change…", action: edit)
                    .accessibilityLabel("\(shortcut == nil ? "Set" : "Edit") keyboard shortcut for \(profile.name)")
            }.frame(minHeight: 40)
            if let registrationMessage {
                Label(registrationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(DockDesign.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4)
    }

}

private struct DisplayOption: Identifiable {
    var id: UInt32
    var title: String
}
