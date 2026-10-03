import Foundation
import Testing
@testable import MyDock

struct N3MotionAutomationTests {
    typealias Snap = DockTransitionPolicy.Snapshot

    @Test func noTransitionMeansNoAction() {
        #expect(DockTransitionPolicy.action(inFlight: nil, requested: Snap(visible: true, style: .grow, reduceMotion: false)) == .none)
    }

    @Test func unchangedSettingsLeaveTransitionAlone() {
        let s = Snap(visible: false, style: .slide, reduceMotion: false)
        #expect(DockTransitionPolicy.action(inFlight: s, requested: s) == .none)
    }

    @Test func styleOrOffChangeMidTransitionNormalizes() {
        let running = Snap(visible: false, style: .grow, reduceMotion: false)
        #expect(DockTransitionPolicy.action(inFlight: running, requested: Snap(visible: false, style: .fade, reduceMotion: false)) == .normalizeImmediately)
        #expect(DockTransitionPolicy.action(inFlight: running, requested: Snap(visible: false, style: .grow, reduceMotion: true)) == .normalizeImmediately)
    }

    @Test func visibilityChangeStartsNewTransition() {
        let running = Snap(visible: true, style: .grow, reduceMotion: false)
        #expect(DockTransitionPolicy.action(inFlight: running, requested: Snap(visible: false, style: .grow, reduceMotion: false)) == .startTransition)
    }

    @Test func finalStateIsFullyNormalized() {
        #expect(DockTransitionPolicy.finalState(Snap(visible: true, style: .grow, reduceMotion: true)) == .init(alpha: 1, scale: 1, usesHiddenOffset: false))
        #expect(DockTransitionPolicy.finalState(Snap(visible: false, style: .slide, reduceMotion: true)) == .init(alpha: 0, scale: 1, usesHiddenOffset: false))
        #expect(DockTransitionPolicy.finalState(Snap(visible: false, style: .grow, reduceMotion: false)) == .init(alpha: 0, scale: 0.94, usesHiddenOffset: true))
    }

    @Test func automationDeniedIsClassifiedFromStderr() {
        let denied = Data("execution error: Not authorized to send Apple events to Finder. (-1743)".utf8)
        #expect(AutomationError.classify(exitStatus: 1, standardError: denied) == .permissionDenied)
        #expect(AutomationError.classify(exitStatus: 1, standardError: Data("x (-1743)".utf8)) == .permissionDenied)
        #expect(AutomationError.classify(exitStatus: 1, standardError: Data("Application isn't running. (-600)".utf8)) == .failed(exitStatus: 1))
        #expect(AutomationError.classify(exitStatus: 2, standardError: Data()) == .failed(exitStatus: 2))
    }

    @Test func messagesDistinguishDeniedFromOtherFailures() {
        let denied = TrashCopy.emptyFailureMessage(for: AutomationError.permissionDenied)
        let other = TrashCopy.emptyFailureMessage(for: AutomationError.failed(exitStatus: 1))
        #expect(denied.contains("Automation") && denied != other)
        #expect(!other.contains("Automation"))
        #expect(NowPlayingCopy.automationMessage(for: AutomationError.permissionDenied, sourceTitle: "Music").contains("Automation"))
        #expect(!NowPlayingCopy.automationMessage(for: AutomationError.failed(exitStatus: 1), sourceTitle: "Music").contains("Privacy"))
    }

#if DEBUG
    @MainActor @Test func rootAssignmentCounterIsReadable() {
        PerformanceSignposts.resetRootAssignmentCount()
        #expect(PerformanceSignposts.rootAssignmentCount == 0)
        PerformanceSignposts.noteRootAssignment()
        #expect(PerformanceSignposts.rootAssignmentCount == 1)
        PerformanceSignposts.resetRootAssignmentCount()
    }
#endif
}
