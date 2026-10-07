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
