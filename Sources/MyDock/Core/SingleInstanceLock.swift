import Darwin
import Foundation

enum SingleInstanceLockError: Error, Equatable {
    case alreadyRunning
    case unavailable(Int32)
}

final class SingleInstanceLock {
    private let descriptor: Int32

    init(fileURL: URL? = nil) throws {
        // The lock lives beside state.json, in the isolated validation layout as well.
        let url = fileURL ?? AppRuntimeEnvironment.applicationSupportDirectory.appendingPathComponent("instance.lock")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw SingleInstanceLockError.unavailable(Self.posixCode(of: error))
        }

        let descriptor = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                                     mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw SingleInstanceLockError.unavailable(errno) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            if code == EWOULDBLOCK { throw SingleInstanceLockError.alreadyRunning }
            throw SingleInstanceLockError.unavailable(code)
        }
        self.descriptor = descriptor
    }

    /// The POSIX code behind a Foundation file error (disk full, read-only volume, permission), or EIO.
    static func posixCode(of error: Error) -> Int32 {
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain { return Int32(error.code) }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return Int32(underlying.code)
        }
        return EIO
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }
}
