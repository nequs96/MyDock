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
    static func schedule(itemID: UUID, fireDate: Date) async throws {
        guard isFutureTarget(fireDate) else { throw CountdownNotificationError.targetExpired }
        let center = UNUserNotificationCenter.current()
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw CountdownNotificationError.permissionDenied
            }
            settings = await center.notificationSettings()
        }
        guard settings.authorizationStatus == .authorized else {
            throw CountdownNotificationError.permissionDenied
        }
        guard isFutureTarget(fireDate) else { throw CountdownNotificationError.targetExpired }

        let identifier = notificationID(itemID: itemID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        let content = UNMutableNotificationContent()
        content.title = "Countdown finished"
        content.body = "Your MyDock countdown is complete."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, fireDate.timeIntervalSinceNow), repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel(itemID: UUID) {
        let identifier = notificationID(itemID: itemID)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    static func notificationID(itemID: UUID) -> String {
        "mydock.countdown.\(itemID.uuidString)"
    }

    static func isFutureTarget(_ target: Date, now: Date = .now) -> Bool {
        target > now
    }
}
