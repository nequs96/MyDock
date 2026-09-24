import Foundation
import UserNotifications

enum HydrationReminderError: LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "MyDock does not have permission to send reminder notifications. Enable them in System Settings and try again."
        }
    }
}

@MainActor
enum HydrationReminderService {
    static func schedule(itemID: UUID, intervalMinutes: Int) async throws {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw HydrationReminderError.permissionDenied
        }
        let identifier = notificationID(for: itemID)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "Time for a drink of water"
        content.body = "Take a moment to drink some water."
        content.sound = .default
        let minutes = min(max(intervalMinutes, 30), 240)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    static func cancel(itemID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID(for: itemID)])
    }

    private static func notificationID(for itemID: UUID) -> String {
        "mydock.hydration.\(itemID.uuidString)"
    }
}
