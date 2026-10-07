import AppKit
import SwiftUI

/// Local, deterministic suggestions: no app-usage collection or network access.
enum DockStarterPreset: String, CaseIterable, Identifiable {
    case everyday, focus, create, develop, commerce, homeOffice, travel, ai, monitor
    var id: String { rawValue }
    var title: String {
        switch self { case .everyday: "Everyday"; case .focus: "Deep focus"; case .create: "Creative space"; case .develop: "Build & code"; case .commerce: "Commerce"; case .homeOffice: "Home office"; case .travel: "Travel"; case .ai: "AI workspace"; case .monitor: "System monitor" }
    }
    var symbol: String {
        switch self { case .everyday: "sun.max"; case .focus: "moon"; case .create: "paintpalette"; case .develop: "chevron.left.forwardslash.chevron.right"; case .commerce: "bag"; case .homeOffice: "house"; case .travel: "airplane"; case .ai: "sparkles"; case .monitor: "waveform.path.ecg" }
    }
    var color: DockProfileColor {
        switch self { case .everyday: .blue; case .focus: .teal; case .create: .purple; case .develop: .orange; case .commerce: .green; case .homeOffice: .blue; case .travel: .teal; case .ai: .purple; case .monitor: .red }
    }
    var detail: String {
        switch self {
        case .everyday: "Your daily essentials, time, and battery at a glance."
        case .focus: "A quiet workspace with a focus timer and a quick note."
        case .create: "Creative apps, inspiration, and music close by."
        case .develop: "Your editor, terminal, browser, and system activity."
        case .commerce: "Store metrics and daily operations. Connect accounts after setup."
        case .homeOffice: "Meetings, reminders, and a quick note."
        case .travel: "Time zones, weather, battery, and easy sharing."
        case .ai: "Local AI activity and available provider limits."
        case .monitor: "System, network, storage, and battery at a glance."
        }
    }
    struct Resolution {
        var items: [DockItem]
        var notes: [String]
    }
    @MainActor func items() -> [DockItem] { resolve().items }
    var widgetKinds: [String] {
        switch self {
        case .everyday: ["Clock", "Battery"]
        case .focus: ["Focus Timer", "Sticky Note"]
        case .create: ["Now Playing", "Sticky Note"]
        case .develop: ["System Activity", "Clock"]
        case .commerce: ["Stripe", "Paddle", "Shopify", "Calendar"]
        case .homeOffice: ["Calendar", "Reminders", "Sticky Note"]
        case .travel: ["World Clock", "Weather", "Battery", "AirDrop"]
        case .ai: ["AI Limits", "AI Activity", "Focus Timer"]
        case .monitor: ["System Activity", "Network Activity", "Battery"]
        }
    }
    /// Bundle identifiers per app slot, preferred first. Apple's iWork apps use `com.apple.iWork.*`.
    var applicationCandidates: [[String]] {
        switch self {
        case .everyday: [["com.apple.finder"], ["com.apple.Safari"], ["com.apple.mail"], ["com.apple.Notes"]]
        case .focus: [["com.apple.finder"], ["com.apple.Notes"], ["com.apple.Safari"]]
        case .create: [["com.apple.finder"], ["com.figma.Desktop", "com.apple.Preview"], ["com.adobe.Photoshop", "com.apple.Photos"], ["com.apple.Safari"]]
        case .develop: [["com.apple.finder"], ["com.microsoft.VSCode", "com.apple.dt.Xcode", "com.apple.TextEdit"], ["com.googlecode.iterm2", "com.apple.Terminal"], ["com.apple.Safari"]]
        case .commerce: [["com.apple.Safari"], ["com.apple.iWork.Numbers"]]
        case .homeOffice: [["com.apple.mail"], ["us.zoom.xos", "com.apple.FaceTime"], ["com.apple.Notes"]]
        case .travel: [["com.apple.Safari"], ["com.apple.Maps"]]
        case .ai: [["com.openai.codex", "com.apple.Terminal"], ["com.apple.Safari"]]
        case .monitor: [["com.apple.ActivityMonitor"], ["com.apple.Terminal"]]
        }
    }

    @MainActor func resolve() -> Resolution {
        let candidates = applicationCandidates
        let widgets = widgetKinds
        var apps: [DockItem] = []
        var notes: [String] = []
        let names = ["com.figma.Desktop": "Figma", "com.adobe.Photoshop": "Photoshop",
                     "com.microsoft.VSCode": "Visual Studio Code", "com.googlecode.iterm2": "iTerm",
                     "us.zoom.xos": "Zoom", "com.openai.codex": "Codex"]
        for group in candidates {
            let preferred = names[group[0]] ?? group[0].split(separator: ".").last.map(String.init) ?? "Preferred app"
            if let match = group.enumerated().compactMap({ index, id in
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: id).map { (index, $0) }
            }).first {
                let app = DockItem.application(at: match.1)
                apps.append(app)
                if match.0 > 0 { notes.append("\(preferred) is unavailable; using \(app.title).") }
            } else { notes.append("\(preferred) is unavailable. You can add a replacement application below.") }
        }
        return Resolution(items: apps + (apps.isEmpty ? [] : [.spacer(.small)]) + widgets.map { .widget($0) }, notes: notes)
    }
}

extension DockStarterPreset {
    /// The redesign style each starter Dock is created with. Everyday and travel stay light
    /// and open (Clear); creative, developer and AI work gets glass modules (Glass); deep focus
    /// keeps its calm opaque surface (Solid); dense or business Docks get tiles (Frosted).
    var quickStyle: DockQuickStyle {
        switch self {
        case .everyday, .travel: .clear
        case .create, .develop, .ai: .glass
        case .focus: .solid
        case .commerce, .homeOffice, .monitor: .frosted
        }
    }

    /// The appearance snapshot a created starter Dock carries: the current global appearance
    /// with this preset's quick style applied. Size, spacing, radius, theme, labels and inset
    /// still follow the user's settings.
    func appearance(basedOn settings: AppSettings) -> ProfileAppearance {
        var styled = settings
        quickStyle.apply(to: &styled)
        return ProfileAppearance(settings: styled)
    }

    /// The Dock the presets sheet creates: this Mac's resolved apps and the preset's widgets,
    /// colour and style snapshot, with notes about substituted or missing apps.
    @MainActor func profile(settings: AppSettings) -> (profile: DockProfile, notes: [String]) {
        let resolution = resolve()
        return (profile(items: resolution.items, settings: settings), resolution.notes)
    }

    /// The same construction for given items, so tests need not resolve apps on this Mac.
    func profile(items: [DockItem], settings: AppSettings) -> DockProfile {
        var dock = DockProfile(name: title, kind: .custom, color: color.rawValue, items: items)
        dock.appearance = appearance(basedOn: settings)
        return dock
    }
}
