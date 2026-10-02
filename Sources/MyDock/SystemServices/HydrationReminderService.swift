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
    private static var generations = WidgetNotificationGenerationPolicy()

    static func begin(itemID: UUID, operationID: UUID) {
        generations.begin(itemID: itemID, operationID: operationID)
    }

    static func isCurrent(itemID: UUID, operationID: UUID) -> Bool {
        generations.isCurrent(itemID: itemID, operationID: operationID)
    }

    static func schedule(itemID: UUID, operationID: UUID, intervalMinutes: Int) async throws {
        let center = UNUserNotificationCenter.current()
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else { return }
        guard try await center.requestAuthorization(options: [.alert, .sound]) else {
            throw HydrationReminderError.permissionDenied
        }
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else { return }
        let identifier = notificationID(for: itemID, operationID: operationID)

        let content = UNMutableNotificationContent()
        content.title = "Time for a drink of water"
        content.body = "Take a moment to drink some water."
        content.sound = .default
        let minutes = min(max(intervalMinutes, 30), 240)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(minutes * 60), repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try await center.add(request)
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let prefix = notificationPrefix(for: itemID)
        let pending = await center.pendingNotificationRequests()
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let obsolete = pending.map(\.identifier).filter {
            ($0 == prefix || $0.hasPrefix(prefix + ".")) && $0 != identifier
        }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
    }

    static func cancel(itemID: UUID, operationID: UUID) {
        generations.begin(itemID: itemID, operationID: operationID)
        let center = UNUserNotificationCenter.current()
        let prefix = notificationPrefix(for: itemID)
        center.removePendingNotificationRequests(withIdentifiers: [prefix])
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            let currentID = generations.currentOperation(for: itemID).map {
                notificationID(for: itemID, operationID: $0)
            }
            let identifiers = WidgetNotificationGenerationPolicy.obsoleteIdentifiers(
                pending.map(\.identifier), prefix: prefix, preserving: currentID)
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
    }

    static func notificationPrefix(for itemID: UUID) -> String {
        "mydock.hydration.\(itemID.uuidString)"
    }

    static func notificationID(for itemID: UUID, operationID: UUID) -> String {
        "\(notificationPrefix(for: itemID)).\(operationID.uuidString)"
    }
}
