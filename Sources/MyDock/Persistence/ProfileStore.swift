import Combine
import Foundation
import OSLog

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var state: PersistentState
    @Published private(set) var persistenceError: String?
    @Published private(set) var persistenceWarning: String?
    var draggingItemID: UUID?

    private let fileURL: URL
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "persistence")
    private var storageWritable = true

    init(fileURL: URL? = nil) {
        let supportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let support = supportRoot.appendingPathComponent(Product.name, isDirectory: true)
        self.fileURL = fileURL ?? support.appendingPathComponent("state.json")
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                let data = try Data(contentsOf: self.fileURL)
                var loaded = try JSONDecoder().decode(PersistentState.self, from: data)
                guard loaded.schemaVersion <= Product.stateSchemaVersion else {
                    self.state = PersistentState()
                    self.storageWritable = false
                    self.persistenceWarning = "This MyDock data was created by a newer version. It was left untouched, and saving is disabled to protect it."
                    return
                }
                loaded.schemaVersion = Product.stateSchemaVersion
                self.state = loaded
            } catch {
                self.state = PersistentState()
                let recoveryURL = self.fileURL.appendingPathExtension("recovery-\(UUID().uuidString)")
                do {
                    try FileManager.default.moveItem(at: self.fileURL, to: recoveryURL)
                    self.persistenceWarning = "Saved profile data could not be opened. The original file was preserved at \(recoveryURL.path). MyDock started with an empty profile list."
                    logger.error("State file could not be decoded and was preserved for recovery")
                } catch {
                    self.storageWritable = false
                    self.persistenceError = "Saved profile data could not be opened or safely preserved. Saving is disabled to avoid overwriting it."
                    logger.error("State recovery failed; writes are disabled")
                }
            }
        } else {
            self.state = PersistentState()
        }
    }

    var customProfiles: [DockProfile] { state.profiles.filter { $0.kind == .custom } }
    var nativeProfiles: [DockProfile] { state.profiles.filter { $0.kind == .native } }
    var activeCustomProfile: DockProfile? {
        guard let id = state.settings.activeCustomProfileID else { return nil }
        return state.profiles.first { $0.id == id && $0.kind == .custom }
    }

    @discardableResult
    func createProfile(kind: DockProfileKind, name: String? = nil) -> UUID {
        let baseName = name ?? (kind == .custom ? "Custom Dock" : "macOS Dock")
        var candidate = baseName
        var suffix = 2
        while state.profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        let profile = DockProfile(name: candidate, kind: kind)
        state.profiles.append(profile)
        if kind == .custom {
            state.settings.activeCustomProfileID = profile.id
            if state.settings.setupMode == .nativeOnly { state.settings.setupMode = .both }
        } else {
            state.settings.activeNativeProfileID = profile.id
        }
        commit()
        return profile.id
    }

    func duplicateProfile(_ id: UUID) {
        guard let original = state.profiles.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id = UUID()
        copy.name = "\(original.name) Copy"
        copy.createdAt = .now
        copy.items = original.items.map { item in
            var copy = item
            copy.id = UUID()
            if copy.widgetKind == "Hydration" { copy.widgetConfiguration?.hydrationRemindersEnabled = false }
            if copy.widgetKind == "Countdown", copy.widgetConfiguration?.countdownMode != .targetDate {
                copy.widgetConfiguration?.resetCountdown()
            }
            if copy.widgetKind == "Alarm", var configuration = copy.widgetConfiguration {
                configuration.alarms = configuration.alarms.map { alarm in
                    var alarm = alarm
                    alarm.isEnabled = false
                    return alarm
                }
                copy.widgetConfiguration = configuration
            }
            return copy
        }
        state.profiles.append(copy)
        commit()
    }

    func deleteProfile(_ id: UUID) {
        DockShortcutStore.shared.remove(for: id)
        if let profile = state.profiles.first(where: { $0.id == id }) {
            profile.items.forEach(cancelScheduledNotifications(for:))
        }
        state.profiles.removeAll { $0.id == id }
        if state.settings.activeCustomProfileID == id {
            state.settings.activeCustomProfileID = customProfiles.first?.id
        }
        if state.settings.activeNativeProfileID == id {
            state.settings.activeNativeProfileID = nativeProfiles.first?.id
        }
        commit()
    }

    func activate(_ id: UUID) {
        guard let profile = state.profiles.first(where: { $0.id == id }) else { return }
        if profile.kind == .custom {
            state.settings.activeCustomProfileID = id
            if state.settings.setupMode == .nativeOnly { state.settings.setupMode = .both }
        } else {
            state.settings.activeNativeProfileID = id
        }
        commit()
    }

    func setSetupMode(_ mode: SetupMode) {
        state.settings.setupMode = mode
        commit()
    }

    func completeOnboarding() {
        state.settings.onboardingComplete = true
        commit()
    }

    func finishOnboarding(setupMode: SetupMode,
                          customDockPosition: DockPosition,
                          customDockDisplayID: UInt32?,
                          importedNativeItems: [DockItem],
                          starterWidgets: [String]) {
        var nextState = state
        nextState.settings.setupMode = setupMode
        nextState.settings.customDockPosition = customDockPosition
        nextState.settings.customDockDisplayID = customDockDisplayID

        if setupMode != .customMain {
            if let existing = nextState.settings.activeNativeProfileID,
               nextState.profiles.contains(where: { $0.id == existing && $0.kind == .native }) {
                // Keep the selected profile.
            } else if let first = nextState.profiles.first(where: { $0.kind == .native }) {
                nextState.settings.activeNativeProfileID = first.id
            } else {
                let profile = DockProfile(name: "macOS Dock", kind: .native, items: importedNativeItems)
                nextState.profiles.append(profile)
                nextState.settings.activeNativeProfileID = profile.id
            }
        }

        if setupMode != .nativeOnly {
            if let existing = nextState.settings.activeCustomProfileID,
               nextState.profiles.contains(where: { $0.id == existing && $0.kind == .custom }) {
                // Keep the selected profile.
            } else if let first = nextState.profiles.first(where: { $0.kind == .custom }) {
                nextState.settings.activeCustomProfileID = first.id
            } else {
                let profile = DockProfile(name: "Custom Dock", kind: .custom,
                                          items: starterWidgets.map(DockItem.widget))
                nextState.profiles.append(profile)
                nextState.settings.activeCustomProfileID = profile.id
            }
        }

        nextState.settings.onboardingComplete = true
        state = nextState
        commit()
    }

    func updateSettings(_ update: (inout AppSettings) -> Void) {
        update(&state.settings)
        commit()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        commit()
    }

    func setProfileColor(_ id: UUID, to color: DockProfileColor) {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[index].color = color.rawValue
        commit()
    }

    func add(_ item: DockItem, to profileID: UUID? = nil) {
        let targetID = profileID ?? state.settings.activeCustomProfileID
        guard let targetID, let index = state.profiles.firstIndex(where: { $0.id == targetID }) else { return }
        state.profiles[index].items.append(item)
        commit()
    }

    func addSpacer(_ kind: SpacerKind) {
        guard let profile = activeCustomProfile ?? state.profiles.first(where: { $0.id == state.settings.activeNativeProfileID }) else { return }
        add(.spacer(kind), to: profile.id)
    }

    func removeItem(_ itemID: UUID, from profileID: UUID) {
        removeItems([itemID], from: profileID)
    }

    func removeItems(_ itemIDs: Set<UUID>, from profileID: UUID) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let removedItems = state.profiles[index].items.filter { itemIDs.contains($0.id) }
        guard !removedItems.isEmpty else { return }
        removedItems.forEach(cancelScheduledNotifications(for:))
        state.profiles[index].items.removeAll { itemIDs.contains($0.id) }
        commit()
    }

    func moveItem(_ itemID: UUID, before targetID: UUID, in profileID: UUID) {
        guard itemID != targetID,
              let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }),
              let sourceIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }),
              let targetIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = state.profiles[profileIndex].items.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        state.profiles[profileIndex].items.insert(item, at: adjustedTarget)
        commit()
    }

    func moveItems(_ itemIDs: Set<UUID>, direction: DockItemMoveDirection, in profileID: UUID) {
        guard !itemIDs.isEmpty,
              let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let items = DockItemOrderingPolicy.moving(state.profiles[profileIndex].items, ids: itemIDs, direction: direction)
        guard items.map(\.id) != state.profiles[profileIndex].items.map(\.id) else { return }
        state.profiles[profileIndex].items = items
        commit()
    }

    func replaceProfile(_ profile: DockProfile) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profile.id }),
              state.profiles[index].kind == profile.kind,
              state.profiles[index] != profile else { return }
        let retainedIDs = Set(profile.items.map(\.id))
        for removed in state.profiles[index].items where !retainedIDs.contains(removed.id) {
            cancelScheduledNotifications(for: removed)
        }
        state.profiles[index] = profile
        commit()
    }

    func replaceItems(_ items: [DockItem], in profileID: UUID) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let retainedIDs = Set(items.map(\.id))
        for removed in state.profiles[index].items where !retainedIDs.contains(removed.id) {
            cancelScheduledNotifications(for: removed)
        }
        state.profiles[index].items = items
        commit()
    }

    private func cancelScheduledNotifications(for item: DockItem) {
        switch item.widgetKind {
        case "Hydration": HydrationReminderService.cancel(itemID: item.id)
        case "Countdown": CountdownNotificationService.cancel(itemID: item.id)
        case "Alarm":
            for alarm in item.widgetConfiguration?.alarms ?? [] {
                AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
            }
        default: break
        }
    }

    func updateWidgetConfiguration(itemID: UUID, in profileID: UUID, update: (inout WidgetConfiguration) -> Void) {
        guard let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }),
              let itemIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }),
              state.profiles[profileIndex].items[itemIndex].type == .widget else { return }
        var configuration = state.profiles[profileIndex].items[itemIndex].widgetConfiguration ?? WidgetConfiguration()
        update(&configuration)
        state.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration
        commit()
    }

    func importProfiles(_ profiles: [DockProfile]) {
        state.profiles.append(contentsOf: profiles)
        commit()
    }

    func commit() {
        guard storageWritable else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            persistenceError = "Could not save MyDock data: \(error.localizedDescription)"
            logger.error("State save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func dismissPersistenceNotice() {
        persistenceWarning = nil
        persistenceError = nil
    }
}
