import Foundation
import UserNotifications

enum AlarmNotificationError: LocalizedError, Equatable {
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
protocol AlarmNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(_ identifiers: [String])
    func removeDelivered(_ identifiers: [String])
}

/// Every system access still fails closed if accidentally injected in validation.
@MainActor
private struct SystemAlarmNotificationClient: AlarmNotificationClient {
    func authorizationStatus() async -> UNAuthorizationStatus {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return .denied }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    func requestAuthorization() async throws -> Bool {
        try AppRuntimeEnvironment.requireNativeEffects()
        return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func add(_ request: UNNotificationRequest) async throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        try await UNUserNotificationCenter.current().add(request)
    }
    func pendingIdentifiers() async -> [String] {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return [] }
        return await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }
    func deliveredIdentifiers() async -> [String] {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return [] }
        return await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier)
    }
    func removePending(_ identifiers: [String]) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func removeDelivered(_ identifiers: [String]) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}

@MainActor
enum AlarmNotificationService {
    private static var currentOperations: [UUID: [UUID: UUID]] = [:]

    static func begin(widgetID: UUID, alarmID: UUID, operationID: UUID) {
        currentOperations[widgetID, default: [:]][alarmID] = operationID
    }

    static func isCurrent(widgetID: UUID, alarmID: UUID, operationID: UUID) -> Bool {
        currentOperations[widgetID]?[alarmID] == operationID
    }

    static func schedule(widgetID: UUID, alarm: DockAlarm, operationID: UUID,
                         client injectedClient: (any AlarmNotificationClient)? = nil) async throws {
        guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else { return }
        if injectedClient == nil { try AppRuntimeEnvironment.requireNativeEffects() }
        let client: any AlarmNotificationClient = injectedClient ?? SystemAlarmNotificationClient()
        // The authored replacement has already been saved by the command owner.
        // Retire older schedules even if new permission or registration fails.
        await removeObsoleteRequests(widgetID: widgetID, alarmID: alarm.id, client: client)
        guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else { return }
        do {
            guard (0...23).contains(alarm.hour), (0...59).contains(alarm.minute) else {
                throw AlarmNotificationError.invalidTime
            }
            try Task.checkCancellation()
            let authorization = await client.authorizationStatus()
            guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else { return }
            if authorization == .notDetermined {
                guard try await client.requestAuthorization() else {
                    throw AlarmNotificationError.permissionDenied
                }
            } else if authorization != .authorized {
                throw AlarmNotificationError.permissionDenied
            }
            guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else { return }

            try Task.checkCancellation()
            let content = UNMutableNotificationContent()
            content.title = alarm.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "MyDock Alarm" : alarm.title
            content.body = "Your scheduled alarm is ready."
            content.sound = .default

            let weekdays = Array(Set(alarm.repeatWeekdays.filter { (1...7).contains($0) })).sorted()
            if weekdays.isEmpty {
                // The ring time recorded when the alarm was armed, so the face and the notification agree.
                let recorded = alarm.scheduledFireDate.flatMap { $0 > .now ? $0 : nil }
                guard let fireDate = recorded ?? AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute) else {
                    throw AlarmNotificationError.invalidTime
                }
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try await client.add(UNNotificationRequest(identifier: oneTimeID(widgetID: widgetID,
                                                                                alarmID: alarm.id,
                                                                                operationID: operationID),
                                                            content: content,
                                                            trigger: trigger))
                guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else {
                    removeOperationRequests(widgetID: widgetID, alarmID: alarm.id, operationID: operationID, client: client)
                    return
                }
            } else {
                for weekday in weekdays {
                    guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else {
                        removeOperationRequests(widgetID: widgetID, alarmID: alarm.id, operationID: operationID, client: client)
                        return
                    }
                    var components = DateComponents()
                    components.weekday = weekday
                    components.hour = alarm.hour
                    components.minute = alarm.minute
                    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                    let identifier = repeatingID(widgetID: widgetID,
                                                 alarmID: alarm.id,
                                                 operationID: operationID,
                                                 weekday: weekday)
                    try await client.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    guard isCurrent(widgetID: widgetID, alarmID: alarm.id, operationID: operationID) else {
                        removeOperationRequests(widgetID: widgetID, alarmID: alarm.id, operationID: operationID, client: client)
                        return
                    }
                }
            }
        } catch {
            removeOperationRequests(widgetID: widgetID, alarmID: alarm.id, operationID: operationID, client: client)
            throw error
        }
        await removeObsoleteRequests(widgetID: widgetID, alarmID: alarm.id, client: client)
    }

    /// Cancels one command without disturbing a replacement that began while it awaited macOS.
    static func cancelOperation(widgetID: UUID, alarmID: UUID, operationID: UUID,
                                client injectedClient: (any AlarmNotificationClient)? = nil) {
        if isCurrent(widgetID: widgetID, alarmID: alarmID, operationID: operationID) {
            currentOperations[widgetID]?.removeValue(forKey: alarmID)
            if currentOperations[widgetID]?.isEmpty == true { currentOperations.removeValue(forKey: widgetID) }
        }
        guard injectedClient != nil || AppRuntimeEnvironment.allowsNativeEffects else { return }
        removeOperationRequests(widgetID: widgetID, alarmID: alarmID, operationID: operationID,
                                client: injectedClient ?? SystemAlarmNotificationClient())
    }

    static func cancel(widgetID: UUID, alarm: DockAlarm,
                       client injectedClient: (any AlarmNotificationClient)? = nil) {
        let previousOperation = currentOperations[widgetID]?[alarm.id]
        currentOperations[widgetID]?.removeValue(forKey: alarm.id)
        if currentOperations[widgetID]?.isEmpty == true { currentOperations.removeValue(forKey: widgetID) }
        let identifiers = legacyIDs(widgetID: widgetID, alarmID: alarm.id)
            + (previousOperation.map { operationIDs(widgetID: widgetID, alarmID: alarm.id, operationID: $0) } ?? [])
        guard injectedClient != nil || AppRuntimeEnvironment.allowsNativeEffects else { return }
        let client: any AlarmNotificationClient = injectedClient ?? SystemAlarmNotificationClient()
        client.removePending(identifiers)
        client.removeDelivered(identifiers)
        Task { @MainActor in await removeObsoleteRequests(widgetID: widgetID, alarmID: alarm.id, client: client) }
    }

    static func cancelAll(widgetID: UUID, alarms: [DockAlarm],
                          client injectedClient: (any AlarmNotificationClient)? = nil) {
        let previous = currentOperations.removeValue(forKey: widgetID) ?? [:]
        let knownAlarmIDs = Set(alarms.map(\.id)).union(previous.keys)
        let identifiers = knownAlarmIDs.flatMap { alarmID in
            legacyIDs(widgetID: widgetID, alarmID: alarmID)
                + (previous[alarmID].map { operationIDs(widgetID: widgetID, alarmID: alarmID, operationID: $0) } ?? [])
        }
        guard injectedClient != nil || AppRuntimeEnvironment.allowsNativeEffects else { return }
        let client: any AlarmNotificationClient = injectedClient ?? SystemAlarmNotificationClient()
        client.removePending(identifiers)
        client.removeDelivered(identifiers)
        Task { @MainActor in await removeObsoleteRequests(widgetID: widgetID, alarmID: nil, client: client) }
    }

    static func reconcileSchedules(in store: ProfileStore) async {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
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

    static func isScheduled(widgetID: UUID, alarm: DockAlarm, pending: Set<String>) -> Bool {
        let weekdays = Set(alarm.repeatWeekdays.filter { (1...7).contains($0) })
        let requiredSuffixes: Set<String> = weekdays.isEmpty ? ["once"] : Set(weekdays.map(String.init))
        let prefix = notificationPrefix(widgetID: widgetID, alarmID: alarm.id) + "."
        if requiredSuffixes.allSatisfy({ pending.contains(prefix + $0) }) { return true }

        var suffixesByOperation: [UUID: Set<String>] = [:]
        for identifier in pending where identifier.hasPrefix(prefix) {
            let tail = identifier.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
            guard tail.count == 2, let operationID = UUID(uuidString: String(tail[0])) else { continue }
            suffixesByOperation[operationID, default: []].insert(String(tail[1]))
        }
        return suffixesByOperation.values.contains { requiredSuffixes.isSubset(of: $0) }
    }

    static func notificationPrefix(widgetID: UUID, alarmID: UUID) -> String {
        "mydock.alarm.\(widgetID.uuidString).\(alarmID.uuidString)"
    }

    static func oneTimeID(widgetID: UUID, alarmID: UUID, operationID: UUID) -> String {
        "\(notificationPrefix(widgetID: widgetID, alarmID: alarmID)).\(operationID.uuidString).once"
    }

    static func repeatingID(widgetID: UUID, alarmID: UUID, operationID: UUID, weekday: Int) -> String {
        "\(notificationPrefix(widgetID: widgetID, alarmID: alarmID)).\(operationID.uuidString).\(weekday)"
    }

    private static func legacyIDs(widgetID: UUID, alarmID: UUID) -> [String] {
        let prefix = notificationPrefix(widgetID: widgetID, alarmID: alarmID)
        return [prefix + ".once"] + (1...7).map { prefix + ".\($0)" }
    }

    private static func operationIDs(widgetID: UUID, alarmID: UUID, operationID: UUID) -> [String] {
        [oneTimeID(widgetID: widgetID, alarmID: alarmID, operationID: operationID)]
            + (1...7).map { repeatingID(widgetID: widgetID, alarmID: alarmID, operationID: operationID, weekday: $0) }
    }

    private static func removeOperationRequests(widgetID: UUID, alarmID: UUID, operationID: UUID,
                                                client: any AlarmNotificationClient) {
        let identifiers = operationIDs(widgetID: widgetID, alarmID: alarmID, operationID: operationID)
        client.removePending(identifiers)
        client.removeDelivered(identifiers)
    }

    private static func removeObsoleteRequests(widgetID: UUID, alarmID: UUID?,
                                                client injectedClient: (any AlarmNotificationClient)? = nil) async {
        guard injectedClient != nil || AppRuntimeEnvironment.allowsNativeEffects else { return }
        let client: any AlarmNotificationClient = injectedClient ?? SystemAlarmNotificationClient()
        let pending = await client.pendingIdentifiers()
        client.removePending(obsoleteIdentifiers(pending, widgetID: widgetID, alarmID: alarmID))
        let delivered = await client.deliveredIdentifiers()
        client.removeDelivered(obsoleteIdentifiers(delivered, widgetID: widgetID, alarmID: alarmID))
    }

    private static func obsoleteIdentifiers(_ identifiers: [String], widgetID: UUID, alarmID: UUID?) -> [String] {
        let widgetPrefix = "mydock.alarm.\(widgetID.uuidString)."
        let alarmPrefix = alarmID.map { notificationPrefix(widgetID: widgetID, alarmID: $0) + "." }
        let preservedPrefixes = (currentOperations[widgetID] ?? [:]).map { key, operationID in
            notificationPrefix(widgetID: widgetID, alarmID: key) + ".\(operationID.uuidString)."
        }
        return identifiers.filter { identifier in
            guard identifier.hasPrefix(widgetPrefix) else { return false }
            if let alarmPrefix, !identifier.hasPrefix(alarmPrefix) { return false }
            return !preservedPrefixes.contains(where: identifier.hasPrefix)
        }
    }
}
