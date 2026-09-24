import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var store: ProfileStore
    @State private var backupMessage: String?
    @State private var marketAPIKeyDraft = ""
    @State private var marketAPIKeySaved = false
    @State private var marketAPIKeyMessage: String?
    @State private var permissionRows: [PermissionOverviewRow] = []
    @State private var screenCaptureMessage: String?
    @State private var windowPreviewMessage: String?
    @ObservedObject private var nativeDockAutoSave = NativeDockAutoSaveMonitor.shared

    var body: some View {
        TabView {
            Form {
                Section("Dock setup") {
                    Picker("Mode", selection: Binding(get: { store.state.settings.setupMode }, set: { store.setSetupMode($0) })) {
                        ForEach(SetupMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    if store.state.settings.setupMode == .customMain {
                        if store.activeCustomProfile == nil {
                            Text("Select or create a Custom Dock profile first. Apple's Dock remains available until a Custom Dock profile is active.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("MyDock hides Apple's Dock while an active Custom Dock profile is the main Dock, then restores its previous auto-hide setting when you leave this mode or quit MyDock.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("macOS Dock profile", selection: Binding(get: { store.state.settings.activeNativeProfileID }, set: { id in
                        guard let id, let profile = store.nativeProfiles.first(where: { $0.id == id }) else {
                            store.updateSettings { $0.activeNativeProfileID = nil }
                            return
                        }
                        Task { @MainActor in
                            do {
                                try await NativeDockController.shared.apply(profile)
                                store.activate(id)
                            } catch {
                                backupMessage = error.localizedDescription
                            }
                        }
                    })) {
                        Text("No profile").tag(Optional<UUID>.none)
                        ForEach(store.nativeProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Custom Dock profile", selection: Binding(get: { store.state.settings.activeCustomProfileID }, set: { id in if let id { store.activate(id) } })) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(store.customProfiles) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Position", selection: Binding(get: { store.state.settings.customDockPosition }, set: { value in store.updateSettings { $0.customDockPosition = value } })) {
                        ForEach(DockPosition.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Display", selection: Binding(get: { store.state.settings.customDockDisplayID }, set: { value in
                        store.updateSettings { $0.customDockDisplayID = value }
                    })) {
                        Text("Main display").tag(Optional<UInt32>.none)
                        ForEach(displayOptions) { option in Text(option.title).tag(Optional(option.id)) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Size")
                            Spacer()
                            Text("\(Int(store.state.settings.customDockSize * 100))%").foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(get: { store.state.settings.customDockSize }, set: { value in
                            store.updateSettings { $0.customDockSize = value }
                        }), in: 0.65...1.5, step: 0.05)
                    }
                }
                Section("Focus filters") {
                    Text("In System Settings → Focus, choose a Focus, select Add Filter, then choose MyDock and a saved Dock profile. When that Focus turns off, MyDock leaves the last applied Dock selected.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Section("Native Dock switching") {
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
                                let accessRequestStarted = CGRequestScreenCaptureAccess()
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
                Section("Custom Dock") {
                    Text("Auto-hide, the reveal handle, desktop-widget placement, and an optional Trash item are available. Minimized-window actions and focused-app minimize require Accessibility access; window names stay on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("Appearance", selection: Binding(get: { store.state.settings.customDockMaterial }, set: { value in
                        store.updateSettings { $0.customDockMaterial = value }
                    })) {
                        ForEach(CustomDockMaterial.allCases) { material in Text(material.title).tag(material) }
                    }
                    if store.state.settings.customDockMaterial == .liquidGlass && !supportsLiquidGlass {
                        Text("Liquid Glass uses the standard frosted material on macOS versions before 26.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Use as desktop widget (behind windows)", isOn: Binding(get: { store.state.settings.customDockDesktopMode }, set: { value in store.updateSettings { $0.customDockDesktopMode = value } }))
                    Toggle("Automatically hide", isOn: Binding(get: { store.state.settings.automaticallyHideCustomDock }, set: { value in store.updateSettings { $0.automaticallyHideCustomDock = value } }))
                        .disabled(store.state.settings.customDockDesktopMode)
                    Toggle("Hide when Apple Dock appears", isOn: Binding(get: { store.state.settings.hideCustomDockWhenSystemDockAppears }, set: { value in store.updateSettings { $0.hideCustomDockWhenSystemDockAppears = value } }))
                    Text("When an on-screen Apple Dock overlaps MyDock, hide MyDock until the Apple Dock retracts. This reads window position only and does not capture screen contents.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.state.settings.customDockDesktopMode {
                        Text("Desktop-widget mode stays behind application windows and is not revealed over fullscreen apps. Auto-hide is paused while this mode is on.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
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
                                _ = CGRequestScreenCaptureAccess()
                                windowPreviewMessage = "Allow MyDock in System Settings → Privacy & Security → Screen Recording, then relaunch it."
                            } else {
                                windowPreviewMessage = "Visible windows will be captured while the Custom Dock is shown."
                            }
                        }
                    Text("Optional on macOS 14 and later. Captured window contents stay in memory and are never uploaded. Minimized windows use app icons when no matching preview is available.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let windowPreviewMessage {
                        Text(windowPreviewMessage).font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("Show Trash", isOn: Binding(get: { store.state.settings.showTrash }, set: { value in store.updateSettings { $0.showTrash = value } }))
                    Toggle("Show app badges", isOn: Binding(get: { store.state.settings.showAppBadges }, set: { value in store.updateSettings { $0.showAppBadges = value } }))
                        .disabled(true)
                    Text("macOS does not provide MyDock a public API to read other apps’ badge counts. This option stays unavailable; MyDock never reads notification contents.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
            }.padding(20).tabItem { Label("Dock", systemImage: "dock.rectangle") }
            Form {
                Section("Saved Docks") {
                    Text("Backups include saved profiles and widget settings. They do not include credentials, permissions, active selection, or global shortcuts.")
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
            }.padding(20).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Section("Permission status") {
                    Text("MyDock asks only when you use a feature that needs access. Automation approval is managed separately for each app MyDock controls.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(permissionRows) { row in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.name).font(.body.weight(.medium))
                                Text(row.status).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            if let settingsURL = row.settingsURL, let url = URL(string: settingsURL) {
                                Link("System Settings…", destination: url).font(.caption)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    HStack {
                        Button("Refresh Status") { Task { await refreshPermissionStatuses() } }
                        Spacer()
                        Text("Refresh after changing a permission.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .tabItem { Label("Permissions", systemImage: "hand.raised") }
            .task { await refreshPermissionStatuses() }
            Form {
                Section("Stripe") {
                    Text("Add Stripe from the widget picker, then open it to name and connect accounts. MyDock uses a restricted key with read access only to Balance and Subscriptions; it never asks for write access. Credentials stay in Keychain and are excluded from profile backups.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if let url = URL(string: "https://dockset.app/manual/stripe") {
                        Link("Stripe setup and metric definitions", destination: url)
                    }
                }
                Section("Market data") {
                    Text("Stock and Watchlist use Alpha Vantage's end-of-day market data. Create a personal API key on their website; free-tier request limits apply. The key is stored in this Mac's Keychain and is never included in backups.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    SecureField(marketAPIKeySaved ? "Key saved in Keychain" : "Alpha Vantage API key", text: $marketAPIKeyDraft)
                        .textFieldStyle(.roundedBorder)
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
                    if let marketAPIKeyMessage {
                        Text(marketAPIKeyMessage).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
            .padding(20)
            .tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }
            .onAppear {
                updateMarketAPIKeyState()
            }
        }
        .frame(width: 640, height: 560)
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MyDock-Backup.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try BackupManager.makeArchive(from: store.state.profiles)
            try data.write(to: url, options: .atomic)
            backupMessage = "Saved \(store.state.profiles.count) profile(s)."
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let report = try BackupManager.readArchive(data)
            store.importProfiles(report.importedProfiles)
            var message = "Restored \(report.importedProfiles.count) profile(s)."
            if !report.missingItems.isEmpty {
                message += " Missing apps or paths: " + report.missingItems.joined(separator: "; ")
            }
            backupMessage = message
        } catch {
            backupMessage = error.localizedDescription
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    private func refreshPermissionStatuses() async {
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        permissionRows = [
            PermissionOverviewRow(name: "Accessibility",
                                  status: WindowAccessibilityService.isTrusted() ? "Allowed — window controls are available." : "Not allowed — minimized-window controls are unavailable.",
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            PermissionOverviewRow(name: "Screen Recording",
                                  status: CGPreflightScreenCaptureAccess() ? "Allowed — the optional switch effect can capture displays." : "Not allowed — native Dock switches continue without the visual freeze.",
                                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"),
            PermissionOverviewRow(name: "Notifications",
                                  status: notificationStatus(notificationSettings.authorizationStatus),
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
            marketAPIKeyMessage = "Saved in Keychain. The Stock and Watchlist widgets can use it now."
        } catch {
            marketAPIKeyMessage = error.localizedDescription
        }
    }

    private func removeMarketAPIKey() {
        do {
            try MarketAPIKeyStore.delete()
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

private struct PermissionOverviewRow: Identifiable {
    var name: String
    var status: String
    var settingsURL: String?
    var id: String { name }
}

private struct DisplayOption: Identifiable {
    var id: UInt32
    var title: String
}
