import Foundation
import UserNotifications

enum CountdownNotificationError: LocalizedError {
    case permissionDenied
    case targetExpired

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Notification access is disabled. The countdown will still run, but macOS cannot alert when it finishes. Enable alerts for MyDock in System Settings."
        case .targetExpired:
            "The countdown finished before macOS could schedule its alert. Set a new target to receive a notification."
        }
    }
}

@MainActor
enum CountdownNotificationService {
    private static var generations = WidgetNotificationGenerationPolicy()

    static func begin(itemID: UUID, operationID: UUID) {
        generations.begin(itemID: itemID, operationID: operationID)
    }

    static func isCurrent(itemID: UUID, operationID: UUID) -> Bool {
        generations.isCurrent(itemID: itemID, operationID: operationID)
    }

    static func schedule(itemID: UUID, operationID: UUID, fireDate: Date) async throws {
        guard isCurrent(itemID: itemID, operationID: operationID) else { return }
        guard isFutureTarget(fireDate) else { throw CountdownNotificationError.targetExpired }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        guard isCurrent(itemID: itemID, operationID: operationID) else { return }
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw CountdownNotificationError.permissionDenied
            }
            settings = await center.notificationSettings()
            guard isCurrent(itemID: itemID, operationID: operationID) else { return }
        }
        guard settings.authorizationStatus == .authorized else {
            throw CountdownNotificationError.permissionDenied
        }
        guard isFutureTarget(fireDate) else { throw CountdownNotificationError.targetExpired }

        let identifier = notificationID(itemID: itemID, operationID: operationID)
        let content = UNMutableNotificationContent()
        content.title = "Countdown finished"
        content.body = "Your MyDock countdown is complete."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        guard isCurrent(itemID: itemID, operationID: operationID) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let pending = await center.pendingNotificationRequests()
        guard isCurrent(itemID: itemID, operationID: operationID) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let obsolete = WidgetNotificationGenerationPolicy.obsoleteIdentifiers(
            pending.map(\.identifier), prefix: notificationID(itemID: itemID), preserving: identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
    }

    static func cancel(itemID: UUID) {
        generations.begin(itemID: itemID, operationID: UUID())
        let prefix = notificationID(itemID: itemID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [prefix])
        center.removeDeliveredNotifications(withIdentifiers: [prefix])
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            let currentID = generations.currentOperation(for: itemID).map {
                notificationID(itemID: itemID, operationID: $0)
            }
            let obsolete = WidgetNotificationGenerationPolicy.obsoleteIdentifiers(
                pending.map(\.identifier), prefix: prefix, preserving: currentID)
            center.removePendingNotificationRequests(withIdentifiers: obsolete)

            let delivered = await center.deliveredNotifications()
            let latestID = generations.currentOperation(for: itemID).map {
                notificationID(itemID: itemID, operationID: $0)
            }
            let obsoleteDelivered = WidgetNotificationGenerationPolicy.obsoleteIdentifiers(
                delivered.map(\.request.identifier), prefix: prefix, preserving: latestID)
            center.removeDeliveredNotifications(withIdentifiers: obsoleteDelivered)
        }
    }

    static func notificationID(itemID: UUID) -> String {
        "mydock.countdown.\(itemID.uuidString)"
    }

    static func notificationID(itemID: UUID, operationID: UUID) -> String {
        "\(notificationID(itemID: itemID)).\(operationID.uuidString)"
    }

    static func isFutureTarget(_ target: Date, now: Date = .now) -> Bool {
        target > now
    }
}
