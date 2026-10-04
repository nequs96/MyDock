import AppKit
import CoreGraphics
import CoreLocation
import EventKit
import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

extension SettingsView {
    var supportsScreenCaptureFreeze: Bool {
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

struct PermissionOverviewRow: Identifiable {
    var name: String
    var status: String
    var settingsURL: String?
    var id: String { name }
    var granted: Bool { status.hasPrefix("Allowed") || status.hasPrefix("Full access") }
    var summary: String {
        if granted { return "Granted" }
        if status.hasPrefix("Not requested") { return "Not requested" }
        if status.hasPrefix("Per-app") { return "Per-app" }
        return "Not granted"
    }
    var explanation: String { status.components(separatedBy: " — ").last ?? status }
    var symbol: String {
        switch name {
        case "Accessibility": "accessibility"; case "Screen Recording": "rectangle.on.rectangle"
        case "Notifications": "bell"; case "Calendar": "calendar"; case "Reminders": "checklist"
        case "Location": "location"; default: "gearshape.2"
        }
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
                        .accessibilityLabel("\(shortcut == nil ? "Set" : "Edit") keyboard shortcut for \(profile.name)")
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
