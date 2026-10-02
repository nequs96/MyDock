import Foundation

enum ProfileSanitizer {
    static func sanitize(_ profile: DockProfile, includeNotes: Bool = false) -> DockProfile {
        var copy = profile
        for index in copy.items.indices {
            guard var c = copy.items[index].widgetConfiguration else { continue }
            if !includeNotes { c.noteText = ""; c.checklistEntries = [] }
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
            for index in c.alarms.indices { c.alarms[index].isEnabled = false }
            copy.items[index].widgetConfiguration = c
        }
        return copy
    }

    static func newIdentity(_ profile: DockProfile) -> DockProfile {
        var copy = profile
        copy.id = UUID(); copy.createdAt = .now
        copy.items = copy.items.map { item in var copy = item; copy.id = UUID(); return copy }
        return copy
    }
}
