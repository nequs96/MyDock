import AppKit
import Combine

/// Owns reveal sampling, pointer/menu observation and cancellable edge dwell.
/// The panel controller retains geometry, motion and consumer visibility ownership.
@MainActor
final class DockRevealMonitor {
    enum Decision: Equatable { case show, hide, suppress, dwell }
    struct Snapshot {
        var canPresent: Bool
        var retainsInteraction: Bool
        var overviewPresent: Bool
        var systemDockOverlaps: Bool
        var desktopMode: Bool
        var autoHide: Bool
        var visible: Bool
        var mouseLocation: NSPoint
        var expandedFrame: NSRect
        var revealFrame: NSRect
        var popoutFrames: [NSRect]

        var decision: Decision? {
            guard canPresent else { return nil }
            if retainsInteraction { return .show }
            if overviewPresent || systemDockOverlaps { return .suppress }
            if desktopMode || !autoHide { return .show }
            if visible && CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: mouseLocation,
                expandedFrame: expandedFrame, popoutFrames: popoutFrames) { return .show }
            return CustomDockVisibilityPolicy.isAtRevealEdge(mouseLocation: mouseLocation,
                revealFrame: revealFrame) ? .dwell : .hide
        }
    }

    private let snapshot: (_ forDwell: Bool) -> Snapshot?
    private let present: (Decision) -> Void
    private let waitForDwell: @MainActor () async throws -> Void
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var samplingTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    private var menuObservations: [AnyCancellable] = []
    private(set) var menuTrackingDepth = 0

    init(snapshot: @escaping (_ forDwell: Bool) -> Snapshot?, present: @escaping (Decision) -> Void,
         waitForDwell: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: .milliseconds(350))
         }) {
        self.snapshot = snapshot
        self.present = present
        self.waitForDwell = waitForDwell
        menuObservations = [
            NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingDepth += 1 }
            },
            NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.menuTrackingDepth = max(0, (self?.menuTrackingDepth ?? 0) - 1) }
            }
        ]
    }

    func startSampling() {
        guard samplingTask == nil else { return }
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self else { return }
                sample()
            }
        }
    }

    func startPointerMonitoring() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged]
        if globalMouseMonitor == nil {
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sample() }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                Task { @MainActor [weak self] in self?.sample() }
                return event
            }
        }
    }

    func stopPointerMonitoring() {
        cancelDwell()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        stopPointerMonitoring()
    }

    func sample() {
        guard let state = snapshot(false), let decision = state.decision else {
            cancelDwell()
            return
        }
        if decision == .dwell {
            scheduleDwell()
            present(.hide)
        } else {
            cancelDwell()
            present(decision)
        }
    }

    private func cancelDwell() {
        dwellTask?.cancel()
        dwellTask = nil
    }

    private func scheduleDwell() {
        guard dwellTask == nil else { return }
        let waitForDwell = self.waitForDwell
        dwellTask = Task { @MainActor [weak self] in
            do {
                try await waitForDwell()
                try Task.checkCancellation()
            } catch { return }
            guard let self else { return }
            dwellTask = nil
            guard let state = snapshot(true), state.canPresent else { return }
            // Fresh completion snapshots use the same retention/suppression precedence as samples.
            if state.retainsInteraction { present(.show); return }
            if state.decision == .suppress { present(.suppress); return }
            if CustomDockVisibilityPolicy.shouldReveal(mouseLocation: state.mouseLocation,
                expandedFrame: state.expandedFrame, revealFrame: state.revealFrame,
                popoutFrames: state.popoutFrames) { present(.show) }
        }
    }
}
