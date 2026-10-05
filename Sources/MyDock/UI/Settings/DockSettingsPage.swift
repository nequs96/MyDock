import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var dockPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        // The page title already says "Dock Setup", so its first card has no heading of its own.
        GroupedSection {
            SettingsControlRow(title: "Mode") {
                Picker("Mode", selection: Binding(get: { store.state.settings.setupMode }, set: { store.setSetupMode($0) })) {
                    ForEach(SetupMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
            }
            GroupedRow("Show active profile name in menu bar", subtitle: "Both active Dock names appear beside the menu-bar icon.", isOn: Binding(
                get: { store.state.settings.showActiveProfileNameInMenuBar },
                set: { enabled in store.updateSettings { $0.showActiveProfileNameInMenuBar = enabled } }
            ))
            if store.state.settings.setupMode == .customMain {
                if store.activeCustomProfile == nil {
                    Text("Create or select a Custom Dock first; Apple’s Dock remains available until then.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("Apple’s Dock stays hidden; MyDock restores its settings on mode change or quit.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
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
                Text("Display disconnected: using the main display until it reconnects. Select Main display to stay there.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.id("Dock setup")
        GroupedSection("Focus filters", footer: FocusFilterAvailability.guidance()) {
            GroupedRow("Dock for each Focus", symbol: "moon.fill", color: .indigo,
                       value: FocusFilterAvailability.hasIntentMetadata() ? "Available" : "Unavailable")
        }.id("Focus filters")
        AutomaticSwitchingSettingsSection(store: store).id("Automatic switching")
        GroupedSection("Native Dock switching") {
            GroupedRow("Automatically save Dock changes", subtitle: "Saves Apple Dock edits to the selected profile, checking every five seconds.", isOn: Binding(
                get: { store.state.settings.automaticallySaveNativeDockChanges },
                set: { enabled in store.updateSettings { $0.automaticallySaveNativeDockChanges = enabled } }
            ))
            if store.state.settings.automaticallySaveNativeDockChanges,
               store.state.settings.activeNativeProfileID == nil {
                Text("Select a macOS Dock profile to start automatic saving.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let message = nativeDockAutoSave.errorMessage, store.state.settings.automaticallySaveNativeDockChanges {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            GroupedRow("Freeze desktop during Dock restart", subtitle: supportsScreenCaptureFreeze
                           ? "Holds one frame per display in memory. Switching works without Screen Recording."
                           : "Requires macOS 14 or later.", isOn: Binding(
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
            if let screenCaptureMessage {
                Text(screenCaptureMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.id("Native Dock switching")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
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

    private var displayOptions: [DisplayOption] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return DisplayOption(id: number.uint32Value, title: screen.localizedName)
        }
    }
}
