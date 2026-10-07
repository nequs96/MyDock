import Foundation
import Testing
@testable import MyDock

/// Wall-clock deadline cases must not compete with this suite’s own process stress tests.
/// Latency bounds are generous ceilings that only catch hangs; the children they race outlive them.
@Suite(.serialized)
struct BoundedSubprocessCaptureTests {
    @Test func capturesStandardOutputAndErrorWithoutPipeBackpressure() throws {
        let script = try makeScript("/usr/bin/yes x | /usr/bin/head -c 262144\n/usr/bin/yes y | /usr/bin/head -c 262144 >&2")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }

        let result = try BoundedSubprocessCapture.run(executableURL: script,
                                                     arguments: [],
                                                     maximumOutputBytes: 300_000,
                                                     maximumErrorBytes: 300_000,
                                                     timeout: 10)

        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput.count == 262_144)
        #expect(result.standardError.count == 262_144)
    }

    @Test func enforcesOutputLimitWhileTheProcessIsWriting() throws {
        let script = try makeScript("while :; do printf '0123456789'; done")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let start = Date.now

        #expect(throws: BoundedSubprocessCaptureError.outputLimitExceeded) {
            try BoundedSubprocessCapture.run(executableURL: script,
                                             arguments: [],
                                             maximumOutputBytes: 4_096,
                                             maximumErrorBytes: 4_096,
                                             timeout: 5)
        }
        #expect(Date.now.timeIntervalSince(start) < 10)
    }

    @Test func timeoutTerminatesAndReapsTheChildProcess() throws {
        let script = try makeScript("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let start = Date.now

        #expect(throws: BoundedSubprocessCaptureError.timedOut) {
            try BoundedSubprocessCapture.run(executableURL: script,
                                             arguments: [],
                                             maximumOutputBytes: 1_024,
                                             maximumErrorBytes: 1_024,
                                             timeout: 0.2)
        }
        #expect(Date.now.timeIntervalSince(start) < 10)
    }

    @Test func timeoutAlsoBoundsPipesInheritedByBackgroundChildren() throws {
        let script = try makeScript("/bin/sleep 20 &\nexit 0")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let start = Date.now

        #expect(throws: BoundedSubprocessCaptureError.timedOut) {
            try BoundedSubprocessCapture.run(executableURL: script,
                                             arguments: [],
                                             maximumOutputBytes: 1_024,
                                             maximumErrorBytes: 1_024,
                                             timeout: 0.2)
        }
        #expect(Date.now.timeIntervalSince(start) < 10)
    }

    @Test func forwardsAndClosesStandardInput() throws {
        let input = Data("local read-only request\n".utf8)
        let result = try BoundedSubprocessCapture.run(executableURL: URL(fileURLWithPath: "/bin/cat"),
                                                     arguments: [],
                                                     input: input,
                                                     maximumOutputBytes: 1_024,
                                                     maximumErrorBytes: 1_024,
                                                     timeout: 3)

        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput == input)
    }

    @Test func closedChildStandardInputDoesNotRaiseSigpipeInTheApp() throws {
        let input = Data(repeating: 0x61, count: 4 * 1024 * 1024)

        #expect(throws: BoundedSubprocessCaptureError.outputReadFailed) {
            try BoundedSubprocessCapture.run(executableURL: URL(fileURLWithPath: "/usr/bin/true"),
                                             arguments: [],
                                             input: input,
                                             maximumOutputBytes: 1_024,
                                             maximumErrorBytes: 1_024,
                                             timeout: 3)
        }
    }

    @Test func cancellingTheAsyncRunnerTerminatesItsChild() async throws {
        // The shell records its PID, then becomes the sleeping child with `exec`.
        let script = try makeScript("dir=$(dirname \"$0\")\necho $$ > \"$dir/child.tmp\" && mv \"$dir/child.tmp\" \"$dir/child.pid\"\nexec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let task = Task.detached(priority: .utility) {
            try await BoundedSubprocessCapture.runCancellable(executableURL: script,
                                                              arguments: [],
                                                              maximumOutputBytes: 1_024,
                                                              maximumErrorBytes: 1_024,
                                                              timeout: 30)
        }
        let marker = script.deletingLastPathComponent().appendingPathComponent("child.pid")
        try await waitForFile(marker)
        let recorded = String(decoding: try Data(contentsOf: marker), as: UTF8.self)
        let pid = try #require(pid_t(recorded.trimmingCharacters(in: .whitespacesAndNewlines)))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("The cancelled subprocess unexpectedly returned output.")
        } catch is CancellationError {
            // The child was terminated and reaped before the cancellation was reported.
            let result = kill(pid, 0)
            let code = errno
            #expect(result == -1)
            #expect(code == ESRCH)
        }
    }

    @Test func cancellingWhileOnlyAnInheritedPipeRemainsReturnsPromptly() async throws {
        let script = try makeScript("/bin/sleep 20 &\ntouch \"$(dirname \"$0\")/started\"\nexit 0")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let task = Task.detached(priority: .utility) {
            try await BoundedSubprocessCapture.runCancellable(executableURL: script,
                                                              arguments: [],
                                                              maximumOutputBytes: 1_024,
                                                              maximumErrorBytes: 1_024,
                                                              timeout: 30)
        }
        try await waitForFile(script.deletingLastPathComponent().appendingPathComponent("started"))
        let start = Date.now
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("The cancelled subprocess unexpectedly returned output.")
        } catch is CancellationError {
            #expect(Date.now.timeIntervalSince(start) < 10)
        }
    }

    private struct ChildDidNotStart: Error {}

    /// Polls for a file the child script writes once it is running.
    private func waitForFile(_ url: URL) async throws {
        let deadline = Date.now.addingTimeInterval(10)
        while !FileManager.default.fileExists(atPath: url.path) {
            guard Date.now < deadline else { throw ChildDidNotStart() }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func makeScript(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appendingPathComponent("capture.sh")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
