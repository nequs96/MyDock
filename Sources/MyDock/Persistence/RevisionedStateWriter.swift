import Foundation

/// All writes share a serial queue. Superseded snapshots never replace a newer revision.
final class RevisionedStateWriter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.mydock.state-writer", qos: .utility)
    private let lock = NSLock()
    private var latestRevision: UInt64 = 0

    private func announce(_ revision: UInt64) {
        lock.lock(); latestRevision = max(latestRevision, revision); lock.unlock()
    }
    private func isCurrent(_ revision: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }; return latestRevision == revision
    }

    func write(_ state: PersistentState, to url: URL, revision: UInt64,
               immediately: Bool, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        announce(revision)
        let work: @Sendable () -> Void = { [self] in
            guard isCurrent(revision) else { return }
            completion(Result { try Self.persist(state, to: url) })
        }
        if immediately { queue.sync(execute: work) }
        else { queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work) }
    }

    func writeImmediately(_ state: PersistentState, to url: URL, revision: UInt64) throws {
        announce(revision)
        try queue.sync { try Self.persist(state, to: url) }
    }

    private static func persist(_ state: PersistentState, to url: URL) throws {
        try ProfileSemanticValidator.validate(state.profiles)
        try ProfileAppearance(settings: state.settings).validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= BackupManager.maximumArchiveBytes else { throw BackupError.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
