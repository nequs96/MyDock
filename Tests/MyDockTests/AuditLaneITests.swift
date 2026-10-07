import Foundation
import Testing
@testable import MyDock

/// Holds an injected loader until the test releases it, so a test can order concurrent work
/// without sleeping. Every holder is released together and a hold after `release` returns at once,
/// so a regression that calls the loader twice fails its assertions instead of hanging the run.
actor AuditLaneIGate {
    private var started = false
    private var released = false
    private var holders: [CheckedContinuation<Void, Never>] = []

    /// True once `hold` has been entered; false after `timeout` if the loader never ran.
    func waitForStart(timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !started {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    func hold() async {
        started = true
        if released { return }
        await withCheckedContinuation { holders.append($0) }
    }

    func release() {
        released = true
        let waiting = holders
        holders = []
        for holder in waiting { holder.resume() }
    }
}

@Suite struct AuditLaneITests {
    @Test func gateReleasedBeforeHoldDoesNotBlock() async {
        let gate = AuditLaneIGate()
        await gate.release()
        await gate.hold()
        let started = await gate.waitForStart()
        #expect(started)
    }

    @Test func gateReleasesEveryHolder() async {
        let gate = AuditLaneIGate()
        let first = Task { await gate.hold() }
        let second = Task { await gate.hold() }
        let started = await gate.waitForStart()
        #expect(started)
        await gate.release()
        await first.value
        await second.value
    }

    @Test func gateReportsALoaderThatNeverStarts() async {
        let started = await AuditLaneIGate().waitForStart(timeout: .milliseconds(20))
        #expect(!started)
    }
}

#if DEBUG
extension AuditLaneITests {
    @MainActor
    @Test func renderModeIsUniqueAndTwoFlagsAreRefused() throws {
        typealias Mode = PremiumVisualQA.RenderMode
        #expect(Set(Mode.allCases.map(\.rawValue)).count == Mode.allCases.count)
        #expect(try Mode.selected(in: [:]) == nil)
        #expect(try Mode.selected(in: ["MYDOCK_GLASS_QA": "0"]) == nil)
        #expect(try Mode.selected(in: ["MYDOCK_GLASS_QA": "1", "MYDOCK_RENDER_QA": "/tmp"]) == .glass)
        #expect(throws: (any Error).self) {
            try Mode.selected(in: ["MYDOCK_GLASS_QA": "1", "MYDOCK_FOCUSED_QA": "1"])
        }
    }

    @MainActor
    @Test func widgetQAMatrixNarrowsByStateRatherThanItsDescription() {
        var matrix = WidgetQAMatrix()
        for definition in WidgetRegistry.all {
            for state in WidgetQAMatrix.required(for: definition) where state.isLayout {
                matrix.record(definition.name, state)
            }
        }
        #expect(matrix.missing(states: { $0.isLayout }).isEmpty)
        let setupFamilies = WidgetRegistry.all.filter { $0.capabilities.hasSetupState }
        #expect(matrix.missing().count == setupFamilies.count)
        #expect(!WidgetQAState.setup.isLayout)
    }

    @MainActor
    @Test func renderFixtureAppsAreFixedSystemApps() {
        let apps = PremiumVisualQA.fixtureAppScan.applications
        #expect(!apps.isEmpty)
        #expect(Set(apps.map(\.id)).count == apps.count)
        #expect(apps.allSatisfy { $0.url.path.hasPrefix("/System/") })
    }
}
#endif
