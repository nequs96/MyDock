import Combine
import Foundation
import OSLog

enum WidgetConfigurationUpdateResult: Equatable {
    case accepted
    case unchanged
    case rejected(String)
    case missingTarget
}

enum WidgetConfigurationMutationError: LocalizedError {
    case missingTarget
    var errorDescription: String? {
        "This widget was removed or is unavailable. Your unfinished note has been kept."
    }
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var state: PersistentState
    struct DockResizePreview: Equatable { let profileID: UUID; let size: Double }
    @Published private(set) var dockResizePreview: DockResizePreview?
    @Published private(set) var persistenceError: String?
    @Published private(set) var persistenceWarning: String?
    @Published private(set) var hasUnpersistedChanges = false
    var draggingItemID: UUID?
    lazy var editSessions = ProfileEditSessionCoordinator(store: self)
    lazy var widgetData = WidgetDataCoordinator(store: self)
    lazy var widgetLifecycle = WidgetLifecycleCoordinator(store: self)
    lazy var history = ProfileLibrary(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("history.json"), retentionDays: 14)
    lazy var personalPresets = ProfileLibrary(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("presets.json"), maximumEntries: 50)
    lazy var utilityDrafts = DockUtilityDraftStore(fileURL: fileURL.deletingLastPathComponent()
        .appendingPathComponent("utility-drafts", isDirectory: true).appendingPathComponent("drafts.json"))

    /// Provider readings (never written to state.json). See `WidgetRuntimeCache`.
    lazy var runtimeCache = WidgetRuntimeCache(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("runtime-cache.json"))

    private let fileURL: URL
    let allowsSystemChanges: Bool
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "persistence")
    private var storageWritable = true
    private var stateLoadedIntact = true
    private let writer: RevisionedStateWriter
    private var revision: UInt64 = 0
    @Published private(set) var isSaving = false
    var canRetryPersistence: Bool { storageWritable }

    init(fileURL: URL? = nil, allowsSystemChanges: Bool = true, stateWriter: RevisionedStateWriter? = nil) {
        self.allowsSystemChanges = allowsSystemChanges && AppRuntimeEnvironment.allowsNativeEffects
        let support = AppRuntimeEnvironment.applicationSupportDirectory
        self.fileURL = fileURL ?? support.appendingPathComponent("state.json")
        self.writer = stateWriter ?? RevisionedStateWriter()
        if FileManager.default.fileExists(atPath: self.fileURL.path) {
            do {
                let data = try BackupManager.boundedArchiveData(from: self.fileURL)
                let schemaVersion = try BackupManager.stateSchemaVersion(in: data)
                guard schemaVersion.map({ $0 <= Product.stateSchemaVersion }) ?? true else {
                    self.state = PersistentState()
                    self.storageWritable = false
                    self.stateLoadedIntact = false
                    self.persistenceWarning = "This MyDock data was created by a newer version. It was left untouched, and saving is disabled to protect it."
                    loadUtilityDrafts()
                    return
                }
                var loaded = try JSONDecoder().decode(PersistentState.self, from: data)
                try ProfileSemanticValidator.validate(loaded.profiles)
                try ProfileAppearance(settings: loaded.settings).validate()
                loaded.schemaVersion = Product.stateSchemaVersion
                self.state = loaded
            } catch BackupError.tooLarge {
                self.state = PersistentState()
                self.storageWritable = false
                self.stateLoadedIntact = false
                self.persistenceWarning = "Saved MyDock data exceeds the supported size. It was left untouched, and saving is disabled to protect it."
            } catch {
                self.state = PersistentState()
                self.stateLoadedIntact = false
                let recoveryURL = self.fileURL.appendingPathExtension("recovery-\(UUID().uuidString)")
                do {
                    try FileManager.default.moveItem(at: self.fileURL, to: recoveryURL)
                    self.persistenceWarning = "Saved profile data could not be opened. The original file was preserved at \(recoveryURL.path). MyDock started with an empty profile list."
                    logger.error("State file could not be decoded and was preserved for recovery")
                    DiagnosticsService.shared.record(.stateRecovered)
                } catch {
                    self.storageWritable = false
                    self.persistenceError = "Saved profile data could not be opened or safely preserved. Saving is disabled to avoid overwriting it."
                    logger.error("State recovery failed; writes are disabled")
                    DiagnosticsService.shared.record(.stateRecoveryFailed)
                }
            }
        } else {
            self.state = PersistentState()
        }
        adoptRuntimeCache()
        loadUtilityDrafts()
    }

    /// Launch migration and resolution. Embedded readings from older state files are copied into the cache when
    /// they are newer, every widget is then resolved through the cache, and a legacy file is rewritten once without
    /// them so a later tenant clear cannot be undone by stale embedded data.
    private func adoptRuntimeCache() {
        guard stateLoadedIntact, storageWritable else { return }
        var foundEmbedded = false
        var live = Set<UUID>()
        for profileIndex in state.profiles.indices {
            for itemIndex in state.profiles[profileIndex].items.indices {
                let item = state.profiles[profileIndex].items[itemIndex]
                guard item.type == .widget, var configuration = item.widgetConfiguration else { continue }
                live.insert(item.id)
                let embedded = configuration.runtimeReadings
                if !embedded.isEmpty { foundEmbedded = true }
                let merged = WidgetRuntimeReadings.preferringNewer(cached: runtimeCache.readings(for: item.id), embedded: embedded)
                runtimeCache.set(merged, for: item.id)
                configuration.resolveRuntimeReadings(runtimeCache.readings(for: item.id))
                if configuration != item.widgetConfiguration { state.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration }
            }
        }
        runtimeCache.prune(keeping: live)
        if foundEmbedded {
            runtimeCache.flush()
            commit(immediately: false)
        }
    }

    /// Keeps the cache in step with in-memory widgets after an authored save: mirrors readings and prunes removed widgets.
    private func mirrorRuntimeCache() {
        guard storageWritable else { return }
        var live = Set<UUID>()
        for profile in state.profiles {
            for item in profile.items where item.type == .widget {
                live.insert(item.id)
                runtimeCache.set(item.widgetConfiguration?.runtimeReadings ?? WidgetRuntimeReadings(), for: item.id)
            }
        }
        runtimeCache.prune(keeping: live)
    }

    /// Opens the private utility drafts once at launch: prunes drafts whose widget or profile no longer exists
    /// (only when the saved state itself loaded intact) and surfaces a notice if an unreadable file was set aside.
    private func loadUtilityDrafts() {
        if stateLoadedIntact && storageWritable { utilityDrafts.discardTargets(notIn: state.profiles) }
        if let notice = utilityDrafts.recoveryNotice {
            persistenceWarning = [persistenceWarning, notice].compactMap { $0 }.joined(separator: " ")
        }
    }

    var customProfiles: [DockProfile] { state.profiles.filter { $0.kind == .custom } }
    var nativeProfiles: [DockProfile] { state.profiles.filter { $0.kind == .native } }
    var activeCustomProfile: DockProfile? {
        guard let id = state.settings.activeCustomProfileID else { return nil }
        return state.profiles.first { $0.id == id && $0.kind == .custom }
    }

    @discardableResult
    func createProfile(kind: DockProfileKind, name: String? = nil) -> UUID? {
        try? createProfileAndPersist(kind: kind, name: name)
    }

    /// A returned identity always belongs to a durably saved profile.
    @discardableResult
    func createProfileAndPersist(kind: DockProfileKind, name: String? = nil) throws -> UUID {
        let baseName = name ?? (kind == .custom ? "Custom Dock" : "macOS Dock")
        var candidate = baseName
        var suffix = 2
        while state.profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(baseName) \(suffix)"
            suffix += 1
        }
        let profile = DockProfile(name: candidate, kind: kind)
        var next = state
        next.profiles.append(profile)
        if kind == .custom {
            next.settings.activeCustomProfileID = profile.id
            if next.settings.setupMode == .nativeOnly { next.settings.setupMode = .both }
        }
        try persistCandidate(next)
        return profile.id
    }

    @discardableResult
    func createProfile(_ resolved: DockProfile) throws -> UUID {
        var profile = resolved
        profile.id = UUID()
        profile.createdAt = .now
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty else { throw EditSessionSaveError.failed("A profile needs a name.") }
        let base = profile.name
        var suffix = 2
        while state.profiles.contains(where: { $0.name.localizedCaseInsensitiveCompare(profile.name) == .orderedSame }) {
            profile.name = "\(base) \(suffix)"; suffix += 1
        }
        try ProfileSemanticValidator.validate(state.profiles + [profile])
        var candidate = state
        candidate.profiles.append(profile)
        if profile.kind == .custom {
            candidate.settings.activeCustomProfileID = profile.id
            if candidate.settings.setupMode == .nativeOnly { candidate.settings.setupMode = .both }
        }
        try persistCandidate(candidate)
        return profile.id
    }

    @discardableResult
    func duplicateProfile(_ id: UUID) throws -> UUID {
        guard let original = state.profiles.first(where: { $0.id == id }) else { throw ProfileDraftMergeError.profileRemoved }
        var copy = original
        copy.id = UUID()
        copy.name = "\(original.name) Copy"
        copy.createdAt = .now
        copy.items = original.items.map(copyItemForDuplication)
        var candidate = state
        candidate.profiles.append(copy)
        try persistCandidate(candidate)
        return copy.id
    }

    @discardableResult
    func duplicateWidget(_ itemID: UUID, in profileID: UUID) -> UUID? {
        guard let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }),
              let itemIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }),
              state.profiles[profileIndex].items[itemIndex].type == .widget else { return nil }
        let copy = copyItemForDuplication(state.profiles[profileIndex].items[itemIndex])
        state.profiles[profileIndex].items.insert(copy, at: itemIndex + 1)
        commit()
        return copy.id
    }

    func copyItemForDuplication(_ item: DockItem) -> DockItem {
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

    func deleteProfile(_ id: UUID) {
        DockShortcutStore.shared.remove(for: id)
        if let profile = state.profiles.first(where: { $0.id == id }) {
            history.record(profile, reason: "Before deletion")
            profile.items.forEach(cancelScheduledNotifications(for:))
            profile.items.forEach { WidgetSetupDraftStore.shared.clearDrafts(for: $0.id) }
        }
        state.profiles.removeAll { $0.id == id }
        utilityDrafts.discardTargets(removedItemIDs: [], removedProfileIDs: [id])
        editSessions.set(nil, for: id)
        if state.settings.activeCustomProfileID == id {
            state.settings.activeCustomProfileID = customProfiles.first?.id
        }
        if state.settings.activeNativeProfileID == id {
            state.settings.activeNativeProfileID = nil
        }
        commit()
    }

    func activate(_ id: UUID) {
        guard let profile = state.profiles.first(where: { $0.id == id }) else { return }
        if profile.kind == .custom {
            state.settings.activeCustomProfileID = id
            if state.settings.setupMode == .nativeOnly { state.settings.setupMode = .both }
        } else { return }
        commit()
    }

    func recordAppliedNativeProfile(_ id: UUID) {
        guard nativeProfiles.contains(where: { $0.id == id }) else { return }
        state.settings.activeNativeProfileID = id
        commit()
    }

    func setActiveCustomProfile(_ id: UUID?) {
        if let id {
            guard state.profiles.contains(where: { $0.id == id && $0.kind == .custom }) else { return }
            if state.settings.setupMode == .nativeOnly { state.settings.setupMode = .both }
        }
        state.settings.activeCustomProfileID = id
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
                          starterWidgets: [String],
                          starterApplications: [DockItem] = []) {
        var nextState = state
        nextState.settings.setupMode = setupMode
        nextState.settings.customDockPosition = customDockPosition
        nextState.settings.customDockDisplayID = customDockDisplayID

        if setupMode != .customMain {
            if let existing = nextState.settings.activeNativeProfileID,
               nextState.profiles.contains(where: { $0.id == existing && $0.kind == .native }) {
                // Keep the selected profile.
            } else if let first = nextState.profiles.first(where: { $0.kind == .native }) {
                // Existing unapplied profiles are not associated with the real Dock.
                _ = first
            } else {
                let profile = DockProfile(name: "macOS Dock", kind: .native, items: importedNativeItems)
                nextState.profiles.append(profile)
                nextState.settings.activeNativeProfileID = importedNativeItems.isEmpty ? nil : profile.id
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
                                          items: starterApplications + (starterApplications.isEmpty || starterWidgets.isEmpty ? [] : [.spacer(.small)]) + starterWidgets.map(DockItem.widget))
                nextState.profiles.append(profile)
                nextState.settings.activeCustomProfileID = profile.id
            }
        }

        nextState.settings.onboardingComplete = true
        do { try persistCandidate(nextState) } catch { }
    }

    func updateSettings(immediately: Bool = false, _ update: (inout AppSettings) -> Void) {
        var settings = state.settings
        update(&settings)
        guard settings != state.settings else { return }
        state.settings = settings
        commit(immediately: immediately)
    }

    func setAppearance(_ appearance: ProfileAppearance?, for profileID: UUID,
                       immediately: Bool = false, recordHistory: Bool = true) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID && $0.kind == .custom }),
              state.profiles[index].appearance != appearance else { return }
        do { try appearance?.validate() }
        catch { persistenceWarning = error.localizedDescription; return }
        if recordHistory { history.record(state.profiles[index], reason: "Before appearance edit") }
        state.profiles[index].appearance = appearance
        commit(immediately: immediately)
    }

    /// A direct Dock resize follows the active profile's existing inheritance choice.
    func previewDockSize(_ size: Double, for profileID: UUID) {
        guard size.isFinite, (0.65...1.5).contains(size), customProfiles.contains(where: { $0.id == profileID }) else { return }
        let preview = DockResizePreview(profileID: profileID, size: size)
        if preview != dockResizePreview { dockResizePreview = preview }
    }

    func finishDockResize(for profileID: UUID) {
        guard let preview = dockResizePreview, preview.profileID == profileID else { return }
        setDockSize(preview.size, for: profileID, recordHistory: true)
        dockResizePreview = nil
        flush()
    }

    func setDockSize(_ size: Double, for profileID: UUID, recordHistory: Bool = false) {
        guard size.isFinite, (0.65...1.5).contains(size),
              let profile = customProfiles.first(where: { $0.id == profileID }) else { return }
        if var appearance = profile.appearance {
            appearance.size = size
            setAppearance(appearance, for: profileID, immediately: false, recordHistory: recordHistory)
        } else {
            updateSettings(immediately: false) { $0.customDockSize = size }
        }
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        state.profiles[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        commit(immediately: false)
    }

    func setProfileColor(_ id: UUID, to color: DockProfileColor) {
        guard let index = state.profiles.firstIndex(where: { $0.id == id }) else { return }
        state.profiles[index].color = color.rawValue
        commit(immediately: false)
    }

    func add(_ item: DockItem, to profileID: UUID? = nil) {
        let targetID = profileID ?? state.settings.activeCustomProfileID
        guard let targetID, let index = state.profiles.firstIndex(where: { $0.id == targetID }) else { return }
        let insertedItem = itemWithUniqueIdentity(item)
        state.profiles[index].items.append(insertedItem)
        commit(immediately: false)
    }

    func insert(_ item: DockItem, before targetID: UUID?, in profileID: UUID) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID }),
              !state.profiles[index].items.contains(where: { $0.id == item.id }) else { return }
        let target = targetID.flatMap { id in state.profiles[index].items.firstIndex(where: { $0.id == id }) }
            ?? state.profiles[index].items.endIndex
        let insertedItem = itemWithUniqueIdentity(item)
        state.profiles[index].items.insert(insertedItem, at: target)
        commit(immediately: false)
    }

    private func itemWithUniqueIdentity(_ item: DockItem) -> DockItem {
        guard state.profiles.contains(where: { $0.items.contains(where: { $0.id == item.id }) }) else { return item }
        var copy = item
        copy.id = UUID()
        return copy
    }

    func moveItems(_ itemIDs: Set<UUID>, before targetID: UUID?, in profileID: UUID) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let items = DockItemOrderingPolicy.moving(state.profiles[index].items, ids: itemIDs, before: targetID)
        guard items != state.profiles[index].items else { return }
        state.profiles[index].items = items
        commit(immediately: false)
    }

    func updateItem(_ itemID: UUID, in profileID: UUID, update: (inout DockItem) -> Void) {
        guard let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }),
              let itemIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }) else { return }
        update(&state.profiles[profileIndex].items[itemIndex])
        commit(immediately: false)
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
        removedItems.forEach { WidgetSetupDraftStore.shared.clearDrafts(for: $0.id) }
        state.profiles[index].items.removeAll { itemIDs.contains($0.id) }
        utilityDrafts.discardTargets(removedItemIDs: Set(removedItems.map(\.id)))
        commit(immediately: false)
    }

    func moveItem(_ itemID: UUID, before targetID: UUID, in profileID: UUID) {
        guard itemID != targetID,
              let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }),
              let sourceIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }),
              let targetIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == targetID }) else { return }
        let item = state.profiles[profileIndex].items.remove(at: sourceIndex)
        let adjustedTarget = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        state.profiles[profileIndex].items.insert(item, at: adjustedTarget)
        commit(immediately: false)
    }

    func moveItems(_ itemIDs: Set<UUID>, direction: DockItemMoveDirection, in profileID: UUID) {
        guard !itemIDs.isEmpty,
              let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let items = DockItemOrderingPolicy.moving(state.profiles[profileIndex].items, ids: itemIDs, direction: direction)
        guard items.map(\.id) != state.profiles[profileIndex].items.map(\.id) else { return }
        state.profiles[profileIndex].items = items
        commit(immediately: false)
    }

    func replaceProfiles(_ profiles: [DockProfile]) throws {
        var next = state.profiles
        for profile in profiles {
            guard let index = next.firstIndex(where: { $0.id == profile.id && $0.kind == profile.kind }) else { throw ProfileDraftMergeError.profileRemoved }
            if next[index] != profile { history.record(next[index], reason: "Before profile edit") }
            next[index] = profile
        }
        try ProfileSemanticValidator.validate(next)
        let retained = Set(next.flatMap { $0.items.map(\.id) })
        var removedIDs = Set<UUID>()
        for item in state.profiles.flatMap(\.items) where !retained.contains(item.id) {
            cancelScheduledNotifications(for: item); WidgetSetupDraftStore.shared.clearDrafts(for: item.id)
            removedIDs.insert(item.id)
        }
        utilityDrafts.discardTargets(removedItemIDs: removedIDs)
        state.profiles = next
        commit()
        guard !hasUnpersistedChanges else { throw EditSessionSaveError.failed(persistenceError ?? "The profiles could not be saved.") }
    }

    func replaceProfile(_ profile: DockProfile) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profile.id }),
              state.profiles[index].kind == profile.kind,
              state.profiles[index] != profile else { return }
        history.record(state.profiles[index], reason: "Before profile edit")
        let retainedIDs = Set(profile.items.map(\.id))
        var removedIDs = Set<UUID>()
        for removed in state.profiles[index].items where !retainedIDs.contains(removed.id) {
            cancelScheduledNotifications(for: removed)
            WidgetSetupDraftStore.shared.clearDrafts(for: removed.id)
            removedIDs.insert(removed.id)
        }
        utilityDrafts.discardTargets(removedItemIDs: removedIDs)
        state.profiles[index] = profile
        commit()
    }

    func replaceItems(_ items: [DockItem], in profileID: UUID) {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let retainedIDs = Set(items.map(\.id))
        var removedIDs = Set<UUID>()
        for removed in state.profiles[index].items where !retainedIDs.contains(removed.id) {
            cancelScheduledNotifications(for: removed)
            WidgetSetupDraftStore.shared.clearDrafts(for: removed.id)
            removedIDs.insert(removed.id)
        }
        utilityDrafts.discardTargets(removedItemIDs: removedIDs)
        state.profiles[index].items = items
        commit()
    }

    private func cancelScheduledNotifications(for item: DockItem) {
        switch item.widgetKind {
        case "Hydration": HydrationReminderService.cancel(itemID: item.id, operationID: UUID())
        case "Countdown": CountdownNotificationService.cancel(itemID: item.id)
        case "Alarm": AlarmNotificationService.cancelAll(widgetID: item.id,
                                                          alarms: item.widgetConfiguration?.alarms ?? [])
        default: break
        }
    }

    /// Accepted and unchanged describe in-memory state, not durable success.
    @discardableResult
    func updateWidgetConfiguration(itemID: UUID, in profileID: UUID, update: (inout WidgetConfiguration) -> Void) -> WidgetConfigurationUpdateResult {
        guard storageWritable else { return .rejected(persistenceWarning ?? "Saving is disabled to protect this data.") }
        guard let profileIndex = state.profiles.firstIndex(where: { $0.id == profileID }),
              let itemIndex = state.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }),
              state.profiles[profileIndex].items[itemIndex].type == .widget else { return .missingTarget }
        let previous = state.profiles[profileIndex].items[itemIndex].widgetConfiguration
        var configuration = previous ?? WidgetConfiguration()
        update(&configuration)
        do { try ProfileSemanticValidator.validate(configuration) }
        catch { persistenceWarning = error.localizedDescription; return .rejected(error.localizedDescription) }
        guard configuration != previous else { return .unchanged }
        state.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration
        if configuration.strippedOfRuntimeReadings == (previous ?? WidgetConfiguration()).strippedOfRuntimeReadings {
            // Provider readings only: update the cache, never the authored state file or its revision.
            runtimeCache.set(configuration.runtimeReadings, for: itemID)
            return .accepted
        }
        commit(immediately: false)
        return .accepted
    }

    /// Critical Save/dismissal boundaries validate and write before acknowledging input.
    func updateWidgetConfigurationAndPersist(itemID: UUID, in profileID: UUID, update: (inout WidgetConfiguration) -> Void) throws {
        var candidate = state
        try updateWidgetConfiguration(in: &candidate, itemID: itemID, profileID: profileID, update: update)
        try persistCandidate(candidate)
    }

    func hasWidget(itemID: UUID, in profileID: UUID) -> Bool {
        state.profiles.first { $0.id == profileID }?.items.contains { $0.id == itemID && $0.type == .widget } ?? false
    }

    /// One failed note keeps the complete pending batch recoverable, without partial publication.
    func persistNoteDrafts(_ drafts: [(itemID: UUID, profileID: UUID, text: String)]) throws {
        guard !drafts.isEmpty else { return }
        var candidate = state
        for draft in drafts {
            try updateWidgetConfiguration(in: &candidate, itemID: draft.itemID, profileID: draft.profileID) { $0.noteText = draft.text }
        }
        try persistCandidate(candidate)
    }

    private func updateWidgetConfiguration(in candidate: inout PersistentState, itemID: UUID, profileID: UUID,
                                           update: (inout WidgetConfiguration) -> Void) throws {
        guard let profileIndex = candidate.profiles.firstIndex(where: { $0.id == profileID }),
              let itemIndex = candidate.profiles[profileIndex].items.firstIndex(where: { $0.id == itemID }),
              candidate.profiles[profileIndex].items[itemIndex].type == .widget else {
            throw WidgetConfigurationMutationError.missingTarget
        }
        var configuration = candidate.profiles[profileIndex].items[itemIndex].widgetConfiguration ?? WidgetConfiguration()
        update(&configuration)
        do { try ProfileSemanticValidator.validate(configuration) }
        catch { persistenceWarning = error.localizedDescription; throw error }
        candidate.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration
    }

    func clearConnectionReferences(_ connection: WidgetConnectionReference) {
        guard !connection.identifier.isEmpty else { return }
        var updatedState = state
        var changed = false
        for profileIndex in updatedState.profiles.indices {
            for itemIndex in updatedState.profiles[profileIndex].items.indices {
                if connection.clearIfMatching(&updatedState.profiles[profileIndex].items[itemIndex]) {
                    changed = true
                }
            }
        }
        guard changed else { return }
        state = updatedState
        commit()
    }

    func importProfiles(_ profiles: [DockProfile]) throws {
        var candidate = state
        candidate.profiles.append(contentsOf: profiles)
        try persistCandidate(candidate)
    }

    private func persistCandidate(_ candidate: PersistentState) throws {
        guard storageWritable else { throw EditSessionSaveError.failed(persistenceWarning ?? "Saving is disabled to protect this data.") }
        revision &+= 1
        do {
            try writer.writeImmediately(candidate, to: fileURL, revision: revision)
            state = candidate
            mirrorRuntimeCache()
            finishWrite(.success(()), revision: revision)
        } catch {
            finishWrite(.failure(error), revision: revision)
            throw error
        }
    }

    func commit(immediately: Bool = true) {
        guard storageWritable else {
            hasUnpersistedChanges = true
            persistenceError = persistenceWarning ?? "Saving is disabled to protect the original data."
            return
        }
        revision &+= 1
        let currentRevision = revision
        mirrorRuntimeCache()
        if immediately {
            do {
                try writer.writeImmediately(state, to: fileURL, revision: currentRevision)
                finishWrite(.success(()), revision: currentRevision)
            } catch { finishWrite(.failure(error), revision: currentRevision) }
        } else {
            isSaving = true
            writer.write(state, to: fileURL, revision: currentRevision, immediately: false) { [weak self] result in
                Task { @MainActor [weak self] in self?.finishWrite(result, revision: currentRevision) }
            }
        }
    }

    /// Lifecycle boundaries wait for the latest revision and report an actual disk result.
    func flush() {
        commit()
        runtimeCache.flush()
    }

    private func finishWrite(_ result: Result<Void, Error>, revision: UInt64) {
        guard revision == self.revision else { return }
        isSaving = false
        switch result {
        case .success:
            let recovered = hasUnpersistedChanges
            hasUnpersistedChanges = false
            persistenceError = nil
            if recovered { DiagnosticsService.shared.record(.stateSaveRecovered) }
        case .failure(let error):
            persistenceError = "Could not save MyDock data: \(error.localizedDescription)"
            hasUnpersistedChanges = true
            logger.error("State save failed: \(error.localizedDescription, privacy: .public)")
            DiagnosticsService.shared.record(.stateSaveFailed)
        }
    }

    func dismissPersistenceNotice() {
        persistenceWarning = nil
        persistenceError = nil
    }
}

enum WidgetConnectionReference {
    case stripe(String)
    case paddle(String)
    case shopify(String)

    var identifier: String {
        switch self {
        case .stripe(let id), .paddle(let id), .shopify(let id): id
        }
    }

    func clearIfMatching(_ item: inout DockItem) -> Bool {
        guard item.type == .widget, var configuration = item.widgetConfiguration else { return false }
        switch self {
        case .stripe(let id):
            guard item.widgetKind == "Stripe", configuration.stripeAccountID == id else { return false }
            configuration.stripeAccountID = ""
            configuration.stripeSnapshot = nil
        case .paddle(let id):
            guard item.widgetKind == "Paddle", configuration.paddleAccountID == id else { return false }
            configuration.paddleAccountID = ""
            configuration.paddleSnapshot = nil
        case .shopify(let id):
            guard item.widgetKind == "Shopify", configuration.shopifyStoreID == id else { return false }
            configuration.shopifyStoreID = ""
            configuration.shopifySnapshot = nil
        }
        item.widgetConfiguration = configuration
        return true
    }
}
