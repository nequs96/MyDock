import Foundation
import Testing
@testable import MyDock

@MainActor
struct ProfileEditingTests {
    @Test func draftPreservesLiveColorAndWidgetUpdates() throws {
        var base = DockProfile(name: "Work", kind: .custom, items: [.widget("Sticky Note"), .widget("Countdown")])
        base.items[0].widgetConfiguration?.noteText = "Original"
        var draft = DockProfileDraft(profile: base)
        draft.update { $0.name = "Deep work" }
        var latest = base
        latest.color = "purple"
        latest.items[0].widgetConfiguration?.noteText = "New note"
        latest.items[1].widgetConfiguration?.startCountdown(at: Date(timeIntervalSince1970: 1_000))
        let merged = try draft.merged(with: latest)
        #expect(merged.name == "Deep work")
        #expect(merged.color == "purple")
        #expect(merged.items == latest.items)
    }

    @Test func differentWidgetFieldsMergeButSameFieldConflicts() throws {
        let base = DockProfile(name: "Work", kind: .custom, items: [.widget("Sticky Note")])
        var draft = DockProfileDraft(profile: base)
        draft.update { $0.items[0].widgetConfiguration?.noteBackground = .blue }
        var latest = base
        latest.items[0].widgetConfiguration?.noteText = "Runtime edit"
        let merged = try draft.merged(with: latest)
        #expect(merged.items[0].widgetConfiguration?.noteBackground == .blue)
        #expect(merged.items[0].widgetConfiguration?.noteText == "Runtime edit")
        draft.update { $0.items[0].widgetConfiguration?.noteText = "Editor edit" }
        #expect(throws: ProfileDraftMergeError.self) { try draft.merged(with: latest) }
    }

    @Test func concurrentDeletionIsNotResurrectedAndAdditionsSurviveReorder() throws {
        let base = DockProfile(name: "Work", kind: .custom, items: [.widget("Clock"), .widget("Battery")])
        var draft = DockProfileDraft(profile: base)
        draft.update { $0.name = "Renamed" }
        var latest = base
        latest.items.removeFirst()
        #expect(try draft.merged(with: latest).items == latest.items)
        latest = base
        let added = DockItem.widget("Hydration")
        latest.items.insert(added, at: 1)
        draft.update { $0.items.reverse() }
        let merged = try draft.merged(with: latest)
        #expect(Set(merged.items.map(\.id)) == Set(latest.items.map(\.id)))
        #expect(merged.items.first?.id == base.items.last?.id)
    }

    @Test func saveFailureAndConflictKeepDirtySession() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ProfileStore(fileURL: file)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Work")
        let original = try #require(store.activeCustomProfile)
        var draft = DockProfileDraft(profile: original)
        draft.update { $0.name = "Draft" }
        store.editSessions.set(draft, for: id)
        store.renameProfile(id, to: "External")
        #expect(throws: ProfileDraftMergeError.self) { try store.editSessions.saveAll() }
        #expect(store.editSessions.hasUnsavedChanges)
        #expect(store.activeCustomProfile?.name == "External")
        store.editSessions.discard(id)
        #expect(!store.editSessions.hasUnsavedChanges)
    }

    @Test func nativeCreateAndDeleteDoNotInventAppliedAssociation() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = ProfileStore(fileURL: file)
        let first = try store.createProfileAndPersist(kind: .native)
        #expect(store.state.settings.activeNativeProfileID == nil)
        store.recordAppliedNativeProfile(first)
        _ = store.createProfile(kind: .native)
        #expect(store.state.settings.activeNativeProfileID == first)
        store.deleteProfile(first)
        #expect(store.state.settings.activeNativeProfileID == nil)
    }

    @Test func countdownDeadlineUsesRemainingTimeAfterResume() {
        var config = WidgetConfiguration()
        config.countdownDurationSeconds = 600
        let start = Date(timeIntervalSince1970: 1_000)
        config.startCountdown(at: start)
        config.pauseCountdown(at: start.addingTimeInterval(240))
        let resume = start.addingTimeInterval(500)
        config.startCountdown(at: resume)
        #expect(config.countdownRemaining(at: resume) == 360)
        #expect(config.countdownNotificationDeadline == resume.addingTimeInterval(360))
    }

    @Test func unboundedTimerInputIsRejectedAndFormattingIsSafe() throws {
        let data = Data(#"{"countdownDurationSeconds":9223372036854775807}"#.utf8)
        #expect(throws: ProfileValidationError.self) { try JSONDecoder().decode(WidgetConfiguration.self, from: data) }
        #expect(TimerValueFormatter.text(.infinity) == "0:00")
        #expect(TimerValueFormatter.text(.nan) == "0:00")
        #expect(TimerValueFormatter.text(-1) == "0:00")
        var profile = DockProfile(name: "Invalid", kind: .custom, items: [.widget("Countdown")])
        profile.items[0].widgetConfiguration?.countdownDurationSeconds = Int.max
        #expect(throws: ProfileValidationError.self) { try BackupManager.makeArchive(from: [profile]) }
    }

    @Test func existingJournalCannotBeReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let journal = FileDockTransactionJournal(fileURL: file)
        try journal.begin(snapshot: [["tile-type": "original"]], profileID: UUID())
        #expect(throws: NativeDockError.self) { try journal.begin(snapshot: [["tile-type": "replacement"]], profileID: UUID()) }
        #expect(try journal.pendingSnapshot()?.first?["tile-type"] as? String == "original")
    }
}

@MainActor
struct WorkspaceAutosaveTests {
    private func fixture() -> (ProfileStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false), directory)
    }
    /// Polls for up to 2 s, then requires the condition so a timeout fails here, not on a later assertion.
    private func eventually(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), sourceLocation: sourceLocation)
    }
    @Test func editsCoalesceAndIndependentProfilesSurviveNavigation() async throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = try store.createProfileAndPersist(kind: .custom, name: "A")
        let b = try store.createProfileAndPersist(kind: .custom, name: "B")
        for (id, name) in [(a, "First edit"), (b, "Other Dock"), (a, "Latest edit")] {
            let original = try #require(store.state.profiles.first { $0.id == id })
            var draft = store.editSessions.drafts[id] ?? DockProfileDraft(profile: original)
            draft.update { $0.name = name }
            store.editSessions.set(draft, for: id)
            store.editSessions.autosave(id, delay: .milliseconds(10))
        }
        try await eventually { store.state.profiles.first { $0.id == a }?.name == "Latest edit" && store.state.profiles.first { $0.id == b }?.name == "Other Dock" }
        #expect(store.state.profiles.first { $0.id == a }?.name == "Latest edit")
        #expect(store.state.profiles.first { $0.id == b }?.name == "Other Dock")
        #expect(!store.editSessions.hasUnsavedChanges)
        let reopened = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        #expect(reopened.state.profiles.map(\.name) == store.state.profiles.map(\.name))
    }
    @Test func failedAutosaveRetainsDraftAndRetryRecovers() async throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfileAndPersist(kind: .custom, name: "Original")
        let original = try #require(store.state.profiles.first { $0.id == id })
        var draft = DockProfileDraft(profile: original)
        draft.update { $0.name = "" }
        store.editSessions.set(draft, for: id)
        store.editSessions.autosave(id, delay: .milliseconds(1))
        try await eventually { store.editSessions.saveFeedback[id] == "Couldn’t save · Retry" }
        #expect(store.editSessions.hasUnsavedChanges)
        #expect(store.state.profiles.first { $0.id == id }?.name == "Original")
        #expect(store.editSessions.saveFeedback[id] == "Couldn’t save · Retry")
        draft.update { $0.name = "Recovered" }
        store.editSessions.set(draft, for: id)
        store.editSessions.autosave(id, delay: .milliseconds(1))
        try await eventually { store.state.profiles.first { $0.id == id }?.name == "Recovered" }
        #expect(store.state.profiles.first { $0.id == id }?.name == "Recovered")
        #expect(!store.editSessions.hasUnsavedChanges)
    }
    @Test func discardCancelsPendingAutosave() async throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfileAndPersist(kind: .custom, name: "Original")
        var draft = DockProfileDraft(profile: try #require(store.state.profiles.first { $0.id == id }))
        draft.update { $0.name = "Discard me" }
        store.editSessions.set(draft, for: id)
        store.editSessions.autosave(id, delay: .milliseconds(20))
        store.editSessions.discard(id)
        try await Task.sleep(for: .milliseconds(60))
        #expect(store.state.profiles.first { $0.id == id }?.name == "Original")
        #expect(store.editSessions.saveFeedback[id] == nil)
    }
    @Test func undoPreservesUnrelatedLiveWidgetChanges() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfile(DockProfile(name: "Original", kind: .custom, items: [.widget("Sticky Note")]))
        let before = try #require(store.state.profiles.first { $0.id == id })
        var after = before; after.name = "Renamed"
        store.replaceProfile(after)
        var current = after; current.items[0].widgetConfiguration?.noteText = "Live note"
        store.replaceProfile(current)
        store.editSessions.load(current)
        _ = try store.editSessions.restore(before, replacing: after)
        try store.editSessions.save(id)
        #expect(store.state.profiles.first { $0.id == id }?.name == "Original")
        #expect(store.state.profiles.first { $0.id == id }?.items[0].widgetConfiguration?.noteText == "Live note")
    }
}
