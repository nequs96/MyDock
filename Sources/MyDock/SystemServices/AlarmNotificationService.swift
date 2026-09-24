import Foundation
import UserNotifications

enum AlarmNotificationError: LocalizedError {
    case permissionDenied
    case invalidTime

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Notification access is disabled. Enable alerts for MyDock in System Settings to schedule alarms."
        case .invalidTime: "MyDock couldn't calculate the next time for this alarm."
        }
    }
}

enum AlarmSchedule {
    static func nextFireDate(hour: Int,
                             minute: Int,
                             repeatWeekdays: [Int] = [],
                             now: Date = .now,
                             calendar: Calendar = .current) -> Date? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let weekdays = Set(repeatWeekdays.filter { (1...7).contains($0) })
        if weekdays.isEmpty {
            var components = calendar.dateComponents([.year, .month, .day], from: now)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let today = calendar.date(from: components) else { return nil }
            if today > now { return today }
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        let matches = weekdays.compactMap { weekday in
            calendar.nextDate(after: now,
                              matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                              matchingPolicy: .nextTime,
                              repeatedTimePolicy: .first,
                              direction: .forward)
        }
        return matches.min()
    }
}

@MainActor
enum AlarmNotificationService {
    static func schedule(widgetID: UUID, alarm: DockAlarm) async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw AlarmNotificationError.permissionDenied
            }
        } else if settings.authorizationStatus != .authorized {
            throw AlarmNotificationError.permissionDenied
        }

        cancel(widgetID: widgetID, alarm: alarm)
        let content = UNMutableNotificationContent()
        content.title = alarm.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "MyDock Alarm" : alarm.title
        content.body = "Your scheduled alarm is ready."
        content.sound = .default

        let weekdays = Array(Set(alarm.repeatWeekdays.filter { (1...7).contains($0) })).sorted()
        do {
            if weekdays.isEmpty {
                guard let fireDate = AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute) else {
                    throw AlarmNotificationError.invalidTime
                }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await center.add(UNNotificationRequest(identifier: oneTimeID(widgetID: widgetID, alarmID: alarm.id),
                                                            content: content,
                                                            trigger: trigger))
            } else {
                for weekday in weekdays {
                    var components = DateComponents()
                    components.weekday = weekday
                    components.hour = alarm.hour
                    components.minute = alarm.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let identifier = repeatingID(widgetID: widgetID, alarmID: alarm.id, weekday: weekday)
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                }
            }
        } catch {
            cancel(widgetID: widgetID, alarm: alarm)
            throw error
        }
    }

    static func cancel(widgetID: UUID, alarm: DockAlarm) {
        let identifiers = notificationIDs(widgetID: widgetID, alarm: alarm)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    static func reconcileSchedules(in store: ProfileStore) async {
        let center = UNUserNotificationCenter.current()
        let authorization = await center.notificationSettings().authorizationStatus
        let pending = await center.pendingNotificationRequests()
        let pendingIdentifiers = Set(pending.map(\.identifier))
        for profile in store.state.profiles where profile.kind == .custom {
            for item in profile.items where item.type == .widget && item.widgetKind == "Alarm" {
                let configuration = item.widgetConfiguration ?? WidgetConfiguration()
                let stale = configuration.alarms.filter { alarm in
                    guard alarm.isEnabled else { return false }
                    return authorization != .authorized || !isScheduled(widgetID: item.id, alarm: alarm, pending: pendingIdentifiers)
                }
                for alarm in stale {
                    store.updateWidgetConfiguration(itemID: item.id, in: profile.id) { configuration in
                        guard let index = configuration.alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
                        configuration.alarms[index].isEnabled = false
                    }
                }
            }
        }
    }

    private static func isScheduled(widgetID: UUID, alarm: DockAlarm, pending: Set<String>) -> Bool {
        let weekdays = Array(Set(alarm.repeatWeekdays.filter { (1...7).contains($0) }))
        if weekdays.isEmpty {
            return pending.contains(oneTimeID(widgetID: widgetID, alarmID: alarm.id))
        }
        return weekdays.allSatisfy { pending.contains(repeatingID(widgetID: widgetID, alarmID: alarm.id, weekday: $0)) }
    }

    private static func notificationIDs(widgetID: UUID, alarm: DockAlarm) -> [String] {
        [oneTimeID(widgetID: widgetID, alarmID: alarm.id)]
            + (1...7).map { repeatingID(widgetID: widgetID, alarmID: alarm.id, weekday: $0) }
    }

    private static func oneTimeID(widgetID: UUID, alarmID: UUID) -> String {
        "mydock.alarm.\(widgetID.uuidString).\(alarmID.uuidString).once"
    }

    private static func repeatingID(widgetID: UUID, alarmID: UUID, weekday: Int) -> String {
        "mydock.alarm.\(widgetID.uuidString).\(alarmID.uuidString).\(weekday)"
    }
}
