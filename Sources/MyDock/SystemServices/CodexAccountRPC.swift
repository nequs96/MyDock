import Foundation
import Darwin

/// A bounded read-only session: initialize first, then request account data.
/// Keeping stdin open until the reply avoids cancelling the server at EOF.
enum CodexAccountRPC {
    static func request(executable: URL, method: String, parameters: [String: Any] = [:], timeout: TimeInterval = 12, environment: [String: String]? = nil) throws -> Data {
        try AppRuntimeEnvironment.requireCredentials()
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
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func response(id: Int) throws -> Data {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while ProcessInfo.processInfo.systemUptime < deadline {
                while let newline = pending.firstIndex(of: 0x0A) {
                    let line = Data(pending[..<newline])
                    pending.removeSubrange(...newline)
                    if let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any], json["id"] as? Int == id {
                        if json["error"] != nil { throw AIUsageError.codexAuthenticationUnavailable }
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
                    } else if count == 0 && index == 0 { throw AIUsageError.codexAuthenticationUnavailable }
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
