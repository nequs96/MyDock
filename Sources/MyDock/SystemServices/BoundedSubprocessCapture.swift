import Darwin
import Foundation

struct BoundedSubprocessOutput: Sendable {
    var standardOutput: Data
    var standardError: Data
    var terminationStatus: Int32
}

enum BoundedSubprocessCaptureError: Error, Equatable, Sendable {
    case timedOut
    case outputLimitExceeded
    case outputReadFailed
}

private final class SubprocessBox: @unchecked Sendable {
    let process: Process
    private let lock = NSLock()
    private var terminationScheduled = false

    init(process: Process) {
        self.process = process
    }

    var isRunning: Bool { process.isRunning }

    func terminateEscalating() {
        lock.lock()
        guard !terminationScheduled, process.isRunning else {
            lock.unlock()
            return
        }
        terminationScheduled = true
        let processID = process.processIdentifier
        lock.unlock()

        if process.isRunning { process.terminate() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(500)) { [self] in
            guard process.isRunning, process.processIdentifier == processID else { return }
            _ = kill(processID, SIGKILL)
        }
    }

}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set() {
        lock.lock()
        storage = true
        lock.unlock()
    }
}

private struct SubprocessDeadline {
    let uptimeNanoseconds: UInt64

    init(timeout: TimeInterval) {
        let now = DispatchTime.now().uptimeNanoseconds
        if timeout == .infinity {
            uptimeNanoseconds = .max
        } else {
            let seconds = timeout.isFinite ? max(0, timeout) : 0
            let available = Double(UInt64.max - now)
            let duration = min(seconds * 1_000_000_000, available)
            uptimeNanoseconds = now + UInt64(max(0, duration))
        }
    }

    var dispatchTime: DispatchTime { DispatchTime(uptimeNanoseconds: uptimeNanoseconds) }

    var isExpired: Bool { DispatchTime.now().uptimeNanoseconds >= uptimeNanoseconds }

    func pollTimeoutMilliseconds() -> Int32 {
        // Without a deadline (an interactive shortcut can wait on the user) a slow tick is enough: cancelling
        // terminates the child, and its closed pipe wakes poll at once.
        if uptimeNanoseconds == .max { return 1_000 }
        let now = DispatchTime.now().uptimeNanoseconds
        guard uptimeNanoseconds > now else { return 0 }
        let remaining = uptimeNanoseconds - now
        let milliseconds = min((remaining + 999_999) / 1_000_000, 100)
        return Int32(max(1, milliseconds))
    }
}

private final class SubprocessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellationRequested = false
    private var process: SubprocessBox?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    func attach(_ process: SubprocessBox) {
        lock.lock()
        self.process = process
        let shouldTerminate = cancellationRequested
        lock.unlock()
        if shouldTerminate { process.terminateEscalating() }
    }

    func cancel() {
        lock.lock()
        cancellationRequested = true
        let process = self.process
        lock.unlock()
        process?.terminateEscalating()
    }
}

private final class BoundedPipeReader: @unchecked Sendable {
    private let fileHandle: FileHandle
    private let maximumBytes: Int
    private let process: SubprocessBox
    private let deadline: SubprocessDeadline
    private let cancellationState: SubprocessRunState?
    private(set) var data = Data()
    private(set) var exceededLimit = false
    private(set) var failed = false
    private(set) var timedOut = false

    init(fileHandle: FileHandle,
         maximumBytes: Int,
         process: SubprocessBox,
         deadline: SubprocessDeadline,
         cancellationState: SubprocessRunState?) {
        self.fileHandle = fileHandle
        self.maximumBytes = max(0, maximumBytes)
        self.process = process
        self.deadline = deadline
        self.cancellationState = cancellationState
    }

    func drain() {
        defer { try? fileHandle.close() }
        let fileDescriptor = fileHandle.fileDescriptor
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0, fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            failed = true
            process.terminateEscalating()
            return
        }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if cancellationState?.isCancelled == true { return }
            guard !deadline.isExpired else {
                timedOut = true
                process.terminateEscalating()
                return
            }

            var descriptor = pollfd(fd: fileDescriptor,
                                    events: Int16(POLLIN | POLLHUP | POLLERR),
                                    revents: 0)
            let pollResult = poll(&descriptor, 1, deadline.pollTimeoutMilliseconds())
            if pollResult == 0 { continue }
            if pollResult < 0 {
                if errno == EINTR { continue }
                failed = true
                process.terminateEscalating()
                return
            }
            if descriptor.revents & Int16(POLLNVAL) != 0 {
                failed = true
                process.terminateEscalating()
                return
            }
            guard descriptor.revents & Int16(POLLIN | POLLHUP | POLLERR) != 0 else { continue }

            let bytesRead = Darwin.read(fileDescriptor, &buffer, buffer.count)
            if bytesRead == 0 { return }
            if bytesRead < 0 {
                if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK { continue }
                failed = true
                process.terminateEscalating()
                return
            }

            let remaining = maximumBytes - data.count
            if remaining > 0 {
                data.append(contentsOf: buffer.prefix(min(bytesRead, remaining)))
            }
            if bytesRead > remaining {
                exceededLimit = true
                process.terminateEscalating()
                return
            }
        }
    }
}

enum BoundedSubprocessCapture {
    static func run(executableURL: URL,
                    arguments: [String],
                    input: Data? = nil,
                    maximumOutputBytes: Int,
                    maximumErrorBytes: Int,
                    timeout: TimeInterval,
                    currentDirectoryURL: URL? = nil,
                    environment: [String: String]? = nil) throws -> BoundedSubprocessOutput {
        try runSynchronously(executableURL: executableURL,
                             arguments: arguments,
                             input: input,
                             maximumOutputBytes: maximumOutputBytes,
                             maximumErrorBytes: maximumErrorBytes,
                             timeout: timeout,
                             currentDirectoryURL: currentDirectoryURL,
                             environment: environment,
                             cancellationState: nil)
    }

    static func runCancellable(executableURL: URL,
                               arguments: [String],
                               input: Data? = nil,
                               maximumOutputBytes: Int,
                               maximumErrorBytes: Int,
                               timeout: TimeInterval,
                               currentDirectoryURL: URL? = nil,
                               environment: [String: String]? = nil) async throws -> BoundedSubprocessOutput {
        let cancellationState = SubprocessRunState()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<BoundedSubprocessOutput, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let result = try runSynchronously(executableURL: executableURL,
                                                          arguments: arguments,
                                                          input: input,
                                                          maximumOutputBytes: maximumOutputBytes,
                                                          maximumErrorBytes: maximumErrorBytes,
                                                          timeout: timeout,
                                                          currentDirectoryURL: currentDirectoryURL,
                                                          environment: environment,
                                                          cancellationState: cancellationState)
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellationState.cancel()
        }
    }

    private static func runSynchronously(executableURL: URL,
                                         arguments: [String],
                                         input: Data? = nil,
                                         maximumOutputBytes: Int,
                                         maximumErrorBytes: Int,
                                         timeout: TimeInterval,
                                         currentDirectoryURL: URL? = nil,
                                         environment: [String: String]? = nil,
                                         cancellationState: SubprocessRunState?) throws -> BoundedSubprocessOutput {
        let process = Process()
        let processBox = SubprocessBox(process: process)
        let deadline = SubprocessDeadline(timeout: timeout)
        cancellationState?.attach(processBox)
        if cancellationState?.isCancelled == true { throw CancellationError() }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = input == nil ? nil : Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL
        process.environment = environment
        if let inputPipe {
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        if cancellationState?.isCancelled == true { processBox.terminateEscalating() }

        let outputReader = BoundedPipeReader(fileHandle: outputPipe.fileHandleForReading,
                                             maximumBytes: maximumOutputBytes,
                                             process: processBox,
                                             deadline: deadline,
                                             cancellationState: cancellationState)
        let errorReader = BoundedPipeReader(fileHandle: errorPipe.fileHandleForReading,
                                            maximumBytes: maximumErrorBytes,
                                            process: processBox,
                                            deadline: deadline,
                                            cancellationState: cancellationState)
        // Each pipe is drained on its own thread rather than a shared dispatch queue: when the shared pool is busy,
        // a queued reader could wait behind its own caller, and the call would never return.
        let readers = DispatchGroup()
        for reader in [outputReader, errorReader] {
            readers.enter()
            let thread = Thread {
                reader.drain()
                readers.leave()
            }
            thread.name = "app.mydock.subprocess-reader"
            thread.qualityOfService = .utility
            thread.start()
        }

        let timedOut = LockedFlag()
        let timeoutWork = DispatchWorkItem {
            timedOut.set()
            processBox.terminateEscalating()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline.dispatchTime, execute: timeoutWork)

        do {
            if let input, let inputPipe {
                try writeInput(input, to: inputPipe.fileHandleForWriting,
                               process: processBox, deadline: deadline,
                               cancellationState: cancellationState, timedOut: timedOut)
            }
            process.waitUntilExit()
        } catch {
            processBox.terminateEscalating()
            process.waitUntilExit()
            readers.wait()
            timeoutWork.cancel()
            if cancellationState?.isCancelled == true { throw CancellationError() }
            if timedOut.value || outputReader.timedOut || errorReader.timedOut {
                throw BoundedSubprocessCaptureError.timedOut
            }
            throw error
        }

        readers.wait()
        timeoutWork.cancel()

        if cancellationState?.isCancelled == true { throw CancellationError() }
        if timedOut.value || outputReader.timedOut || errorReader.timedOut {
            throw BoundedSubprocessCaptureError.timedOut
        }
        if outputReader.failed || errorReader.failed { throw BoundedSubprocessCaptureError.outputReadFailed }
        if outputReader.exceededLimit || errorReader.exceededLimit {
            throw BoundedSubprocessCaptureError.outputLimitExceeded
        }
        return BoundedSubprocessOutput(standardOutput: outputReader.data,
                                       standardError: errorReader.data,
                                       terminationStatus: process.terminationStatus)
    }

    private static func writeInput(_ input: Data,
                                   to fileHandle: FileHandle,
                                   process: SubprocessBox,
                                   deadline: SubprocessDeadline,
                                   cancellationState: SubprocessRunState?,
                                   timedOut: LockedFlag) throws {
        defer { try? fileHandle.close() }
        var blockedSignals = sigset_t()
        sigemptyset(&blockedSignals)
        sigaddset(&blockedSignals, SIGPIPE)
        var originalSignalMask = sigset_t()
        guard pthread_sigmask(SIG_BLOCK, &blockedSignals, &originalSignalMask) == 0 else {
            throw BoundedSubprocessCaptureError.outputReadFailed
        }
        var receivedBrokenPipe = false
        defer {
            if receivedBrokenPipe {
                var pendingSignals = sigset_t()
                if sigpending(&pendingSignals) == 0, sigismember(&pendingSignals, SIGPIPE) == 1 {
                    var receivedSignal: Int32 = 0
                    _ = sigwait(&blockedSignals, &receivedSignal)
                }
            }
            _ = pthread_sigmask(SIG_SETMASK, &originalSignalMask, nil)
        }

        let fileDescriptor = fileHandle.fileDescriptor
        let flags = fcntl(fileDescriptor, F_GETFL)
        guard flags >= 0, fcntl(fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw BoundedSubprocessCaptureError.outputReadFailed
        }

        try input.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < buffer.count {
                if cancellationState?.isCancelled == true { throw CancellationError() }
                guard !deadline.isExpired else {
                    timedOut.set()
                    process.terminateEscalating()
                    throw BoundedSubprocessCaptureError.timedOut
                }

                let bytesWritten = Darwin.write(fileDescriptor,
                                                baseAddress.advanced(by: offset),
                                                buffer.count - offset)
                if bytesWritten > 0 {
                    offset += bytesWritten
                    continue
                }
                if bytesWritten < 0 && errno == EINTR { continue }
                if bytesWritten < 0 && errno == EPIPE {
                    receivedBrokenPipe = true
                    throw BoundedSubprocessCaptureError.outputReadFailed
                }
                if bytesWritten < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    var descriptor = pollfd(fd: fileDescriptor, events: Int16(POLLOUT), revents: 0)
                    let pollResult = poll(&descriptor, 1, deadline.pollTimeoutMilliseconds())
                    if pollResult == 0 { continue }
                    if pollResult < 0 && errno == EINTR { continue }
                    if pollResult < 0 || descriptor.revents & Int16(POLLNVAL | POLLERR | POLLHUP) != 0 {
                        throw BoundedSubprocessCaptureError.outputReadFailed
                    }
                    continue
                }
                throw BoundedSubprocessCaptureError.outputReadFailed
            }
        }
    }
}
