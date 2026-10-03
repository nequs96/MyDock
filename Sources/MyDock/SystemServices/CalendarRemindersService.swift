import EventKit
import Foundation

enum CalendarRemindersServiceError: LocalizedError {
    case accessDenied
    case calendarUnavailable
    case reminderUnavailable
    case reminderFetchFailed
    case noWritableReminderList

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Allow Calendar or Reminders access in System Settings to use this widget."
        case .calendarUnavailable: "That calendar is no longer available. Choose another calendar or show all calendars."
        case .reminderUnavailable: "That reminder is no longer available. Refresh the list and try again."
        case .reminderFetchFailed: "Reminders could not be loaded. Check access and try again."
        case .noWritableReminderList: "There is no writable Reminders list available."
        }
    }
}

struct CalendarListSnapshot: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
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
                    meetingURL: meetingURL(event)
                )
            }
            .sorted { CalendarEventOrdering.precedes($0, $1, now: now) }
            .prefix(60)
            .map { $0 }
        guard hasFullAccess(to: .event) else { throw CalendarRemindersServiceError.accessDenied }
        return events
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
        let snapshots: [ReminderSnapshot]? = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
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
                continuation.resume(returning: snapshots)
            }
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
    static func precedes(_ lhs: CalendarEventSnapshot, _ rhs: CalendarEventSnapshot, now: Date = .now) -> Bool {
        let lhsOngoing = !lhs.isAllDay && lhs.startDate <= now && lhs.endDate >= now
        let rhsOngoing = !rhs.isAllDay && rhs.startDate <= now && rhs.endDate >= now
        if lhsOngoing != rhsOngoing { return lhsOngoing }
        if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
        if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    static func compactEvent(from events: [CalendarEventSnapshot], now: Date = .now) -> CalendarEventSnapshot? {
        events.sorted { precedes($0, $1, now: now) }.first
    }
}
