import Foundation
import Darwin

/// A flag that another thread sets to stop blocking work; the work checks it between bounded steps.
final class BackgroundCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }
}

/// Runs blocking work (a subprocess wait, a log scan) on a utility queue instead of a Swift-concurrency
/// thread, so it cannot starve the cooperative pool. Cancelling the calling task sets the work's flag.
enum BackgroundWork {
    static func run<T: Sendable>(_ work: @escaping @Sendable (BackgroundCancellation) -> T) async -> T {
        let cancellation = BackgroundCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                DispatchQueue.global(qos: .utility).async { continuation.resume(returning: work(cancellation)) }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    static func runThrowing<T: Sendable>(_ work: @escaping @Sendable (BackgroundCancellation) throws -> T) async throws -> T {
        let cancellation = BackgroundCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try work(cancellation)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }
}

/// A bounded read-only session: initialize first, then request account data.
/// Keeping stdin open until the reply avoids cancelling the server at EOF.
enum CodexAccountRPC {
    /// The same request off the Swift-concurrency pool; cancelling the task stops the server within one poll interval.
    static func requestInBackground(executable: URL, method: String, parameters: [String: any Sendable] = [:],
                                    timeout: TimeInterval = 12, environment: [String: String]? = nil) async throws -> Data {
        try await BackgroundWork.runThrowing { cancellation in
            try CodexAccountRPC.request(executable: executable, method: method, parameters: parameters.mapValues { $0 as Any },
                                        timeout: timeout, environment: environment, cancellation: cancellation)
        }
    }

    /// A JSON-RPC error names what failed: a missing method means this Codex cannot serve the request,
    /// anything else is treated as the account being unavailable to the app-server.
    static func usageError(forRPCError error: Any) -> AIUsageError {
        let object = error as? [String: Any]
        let code = (object?["code"] as? NSNumber)?.intValue
        let message = ((object?["message"] as? String) ?? (error as? String) ?? "").lowercased()
        if code == -32601 || message.contains("method not found") || message.contains("unknown method")
            || message.contains("unknown variant") {
            return .codexAppServerUnsupported
        }
        return .codexAuthenticationUnavailable
    }

    static func request(executable: URL, method: String, parameters: [String: Any] = [:], timeout: TimeInterval = 12,
                        environment: [String: String]? = nil, cancellation: BackgroundCancellation? = nil) throws -> Data {
        let process = Process()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = environment ?? ProcessInfo.processInfo.environment
        environment["RUST_LOG"] = "off"
        process.environment = environment
        try process.run()
        // A server that exits mid-session must not take MyDock down: writing to its closed stdin
        // then fails with EPIPE instead of raising SIGPIPE, whose default action ends the process.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let pid = process.processIdentifier
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(500)) {
                    if process.isRunning, process.processIdentifier == pid { kill(pid, SIGKILL) }
                }
            }
            try? output.fileHandleForReading.close()
            try? errors.fileHandleForReading.close()
        }
        let fd = output.fileHandleForReading.fileDescriptor
        let errorFD = errors.fileHandleForReading.fileDescriptor
        for descriptor in [fd, errorFD] {
            let flags = fcntl(descriptor, F_GETFL)
            guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw AIUsageError.codexResponseInvalid }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var pending = Data()
        var receivedBytes = 0
        func send(_ request: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: request)
            data.append(0x0A)
            // The server already exited, so this Codex cannot serve the session.
            do { try input.fileHandleForWriting.write(contentsOf: data) }
            catch { throw AIUsageError.codexAppServerUnsupported }
        }
        func response(id: Int) throws -> Data {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while ProcessInfo.processInfo.systemUptime < deadline {
                if cancellation?.isCancelled == true { throw CancellationError() }
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any], json["id"] as? Int == id {
                        if let error = json["error"], !(error is NSNull) { throw usageError(forRPCError: error) }
                        return line
                    }
                }
                var descriptors = [pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0),
                                   pollfd(fd: errorFD, events: Int16(POLLIN | POLLHUP), revents: 0)]
                let result = poll(&descriptors, 2, 50)
                if result < 0 && errno != EINTR { throw AIUsageError.codexResponseInvalid }
                for index in descriptors.indices where descriptors[index].revents & Int16(POLLIN | POLLHUP) != 0 {
                    let count = Darwin.read(descriptors[index].fd, &buffer, buffer.count)
                    if count > 0 {
                        receivedBytes += count
                        guard receivedBytes <= 2_000_000 else { throw AIUsageError.codexResponseInvalid }
                        if index == 0 { pending.append(contentsOf: buffer.prefix(count)) }
                    } else if count == 0 && index == 0 {
                        // The server closed its output before replying: it exited or does not speak this protocol.
                        throw AIUsageError.codexAppServerUnsupported
                    }
                }
            }
            throw AIUsageError.codexAppServerTimedOut
        }
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "mydock", "title": "MyDock", "version": Product.marketingVersion]]])
        _ = try response(id: 1)
        try send(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
        try send(["jsonrpc": "2.0", "id": 2, "method": method, "params": parameters])
        return try response(id: 2)
    }
}
