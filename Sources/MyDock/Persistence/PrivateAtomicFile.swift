import Darwin
import Foundation

/// The one commit sequence for MyDock's private files (state, history, presets, drafts and the runtime cache): a 0700
/// folder, a 0600 sibling created exclusively without following links, written in full and flushed to the drive,
/// then renamed over the destination. The file never exists with default permissions or partial contents.
enum PrivateAtomicFile {
    enum Checkpoint: Equatable { case temporaryWritten, beforeAtomicCommit }

    /// Temporaries are named `.mydock-state-<UUID>.tmp`, so `RevisionedStateWriter.removeAbandonedTemporaries` can
    /// clean up any left by a crash.
    static let temporaryPrefix = ".mydock-state-"

    static func write(_ data: Data, to url: URL, checkpoint: ((Checkpoint) throws -> Void)? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        // Prepare a private sibling completely before the commit point. Nothing after rename can
        // report failure with new bytes on disk while the caller still retains the old contents.
        let temporary = url.deletingLastPathComponent().appendingPathComponent(temporaryPrefix + UUID().uuidString + ".tmp")
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
        // Plain fsync leaves the bytes in the drive cache on macOS; F_FULLFSYNC makes them durable before the
        // rename can be. Volumes that do not support it fall back to fsync.
        if Darwin.fcntl(descriptor, F_FULLFSYNC) != 0 {
            guard Darwin.fsync(descriptor) == 0 else { throw posixError() }
        }
        let closeResult = Darwin.close(descriptor)
        descriptor = -1
        guard closeResult == 0 else { throw posixError() }
        try checkpoint?(.beforeAtomicCommit)
        let result = temporary.withUnsafeFileSystemRepresentation { source in
            url.withUnsafeFileSystemRepresentation { destination in Darwin.rename(source!, destination!) }
        }
        guard result == 0 else { throw posixError() }
        // Make the rename itself durable. Best effort: the commit has happened, so nothing is reported from here.
        let folder = url.deletingLastPathComponent().withUnsafeFileSystemRepresentation { Darwin.open($0!, O_RDONLY) }
        if folder >= 0 { _ = Darwin.fsync(folder); _ = Darwin.close(folder) }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
