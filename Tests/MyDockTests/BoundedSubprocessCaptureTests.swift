import Foundation
import Testing
@testable import MyDock

/// Wall-clock deadline cases must not compete with this suite’s own process stress tests.
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
        #expect(Date.now.timeIntervalSince(start) < 3)
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
        #expect(Date.now.timeIntervalSince(start) < 3)
    }

    @Test func timeoutAlsoBoundsPipesInheritedByBackgroundChildren() throws {
        let script = try makeScript("/bin/sleep 2 &\nexit 0")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let start = Date.now

        #expect(throws: BoundedSubprocessCaptureError.timedOut) {
            try BoundedSubprocessCapture.run(executableURL: script,
                                             arguments: [],
                                             maximumOutputBytes: 1_024,
                                             maximumErrorBytes: 1_024,
                                             timeout: 0.2)
        }
        #expect(Date.now.timeIntervalSince(start) < 1.5)
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
        let script = try makeScript("exec /bin/sleep 30")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let task = Task.detached(priority: .utility) {
            try await BoundedSubprocessCapture.runCancellable(executableURL: script,
                                                              arguments: [],
                                                              maximumOutputBytes: 1_024,
                                                              maximumErrorBytes: 1_024,
                                                              timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("The cancelled subprocess unexpectedly returned output.")
        } catch is CancellationError {
            // Expected cancellation after the child has been terminated.
        }
    }

    @Test func cancellingWhileOnlyAnInheritedPipeRemainsReturnsPromptly() async throws {
        let script = try makeScript("/bin/sleep 5 &\nexit 0")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let task = Task.detached(priority: .utility) {
            try await BoundedSubprocessCapture.runCancellable(executableURL: script,
                                                              arguments: [],
                                                              maximumOutputBytes: 1_024,
                                                              maximumErrorBytes: 1_024,
                                                              timeout: 30)
        }
        try await Task.sleep(for: .milliseconds(150))
        let start = Date.now
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("The cancelled subprocess unexpectedly returned output.")
        } catch is CancellationError {
            #expect(Date.now.timeIntervalSince(start) < 1)
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
