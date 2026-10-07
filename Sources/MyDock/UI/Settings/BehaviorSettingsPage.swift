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
            GroupedRow("Hide when macOS Dock appears", isOn: Binding(get: { store.state.settings.hideCustomDockWhenSystemDockAppears }, set: { value in store.updateSettings { $0.hideCustomDockWhenSystemDockAppears = value } }))
            if store.state.settings.customDockDesktopMode {
                GroupedNote("Stays behind windows, including fullscreen apps; auto-hide is paused.")
            }
        }.id("Custom Dock behavior").help("The screen edge stays active without a handle; overlap detection uses window positions without screen capture.")
        GroupedSection("Apps and windows", footer: "Window previews stay on this Mac.") {
            GroupedRow("Show running apps", isOn: Binding(get: { store.state.settings.showRunningApps }, set: { value in store.updateSettings { $0.showRunningApps = value } }))
            GroupedRow("Show recent apps", subtitle: "Up to three recently used apps that are not in the Dock.", isOn: Binding(get: { store.state.settings.showRecentApps }, set: { value in store.updateSettings { $0.showRecentApps = value } }))
            GroupedRow("Show minimized windows", isOn: Binding(get: { store.state.settings.showMinimizedWindows }, set: { value in store.updateSettings { $0.showMinimizedWindows = value } }))
                .onChange(of: store.state.settings.showMinimizedWindows) { enabled in
                    if enabled { _ = WindowAccessibilityService.requestAccessPrompt() }
                }
            // Thumbnails replace the icons of minimized-window tiles, so the row sits under the
            // setting it depends on and says why it is unavailable.
            GroupedRow("Minimized window thumbnails",
                       subtitle: !supportsWindowPreviewCapture ? "Requires macOS 14."
                           : store.state.settings.showMinimizedWindows ? "Uses Screen Recording." : "Turn on Show minimized windows first.",
                       isOn: Binding(get: { store.state.settings.showWindowPreviews }, set: { value in store.updateSettings { $0.showWindowPreviews = value } }))
                .disabled(!store.state.settings.showMinimizedWindows || !supportsWindowPreviewCapture)
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
                GroupedNote(windowPreviewMessage)
            }
            GroupedRow("Show window previews", subtitle: "Hover over an open app to see its windows.", isOn: Binding(get: { store.state.settings.showWindowPreviewsOnHover }, set: { value in store.updateSettings { $0.showWindowPreviewsOnHover = value } }))
                .onChange(of: store.state.settings.showWindowPreviewsOnHover) { enabled in
                    if enabled && !WindowAccessibilityService.isTrusted() { _ = WindowAccessibilityService.requestAccessPrompt() }
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
        }.id("Dock items").help("Reads available macOS Dock badge labels through Accessibility; notification contents stay private.")
        GroupedSection("Interaction") {
            GroupedRow("Click focused app to minimize", isOn: Binding(get: { store.state.settings.clickFocusedAppToMinimize }, set: { value in store.updateSettings { $0.clickFocusedAppToMinimize = value } }))
                .onChange(of: store.state.settings.clickFocusedAppToMinimize) { enabled in
                    if enabled { _ = WindowAccessibilityService.requestAccessPrompt() }
                }
            // One status line for the page, shown only while access is missing. It is a warning only
            // once a feature that needs access is on; every such feature is off by default.
            if !accessibilityTrusted {
                GroupedNote("Accessibility access is needed for window controls and app badges.",
                            tone: behaviorNeedsAccessibility ? .warning : .secondary,
                            actionTitle: "Accessibility Settings…") { SystemSettingsPane.open(.accessibility) }
            }
            // The Dock can magnify only from macOS 14, so the switch is not offered on macOS 13.
            if DockMagnificationSupport.isAvailable {
                GroupedRow("Magnification", isOn: Binding(get: { store.state.settings.magnificationEnabled }, set: { value in store.updateSettings { $0.magnificationEnabled = value } }))
            }
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
    // Access is granted in System Settings, so the status is re-read when MyDock comes back.
    .onAppear { accessibilityTrusted = WindowAccessibilityService.isTrusted() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        accessibilityTrusted = WindowAccessibilityService.isTrusted()
    }
    }

    /// Whether a Behavior feature that is switched on stops working without Accessibility access.
    private var behaviorNeedsAccessibility: Bool {
        let settings = store.state.settings
        return settings.showMinimizedWindows || settings.showWindowPreviewsOnHover || settings.clickFocusedAppToMinimize
            || (DockBadgeReader.isSupported && settings.showAppBadges)
    }
}
