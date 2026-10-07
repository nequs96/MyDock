import Foundation

/// Discovery describes family capabilities, never current account or permission health.
enum WidgetDiscoveryFilter: String, CaseIterable, Identifiable {
    case all = "All widgets"
    case noConnection = "No account connection"
    case connected = "Account connection"
    case permissions = "May request permission"
    case privateContent = "Personal content"
    var id: String { rawValue }

    func includes(_ definition: WidgetDefinition) -> Bool {
        switch self {
        case .all: true
        case .noConnection: !definition.capabilities.needsConnection
        case .connected: definition.capabilities.needsConnection
        case .permissions: !definition.capabilities.permissions.isEmpty
        case .privateContent: definition.capabilities.holdsPrivateContent
        }
    }
}

enum WidgetDiscovery {
    static func applicationKey(_ item: DockItem) -> String? {
        guard item.type == .application, let url = item.url else { return nil }
        return InstalledApplicationIdentity.normalizedURL(url).absoluteString
    }

    static func containsApplication(_ item: DockItem, in items: [DockItem]) -> Bool {
        guard let key = applicationKey(item) else { return false }
        return items.contains { applicationKey($0) == key }
    }

    static func matches(_ definition: WidgetDefinition, query: String) -> Bool {
        let text = [definition.name, definition.description, definition.category.rawValue,
                    synonyms[definition.name] ?? ""].joined(separator: " ")
        return matchesTerms(text, query: query)
    }

    /// Every word of the query appears somewhere in `text`, in any order. An empty query matches.
    /// Widgets, apps and More entries all search this way.
    static func matchesTerms(_ text: String, query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy { text.localizedStandardContains(String($0)) }
    }

    static func canAdd(_ item: DockItem, alreadyAdded: Bool) -> Bool {
        item.type == .widget || !alreadyAdded
    }

    private static let synonyms: [String: String] = [
        "Stock": "share price market ticker investment", "Watchlist": "shares prices market portfolio investment",
        "Calendar": "meeting appointment schedule agenda next event", "Reminders": "Apple native tasks todo due",
        "Now Playing": "music audio playback song track media Spotify", "Weather": "temperature rain forecast location",
        "Focus Timer": "pomodoro work session concentration", "Sticky Note": "memo write text jot",
        "Battery": "charge power energy accessory", "Shortcuts": "automation workflow run action",
        "Stripe": "revenue subscriptions business MRR ARR", "Paddle": "revenue subscriptions business MRR ARR",
        "Shopify": "sales orders shop store commerce", "Clock": "local time date",
        "World Clock": "cities timezone time zone international", "Stopwatch": "elapsed time measure timing",
        "Countdown": "deadline duration remaining timer notification", "Alarm": "wake notification reminder time",
        "Time Progress": "day week month year remaining percentage", "Hydration": "water drink volume log reminder",
        "System Activity": "CPU processor memory RAM swap load thermal", "Network Activity": "internet upload download bandwidth speed interface",
        "Audio Output": "sound speakers headphones airpods volume mute device switch bluetooth",
        "AI Limits": "Codex Claude Copilot quota allowance usage", "AI Activity": "Codex Claude tokens sessions local logs",
        "AirDrop": "share send transfer files", "Trash": "bin recycle deleted files",
        "Disk Space": "storage free capacity volume drive", "Calculator": "math arithmetic expression",
        "Quick Checklist": "local private tasks todo to do account free", "File Shelf": "keep saved documents references tray",
        "Text Snippets": "saved reusable text copy paste clipboard", "Quick Links": "bookmark website URL browser",
        "Unit Converter": "convert measurement length mass weight temperature volume speed data units",
        "Color Picker": "colour eyedropper HEX RGB palette screen sample", "App Folder": "group applications launcher collection"
    ]
}
