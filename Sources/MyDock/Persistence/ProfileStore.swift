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

    @Published private(set) var state: PersistentState { didSet { ownedItemIDsCache = nil } }
    /// Every item ID in `state`, rebuilt on demand after a change; presentation checks ownership on each render.
    private var ownedItemIDsCache: Set<UUID>?
    private var ownedItemIDs: Set<UUID> {
        if let ownedItemIDsCache { return ownedItemIDsCache }
        let ids = Set(state.profiles.flatMap { $0.items.map(\.id) })
        ownedItemIDsCache = ids
        return ids
    }
    struct DockResizePreview: Equatable { let profileID: UUID; let size: Double }
    @Published private(set) var dockResizePreview: DockResizePreview?
    @Published private(set) var persistenceError: String?
    @Published private(set) var persistenceWarning: String?
    @Published private(set) var hasUnpersistedChanges = false
    lazy var editSessions = ProfileEditSessionCoordinator(store: self)
    lazy var widgetData = WidgetDataCoordinator(store: self)
    lazy var widgetLifecycle = WidgetLifecycleCoordinator(store: self)
    lazy var history = ProfileLibrary(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("history.json"), retentionDays: 14, writesInBackground: true)
    lazy var personalPresets = ProfileLibrary(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("presets.json"), maximumEntries: 50)
    lazy var utilityDrafts = DockUtilityDraftStore(fileURL: fileURL.deletingLastPathComponent()
        .appendingPathComponent("utility-drafts", isDirectory: true).appendingPathComponent("drafts.json"))

    /// Provider readings (never written to state.json). See `WidgetRuntimeCache`.
    lazy var runtimeCache = runtimeCacheOverride ?? WidgetRuntimeCache(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent("runtime-cache.json"))
    private let runtimeCacheOverride: WidgetRuntimeCache?
    private var runtimeMigrationPending = false

    private let fileURL: URL
    let allowsSystemChanges: Bool
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "persistence")
    private var storageWritable = true
    private var stateLoadedIntact = true
    /// False when some saved Docks were set aside at launch: their widgets' drafts must survive until they are recovered.
    private var everySavedDockLoaded = true
    private let writer: RevisionedStateWriter
    private var revision: UInt64 = 0
    @Published private(set) var isSaving = false
    var canRetryPersistence: Bool { storageWritable }

    init(fileURL: URL? = nil, allowsSystemChanges: Bool = true, stateWriter: RevisionedStateWriter? = nil, runtimeCache: WidgetRuntimeCache? = nil) {
        self.allowsSystemChanges = allowsSystemChanges && AppRuntimeEnvironment.allowsNativeEffects
        let support = AppRuntimeEnvironment.applicationSupportDirectory
        self.fileURL = fileURL ?? support.appendingPathComponent("state.json")
        self.writer = stateWriter ?? RevisionedStateWriter()
        self.runtimeCacheOverride = runtimeCache
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
                let loaded = try PersistentStateLoader.load(data)
                // The readable Docks stay in use; a copy of the file as it was keeps the rest recoverable.
                let recoveryURL = loaded.isPartial ? self.fileURL.appendingPathExtension("recovery-\(UUID().uuidString)") : nil
                if let recoveryURL { try FileManager.default.copyItem(at: self.fileURL, to: recoveryURL) }
                var state = loaded.state
                state.schemaVersion = Product.stateSchemaVersion
                self.state = state
                self.everySavedDockLoaded = loaded.setAside.isEmpty
                if let recoveryURL {
                    self.persistenceWarning = PersistentStateLoader.warning(for: loaded, preservedAt: recoveryURL.path)
                    logger.error("Some saved Docks could not be read and were set aside; the original file was preserved")
                    DiagnosticsService.shared.record(.stateRecovered)
                }
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
        if storageWritable {
            // State, history, presets and the runtime cache live in the support folder; utility drafts in a subfolder.
            let support = self.fileURL.deletingLastPathComponent()
            for folder in [support, support.appendingPathComponent("utility-drafts", isDirectory: true)] {
                RevisionedStateWriter.removeAbandonedTemporaries(in: folder)
            }
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
                runtimeCache.set(configuration.runtimeReadings, for: item.id)
                configuration.stripRuntimeReadings()
                if configuration != item.widgetConfiguration { state.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration }
            }
        }
        runtimeCache.prune(keeping: live)
        // Strip legacy embedded readings only once the cache durably holds them.
        if foundEmbedded {
            runtimeMigrationPending = true
            do {
                try finishPendingRuntimeMigration()
                commit(immediately: false)
            } catch {
                persistenceWarning = error.localizedDescription
            }
        }
    }

    /// A legacy state file remains the disk fallback until its readings have a durable cache copy.
    /// Routine authored saves must not bypass the launch migration's failure boundary.
    private func finishPendingRuntimeMigration() throws {
        guard runtimeMigrationPending else { return }
        guard runtimeCache.flush() else {
            throw EditSessionSaveError.failed("Saved provider readings could not be moved to their cache. The original saved data has been kept. Retry saving after storage is available.")
        }
        runtimeMigrationPending = false
    }

    /// Authored mutations retain the newest matching cache readings, absorb legacy imports, and prune deletions.
    private func mirrorRuntimeCache() {
        guard storageWritable else { return }
        var live = Set<UUID>()
        var authored = state
        for profileIndex in authored.profiles.indices {
            for itemIndex in authored.profiles[profileIndex].items.indices {
                let item = authored.profiles[profileIndex].items[itemIndex]
                guard item.type == .widget, var configuration = item.widgetConfiguration else { continue }
                live.insert(item.id)
                let merged = WidgetRuntimeReadings.preferringNewer(cached: runtimeCache.readings(for: item.id),
                                                                  embedded: configuration.runtimeReadings)
                configuration.resolveRuntimeReadings(merged)
                runtimeCache.set(configuration.runtimeReadings, for: item.id)
                configuration.stripRuntimeReadings()
                authored.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration
            }
        }
        if authored != state { state = authored }
        runtimeCache.prune(keeping: live)
    }

    /// Runtime projection belongs to presentation only; authored profiles and edit sessions remain unchanged.
    func presentationItem(_ item: DockItem) -> DockItem {
        var projected = item
        // Inert library/render samples have no repository owner and keep their explicit example readings.
        guard ownedItemIDs.contains(item.id) else { return projected }
        projected.widgetConfiguration?.resolveCachedRuntimeReadings(runtimeCache.readings(for: item.id))
        return projected
    }

    func presentationProfile(_ profile: DockProfile) -> DockProfile {
        guard state.profiles.contains(where: { $0.id == profile.id }) else { return profile }
        var projected = profile
        // The profile already establishes ownership; avoid a whole-repository lookup for every face.
        projected.items = profile.items.map { item in
            var item = item
            item.widgetConfiguration?.resolveCachedRuntimeReadings(runtimeCache.readings(for: item.id))
            return item
        }
        return projected
    }

    func presentationConfiguration(for item: DockItem, in profileID: UUID) -> WidgetConfiguration {
        guard let current = state.profiles.first(where: { $0.id == profileID })?.items.first(where: { $0.id == item.id }) else {
            return item.widgetConfiguration ?? WidgetConfiguration()
        }
        var configuration = current.widgetConfiguration ?? WidgetConfiguration()
        configuration.resolveCachedRuntimeReadings(runtimeCache.readings(for: current.id))
        return configuration
    }

    /// Opens the private utility drafts once at launch: prunes drafts whose widget or profile no longer exists
    /// (only when every saved Dock loaded) and surfaces a notice if an unreadable file was set aside.
    private func loadUtilityDrafts() {
        if stateLoadedIntact && everySavedDockLoaded && storageWritable { utilityDrafts.discardTargets(notIn: state.profiles) }
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

    /// A name no other profile uses ("Work", "Work 2", ...), within the validator's name limit. A name is shortened
    /// only when it, with any number it needs, would not fit.
    private func uniqueProfileName(_ name: String, in profiles: [DockProfile]) -> String {
        let existing = profiles.map(\.name)
        let unique = PortableDockPackage.uniqueName(name, existing: existing)
        guard unique.count > ProfileSemanticValidator.maximumNameLength else { return unique }
        return PortableDockPackage.uniqueName(String(name.prefix(ProfileSemanticValidator.maximumNameLength - 10)), existing: existing)
    }

    /// A returned identity always belongs to a durably saved profile.
    @discardableResult
    func createProfileAndPersist(kind: DockProfileKind, name: String? = nil) throws -> UUID {
        let profile = DockProfile(name: uniqueProfileName(name ?? (kind == .custom ? "Custom Dock" : "macOS Dock"), in: state.profiles),
                                  kind: kind)
        var next = state
        next.profiles.append(profile)
        if kind == .custom {
            next.settings.activeCustomProfileID = profile.id
            if next.settings.setupMode == .nativeOnly { next.settings.setupMode = .both }
        }
        try persistCandidate(next)
        return profile.id
    }

    /// Adds a new Dock. `activate: false` keeps the live Dock and setup mode as they are: Recovery restores pass it,
    /// like backup Restore, and in the editor the Activate button is then the explicit step that turns the new Dock on.
    @discardableResult
    func createProfile(_ resolved: DockProfile, activate: Bool = true) throws -> UUID {
        var profile = resolved
        profile.id = UUID()
        profile.createdAt = .now
        profile.name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.name.isEmpty else { throw EditSessionSaveError.failed(EditSessionSaveError.missingName) }
        profile.name = uniqueProfileName(profile.name, in: state.profiles)
        try ProfileSemanticValidator.validate(state.profiles + [profile])
        var candidate = state
        candidate.profiles.append(profile)
        if activate, profile.kind == .custom {
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
        copy.name = uniqueProfileName("\(original.name) Copy", in: state.profiles)
        copy.createdAt = .now
        copy.items = original.items.map(copyItemForDuplication)
        copy.workspace = original.workspace?.remapped(from: original.items, to: copy.items)
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
        item.preparedForNewIdentity()
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
        // Switching Docks (including automatic switching and swipes) is routine: coalesce it off the main thread.
        commit(immediately: false)
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

    /// Saves the setup choices and marks onboarding complete only when that write succeeds.
    func finishOnboarding(setupMode: SetupMode,
                          customDockPosition: DockPosition,
                          customDockDisplayID: UInt32?,
                          importedNativeItems: [DockItem],
                          starterWidgets: [String],
                          starterApplications: [DockItem] = []) throws {
        var nextState = state
        nextState.settings.setupMode = setupMode
        nextState.settings.customDockPosition = customDockPosition
        nextState.settings.customDockDisplayID = customDockDisplayID

        if setupMode != .customMain {
            if let existing = nextState.settings.activeNativeProfileID,
               nextState.profiles.contains(where: { $0.id == existing && $0.kind == .native }) {
                // Keep the selected profile.
            } else if nextState.profiles.contains(where: { $0.kind == .native }) {
                // Existing unapplied profiles are not associated with the real Dock.
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
        nextState.settings.lastSeenWhatsNewVersion = Product.marketingVersion
        try persistCandidate(nextState)
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
        guard size.isFinite, DockAppearanceBounds.size.contains(size), customProfiles.contains(where: { $0.id == profileID }) else { return }
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
        guard size.isFinite, DockAppearanceBounds.size.contains(size),
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

    /// Returns the inserted item's ID, which differs from `item.id` when that ID was already in use.
    @discardableResult
    func insert(_ item: DockItem, before targetID: UUID?, in profileID: UUID) -> UUID? {
        guard let index = state.profiles.firstIndex(where: { $0.id == profileID }),
              !state.profiles[index].items.contains(where: { $0.id == item.id }) else { return nil }
        let target = targetID.flatMap { id in state.profiles[index].items.firstIndex(where: { $0.id == id }) }
            ?? state.profiles[index].items.endIndex
        let insertedItem = itemWithUniqueIdentity(item)
        state.profiles[index].items.insert(insertedItem, at: target)
        commit(immediately: false)
        return insertedItem.id
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

    func replaceProfiles(_ profiles: [DockProfile]) throws {
        let profiles = profiles.map(\.strippedOfRuntimeReadings)
        var next = state.profiles
        var replaced: [DockProfile] = []
        for profile in profiles {
            guard let index = next.firstIndex(where: { $0.id == profile.id && $0.kind == profile.kind }) else { throw ProfileDraftMergeError.profileRemoved }
            if next[index] != profile { replaced.append(next[index]) }
            next[index] = profile
        }
        try ProfileSemanticValidator.validate(next)
        // History records only an edit that is about to happen, never one validation rejected.
        for profile in replaced { history.record(profile, reason: "Before profile edit") }
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
        let profile = profile.strippedOfRuntimeReadings
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
        case "Hydration": HydrationReminderService.cancel(itemID: item.id)
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
        let authored = state.profiles[profileIndex].items[itemIndex]
        let previous = presentationItem(authored).widgetConfiguration ?? WidgetConfiguration()
        var configuration = previous
        update(&configuration)
        configuration.invalidateUnchangedReadings(after: previous)
        do { try ProfileSemanticValidator.validate(configuration) }
        catch { persistenceWarning = error.localizedDescription; return .rejected(error.localizedDescription) }
        guard configuration != previous else { return .unchanged }
        if configuration.strippedOfRuntimeReadings == previous.strippedOfRuntimeReadings {
            // A cache notification updates consumers, without publishing authored state, history or revisions.
            runtimeCache.set(configuration.runtimeReadings, for: itemID)
            return .accepted
        }
        runtimeCache.set(configuration.runtimeReadings, for: itemID)
        state.profiles[profileIndex].items[itemIndex].widgetConfiguration = configuration.strippedOfRuntimeReadings
        commit(immediately: false)
        return .accepted
    }

    /// The only write path for provider readings: resolves the display configuration (authored values plus
    /// identity-matched cache readings), lets the provider update it, and stores only the resulting readings in the
    /// cache. Authored profile state, history, undo and edit sessions are never touched; authored changes made by
    /// `update` are ignored by design.
    @discardableResult
    func publishRuntimeReadings(itemID: UUID, in profileID: UUID, update: (inout WidgetConfiguration) -> Void) -> WidgetConfigurationUpdateResult {
        guard let authored = state.profiles.first(where: { $0.id == profileID })?.items.first(where: { $0.id == itemID }),
              authored.type == .widget else { return .missingTarget }
        let previous = presentationItem(authored).widgetConfiguration ?? WidgetConfiguration()
        var display = previous
        update(&display)
        // Readings keep the identity of the authored configuration, never a retagged one.
        var resolved = authored.widgetConfiguration ?? WidgetConfiguration()
        resolved.resolveRuntimeReadings(display.runtimeReadings)
        return runtimeCache.set(resolved.runtimeReadings, for: itemID) ? .accepted : .unchanged
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
        // Callers show this rejection where the edit was made; it is not a data-integrity notice.
        try ProfileSemanticValidator.validate(configuration)
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

    /// Appends restored or imported profiles, each under a name no other profile uses.
    func importProfiles(_ profiles: [DockProfile]) throws {
        var candidate = state
        for var profile in profiles {
            profile.name = uniqueProfileName(profile.name, in: candidate.profiles)
            candidate.profiles.append(profile)
        }
        try persistCandidate(candidate)
    }

    private func persistCandidate(_ candidate: PersistentState) throws {
        guard storageWritable else { throw EditSessionSaveError.failed(persistenceWarning ?? "Saving is disabled to protect this data.") }
        try finishPendingRuntimeMigration()
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
        do { try finishPendingRuntimeMigration() }
        catch {
            hasUnpersistedChanges = true
            persistenceError = error.localizedDescription
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
            writer.write(state, to: fileURL, revision: currentRevision) { [weak self] result in
                Task { @MainActor [weak self] in self?.finishWrite(result, revision: currentRevision) }
            }
        }
    }

    /// Lifecycle boundaries wait for the latest revision and report an actual disk result.
    func flush() {
        commit()
        runtimeCache.flush()
        ProfileLibrary.waitForPendingWrites()
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
            // Only the error's domain and code are public; its description can name files or user content.
            let nsError = error as NSError
            logger.error("State save failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .private)")
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
