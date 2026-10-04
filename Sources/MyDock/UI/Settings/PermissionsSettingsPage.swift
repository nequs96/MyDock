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
}
