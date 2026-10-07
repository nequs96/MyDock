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
            GroupedRow("Show active Dock name in menu bar", subtitle: "Both active Dock names appear beside the menu-bar icon.", isOn: Binding(
                get: { store.state.settings.showActiveProfileNameInMenuBar },
                set: { enabled in store.updateSettings { $0.showActiveProfileNameInMenuBar = enabled } }
            ))
            if store.state.settings.setupMode == .customMain {
                if store.activeCustomProfile == nil {
                    GroupedNote("Create or select a Custom Dock first; Apple’s Dock remains available until then.")
                } else {
                    GroupedNote("Apple’s Dock stays hidden; MyDock restores its settings on mode change or quit.")
                }
            }
            if let errorMessage = nativeDockVisibility.errorMessage {
                GroupedNote(errorMessage, tone: .warning, actionTitle: "Retry") {
                    let customMainRequested = store.state.settings.setupMode == .customMain
                        && store.activeCustomProfile != nil
                    Task { @MainActor in
                        if store.allowsSystemChanges { try? await nativeDockVisibility.setCustomDockMain(customMainRequested) }
                    }
                }
            }
            SettingsControlRow(title: "macOS Dock") {
                Picker("macOS Dock", selection: Binding(
                    get: {
                        isApplyingNativeProfile
                            ? nativeProfileSwitchTargetID
                            : store.state.settings.activeNativeProfileID
                    },
                    set: { selectNativeProfile($0) }
                )) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(store.nativeProfiles) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            .disabled(isApplyingNativeProfile)
            if isApplyingNativeProfile {
                GroupedNote("Applying \(store.nativeProfiles.first(where: { $0.id == nativeProfileSwitchTargetID })?.name ?? "macOS Dock")…",
                            showsProgress: true)
            }
            if let nativeProfileSwitchMessage {
                if let failedID = nativeProfileSwitchFailedID {
                    GroupedNote(nativeProfileSwitchMessage, tone: .warning, actionTitle: "Retry") { selectNativeProfile(failedID) }
                        .disabled(isApplyingNativeProfile)
                } else {
                    GroupedNote(nativeProfileSwitchMessage)
                }
            }
            SettingsControlRow(title: "Custom Dock") {
                Picker("Custom Dock", selection: Binding(
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
                GroupedNote("Display disconnected: using the main display until it reconnects. Select Main display to stay there.")
            }
        }.id("Dock setup")
        GroupedSection("Focus filters", footer: FocusFilterAvailability.guidance()) {
            GroupedRow("Dock for each Focus", symbol: "moon.fill", color: .indigo,
                       value: FocusFilterAvailability.hasIntentMetadata() ? "Available" : "Unavailable")
        }.id("Focus filters")
        AutomaticSwitchingSettingsSection(store: store).id("Automatic switching")
        GroupedSection("Native Dock switching") {
            GroupedRow("Automatically save Dock changes", subtitle: "Saves Apple Dock edits to the selected macOS Dock, checking every five seconds.", isOn: Binding(
                get: { store.state.settings.automaticallySaveNativeDockChanges },
                set: { enabled in store.updateSettings { $0.automaticallySaveNativeDockChanges = enabled } }
            ))
            if store.state.settings.automaticallySaveNativeDockChanges,
               store.state.settings.activeNativeProfileID == nil {
                GroupedNote("Select a macOS Dock to start automatic saving.")
            }
            if let message = nativeDockAutoSave.errorMessage, store.state.settings.automaticallySaveNativeDockChanges {
                GroupedNote(message, tone: .warning)
            }
            GroupedRow("Freeze desktop during Dock restart", subtitle: supportsScreenCaptureFreeze
                           ? "Holds one frame per display in memory. Switching works without Screen Recording."
                           : "Requires macOS 14 or later.", isOn: Binding(
                get: { store.state.settings.smoothNativeDockSwitches },
                set: { enabled in
                    store.updateSettings { $0.smoothNativeDockSwitches = enabled }
                    screenCaptureMessage = nil
                    // The row is disabled before macOS 14, so enabling always has the capture API.
                    guard enabled else { return }
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
                GroupedNote(screenCaptureMessage)
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
            nativeProfileSwitchMessage = "That macOS Dock is no longer available. Choose another one."
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
