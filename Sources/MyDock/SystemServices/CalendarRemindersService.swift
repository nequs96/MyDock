import CoreGraphics
import EventKit
import Foundation

enum CalendarRemindersServiceError: LocalizedError {
    case accessDenied
    case calendarUnavailable
    case reminderUnavailable
    case reminderFetchFailed
    case reminderFetchTimedOut
    case noWritableReminderList

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Allow Calendar or Reminders access in System Settings to use this widget."
        case .calendarUnavailable: "That calendar is no longer available. Choose another calendar or show all calendars."
        case .reminderUnavailable: "That reminder is no longer available. Refresh the list and try again."
        case .reminderFetchFailed: "Reminders could not be loaded. Check access and try again."
        case .reminderFetchTimedOut: "Reminders did not respond in time. Try again."
        case .noWritableReminderList: "There is no writable Reminders list available."
        }
    }
}

struct CalendarListSnapshot: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
}

/// A calendar's colour as sRGB components. Runtime-only: read from EventKit with each event, never persisted
/// in profiles or backups (CGColor is not Sendable, so the snapshot carries plain numbers).
struct CalendarColorSnapshot: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamped(red); self.green = Self.clamped(green); self.blue = Self.clamped(blue)
    }

    init?(cgColor: CGColor?) {
        guard let cgColor, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else { return nil }
        self.init(red: Double(components[0]), green: Double(components[1]), blue: Double(components[2]))
    }

    private static func clamped(_ value: Double) -> Double { value.isFinite ? min(1, max(0, value)) : 0 }
}

struct CalendarEventSnapshot: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    var meetingURL: URL?
    /// The event calendar's colour; nil when EventKit reports none. Runtime-only.
    var calendarColor: CalendarColorSnapshot? = nil

    var timeDescription: String {
        if isAllDay { return "All day" }
        return startDate.formatted(date: .omitted, time: .shortened)
    }
}

struct ReminderListSnapshot: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
}

struct ReminderSnapshot: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var dueDate: Date?
    var calendarID: String
    var calendarTitle: String
}

/// EventKit access is intentionally isolated behind an actor. The widget UI only receives
/// immutable snapshots, and no personal calendar or reminder data is read until a widget is used.
actor CalendarRemindersService {
    static let shared = CalendarRemindersService()
    /// Upper bound for one EventKit reminders fetch; the native token is cancelled when it elapses.
    static let reminderFetchTimeout: TimeInterval = 20

    private let eventStore = EKEventStore()

    func hasCalendarAccess() -> Bool { hasFullAccess(to: .event) }
    func hasRemindersAccess() -> Bool { hasFullAccess(to: .reminder) }

    func requestCalendarAccess() async throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        if hasFullAccess(to: .event) { return }
        let granted: Bool
        do {
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
        } catch {
            throw error
        }
        guard granted, hasFullAccess(to: .event) else {
            throw CalendarRemindersServiceError.accessDenied
        }
    }

    func requestRemindersAccess() async throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        if hasFullAccess(to: .reminder) { return }
        let granted: Bool
        do {
            if #available(macOS 14.0, *) {
                granted = try await eventStore.requestFullAccessToReminders()
            } else {
                granted = try await eventStore.requestAccess(to: .reminder)
            }
        } catch {
            throw error
        }
        guard granted, hasFullAccess(to: .reminder) else {
            throw CalendarRemindersServiceError.accessDenied
        }
    }

    func calendarLists() throws -> [CalendarListSnapshot] {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard hasFullAccess(to: .event) else { throw CalendarRemindersServiceError.accessDenied }
        let lists = eventStore.calendars(for: .event)
            .map { CalendarListSnapshot(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard hasFullAccess(to: .event) else { throw CalendarRemindersServiceError.accessDenied }
        return lists
    }

    func reminderLists() throws -> [ReminderListSnapshot] {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard hasFullAccess(to: .reminder) else { throw CalendarRemindersServiceError.accessDenied }
        let lists = eventStore.calendars(for: .reminder)
            .map { ReminderListSnapshot(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard hasFullAccess(to: .reminder) else { throw CalendarRemindersServiceError.accessDenied }
        return lists
    }

    func events(calendarIDs: [String], includeAllDay: Bool, now: Date = .now) throws -> [CalendarEventSnapshot] {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard hasFullAccess(to: .event) else { throw CalendarRemindersServiceError.accessDenied }
        let available = eventStore.calendars(for: .event)
        let selected: [EKCalendar]?
        if calendarIDs.isEmpty {
            selected = nil
        } else {
            selected = available.filter { calendarIDs.contains($0.calendarIdentifier) }
            guard !(selected?.isEmpty ?? true) else { throw CalendarRemindersServiceError.calendarUnavailable }
        }
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(7 * 86_400)
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: selected)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate > now }
            .filter { includeAllDay || !$0.isAllDay }
            .map { event in
                let title = displayTitle(event.title)
                return CalendarEventSnapshot(
                    id: event.eventIdentifier ?? "\(event.calendar.calendarIdentifier):\(event.startDate.timeIntervalSince1970):\(title)",
                    title: title,
                    startDate: event.startDate,
                    endDate: event.endDate,
                    isAllDay: event.isAllDay,
                    calendarID: event.calendar.calendarIdentifier,
                    calendarTitle: event.calendar.title,
                    meetingURL: meetingURL(event),
                    calendarColor: CalendarColorSnapshot(cgColor: event.calendar.cgColor)
                )
            }
        guard hasFullAccess(to: .event) else { throw CalendarRemindersServiceError.accessDenied }
        return CalendarEventOrdering.select(events, calendarIDs: calendarIDs, includeAllDay: includeAllDay, now: now)
    }

    func reminders(calendarID: String) async throws -> [ReminderSnapshot] {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard hasFullAccess(to: .reminder) else { throw CalendarRemindersServiceError.accessDenied }
        let available = eventStore.calendars(for: .reminder)
        let selected: [EKCalendar]?
        if calendarID.isEmpty {
            selected = nil
        } else {
            selected = available.filter { $0.calendarIdentifier == calendarID }
            guard !(selected?.isEmpty ?? true) else { throw CalendarRemindersServiceError.calendarUnavailable }
        }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: selected)
        let store = eventStore
        let outcome: BoundedFetchOutcome<[ReminderSnapshot]?> = await BoundedNativeFetch.run(timeout: Self.reminderFetchTimeout) { complete in
            let token = store.fetchReminders(matching: predicate) { reminders in
                let snapshots = reminders?.map { reminder in
                    let rawTitle = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return ReminderSnapshot(
                        id: reminder.calendarItemIdentifier,
                        title: rawTitle.isEmpty ? "Untitled reminder" : rawTitle,
                        dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                        calendarID: reminder.calendar.calendarIdentifier,
                        calendarTitle: reminder.calendar.title
                    )
                }.sorted { lhs, rhs in
                    switch (lhs.dueDate, rhs.dueDate) {
                    case let (l?, r?): return l == r ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : l < r
                    case (_?, nil): return true
                    case (nil, _?): return false
                    case (nil, nil): return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    }
                }
                complete(snapshots)
            }
            // Cancelling or timing out releases the native fetch instead of leaving it queued.
            nonisolated(unsafe) let fetchToken = token
            nonisolated(unsafe) let fetchStore = store
            return { fetchStore.cancelFetchRequest(fetchToken) }
        }
        let snapshots: [ReminderSnapshot]?
        switch outcome {
        case .value(let value): snapshots = value
        case .cancelled: throw CancellationError()
        case .timedOut: throw CalendarRemindersServiceError.reminderFetchTimedOut
        }
        guard hasFullAccess(to: .reminder) else { throw CalendarRemindersServiceError.accessDenied }
        try Task.checkCancellation()
        guard let snapshots else { throw CalendarRemindersServiceError.reminderFetchFailed }
        return snapshots
    }

    func addReminder(title: String, calendarID: String) throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard hasFullAccess(to: .reminder) else { throw CalendarRemindersServiceError.accessDenied }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let lists = eventStore.calendars(for: .reminder)
        let calendar: EKCalendar?
        if calendarID.isEmpty {
            let defaultList = eventStore.defaultCalendarForNewReminders()
            calendar = defaultList.flatMap { $0.isImmutable ? nil : $0 } ?? lists.first(where: { !$0.isImmutable })
        } else {
            calendar = lists.first(where: { $0.calendarIdentifier == calendarID && !$0.isImmutable })
        }
        guard let calendar else { throw CalendarRemindersServiceError.noWritableReminderList }
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        try eventStore.save(reminder, commit: true)
    }

    func setReminderCompleted(identifier: String, completed: Bool) throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard hasFullAccess(to: .reminder) else { throw CalendarRemindersServiceError.accessDenied }
        guard let reminder = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw CalendarRemindersServiceError.reminderUnavailable
        }
        reminder.isCompleted = completed
        reminder.completionDate = completed ? .now : nil
        try eventStore.save(reminder, commit: true)
    }

    private func hasFullAccess(to type: EKEntityType) -> Bool {
        let status = EKEventStore.authorizationStatus(for: type)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    private func displayTitle(_ title: String?, fallback: String = "Untitled event") -> String {
        let title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? fallback : title
    }

    private func meetingURL(_ event: EKEvent) -> URL? {
        var candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        let expression = try? NSRegularExpression(pattern: "https?://[^\\s<>\\\"']+", options: [.caseInsensitive])
        var matches: [String] = []
        if let expression {
            for text in candidates {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                matches.append(contentsOf: expression.matches(in: text, range: range).compactMap { match in
                    guard let range = Range(match.range, in: text) else { return nil }
                    return String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;)]}"))
                })
            }
        }
        candidates = matches
        for candidate in candidates {
            guard let url = URL(string: candidate), let host = url.host?.lowercased(), url.scheme == "https" else { continue }
            if host == "zoom.us" || host.hasSuffix(".zoom.us")
                || host == "meet.google.com"
                || host == "teams.microsoft.com" || host == "teams.live.com" || host.hasSuffix(".teams.microsoft.com") {
                return url
            }
        }
        return nil
    }
}

enum CalendarEventOrdering {
    /// Empty IDs mean all calendars; a nonempty scope never falls back to unrelated events.
    static func select(_ events: [CalendarEventSnapshot], calendarIDs: [String],
                       includeAllDay: Bool, now: Date = .now) -> [CalendarEventSnapshot] {
        events.filter { $0.endDate > now && (includeAllDay || !$0.isAllDay)
            && (calendarIDs.isEmpty || calendarIDs.contains($0.calendarID)) }
            .sorted { precedes($0, $1, now: now) }
            .prefix(60).map { $0 }
    }

    static func precedes(_ lhs: CalendarEventSnapshot, _ rhs: CalendarEventSnapshot, now: Date = .now) -> Bool {
        let lhsOngoing = !lhs.isAllDay && lhs.startDate <= now && lhs.endDate > now
        let rhsOngoing = !rhs.isAllDay && rhs.startDate <= now && rhs.endDate > now
        if lhsOngoing != rhsOngoing { return lhsOngoing }
        if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    static func compactEvent(from events: [CalendarEventSnapshot], now: Date = .now) -> CalendarEventSnapshot? {
        events.filter { $0.endDate > now }.sorted { precedes($0, $1, now: now) }.first
    }
}
