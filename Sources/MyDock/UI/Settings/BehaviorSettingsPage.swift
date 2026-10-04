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
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

}
