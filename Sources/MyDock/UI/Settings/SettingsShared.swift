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
    let statusTitle: String
    let explanation: String
    var settingsURL: String?
    var id: String { name }
    var granted: Bool { statusTitle.hasPrefix("Allowed") || statusTitle.hasPrefix("Full access") }
    var summary: String {
        if granted { return "Granted" }
        if statusTitle.hasPrefix("Not requested") { return "Not requested" }
        if statusTitle.hasPrefix("Per-app") { return "Per-app" }
        return "Not granted"
    }
    init(name: String, status: String, settingsURL: String? = nil) {
        self.name = name
        self.settingsURL = settingsURL
        if let separator = status.range(of: " — ") {
            statusTitle = Self.sentenceCase(String(status[..<separator.lowerBound]))
            explanation = Self.sentenceCase(String(status[separator.upperBound...]))
        } else {
            statusTitle = Self.sentenceCase(status)
            explanation = Self.sentenceCase(status)
        }
    }
    private static func sentenceCase(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "" }
        return String(first).uppercased() + trimmed.dropFirst()
    }
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
