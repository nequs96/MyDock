import SwiftUI

struct SettingsSearchEntry: Identifiable {
    var title: String
    var section: String
    var page: MyDockSettingsPage
    var keywords: String
    var id: String { page.rawValue + title }
}

enum SettingsSearchCatalog {
    static func pages(matching query: String) -> [MyDockSettingsPage] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return MyDockSettingsPage.allCases }
        let matchingEntries = matches(query)
        return MyDockSettingsPage.allCases.filter { page in
            page.title.localizedStandardContains(query) || page.searchTerms.localizedStandardContains(query)
                || matchingEntries.contains { $0.page == page }
        }
    }
    static let entries: [SettingsSearchEntry] = [
        .init(title: "Mode", section: "Dock setup", page: .dock, keywords: "native custom main apple"),
        .init(title: "Display and edge", section: "Dock setup", page: .dock, keywords: "monitor screen bottom left right position"),
        .init(title: "Native profile and auto-save", section: "Dock setup", page: .dock, keywords: "apply switch macos save"),
        .init(title: "Appearance scope", section: "Scope", page: .appearance, keywords: "profile inherit global override undo"),
        .init(title: "Color theme and material", section: "Glass", page: .appearance, keywords: "light dark system glass frost frosted solid clear transparency clarity liquid opacity"),
        .init(title: "Edge", section: "Edge", page: .appearance, keywords: "none hairline contrast only outline border"),
        .init(title: "Default widget surface", section: "Default widget surface", page: .appearance, keywords: "glass plain tile widgets"),
        .init(title: "Floating inset", section: "Floating inset", page: .appearance, keywords: "layout screen gap 24"),
        .init(title: "Auto tint", section: "Auto tint", page: .appearance, keywords: "automatic profile color strength"),
        .init(title: "Tint strength", section: "Tint strength", page: .appearance, keywords: "glass color zero"),
        .init(title: "Glass finish", section: "Glass", page: .appearance, keywords: "clear frosted material"),
        .init(title: "Glass opacity", section: "Glass opacity", page: .appearance, keywords: "transparent opaque"),
        .init(title: "Clear", section: "Style Clear", page: .appearance, keywords: "quick style swatch preset"),
        .init(title: "Glass", section: "Style Glass", page: .appearance, keywords: "quick style swatch preset"),
        .init(title: "Frosted", section: "Style Frosted", page: .appearance, keywords: "quick style swatch preset"),
        .init(title: "Solid", section: "Style Solid", page: .appearance, keywords: "quick style swatch preset"),
        .init(title: "Midnight", section: "Style Midnight", page: .appearance, keywords: "quick style swatch preset"),
        .init(title: "Dock animations", section: "Dock animations", page: .behavior, keywords: "animate animation reveal fade slide grow motion"),
        .init(title: "Widget cards and names", section: "Widgets", page: .appearance, keywords: "widget layout icon appearance width compact standard wide trend"),
        .init(title: "Tile size and spacing", section: "Layout", page: .appearance, keywords: "density resize scale gap"),
        .init(title: "Corner roundness", section: "Layout", page: .appearance, keywords: "radius round corners"),
        .init(title: "Automatically hide and reveal handle", section: "Custom Dock behavior", page: .behavior, keywords: "autohide dwell edge"),
        .init(title: "Desktop widget mode", section: "Custom Dock behavior", page: .behavior, keywords: "behind windows fullscreen"),
        .init(title: "Hide when Apple Dock appears", section: "Custom Dock behavior", page: .behavior, keywords: "overlap native"),
        .init(title: "Running apps and minimized windows", section: "Apps and windows", page: .behavior, keywords: "applications restore"),
        .init(title: "Window previews", section: "Apps and windows", page: .behavior, keywords: "screen recording cache capture"),
        .init(title: "Magnification", section: "Interaction", page: .behavior, keywords: "hover zoom animation motion"),
        .init(title: "Trash and app badges", section: "Dock items", page: .behavior, keywords: "notifications count"),
        .init(title: "Keyboard shortcuts", section: "Global profile shortcuts", page: .shortcuts, keywords: "hotkey global switch"),
        .init(title: "Backup and restore", section: "Saved Docks", page: .general, keywords: "export import json saved docks"),
        .init(title: "Recovery and history", section: "Recovery & history", page: .general, keywords: "undo snapshot previous revision"),
        .init(title: "MyDock appearance", section: "Application", page: .general, keywords: "interface light dark system theme"),
        .init(title: "Launch at login", section: "Application", page: .general, keywords: "startup"),
        .init(title: "Check for updates", section: "Updates", page: .general, keywords: "version release source repository"),
        .init(title: "Connections", section: "Connections", page: .integrations, keywords: "stripe paddle shopify account key token disconnect replace"),
        .init(title: "Market API key", section: "Market data", page: .integrations, keywords: "stock watchlist alpha vantage"),
        .init(title: "GitHub Copilot credentials", section: "GitHub Copilot usage", page: .integrations, keywords: "ai credits token plan limits"),
        .init(title: "Permissions", section: "Permission status", page: .permissions, keywords: "accessibility automation calendar reminders location notifications screen recording"),
    ]
    static func matches(_ query: String) -> [SettingsSearchEntry] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        return entries.filter { entry in terms.allSatisfy { (entry.title + " " + entry.section + " " + entry.keywords).lowercased().contains($0) } }
    }
}

struct SettingsSearchResults: View {
    var query: String
    var select: (SettingsSearchEntry) -> Void
    var body: some View {
        DockScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search results").font(DockDesign.title)
                Text("Settings matching “\(query)”").font(DockDesign.body).foregroundStyle(.secondary)
                let matches = SettingsSearchCatalog.matches(query)
                if matches.isEmpty { Text("No matching settings. Try a feature or control name.").foregroundStyle(.secondary) }
                ForEach(matches) { entry in
                    SidebarRow {
                        HStack {
                            GroupedRowGlyph(symbol: entry.page.symbol, color: entry.page.designColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.title).font(.system(size: 13, weight: .medium))
                                Text(entry.page.title + " → " + entry.section).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.padding(.vertical, 8)
                    } action: { select(entry) }
                }
            }.padding(DockDesign.Space.page).frame(maxWidth: DockDesign.settingsWidth).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
