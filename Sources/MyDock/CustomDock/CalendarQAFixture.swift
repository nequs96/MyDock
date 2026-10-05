#if DEBUG
import Foundation

/// DEBUG-only Calendar fixtures for isolated visual QA. When active, the production Calendar views read these
/// snapshots instead of EventKit, so empty, ongoing and upcoming states render without Calendar permission and
/// without touching the user's calendars. Never compiled into release builds.
enum CalendarQAFixture: String, CaseIterable {
    case empty, ongoing, upcoming

    static let environmentKey = "MYDOCK_CALENDAR_FIXTURE"

    /// Set by the QA export while it renders one state; takes precedence over the environment.
    @MainActor static var override: CalendarQAFixture?

    /// Set by the QA export to render the truthful "access denied" state without asking EventKit.
    @MainActor static var simulatesDeniedAccess = false

    /// Pure selection: an unknown or missing value selects nothing, so production behavior is unchanged.
    static func selection(override: CalendarQAFixture?, environment: [String: String]) -> CalendarQAFixture? {
        override ?? environment[environmentKey].flatMap { CalendarQAFixture(rawValue: $0.lowercased()) }
    }

    @MainActor static var current: CalendarQAFixture? {
        selection(override: override, environment: ProcessInfo.processInfo.environment)
    }

    var calendars: [CalendarListSnapshot] { [CalendarListSnapshot(id: "qa-calendar", title: "Work")] }

    func events(now: Date = Date()) -> [CalendarEventSnapshot] {
        func event(_ id: String, _ title: String, start: TimeInterval, end: TimeInterval) -> CalendarEventSnapshot {
            CalendarEventSnapshot(id: id, title: title, startDate: now.addingTimeInterval(start), endDate: now.addingTimeInterval(end),
                                  isAllDay: false, calendarID: "qa-calendar", calendarTitle: "Work", meetingURL: nil)
        }
        switch self {
        case .empty: return []
        case .ongoing: return [event("qa-ongoing", "Design review", start: -15 * 60, end: 30 * 60),
                               event("qa-later", "Planning sync", start: 3 * 3600, end: 4 * 3600)]
        case .upcoming: return [event("qa-next", "Team standup", start: 45 * 60, end: 75 * 60),
                                event("qa-after", "Lunch with Sam", start: 4 * 3600, end: 5 * 3600)]
        }
    }
}

/// DEBUG-only Reminders fixtures for isolated visual QA: the production Reminders views read these instead of
/// EventKit while an export renders, so list, empty and denied states render without touching the user's lists.
enum RemindersQAFixture: String, CaseIterable {
    case list, empty, denied

    @MainActor static var override: RemindersQAFixture?

    var lists: [ReminderListSnapshot] { self == .denied ? [] : [ReminderListSnapshot(id: "qa-list", title: "Errands")] }

    func reminders(now: Date = Date()) -> [ReminderSnapshot] {
        guard self == .list else { return [] }
        return [ReminderSnapshot(id: "qa-1", title: "Return library books", dueDate: now.addingTimeInterval(-26 * 3600), calendarID: "qa-list", calendarTitle: "Errands"),
                ReminderSnapshot(id: "qa-2", title: "Pick up groceries", dueDate: now.addingTimeInterval(3 * 3600), calendarID: "qa-list", calendarTitle: "Errands"),
                ReminderSnapshot(id: "qa-3", title: "Book a dentist appointment", dueDate: nil, calendarID: "qa-list", calendarTitle: "Errands")]
    }
}
#endif
