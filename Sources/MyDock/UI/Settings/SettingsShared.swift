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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(profile.kind.title).font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(shortcut?.displayString ?? "—").font(.system(size: 13, weight: .medium).monospaced())
                    .foregroundStyle(shortcut == nil ? Color.secondary : Color.primary)
                    .padding(.horizontal, 10).frame(minWidth: 80, minHeight: 28)
                    .background(DockDesign.input, in: RoundedRectangle(cornerRadius: 6))
                Button(shortcut == nil ? "Set…" : "Change…", action: edit)
                    .accessibilityLabel("\(shortcut == nil ? "Set" : "Edit") keyboard shortcut for \(profile.name)")
            }.frame(minHeight: 40)
            if let registrationMessage {
                Label(registrationMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(DockDesign.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 4)
    }

}

struct DisplayOption: Identifiable {
    var id: UInt32
    var title: String
}
