import Foundation
import UserNotifications

/// The one reading of notification permission shared by Alarm, Countdown and Hydration.
enum NotificationAuthorization {
    /// Statuses under which macOS delivers MyDock's alerts, including quiet provisional delivery.
    static func isDeliverable(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        @unknown default: false
        }
    }

    static let deniedMessage = "Notification access is disabled. Enable alerts for MyDock in System Settings."
}

struct WidgetNotificationGenerationPolicy {
    private(set) var currentOperationByItem: [UUID: UUID] = [:]

    mutating func begin(itemID: UUID, operationID: UUID) {
        currentOperationByItem[itemID] = operationID
    }

    /// Invalidates the item's in-flight operation and forgets the item, so the map does not grow per item ever touched.
    mutating func end(itemID: UUID) {
        currentOperationByItem.removeValue(forKey: itemID)
    }

    func isCurrent(itemID: UUID, operationID: UUID) -> Bool {
        currentOperationByItem[itemID] == operationID
    }

    func currentOperation(for itemID: UUID) -> UUID? {
        currentOperationByItem[itemID]
    }

    static func obsoleteIdentifiers(_ identifiers: [String], prefix: String, preserving currentID: String?) -> [String] {
        identifiers.filter { identifier in
            (identifier == prefix || identifier.hasPrefix(prefix + ".")) && identifier != currentID
        }
    }
}
