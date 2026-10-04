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

    func write(_ state: PersistentState, to url: URL, revision: UInt64,
               immediately: Bool, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        announce(revision)
        let work: @Sendable () -> Void = { [self] in
            guard isCurrent(revision) else { return }
            completion(Result { try persistState(state.strippedOfRuntimeReadings, url) })
        }
        if immediately { queue.sync(execute: work) }
        else { queue.asyncAfter(deadline: .now() + .milliseconds(150), execute: work) }
    }

    func writeImmediately(_ state: PersistentState, to url: URL, revision: UInt64) throws {
        announce(revision)
        try queue.sync { try persistState(state.strippedOfRuntimeReadings, url) }
    }

    enum PersistenceCheckpoint: Equatable { case temporaryWritten, beforeAtomicCommit }

    static func persist(_ state: PersistentState, to url: URL,
                        checkpoint: ((PersistenceCheckpoint) throws -> Void)? = nil) throws {
        try ProfileSemanticValidator.validate(state.profiles)
        try ProfileAppearance(settings: state.settings).validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(state)
        guard data.count <= BackupManager.maximumArchiveBytes else { throw BackupError.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // Prepare a private sibling completely before the commit point. Nothing after rename can
        // report failure with new bytes on disk while ProfileStore still retains the old candidate.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".mydock-state-\(UUID().uuidString).tmp")
        var descriptor = temporary.withUnsafeFileSystemRepresentation {
            Darwin.open($0!, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        }
        guard descriptor >= 0 else { throw posixError() }
        defer {
            if descriptor >= 0 { _ = Darwin.close(descriptor) }
            // This unique sibling is the only file this writer owns for cleanup.
            _ = temporary.withUnsafeFileSystemRepresentation { Darwin.unlink($0!) }
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else { throw posixError() }
        try data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(descriptor, base.advanced(by: offset), bytes.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw posixError()
                }
                guard written > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) }
                offset += written
            }
        }
        try checkpoint?(.temporaryWritten)
        guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        let closeResult = Darwin.close(descriptor)
        descriptor = -1
        guard closeResult == 0 else { throw posixError() }
        try checkpoint?(.beforeAtomicCommit)
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            url.withUnsafeFileSystemRepresentation { destination in Darwin.rename(source!, destination!) }
        }
        guard result == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
