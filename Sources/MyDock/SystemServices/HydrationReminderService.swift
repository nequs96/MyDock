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

enum HydrationNotificationAuthorization: Equatable, Sendable {
    case authorized
    case denied
    case notDetermined
}

/// Notification access used by Hydration reminders. Fixtures inject a fake; the app uses `LiveHydrationNotificationCenter`.
@MainActor
protocol HydrationNotificationCenter {
    func authorization() async -> HydrationNotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(identifier: String, intervalMinutes: Int) async throws
    func remove(identifiers: [String])
}

@MainActor
struct LiveHydrationNotificationCenter: HydrationNotificationCenter {
    func authorization() async -> HydrationNotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func add(identifier: String, intervalMinutes: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Time for a drink of water"
        content.body = "Take a moment to drink some water."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(intervalMinutes * 60), repeats: true)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    func remove(identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// An enabled Hydration reminder as saved in a profile.
struct HydrationReminderTarget: Equatable, Sendable {
    var profileID: UUID
    var itemID: UUID
    var intervalMinutes: Int
}

enum HydrationReconcileAction: Equatable {
    /// Notifications are not allowed any more, so the saved enabled state cannot be honoured.
    case disable(HydrationReminderTarget)
    /// Authorized but no pending request survived (relaunch, cleared by the system).
    case schedule(HydrationReminderTarget)
    /// Duplicate or orphaned pending requests to remove.
    case remove([String])
}

@MainActor
enum HydrationReconcilePlanner {
    static let identifierRoot = "mydock.hydration."

    /// Pure decision: never prompts, never schedules a second request for an item that already has one.
    static func plan(targets: [HydrationReminderTarget],
                     authorization: HydrationNotificationAuthorization,
                     pending: [String]) -> [HydrationReconcileAction] {
        var actions: [HydrationReconcileAction] = []
        var removals: [String] = []
        let enabledItems = Set(targets.map(\.itemID))

        for target in targets {
            let prefix = HydrationReminderService.notificationPrefix(for: target.itemID)
            let own = pending.filter { $0 == prefix || $0.hasPrefix(prefix + ".") }.sorted()
            guard authorization == .authorized else {
                removals.append(contentsOf: own)
                actions.append(.disable(target))
                continue
            }
            if own.isEmpty {
                actions.append(.schedule(target))
            } else if own.count > 1 {
                removals.append(contentsOf: own.dropFirst())
            }
        }
        // Pending Hydration requests whose item no longer has reminders enabled.
        for identifier in pending where identifier.hasPrefix(identifierRoot) {
            guard let itemID = itemID(fromIdentifier: identifier), !enabledItems.contains(itemID) else { continue }
            removals.append(identifier)
        }
        if !removals.isEmpty { actions.insert(.remove(Array(Set(removals)).sorted()), at: 0) }
        return actions
    }

    static func itemID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(identifierRoot) else { return nil }
        let remainder = identifier.dropFirst(identifierRoot.count)
        return UUID(uuidString: String(remainder.prefix(36)))
    }
}

enum HydrationReconcileOutcome: Equatable {
    case unchanged(UUID)
    case rescheduled(UUID)
    case disabled(UUID)
    case superseded(UUID)
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
        try AppRuntimeEnvironment.requireNativeEffects()
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        try await schedule(itemID: itemID, operationID: operationID, intervalMinutes: intervalMinutes,
                           center: LiveHydrationNotificationCenter(), promptForAuthorization: true)
    }

    static func schedule(itemID: UUID,
                         operationID: UUID,
                         intervalMinutes: Int,
                         center: any HydrationNotificationCenter,
                         promptForAuthorization: Bool) async throws {
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else { return }
        if promptForAuthorization {
            guard try await center.requestAuthorization() else {
                throw HydrationReminderError.permissionDenied
            }
        } else if await center.authorization() != .authorized {
            throw HydrationReminderError.permissionDenied
        }
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else { return }
        let identifier = notificationID(for: itemID, operationID: operationID)
        let minutes = min(max(intervalMinutes, 30), 240)
        try await center.add(identifier: identifier, intervalMinutes: minutes)
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else {
            center.remove(identifiers: [identifier])
            return
        }
        let prefix = notificationPrefix(for: itemID)
        let pending = await center.pendingIdentifiers()
        guard generations.isCurrent(itemID: itemID, operationID: operationID) else {
            center.remove(identifiers: [identifier])
            return
        }
        let obsolete = pending.filter {
            ($0 == prefix || $0.hasPrefix(prefix + ".")) && $0 != identifier
        }
        center.remove(identifiers: obsolete)
    }

    static func cancel(itemID: UUID, operationID: UUID) {
        generations.begin(itemID: itemID, operationID: operationID)
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        cancelPending(itemID: itemID, center: LiveHydrationNotificationCenter())
    }

    static func cancelPending(itemID: UUID, center: any HydrationNotificationCenter) {
        let prefix = notificationPrefix(for: itemID)
        center.remove(identifiers: [prefix])
        Task { @MainActor in
            let pending = await center.pendingIdentifiers()
            let currentID = generations.currentOperation(for: itemID).map {
                notificationID(for: itemID, operationID: $0)
            }
            let identifiers = WidgetNotificationGenerationPolicy.obsoleteIdentifiers(
                pending, prefix: prefix, preserving: currentID)
            center.remove(identifiers: identifiers)
        }
    }

    /// Startup/wake reconciliation. Reads authorization and pending requests without prompting, then
    /// reschedules reminders that were lost or disables ones that can no longer be delivered.
    /// `targets` is read after the asynchronous reads so it reflects the latest saved configuration.
    static func reconcile(using center: any HydrationNotificationCenter,
                          targets: () -> [HydrationReminderTarget]) async -> [HydrationReconcileOutcome] {
        let authorization = await center.authorization()
        let pending = await center.pendingIdentifiers()
        let current = targets()
        var outcomes: [HydrationReconcileOutcome] = []
        let actions = HydrationReconcilePlanner.plan(targets: current, authorization: authorization, pending: pending)
        var handled = Set<UUID>()
        for action in actions {
            switch action {
            case .remove(let identifiers):
                center.remove(identifiers: identifiers)
            case .disable(let target):
                handled.insert(target.itemID)
                outcomes.append(.disabled(target.itemID))
            case .schedule(let target):
                handled.insert(target.itemID)
                let operationID = UUID()
                begin(itemID: target.itemID, operationID: operationID)
                do {
                    try await schedule(itemID: target.itemID, operationID: operationID,
                                       intervalMinutes: target.intervalMinutes,
                                       center: center, promptForAuthorization: false)
                    outcomes.append(isCurrent(itemID: target.itemID, operationID: operationID)
                                    ? .rescheduled(target.itemID) : .superseded(target.itemID))
                } catch {
                    outcomes.append(isCurrent(itemID: target.itemID, operationID: operationID)
                                    ? .disabled(target.itemID) : .superseded(target.itemID))
                }
            }
        }
        for target in current where !handled.contains(target.itemID) {
            outcomes.append(.unchanged(target.itemID))
        }
        return outcomes
    }

    /// Applies reconciliation to saved profiles. Mirrors the Alarm startup reconcile.
    static func reconcileSchedules(in store: ProfileStore) async {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let outcomes = await reconcile(using: LiveHydrationNotificationCenter()) {
            enabledTargets(in: store)
        }
        let profileByItem = Dictionary(enabledTargets(in: store).map { ($0.itemID, $0.profileID) },
                                       uniquingKeysWith: { first, _ in first })
        for case .disabled(let itemID) in outcomes {
            guard let profileID = profileByItem[itemID] else { continue }
            store.updateWidgetConfiguration(itemID: itemID, in: profileID) { $0.hydrationRemindersEnabled = false }
        }
    }

    private static func enabledTargets(in store: ProfileStore) -> [HydrationReminderTarget] {
        store.state.profiles.filter { $0.kind == .custom }.flatMap { profile in
            profile.items.compactMap { item -> HydrationReminderTarget? in
                guard item.type == .widget, item.widgetKind == "Hydration",
                      let configuration = item.widgetConfiguration, configuration.hydrationRemindersEnabled else { return nil }
                return HydrationReminderTarget(profileID: profile.id, itemID: item.id,
                                               intervalMinutes: configuration.hydrationReminderIntervalMinutes)
            }
        }
    }

    static func notificationPrefix(for itemID: UUID) -> String {
        "mydock.hydration.\(itemID.uuidString)"
    }

    static func notificationID(for itemID: UUID, operationID: UUID) -> String {
        "\(notificationPrefix(for: itemID)).\(operationID.uuidString)"
    }
}
