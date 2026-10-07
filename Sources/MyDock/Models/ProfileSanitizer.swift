import Foundation

enum ProfileSanitizer {
    /// Alarm titles are free text, so private-text exclusion replaces them with this generic name.
    static let genericAlarmTitle = "Alarm"

    static func sanitize(_ profile: DockProfile, includeNotes: Bool = false) -> DockProfile {
        var copy = profile
        for index in copy.items.indices {
            guard var c = copy.items[index].widgetConfiguration else { continue }
            if !includeNotes { c.noteText = ""; c.checklistEntries = [] }
            c.shelfFiles = []; c.quickLinks = []
            if !includeNotes { c.textSnippets = [] }
            c.stripeAccountID = ""; c.stripeSnapshot = nil
            c.paddleAccountID = ""; c.paddleSnapshot = nil
            c.shopifyStoreID = ""; c.shopifySnapshot = nil
            c.stockSnapshot = nil
            for index in c.watchlistStocks.indices { c.watchlistStocks[index].snapshot = nil }
            c.aiLimitsSnapshot = nil; c.aiActivitySnapshot = nil
            c.hydrationEntries = []; c.hydrationLastRemovedEntry = nil; c.hydrationRemindersEnabled = false
            c.selectedCalendarIDs = []; c.selectedReminderCalendarID = ""
            c.selectedShortcutName = ""
            c.weatherLocation = nil; c.cachedWeatherForecast = nil
            c.resetFocusTimer(); c.resetStopwatch(); c.resetCountdown()
            c.countdownTargetDate = nil
            for index in c.alarms.indices {
                c.alarms[index].isEnabled = false
                if !includeNotes { c.alarms[index].title = genericAlarmTitle }
            }
            copy.items[index].widgetConfiguration = c
        }
        return copy
    }

    static func newIdentity(_ profile: DockProfile) -> DockProfile {
        var copy = profile
        copy.id = UUID(); copy.createdAt = .now
        copy.items = copy.items.map { $0.preparedForNewIdentity() }
        copy.workspace = profile.workspace?.remapped(from: profile.items, to: copy.items)
        return copy
    }
}

extension DockItem {
    /// A copy that can live beside the original: a new identity, and nothing that would schedule on this Mac a second
    /// time. Hydration reminders and alarms start off, and a duration Countdown starts from its full duration.
    /// Duplication, Restore, Dock packages and Recovery all use this one rule.
    func preparedForNewIdentity() -> DockItem {
        var copy = self
        copy.id = UUID()
        if copy.widgetKind == "Hydration" { copy.widgetConfiguration?.hydrationRemindersEnabled = false }
        if copy.widgetKind == "Countdown", copy.widgetConfiguration?.countdownMode != .targetDate {
            copy.widgetConfiguration?.resetCountdown()
        }
        if copy.widgetKind == "Alarm", var configuration = copy.widgetConfiguration {
            for index in configuration.alarms.indices { configuration.alarms[index].isEnabled = false }
            copy.widgetConfiguration = configuration
        }
        return copy
    }
}
