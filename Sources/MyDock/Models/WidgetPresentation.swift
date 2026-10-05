import Foundation

/// Layout is semantic and owns geometry. Icon appearance never participates in it.
enum WidgetLayout: String, Codable, CaseIterable, Identifiable {
    case icon, compact, standard, wide, meter, trend
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WidgetIconAppearance: String, Codable, CaseIterable, Identifiable {
    case accent, soft, mono, outline
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    init(legacy: WidgetIconStyle) {
        switch legacy { case .live, .tinted: self = .soft; case .gradient: self = .accent; case .outline: self = .mono }
    }
}

enum AIActivitySecondaryMetric: String, Codable, CaseIterable, Identifiable {
    case sessions, toolCalls, requests, none
    var id: String { rawValue }
    var title: String { switch self { case .sessions: "Sessions"; case .toolCalls: "Tool calls"; case .requests: "Requests"; case .none: "None" } }
}
enum SystemSecondaryMetric: String, Codable, CaseIterable, Identifiable {
    case memory, load, none
    var id: String { rawValue }
    var title: String { switch self { case .memory: "Memory"; case .load: "Load average"; case .none: "None" } }
}

struct WidgetLayoutOption: Identifiable, Hashable {
    var layout: WidgetLayout
    var width: Double
    var title: String
    var detail: String
    var id: WidgetLayout { layout }
}

/// System permissions a widget family may ask for. Descriptive only; requests stay in the owning services.
enum WidgetSystemPermission: String, Hashable, CaseIterable {
    case calendars, reminders, location, automation, notifications

    /// Short user-facing noun used in capability notes.
    var title: String {
        switch self {
        case .calendars: "Calendar"
        case .reminders: "Reminders"
        case .location: "Location"
        case .automation: "Automation"
        case .notifications: "Notifications"
        }
    }
}

/// What kind of refresh a family needs while visible.
enum WidgetRefreshDemand: String, Hashable, CaseIterable {
    case none            // static or user-driven content
    case timeTick        // local clock-derived content
    case localSampling   // local system samplers
    case remoteFetch     // network-backed content
    case externalSource  // another app or system store
}

/// Typed capability descriptor for one widget family. The family's stable name string stays the persisted identity.
struct WidgetCapabilities: Hashable {
    var layouts: [WidgetLayoutOption]
    var defaultLayout: WidgetLayout
    var needsConnection = false
    var permissions: Set<WidgetSystemPermission> = []
    var hasSetupState = false
    var holdsPrivateContent = false
    var refreshDemand: WidgetRefreshDemand = .none

    /// Short, truthful note derived only from the family's capabilities. It describes what the family may use,
    /// never whether a permission is currently granted. Nil when the family needs nothing special.
    var accessNote: String? {
        var parts: [String] = []
        if !permissions.isEmpty {
            let names = WidgetSystemPermission.allCases.filter(permissions.contains).map(\.title).joined(separator: ", ")
            parts.append("May ask for \(names) access when you use it.")
        }
        if holdsPrivateContent { parts.append("Can show personal content on your Dock.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

enum WidgetLayoutPresets {
    static func option(_ layout: WidgetLayout, _ width: Double, _ detail: String, title: String? = nil) -> WidgetLayoutOption {
        .init(layout: layout, width: width, title: title ?? layout.title, detail: detail)
    }
    static let aiActivity = [option(.compact, 88, "Usage total"), option(.standard, 126, "Total and session metadata"), option(.trend, 184, "History without chart axes", title: "Activity")]
    static let systemActivity = [option(.compact, 86, "CPU and live history"), option(.meter, 92, "CPU in a ring gauge"), option(.trend, 158, "History and one secondary reading", title: "Trend")]
    static let networkActivity = [option(.compact, 100, "Download and upload"), option(.trend, 170, "Rates and download history")]
    static let battery = [option(.compact, 90, "Charge ring and percentage"), option(.wide, 156, "Mac and available accessories")]
    static let diskSpace = [option(.compact, 104, "Free space and a usage ring"), option(.wide, 158, "Available and total capacity")]
    static let clock = [option(.compact, 104, "Local time"), option(.standard, 112, "Time and date")]
    static let worldClock = [option(.compact, 88, "Primary city"), option(.wide, 164, "City and time zone")]
    static let weather = [option(.compact, 92, "Temperature and condition"), option(.standard, 132, "Place and current weather"), option(.wide, 184, "Upcoming hours", title: "Forecast")]
    static let nowPlaying = [option(.compact, 112, "Artwork and track"), option(.wide, 186, "Track and artist", title: "Track")]
    static let timer = [option(.compact, 88, "Timer and state"), option(.standard, 124, "Time and progress")]
    static let schedule = [option(.compact, 88, "At a glance"), option(.wide, 154, "Next item and count")]
    static let market = [option(.compact, 108, "Ticker and price"), option(.trend, 176, "Price and market history")]
    static let savedCollection = [option(.compact, 96, "Saved item count"), option(.wide, 164, "Count and most recent item")]
    static let quickTool = [option(.icon, 54, "Quick tool"), option(.compact, 104, "Tool and identity")]
    static let stickyNote = [option(.standard, 120, "A short note"), option(.wide, 176, "More of your note")]
    static let quickAction = [option(.icon, 54, "Quick action"), option(.compact, 88, "Action and identity")]
    static let generic = [option(.compact, 88, "Essential information"), option(.standard, 124, "More context")]
}

/// Thin facade over the registry's capability descriptors. Unknown kinds keep the generic fallback.
enum WidgetPresentationCatalog {
    static func options(for kind: String) -> [WidgetLayoutOption] {
        WidgetRegistry.definition(named: kind)?.capabilities.layouts ?? WidgetLayoutPresets.generic
    }
    static func defaultLayout(for kind: String) -> WidgetLayout {
        WidgetRegistry.definition(named: kind)?.capabilities.defaultLayout ?? .compact
    }
    static func resolvedLayout(for kind: String, configuration: WidgetConfiguration, compactDefault: Bool = false) -> WidgetLayout {
        let choices = options(for: kind)
        if let selected = configuration.widgetLayout {
            if choices.contains(where: { $0.layout == selected }) { return selected }
            // Old generic Wide sizes map to the widget's richest supported layout.
            if selected == .wide || selected == .trend { return choices.last!.layout }
            if selected == .compact { return choices.first!.layout }
        }
        return compactDefault ? choices.first!.layout : defaultLayout(for: kind)
    }
    static func width(for kind: String, layout: WidgetLayout) -> Double {
        options(for: kind).first { $0.layout == layout }?.width ?? options(for: kind).first!.width
    }
}

/// Real samples only, bounded to two minutes at the existing four-second cadence.
enum WidgetTelemetryHistory {
    static func appending(_ value: Double?, to values: [Double], limit: Int = 30) -> [Double] {
        guard let value, value.isFinite, (0...100).contains(value) else { return values }
        return Array((values + [value]).suffix(max(1, limit)))
    }
}
