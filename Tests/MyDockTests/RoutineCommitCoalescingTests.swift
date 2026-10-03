import Foundation
import Testing
@testable import MyDock

/// MD-E01: routine commits are coalesced onto the writer queue; durable paths stay synchronous. Fixture files only.
@MainActor
struct RoutineCommitCoalescingTests {
    private final class Disk: @unchecked Sendable {
        struct Failure: Error {}
        private let lock = NSLock()
        private var fails = false
        private var writes = 0
        func setFailure(_ v: Bool) { lock.lock(); fails = v; lock.unlock() }
        var writeCount: Int { lock.lock(); defer { lock.unlock() }; return writes }
        func writer() -> RevisionedStateWriter {
            RevisionedStateWriter { [self] state, url in
                lock.lock(); let failure = fails; if !failure { writes += 1 }; lock.unlock()
                if failure { throw Failure() }
                try RevisionedStateWriter.persist(state, to: url)
            }
        }
    }

    private func makeStore() -> (ProfileStore, URL, Disk, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-RoutineCommit-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("state.json")
        let disk = Disk()
        return (ProfileStore(fileURL: file, allowsSystemChanges: false, stateWriter: disk.writer()), file, disk, directory)
    }

    private func diskSettings(_ file: URL) throws -> AppSettings {
        try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: file)).settings
    }

    private func wait(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
    }

    @Test func rapidRoutineChangesCoalesceIntoOrderedFinalFile() async throws {
        let (store, file, disk, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let baseline = disk.writeCount
        for index in 1...40 { store.updateSettings { $0.customDockSize = 0.7 + Double(index) / 100 } }
        #expect(disk.writeCount == baseline)
        await wait { disk.writeCount > baseline && !store.isSaving }
        #expect(try diskSettings(file).customDockSize == 1.1)
        #expect(disk.writeCount - baseline <= 2)
        #expect(!store.hasUnpersistedChanges && store.persistenceError == nil)
    }

    @Test func asyncFailureSurfacesErrorAndUnpersistedState() async throws {
        let (store, _, disk, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        disk.setFailure(true)
        store.updateSettings { $0.customDockSize = 0.9 }
        await wait { store.hasUnpersistedChanges }
        #expect(store.hasUnpersistedChanges)
        #expect(store.persistenceError != nil)
        #expect(!store.isSaving)
    }

    @Test func flushAfterPendingAsyncWritesNewestAndReflectsDisk() async throws {
        let (store, file, _, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        store.updateSettings { $0.customDockSize = 0.8 }
        store.updateSettings { $0.customDockSize = 1.2 }
        store.flush()
        #expect(!store.hasUnpersistedChanges)
        #expect(try diskSettings(file).customDockSize == 1.2)
        try await Task.sleep(for: .milliseconds(400))
        #expect(try diskSettings(file).customDockSize == 1.2)
    }

    @Test func quitFlushAfterAsyncFailureRetriesAndRecovers() async throws {
        let (store, file, disk, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        disk.setFailure(true)
        store.updateSettings { $0.customDockSize = 1.3 }
        await wait { store.hasUnpersistedChanges }
        store.flush()
        #expect(store.hasUnpersistedChanges)
        disk.setFailure(false)
        store.flush()
        #expect(!store.hasUnpersistedChanges && store.persistenceError == nil)
        #expect(try diskSettings(file).customDockSize == 1.3)
    }

    @Test func criticalPathsRemainSynchronousAndTruthful() throws {
        let (store, file, disk, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        disk.setFailure(true)
        #expect(throws: (any Error).self) { try store.importProfiles([DockProfile(name: "Import", kind: .custom)]) }
        disk.setFailure(false)
        let id = try store.createProfile(DockProfile(name: "Created", kind: .custom))
        let onDisk = try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: file))
        #expect(onDisk.profiles.contains { $0.id == id })
    }
}
