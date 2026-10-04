import Foundation

enum WidgetTimingPresentation {
    static func eventStatus(_ event: CalendarEventSnapshot, now: Date) -> String {
        if event.isAllDay { return "All day" }
        if event.endDate <= now { return "Ended" }
        if event.startDate <= now { return "Ongoing · ends in " + duration(event.endDate.timeIntervalSince(now)) }
        return "Starts in " + duration(event.startDate.timeIntervalSince(now))
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "unavailable" }
        let minutes = Int(min(5_256_000, max(1, ceil(seconds / 60))))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min") }
        return "\(hours / 24) day\(hours / 24 == 1 ? "" : "s")" + (hours % 24 == 0 ? "" : " \(hours % 24) hr")
    }

    static func dayRelation(offset: Int, reference: String) -> String {
        if offset == 0 { return "Same date as \(reference)" }
        return "\(offset.magnitude) day\(offset.magnitude == 1 ? "" : "s") \(offset > 0 ? "ahead of" : "behind") \(reference)"
    }

    static func isStale(fetchedAt: Date, now: Date, maximumAge: TimeInterval) -> Bool {
        now.timeIntervalSince(fetchedAt) > maximumAge
    }

    static func readingStatus(fetchedAt: Date, now: Date, maximumAge: TimeInterval) -> String {
        (isStale(fetchedAt: fetchedAt, now: now, maximumAge: maximumAge) ? "Saved reading · " : "Updated ")
            + fetchedAt.formatted(.relative(presentation: .numeric))
    }
}
