import Foundation
import Testing
@testable import MyDock

/// Fixture files and an injected writer only; no default credentials, notifications or native services.
@MainActor
struct RequiredPersistenceCorrectionTests {
    @Test func unknownFutureModelsStayAtTheirOriginalPathAndRefuseWrites() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        let futureVersion = Product.stateSchemaVersion + 1
        let models = [
            #""profiles":[{"kind":"future-profile"}],"settings":{}"#,
            #""profiles":[{"items":[{"type":"future-item"}]}],"settings":{}"#,
            #""profiles":[],"settings":{"setupMode":"future-mode"}"#
        ]
        for model in models {
            let original = Data("{\"schemaVersion\":\(futureVersion),\(model)}".utf8)
            try original.write(to: file)
            let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
            #expect(!store.canRetryPersistence)
            #expect(store.state.profiles.isEmpty)
            #expect(store.createProfile(kind: .custom) == nil)
            #expect(throws: (any Error).self) { try store.importProfiles([DockProfile(name: "Import", kind: .custom)]) }
            store.flush()
            #expect(try Data(contentsOf: file) == original)
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["state.json"])
        }
    }

    @Test func unsupportedBackupVersionIsRecognizedBeforeUnknownModels() throws {
        let original = Data(#"{"formatVersion":2,"profiles":[{"kind":"future-profile"}]}"#.utf8)
        do {
            _ = try BackupManager.readArchive(original)
            Issue.record("A future archive was accepted")
        } catch BackupError.unsupportedVersion(let version) {
            #expect(version == 2)
        } catch {
            Issue.record("Compatibility should fail before decoding profiles: \(error)")
        }
    }

    @Test func oversizedSavedStateStaysUntouchedAndReadOnly() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        let original = Data(repeating: 0x20, count: BackupManager.maximumArchiveBytes + 1)
        try original.write(to: file)
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(!store.canRetryPersistence)
        #expect(store.createProfile(kind: .custom) == nil)
        #expect(try Data(contentsOf: file) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["state.json"])
    }

    @Test func sameVersionCorruptionStillPreservesAnOriginalRecoveryFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        let original = Data("{\"schemaVersion\":\(Product.stateSchemaVersion),\"profiles\":\"invalid\"}".utf8)
        try original.write(to: file)
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(store.canRetryPersistence)
        let recovery = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.lastPathComponent.hasPrefix("state.json.recovery-") })
        #expect(try Data(contentsOf: recovery) == original)
        _ = try store.createProfileAndPersist(kind: .custom)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: recovery) == original)
    }

    @Test func combinedProfileImportLimitNeverPublishesOrReplacesSavedState() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        try store.importProfiles((0..<500).map { DockProfile(name: "Profile \($0)", kind: .custom) })
        let profiles = store.state.profiles
        let original = try Data(contentsOf: file)
        #expect(throws: ProfileValidationError.self) {
            try store.importProfiles([DockProfile(name: "One too many", kind: .custom)])
        }
        #expect(store.state.profiles == profiles)
        #expect(try Data(contentsOf: file) == original)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).state.profiles == profiles)
    }

    @Test func combinedItemImportLimitDoesNotAcceptIndividuallyValidOverflow() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let full = DockProfile(name: "Full", kind: .custom, items: (0..<20_000).map { _ in .spacer(.small) })
        try store.importProfiles([full])
        let original = try Data(contentsOf: file)
        let additional = DockProfile(name: "Additional", kind: .custom, items: [.spacer(.small)])
        try ProfileSemanticValidator.validate([additional])
        #expect(throws: ProfileValidationError.self) { try store.importProfiles([additional]) }
        #expect(store.state.profiles == [full])
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func failedCreateDuplicateAndImportKeepExistingStateAndBytes() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let disk = RequiredPersistenceFixtureDisk()
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false, stateWriter: disk.writer())
        let id = try store.createProfileAndPersist(kind: .custom, name: "Existing")
        let profiles = store.state.profiles
        let settings = store.state.settings
        let original = try Data(contentsOf: file)
        disk.setFailure(true)
        #expect(store.createProfile(kind: .custom, name: "Rejected") == nil)
        #expect(throws: RequiredPersistenceFixtureDisk.Failure.self) { try store.duplicateProfile(id) }
        #expect(throws: RequiredPersistenceFixtureDisk.Failure.self) {
            try store.importProfiles([DockProfile(name: "Import", kind: .custom)])
        }
        #expect(store.state.profiles == profiles)
        #expect(store.state.settings == settings)
        #expect(try Data(contentsOf: file) == original)
        disk.setFailure(false)
        let copyID = try store.duplicateProfile(id)
        #expect(copyID != id)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).state.profiles.count == 2)
    }

    @Test func routineWidgetAcceptanceIsDifferentFromDurableSave() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let (store, profileID, note) = try noteFixture(file: file)
        #expect(store.updateWidgetConfiguration(itemID: UUID(), in: profileID) { $0.noteText = "Missing" } == .missingTarget)
        #expect(store.updateWidgetConfiguration(itemID: note.id, in: profileID) { $0.noteText = "Queued" } == .accepted)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "")
        try store.updateWidgetConfigurationAndPersist(itemID: note.id, in: profileID) { $0.noteText = "Durable" }
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "Durable")
    }

    @Test func rejectedUnicodeNoteSurvivesSaveAndQuitFlushForRetry() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let (store, profileID, note) = try noteFixture(file: file)
        let drafts = WidgetSetupDraftStore()
        let boundary = String(repeating: "é", count: 524_288)
        try drafts.saveNote(boundary, for: note.id, in: profileID, to: store)
        #expect(!drafts.hasPendingNotes)
        let rejected = boundary + "é"
        #expect(throws: ProfileValidationError.self) { try drafts.saveNote(rejected, for: note.id, in: profileID, to: store) }
        #expect(drafts.noteDraft(for: note.id, in: profileID) == rejected)
        if case .success = drafts.flushNotes(to: store) { Issue.record("Rejected note flush reported success") }
        #expect(drafts.hasPendingNotes)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).activeCustomProfile?.items.first?.widgetConfiguration?.noteText == boundary)
        drafts.updateNoteDraft("Corrected", for: note.id, in: profileID)
        try drafts.flushNotes(to: store).get()
        #expect(!drafts.hasPendingNotes)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "Corrected")
    }

    @Test func failedNoteWriteKeepsDraftAndRetryFlushClearsOnlyAfterDurability() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let disk = RequiredPersistenceFixtureDisk()
        let (store, profileID, note) = try noteFixture(file: file, writer: disk.writer())
        let drafts = WidgetSetupDraftStore()
        disk.setFailure(true)
        #expect(throws: RequiredPersistenceFixtureDisk.Failure.self) { try drafts.saveNote("Keep this draft", for: note.id, in: profileID, to: store) }
        #expect(drafts.noteDraft(for: note.id, in: profileID) == "Keep this draft")
        if case .success = drafts.flushNotes(to: store) { Issue.record("Failed write flush reported success") }
        #expect(store.activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "")
        disk.setFailure(false)
        try drafts.flushNotes(to: store).get()
        #expect(!drafts.hasPendingNotes)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "Keep this draft")
    }

    @Test func aFailedBatchCannotPartiallyAcknowledgeAnotherNote() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let first = DockItem.widget("Sticky Note"), second = DockItem.widget("Sticky Note")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let profileID = try store.createProfile(DockProfile(name: "Notes", kind: .custom, items: [first, second]))
        let original = try Data(contentsOf: file)
        let drafts = WidgetSetupDraftStore()
        drafts.updateNoteDraft("Valid unfinished note", for: first.id, in: profileID)
        drafts.updateNoteDraft(String(repeating: "x", count: 1_048_577), for: second.id, in: profileID)
        if case .success = drafts.flushNotes(to: store) { Issue.record("Invalid batch reported success") }
        #expect(drafts.noteDraft(for: first.id, in: profileID) == "Valid unfinished note")
        #expect(store.activeCustomProfile?.items.allSatisfy { $0.widgetConfiguration?.noteText == "" } == true)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func staleDebounceCannotOverwriteNewerDraftAndMissingTargetRetainsInput() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let (store, profileID, note) = try noteFixture(file: file)
        let drafts = WidgetSetupDraftStore()
        drafts.updateNoteDraft("Newest", for: note.id, in: profileID)
        try drafts.saveNote("Older", for: note.id, in: profileID, to: store)
        #expect(drafts.noteDraft(for: note.id, in: profileID) == "Newest")
        #expect(store.activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "")
        let missingID = UUID()
        #expect(throws: WidgetConfigurationMutationError.self) { try drafts.saveNote("Recoverable", for: missingID, in: profileID, to: store) }
        #expect(drafts.noteDraft(for: missingID, in: profileID) == "Recoverable")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-PersistenceCorrection-\(UUID().uuidString)", isDirectory: true)
    }

    private func noteFixture(file: URL, writer: RevisionedStateWriter? = nil) throws -> (ProfileStore, UUID, DockItem) {
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false, stateWriter: writer)
        let note = DockItem.widget("Sticky Note")
        let profileID = try store.createProfile(DockProfile(name: "Notes", kind: .custom, items: [note]))
        return (store, profileID, note)
    }
}

private final class RequiredPersistenceFixtureDisk: @unchecked Sendable {
    struct Failure: Error {}
    private let lock = NSLock()
    private var fails = false

    func setFailure(_ value: Bool) { lock.lock(); fails = value; lock.unlock() }
    func writer() -> RevisionedStateWriter {
        RevisionedStateWriter { [self] state, url in
            lock.lock(); let failure = fails; lock.unlock()
            if failure { throw Failure() }
            try RevisionedStateWriter.persist(state, to: url)
        }
    }
}
