import Darwin
import Foundation

enum SingleInstanceLockError: Error, Equatable {
    case alreadyRunning
    case unavailable(Int32)
}

final class SingleInstanceLock {
    private let descriptor: Int32

    init(fileURL: URL? = nil) throws {
        let supportRoot = AppRuntimeEnvironment.applicationSupportDirectory.deletingLastPathComponent()
        let directory = supportRoot.appendingPathComponent(Product.name, isDirectory: true)
        let url = fileURL ?? directory.appendingPathComponent("instance.lock")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw SingleInstanceLockError.unavailable(Int32(EACCES))
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

    deinit {
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }
}
