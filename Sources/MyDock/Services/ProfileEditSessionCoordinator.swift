import AppKit
import Combine

@MainActor
final class ProfileEditSessionCoordinator: ObservableObject {
    @Published private(set) var drafts: [UUID: DockProfileDraft] = [:]
    private weak var store: ProfileStore?
    @Published private(set) var saveFeedback: [UUID: String] = [:]
    private var autosaves: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]

    /// Independent per-profile jobs survive navigation and coalesce rapid edits.
    /// Save errors leave the merge-safe draft untouched for retry or recovery.
    func autosave(_ id: UUID, delay: Duration = .milliseconds(500)) {
        autosaves[id]?.cancel()
        let generation = UUID()
        generations[id] = generation
        saveFeedback[id] = "Saving…"
        autosaves[id] = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.generations[id] == generation else { return }
            do {
                try self.save(id)
                self.saveFeedback[id] = "Saved"
                try await Task.sleep(for: .seconds(1.2))
                guard self.generations[id] == generation else { return }
                self.saveFeedback[id] = nil
                self.autosaves[id] = nil
            } catch is CancellationError { }
            catch {
                guard self.generations[id] == generation else { return }
                self.saveFeedback[id] = "Couldn’t save · Retry"
                self.autosaves[id] = nil
            }
        }
    }

    private func cancelAutosave(_ id: UUID) {
        autosaves[id]?.cancel()
        autosaves[id] = nil
        generations[id] = nil
        saveFeedback[id] = nil
    }

    /// Undo only the edit's changed fields, retaining unrelated live widget data.
    func restore(_ before: DockProfile, replacing after: DockProfile) throws -> DockProfile {
        let current = drafts[before.id]?.profile ?? store?.state.profiles.first { $0.id == before.id }
        guard let current else { throw ProfileDraftMergeError.profileRemoved }
        var inverse = DockProfileDraft(profile: after)
        inverse.update { $0 = before }
        let merged = try inverse.merged(with: current)
        var draft = drafts[before.id] ?? DockProfileDraft(profile: current)
        draft.update { $0 = merged }
        drafts[before.id] = draft
        return current
    }

    init(store: ProfileStore) { self.store = store }

    var hasUnsavedChanges: Bool { drafts.values.contains(where: \.isDirty) }

    func set(_ draft: DockProfileDraft?, for id: UUID) {
        if draft == nil { cancelAutosave(id) }
        drafts[id] = draft
    }

    func load(_ profile: DockProfile) {
        guard drafts[profile.id]?.isDirty != true else { return }
        drafts[profile.id] = DockProfileDraft(profile: profile)
    }

    @discardableResult
    func save(_ id: UUID) throws -> DockProfile? {
        guard let store else { return drafts[id]?.profile }
        guard let draft = drafts[id], draft.isDirty else { return store.state.profiles.first { $0.id == id } }
        guard let latest = store.state.profiles.first(where: { $0.id == id }) else { throw ProfileDraftMergeError.profileRemoved }
        var merged = try draft.merged(with: latest)
        merged.name = merged.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !merged.name.isEmpty else { throw ProfileDraftMergeError.conflict("an empty profile name") }
        try ProfileSemanticValidator.validate([merged])
        store.replaceProfile(merged)
        if store.hasUnpersistedChanges { store.flush() }
        guard !store.hasUnpersistedChanges else {
            throw EditSessionSaveError.failed(store.persistenceError ?? "The profile could not be saved.")
        }
        drafts[id] = DockProfileDraft(profile: merged)
        return merged
    }

    func saveAll() throws {
        guard let store else { return }
        var mergedProfiles: [DockProfile] = []
        for draft in drafts.values where draft.isDirty {
            guard let latest = store.state.profiles.first(where: { $0.id == draft.profile.id }) else { throw ProfileDraftMergeError.profileRemoved }
            var merged = try draft.merged(with: latest)
            merged.name = merged.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !merged.name.isEmpty else { throw EditSessionSaveError.failed("A profile needs a name before it can be saved.") }
            mergedProfiles.append(merged)
        }
        guard !mergedProfiles.isEmpty else { return }
        try store.replaceProfiles(mergedProfiles)
        for profile in mergedProfiles { drafts[profile.id] = DockProfileDraft(profile: profile); cancelAutosave(profile.id) }
    }

    func discard(_ id: UUID) {
        cancelAutosave(id)
        guard let profile = store?.state.profiles.first(where: { $0.id == id }) else { drafts[id] = nil; return }
        drafts[id] = DockProfileDraft(profile: profile)
    }

    func resolveBeforeQuitting(action: String = "Quit") -> Bool {
        guard hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Save your Dock changes?"
        alert.informativeText = "Your profile drafts have changes that are not saved."
        alert.addButton(withTitle: "Save Changes")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel " + action)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            do { try saveAll(); return true }
            catch {
                let failure = NSAlert()
                failure.messageText = "Your changes could not be saved"
                failure.informativeText = error.localizedDescription
                failure.runModal()
                return false
            }
        case .alertSecondButtonReturn:
            for id in Array(drafts.keys) { discard(id) }
            return true
        default: return false
        }
    }
}

enum EditSessionSaveError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let message) = self { message } else { nil } }
}
