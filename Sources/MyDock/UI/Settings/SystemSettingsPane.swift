import AppKit

/// The System Settings panes MyDock links to, each written once. Opening one is a native action,
/// so isolated validation and visual-QA sessions never launch System Settings.
enum SystemSettingsPane: String, CaseIterable, Sendable {
    case accessibility, screenCapture, notifications, calendars, reminders, location, automation, fullDiskAccess

    var address: String {
        switch self {
        case .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .screenCapture: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        case .notifications: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .calendars: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        case .reminders: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
        case .location: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        case .automation: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
        case .fullDiskAccess: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        }
    }

    var url: URL? { URL(string: address) }

    static func open(_ pane: SystemSettingsPane) {
        guard AppRuntimeEnvironment.allowsNativeEffects, let url = pane.url else { return }
        NSWorkspace.shared.open(url)
    }
}
