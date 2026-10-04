import Foundation
import Testing
@testable import MyDock

/// Filesystem fixtures qualify the normal commit boundary, not power-loss recovery on every filesystem.
struct ReliabilityDurableWriteTests {
    private enum Injected: Error { case failure }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-DurableWrite-\(UUID().uuidString)")
    }

    private func state(_ name: String) -> PersistentState {
        var state = PersistentState()
        state.profiles = [.init(name: name, kind: .custom)]
        return state
    }

    @Test func failuresAfterTemporaryWriteAndBeforeCommitPreserveOriginalAndRemoveOnlyOwnedTemporary() throws {
        for checkpoint in [RevisionedStateWriter.PersistenceCheckpoint.temporaryWritten, .beforeAtomicCommit] {
            let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("state.json")
            try RevisionedStateWriter.persist(state("Original"), to: file)
            let original = try Data(contentsOf: file)
            let unrelated = dir.appendingPathComponent("unrelated.tmp")
            try Data("Keep me".utf8).write(to: unrelated)
            #expect(throws: Injected.self) {
                try RevisionedStateWriter.persist(state("Candidate"), to: file) { current in
                    if current == checkpoint { throw Injected.failure }
                }
            }
            #expect(try Data(contentsOf: file) == original)
            #expect(try String(contentsOf: unrelated, encoding: .utf8) == "Keep me")
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["state.json", "unrelated.tmp"])
        }
    }

    @Test func successfulReplacementIsPrivateAndReopensAsTheExactCandidate() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        try RevisionedStateWriter.persist(state("Original"), to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        let candidate = state("Candidate")
        try RevisionedStateWriter.persist(candidate, to: file)
        #expect(try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: file)) == candidate)
        #expect((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int) == 0o600)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["state.json"])
    }

    @MainActor @Test func candidateFailureAfterPreparationPreservesMemoryAndDisk() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("state.json")
        let original = state("Original")
        try RevisionedStateWriter.persist(original, to: file)
        let bytes = try Data(contentsOf: file)
        let writer = RevisionedStateWriter { state, url in
            try RevisionedStateWriter.persist(state, to: url) { checkpoint in
                if checkpoint == .beforeAtomicCommit { throw Injected.failure }
            }
        }
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false, stateWriter: writer)
        #expect(throws: Injected.self) {
            _ = try store.createProfile(.init(name: "Candidate", kind: .custom))
        }
        #expect(store.state == original)
        #expect(store.hasUnpersistedChanges && store.persistenceError != nil)
        #expect(try Data(contentsOf: file) == bytes)
    }
}
