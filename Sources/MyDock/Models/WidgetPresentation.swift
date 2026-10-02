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

enum WidgetPresentationCatalog {
    static func options(for kind: String) -> [WidgetLayoutOption] {
        switch kind {
        case "AI Activity": return [option(.compact, 88, "Usage total"), option(.standard, 126, "Total and session metadata"), option(.trend, 184, "History without chart axes", title: "Activity")]
        case "System Activity": return [option(.compact, 86, "CPU and live history"), option(.meter, 92, "CPU with a small meter"), option(.trend, 158, "History and one secondary reading", title: "Trend")]
        case "Network Activity": return [option(.compact, 100, "Download and upload"), option(.trend, 170, "Rates and download history")]
        case "Battery": return [option(.compact, 90, "Charge and battery shape"), option(.wide, 156, "Mac and available accessories")]
        case "Disk Space": return [option(.compact, 104, "Free space and capacity bar"), option(.wide, 158, "Available and total capacity")]
        case "Clock": return [option(.compact, 84, "Local time"), option(.standard, 112, "Time and date")]
        case "World Clock": return [option(.compact, 88, "Primary city"), option(.wide, 164, "City and time zone")]
        case "Weather": return [option(.compact, 92, "Temperature and condition"), option(.standard, 132, "Place and current weather"), option(.wide, 184, "Upcoming hours", title: "Forecast")]
        case "Now Playing": return [option(.compact, 112, "Artwork and track"), option(.wide, 186, "Track and artist", title: "Track")]
        case "Focus Timer", "Countdown", "Stopwatch": return [option(.compact, 88, "Timer and state"), option(.standard, 124, "Time and progress")]
        case "Calendar", "Reminders", "Quick Checklist": return [option(.compact, 88, "At a glance"), option(.wide, 154, "Next item and count")]
        case "Stock", "Watchlist": return [option(.compact, 108, "Ticker and price"), option(.trend, 176, "Price and market history")]
        case "Sticky Note": return [option(.standard, 120, "A short note"), option(.wide, 176, "More of your note")]
        case "AirDrop", "Trash", "Calculator", "Shortcuts", "App Folder": return [option(.icon, 54, "Quick action"), option(.compact, 88, "Action and identity")]
        default: return [option(.compact, 88, "Essential information"), option(.standard, 124, "More context")]
        }
    }
    static func defaultLayout(for kind: String) -> WidgetLayout {
        switch kind {
        case "AI Activity", "Weather", "Sticky Note": .standard
        case "Now Playing": .wide
        case "AirDrop", "Trash", "Calculator", "Shortcuts", "App Folder": .icon
        default: .compact
        }
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
    private static func option(_ layout: WidgetLayout, _ width: Double, _ detail: String, title: String? = nil) -> WidgetLayoutOption {
        .init(layout: layout, width: width, title: title ?? layout.title, detail: detail)
    }
}

/// Real samples only, bounded to two minutes at the existing four-second cadence.
enum WidgetTelemetryHistory {
    static func appending(_ value: Double?, to values: [Double], limit: Int = 30) -> [Double] {
        guard let value, value.isFinite, (0...100).contains(value) else { return values }
        return Array((values + [value]).suffix(max(1, limit)))
    }
}
