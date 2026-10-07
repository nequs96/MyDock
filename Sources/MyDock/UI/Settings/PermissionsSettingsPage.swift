import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var permissionsPage: some View {
    DockScrollView {
        VStack(alignment: .leading, spacing: 20) {
        SettingsPageHeader(page: selectedPage)
        GroupedSection("Permission status", footer: "Access is requested when needed.") {
            ForEach(permissionRows) { row in
                GroupedRow(row.name, subtitle: row.explanation, symbol: row.symbol, color: .blue,
                           value: row.summary, chevron: row.pane != nil,
                           action: row.pane.map { pane in { SystemSettingsPane.open(pane) } })
                    .help(row.name == "Automation" ? "MyDock cannot read a universal Automation status; approval is per app." : row.explanation)
                    .accessibilityHint(row.pane != nil ? "\(row.explanation) Opens \(row.name) in System Settings." : row.explanation)
            }
        }.id("Permission status").help("Access is requested when needed; Automation approval is per app.")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    .task { await refreshPermissionStatuses() }
    // Permissions change in System Settings, so returning to MyDock re-reads them.
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        Task { await refreshPermissionStatuses() }
    }
    }

    @MainActor
    private func refreshPermissionStatuses() async {
        let notificationSettings = AppRuntimeEnvironment.allowsNativeEffects
            ? await UNUserNotificationCenter.current().notificationSettings() : nil
        permissionRows = [
            .accessibility(trusted: WindowAccessibilityService.isTrusted()),
            .screenRecording(allowed: CGPreflightScreenCaptureAccess()),
            .notifications(notificationSettings?.authorizationStatus),
            .events(.event, status: EKEventStore.authorizationStatus(for: .event)),
            .events(.reminder, status: EKEventStore.authorizationStatus(for: .reminder)),
            .location(CLLocationManager().authorizationStatus),
            .automation
        ]
        DiagnosticsService.shared.record(.permissionStatusRefreshed)
    }
}
