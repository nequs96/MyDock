import Foundation
import Darwin

/// All writes share a serial queue. Superseded snapshots never replace a newer revision.
final class RevisionedStateWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.mydock.state-writer", qos: .utility)
    private let lock = NSLock()
    private var latestRevision: UInt64 = 0
    private let persistState: @Sendable (PersistentState, URL) throws -> Void

    init(persistState: (@Sendable (PersistentState, URL) throws -> Void)? = nil) {
        self.persistState = persistState ?? { try Self.persist($0, to: $1) }
    }

    private func announce(_ revision: UInt64) {
        lock.lock(); latestRevision = max(latestRevision, revision); lock.unlock()
    }
    private func isCurrent(_ revision: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return latestRevision == revision
    }

    /// Coalesced background write: a newer revision announced within 150 ms supersedes this one.
    func write(_ state: PersistentState, to url: URL, revision: UInt64,
               completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        announce(revision)
        queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [self] in
            guard isCurrent(revision) else { return }
            completion(Result { try persistState(state.strippedOfRuntimeReadings, url) })
        }
    }

    func writeImmediately(_ state: PersistentState, to url: URL, revision: UInt64) throws {
        announce(revision)
        try queue.sync { try persistState(state.strippedOfRuntimeReadings, url) }
    }

    typealias PersistenceCheckpoint = PrivateAtomicFile.Checkpoint

    static func persist(_ state: PersistentState, to url: URL,
                        checkpoint: ((PersistenceCheckpoint) throws -> Void)? = nil) throws {
        try ProfileSemanticValidator.validate(state.profiles)
        try ProfileAppearance(settings: state.settings).validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= BackupManager.maximumArchiveBytes else { throw BackupError.tooLarge }
        try PrivateAtomicFile.write(data, to: url, checkpoint: checkpoint)
    }

    /// Removes `.mydock-state-*.tmp` siblings left by a crash between creating and cleaning up a temporary file.
    /// Only files older than `minimumAge` are touched, so a write in flight is never removed.
    static func removeAbandonedTemporaries(in folder: URL, minimumAge: TimeInterval = 60, now: Date = .now) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        for name in names where name.hasPrefix(PrivateAtomicFile.temporaryPrefix) && name.hasSuffix(".tmp") {
            let file = folder.appendingPathComponent(name)
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true, let modified = values.contentModificationDate,
                  now.timeIntervalSince(modified) >= minimumAge else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
