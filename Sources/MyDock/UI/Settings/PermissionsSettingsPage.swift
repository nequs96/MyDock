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
                GroupedRow(row.name, subtitle: row.explanation, symbol: row.symbol, color: .blue) {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label(row.summary, systemImage: row.granted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11)).foregroundStyle(row.granted ? Color.green : Color.secondary)
                        if let settingsURL = row.settingsURL, let url = URL(string: settingsURL) {
                            Link("Open Settings", destination: url)
                                .accessibilityLabel("Open \(row.name) settings")
                        }
                    }.fixedSize(horizontal: true, vertical: false)
                }.help(row.name == "Automation" ? "MyDock cannot read a universal Automation status; approval is per app." : row.explanation)
            }
            GroupedRow("Refresh Status", role: .button) { Task { await refreshPermissionStatuses() } }
                .help("Refresh after changing a permission.")
        }.id("Permission status").help("Access is requested when needed; Automation approval is per app.")
        }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
    }
    .task { await refreshPermissionStatuses() }
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
                                  status: "Per-app — Approval appears when you use Now Playing or confirm Empty Trash.",
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
}
