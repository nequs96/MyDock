import Foundation

/// Recognises meeting links in an event's URL or location. Pure; never invents a link and never reads notes.
enum MeetingLinkDetector {
    /// A link host matches when it equals one of these or is a subdomain of one.
    static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]

    static func isRecognised(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), !host.isEmpty else { return false }
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The event's own URL first, then a link written in its location text.
    static func link(url: URL?, location: String?) -> URL? {
        if let url, isRecognised(url) { return url }
        guard let location, !location.isEmpty,
              let expression = try? NSRegularExpression(pattern: "https?://[^\\s<>\\\"']+", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(location.startIndex..<location.endIndex, in: location)
        for match in expression.matches(in: location, range: range) {
            guard let swiftRange = Range(match.range, in: location) else { continue }
            let text = String(location[swiftRange]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]}"))
            if let candidate = URL(string: text), isRecognised(candidate) { return candidate }
        }
        return nil
    }
}

/// The one action an event offers: join a recognised meeting, or open the event's calendar.
enum CalendarEventAction: Equatable {
    case join(URL)
    case openInCalendar

    static func action(for event: CalendarEventSnapshot) -> CalendarEventAction {
        if let url = event.meetingURL, MeetingLinkDetector.isRecognised(url) { return .join(url) }
        return .openInCalendar
    }
}

/// Pure choice of the next relevant event and the wording around it.
enum NextMeeting {
    static func isOngoing(_ event: CalendarEventSnapshot, now: Date) -> Bool {
        !event.isAllDay && event.startDate <= now && event.endDate > now
    }

    /// Not ended, not declined by the current user (only when EventKit reported a status), and in the selected calendars.
    /// An empty selection means all calendars; a nonempty one never falls back to others.
    static func relevant(_ events: [CalendarEventSnapshot], calendarIDs: [String] = [], now: Date) -> [CalendarEventSnapshot] {
        events.filter { $0.endDate > now && $0.declinedByCurrentUser != true
            && (calendarIDs.isEmpty || calendarIDs.contains($0.calendarID)) }
    }

    /// An ongoing event that started longer ago than this yields to one about to start.
    static let longOngoingThreshold: TimeInterval = 30 * 60
    /// How soon an upcoming event must start to take over from a long ongoing one.
    static let imminentWindow: TimeInterval = 15 * 60

    /// Ongoing beats upcoming, except that a meeting starting within `imminentWindow` beats a block (Focus,
    /// Working from home) that began more than `longOngoingThreshold` ago. All-day and Free events are never "next".
    static func next(from events: [CalendarEventSnapshot], calendarIDs: [String] = [], now: Date) -> CalendarEventSnapshot? {
        let ordered = relevant(events, calendarIDs: calendarIDs, now: now).filter { !$0.isAllDay && !$0.isFree }
            .sorted { CalendarEventOrdering.precedes($0, $1, now: now) }
        let ongoing = ordered.filter { isOngoing($0, now: now) }
        if let recent = ongoing.first(where: { now.timeIntervalSince($0.startDate) <= longOngoingThreshold }) { return recent }
        if !ongoing.isEmpty,
           let imminent = ordered.first(where: { !isOngoing($0, now: now) && $0.startDate.timeIntervalSince(now) <= imminentWindow }) {
            return imminent
        }
        return ordered.first
    }

    /// All-day events that cover today in `calendar`, for one quiet line.
    static func allDayToday(from events: [CalendarEventSnapshot], calendarIDs: [String] = [], now: Date,
                            calendar: Calendar = .current) -> [CalendarEventSnapshot] {
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        return relevant(events, calendarIDs: calendarIDs, now: now).filter { $0.isAllDay && $0.startDate < startOfTomorrow }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// "Holiday", "Holiday, Birthday" or "Holiday +2".
    static func allDayLine(_ events: [CalendarEventSnapshot]) -> String? {
        let titles = events.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard let first = titles.first else { return nil }
        if titles.count == 1 { return first }
        if titles.count == 2 { return first + ", " + titles[1] }
        return first + " +\(titles.count - 1)"
    }

    /// "now" while ongoing, "in 12 min" within twelve hours (elapsed time, so midnight and DST cannot skew it),
    /// otherwise the start's day and time in `calendar`'s time zone.
    static func heroValue(_ event: CalendarEventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        if isOngoing(event, now: now) { return "now" }
        let seconds = event.startDate.timeIntervalSince(now)
        if seconds < 12 * 3_600 { return "in " + CalendarEventRowPresentation.relative(seconds) }
        return dayAndTime(event.startDate, now: now, calendar: calendar)
    }

    /// "18:30", "Tomorrow 09:00" or "Tue 09:00", judged by calendar days in `calendar`.
    static func dayAndTime(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = time(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return clock }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow " + clock
        }
        return date.formatted(weekdayStyle(calendar)) + " " + clock
    }

    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: calendar.locale ?? .current,
                                        calendar: calendar, timeZone: calendar.timeZone))
    }

    private static func weekdayStyle(_ calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: calendar.locale ?? .current,
                         calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
    }

    /// The location text to show: only when present, and not just the meeting link the Join action already covers.
    static func locationText(_ event: CalendarEventSnapshot) -> String? {
        guard let text = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.lowercased().hasPrefix("http"), URL(string: text) != nil { return nil }
        return text
    }
}
