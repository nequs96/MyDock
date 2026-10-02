import Foundation

struct WidgetNotificationGenerationPolicy {
    private(set) var currentOperationByItem: [UUID: UUID] = [:]

    mutating func begin(itemID: UUID, operationID: UUID) {
        currentOperationByItem[itemID] = operationID
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
