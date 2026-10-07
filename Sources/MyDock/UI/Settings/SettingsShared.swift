import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    /// The Dock-switch freeze captures displays with ScreenCaptureKit, which it uses from macOS 14.
    var supportsScreenCaptureFreeze: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// Minimized-window thumbnails are captured with ScreenCaptureKit, which MyDock uses from macOS 14.
    var supportsWindowPreviewCapture: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }
}

enum DockDensityPreset: String, CaseIterable, Identifiable {
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

/// What a permission row reports. The summary shown in the row comes from here, never from the copy.
enum PermissionState: Equatable, Sendable {
    case granted, notRequested, perApp, denied, unavailable

    var summary: String {
        switch self {
        case .granted: "Granted"
        case .notRequested: "Not requested"
        case .perApp: "Per-app"
        case .denied: "Not granted"
        case .unavailable: "Unavailable"
        }
    }
}

/// One row of the Permissions page: an explicit state, one short sentence on what it means for
/// MyDock, and the System Settings pane that changes it.
struct PermissionOverviewRow: Identifiable, Equatable {
    var name: String
    var state: PermissionState
    var explanation: String
    var pane: SystemSettingsPane?
    var id: String { name }
    var granted: Bool { state == .granted }
    var summary: String { state.summary }

    var symbol: String {
        switch name {
        case "Accessibility": "accessibility"; case "Screen Recording": "rectangle.on.rectangle"
        case "Notifications": "bell"; case "Calendar": "calendar"; case "Reminders": "checklist"
        case "Location": "location"; default: "gearshape.2"
        }
    }

    static func accessibility(trusted: Bool) -> Self {
        Self(name: "Accessibility", state: trusted ? .granted : .denied,
             explanation: trusted ? "Window controls, previews and app badges are available."
                : "Window controls, previews and app badges are unavailable.",
             pane: .accessibility)
    }

    static func screenRecording(allowed: Bool) -> Self {
        Self(name: "Screen Recording", state: allowed ? .granted : .denied,
             explanation: allowed ? "Window thumbnails and the optional switch freeze can capture the screen."
                : "Previews show window titles only; Dock switching still works.",
             pane: .screenCapture)
    }

    /// `nil` when notification status cannot be read (isolated validation sessions).
    static func notifications(_ status: UNAuthorizationStatus?) -> Self {
        var row = Self(name: "Notifications", state: .unavailable, explanation: "Status unavailable.", pane: .notifications)
        switch status {
        case nil: row.explanation = "Unavailable in this isolated run."
        case .notDetermined?: row.state = .notRequested; row.explanation = "Alarms, countdowns, and hydration reminders ask when enabled."
        case .denied?: row.state = .denied; row.explanation = "Scheduled alerts will not appear."
        case .authorized?, .provisional?, .ephemeral?: row.state = .granted; row.explanation = "Scheduled alerts can appear."
        case _?: break
        }
        return row
    }

    /// Calendar or Reminders access.
    static func events(_ entity: EKEntityType, status: EKAuthorizationStatus) -> Self {
        let isCalendar = entity == .event
        var result = Self(name: isCalendar ? "Calendar" : "Reminders", state: .granted, explanation: "Allowed.",
                          pane: isCalendar ? .calendars : .reminders)
        if #available(macOS 14.0, *) {
            if status == .fullAccess { result.explanation = "Full access allowed."; return result }
            if status == .writeOnly {
                result.state = .denied
                result.explanation = "Write-only access; MyDock needs read access for this widget."
                return result
            }
        }
        switch status {
        case .notDetermined: result.state = .notRequested; result.explanation = "Access is requested when the widget opens."
        case .restricted: result.state = .denied; result.explanation = "Restricted by macOS or device policy."
        case .denied: result.state = .denied; result.explanation = "Open System Settings to allow access."
        default: break
        }
        return result
    }

    static func location(_ status: CLAuthorizationStatus) -> Self {
        var row = Self(name: "Location", state: .unavailable, explanation: "Status unavailable.", pane: .location)
        switch status {
        case .notDetermined: row.state = .notRequested; row.explanation = "Only the Weather current-location action asks."
        case .restricted: row.state = .denied; row.explanation = "Restricted by macOS or device policy."
        case .denied: row.state = .denied; row.explanation = "City search still works without location access."
        case .authorizedAlways, .authorized: row.state = .granted; row.explanation = "Allowed."
        case .authorizedWhenInUse: row.state = .granted; row.explanation = "Allowed while using MyDock."
        @unknown default: break
        }
        return row
    }

    static var automation: Self {
        Self(name: "Automation", state: .perApp,
             explanation: "Approval appears when you use Now Playing or confirm Empty Trash.", pane: .automation)
    }
}

struct SettingsShortcutRow: View {
    var profile: DockProfile
    var shortcut: DockShortcut?
    var registrationMessage: String?
    var edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GroupedRow(profile.name, subtitle: profile.kind.title) {
                HStack(spacing: 12) {
                    Text(shortcut?.displayString ?? "—").font(.system(size: 13, weight: .medium).monospaced())
                        .foregroundStyle(shortcut == nil ? Color.secondary : Color.primary)
                    Button(shortcut == nil ? "Set…" : "Change…", action: edit)
                        .accessibilityLabel("\(shortcut == nil ? "Set" : "Change") keyboard shortcut for \(profile.name)")
                }
            }
            if let registrationMessage {
                Label(registrationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(DockDesign.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

struct DisplayOption: Identifiable {
    var id: UInt32
    var title: String
}

/// Inline disclosure in a grouped card: a chevron that turns down when expanded and one row inset.
struct SettingsExpansionRow<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @DockAccessibilityStyle() private var accessibility
    var body: some View {
        VStack(spacing: 0) {
            GroupedRow(title, isExpanded: isExpanded) {
                DockDesign.Motion.perform(DockDesign.Motion.disclosure, reduceMotion: accessibility.reduceMotion) { isExpanded.toggle() }
            }
            if isExpanded {
                content.padding(DockDesign.Grouped.rowHorizontalPadding).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
