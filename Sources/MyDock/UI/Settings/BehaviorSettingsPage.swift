import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var behaviorPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        GroupedSection("Custom Dock behavior", footer: "The screen edge stays active without a handle.") {
            GroupedRow("Use as desktop widget (behind windows)", isOn: Binding(get: { store.state.settings.customDockDesktopMode }, set: { value in store.updateSettings { $0.customDockDesktopMode = value } }))
            GroupedRow("Automatically hide", isOn: Binding(get: { store.state.settings.automaticallyHideCustomDock }, set: { value in store.updateSettings { $0.automaticallyHideCustomDock = value } }))
                .disabled(store.state.settings.customDockDesktopMode)
            GroupedRow("Show reveal handle while hidden", isOn: Binding(
                get: { store.state.settings.showRevealHandle },
                set: { value in store.updateSettings { $0.showRevealHandle = value } }
            ))
            .disabled(!store.state.settings.automaticallyHideCustomDock || store.state.settings.customDockDesktopMode)
            GroupedRow("Hide when Apple Dock appears", isOn: Binding(get: { store.state.settings.hideCustomDockWhenSystemDockAppears }, set: { value in store.updateSettings { $0.hideCustomDockWhenSystemDockAppears = value } }))
            if store.state.settings.customDockDesktopMode {
                Text("Stays behind windows, including fullscreen apps; auto-hide is paused.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.id("Custom Dock behavior").help("The screen edge stays active without a handle; overlap detection uses window positions without screen capture.")
        GroupedSection("Apps and windows", footer: "Window previews stay on this Mac.") {
            GroupedRow("Show running apps", isOn: Binding(get: { store.state.settings.showRunningApps }, set: { value in store.updateSettings { $0.showRunningApps = value } }))
            GroupedRow("Show recent apps", subtitle: "Up to three recently used apps that are not in the Dock.", isOn: Binding(get: { store.state.settings.showRecentApps }, set: { value in store.updateSettings { $0.showRecentApps = value } }))
            GroupedRow("Show minimized windows", isOn: Binding(get: { store.state.settings.showMinimizedWindows }, set: { value in store.updateSettings { $0.showMinimizedWindows = value } }))
                .onChange(of: store.state.settings.showMinimizedWindows) { enabled in
                    if enabled { _ = WindowAccessibilityService.requestAccessPrompt() }
                }
            GroupedRow("Show window previews", subtitle: "Hover over an open app to see its windows.", isOn: Binding(get: { store.state.settings.showWindowPreviewsOnHover }, set: { value in store.updateSettings { $0.showWindowPreviewsOnHover = value } }))
                .onChange(of: store.state.settings.showWindowPreviewsOnHover) { enabled in
                    if enabled && !WindowAccessibilityService.isTrusted() { _ = WindowAccessibilityService.requestAccessPrompt() }
                }
            GroupedRow("Cache window previews", isOn: Binding(get: { store.state.settings.showWindowPreviews }, set: { value in store.updateSettings { $0.showWindowPreviews = value } }))
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
            if let windowPreviewMessage {
                Text(windowPreviewMessage).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.id("Apps and windows").help("macOS 14+: previews stay local for 24 hours and are deleted when disabled; duplicates or unavailable previews use app icons.")
        GroupedSection("Dock items", footer: DockBadgeReader.isSupported ? "Notification contents stay private." : "App badge labels require macOS 14 or later.") {
            GroupedRow("Show Trash", isOn: Binding(get: { store.state.settings.showTrash }, set: { value in store.updateSettings { $0.showTrash = value } }))
            GroupedRow("Show app badges", isOn: Binding(get: { store.state.settings.showAppBadges }, set: { value in store.updateSettings { $0.showAppBadges = value } }))
                .disabled(!DockBadgeReader.isSupported)
                .onChange(of: store.state.settings.showAppBadges) { enabled in
                    if enabled && !WindowAccessibilityService.isTrusted() {
                        _ = WindowAccessibilityService.requestAccessPrompt()
                    }
                }
            if DockBadgeReader.isSupported, store.state.settings.showAppBadges,
               !WindowAccessibilityService.isTrusted() {
                HStack {
                    Text("Allow MyDock under Privacy & Security → Accessibility to show badge labels.")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                    Spacer()
                    Button("Accessibility Settings…", action: openAccessibilitySettings)
                        .controlSize(.small)
                }
            }
        }.id("Dock items").help("Reads available Apple Dock badge labels through Accessibility; notification contents stay private.")
        GroupedSection("Interaction") {
            GroupedRow("Click focused app to minimize", isOn: Binding(get: { store.state.settings.clickFocusedAppToMinimize }, set: { value in store.updateSettings { $0.clickFocusedAppToMinimize = value } }))
                .onChange(of: store.state.settings.clickFocusedAppToMinimize) { enabled in
                    if enabled { _ = WindowAccessibilityService.requestAccessPrompt() }
                }
            HStack {
                Text(WindowAccessibilityService.isTrusted() ? "Accessibility access is enabled." : "Accessibility access is needed for window controls.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Button("Accessibility Settings…", action: openAccessibilitySettings)
            }
            GroupedRow("Magnification", isOn: Binding(get: { store.state.settings.magnificationEnabled }, set: { value in store.updateSettings { $0.magnificationEnabled = value } }))
        }.id("Interaction")
        GroupedSection("Dock animations", footer: "Reveal and hide effects respect Reduce Motion.") {
            GroupedRow("Animate Dock appearance", isOn: Binding(get: { store.state.settings.dockAnimationsEnabled }, set: { value in store.updateSettings { $0.dockAnimationsEnabled = value } }))
            SettingsControlRow(title: "Reveal effect") {
                Picker("Reveal effect", selection: Binding(get: { store.state.settings.dockAnimationStyle }, set: { value in store.updateSettings { $0.dockAnimationStyle = value } })) {
                    ForEach(DockAnimationStyle.allCases) { Text($0.title).tag($0) }
                }.disabled(!store.state.settings.dockAnimationsEnabled)
            }
            GroupedRow("Preview animation", role: .button, symbol: "play.fill") {
                NotificationCenter.default.post(name: CustomDockWindowController.animationPreviewNotification, object: store)
            }.disabled(!store.state.settings.dockAnimationsEnabled || store.state.settings.setupMode == .nativeOnly || store.activeCustomProfile == nil)
        }.id("Dock animations")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

}
