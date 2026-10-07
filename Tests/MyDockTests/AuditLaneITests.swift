import Foundation
import Testing
@testable import MyDock

/// Holds an injected loader until the test releases it, so a test can order concurrent work
/// without sleeping. `waitForStart` returns once `hold` has been entered.
actor AuditLaneIGate {
    private var started = false
    private var onStart: CheckedContinuation<Void, Never>?
    private var onRelease: CheckedContinuation<Void, Never>?
    private var released = false
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { onStart = $0 }
    }
    func hold() async {
        started = true; onStart?.resume(); onStart = nil
        if released { return }
        await withCheckedContinuation { onRelease = $0 }
    }
    func release() { released = true; onRelease?.resume(); onRelease = nil }
}

@Suite struct AuditLaneITests {
    @Test func gateReleasedBeforeHoldDoesNotBlock() async {
        let gate = AuditLaneIGate()
        await gate.release()
        await gate.hold()
        await gate.waitForStart()
    }
}
