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
    /// True for the Dock's own windows (the panel, its popouts, the reveal handle).
    private let ownsMenuWindow: @MainActor (NSWindow) -> Bool
    private let waitForDwell: @MainActor () async throws -> Void
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var samplingTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    private var menuObservations: [AnyCancellable] = []
    private var presenceObservation: AnyCancellable?
    /// Menus opened from the Dock that are tracking now; any other menu in MyDock is not counted.
    private var trackedMenus = Set<ObjectIdentifier>()
    var menuTrackingDepth: Int { trackedMenus.count }
    /// Sampling was requested; it runs only while the session is present.
    private var wantsSampling = false
    private var systemIsAway = false
    /// One queued pointer sample stands for every pointer event that arrives before it runs.
    private var samplePending = false
    var isSampling: Bool { samplingTask != nil }

    init(snapshot: @escaping (_ forDwell: Bool) -> Snapshot?, present: @escaping (Decision) -> Void,
         ownsMenuWindow: @escaping @MainActor (NSWindow) -> Bool = { _ in true },
         waitForDwell: @escaping @MainActor () async throws -> Void = {
             try await Task.sleep(for: .milliseconds(350))
         }) {
        self.snapshot = snapshot
        self.present = present
        self.ownsMenuWindow = ownsMenuWindow
        self.waitForDwell = waitForDwell
        // Menus post these on the main thread.
        menuObservations = [
            NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification).sink { [weak self] notification in
                guard let menu = (notification.object as? NSMenu).map({ ObjectIdentifier($0) }) else { return }
                MainActor.assumeIsolated {
                    self?.menuBeganTracking(menu, eventWindow: NSApplication.shared.currentEvent?.window)
                }
            },
            NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification).sink { [weak self] notification in
                guard let menu = (notification.object as? NSMenu).map({ ObjectIdentifier($0) }) else { return }
                MainActor.assumeIsolated { self?.menuEndedTracking(menu) }
            }
        ]
        presenceObservation = SystemPresenceMonitor.shared.$isAway.removeDuplicates().sink { [weak self] away in
            MainActor.assumeIsolated { self?.setSystemAway(away) }
        }
    }

    /// A tile or popout menu keeps the Dock shown. Settings pop-ups and the status menu do not reveal an
    /// auto-hidden Dock. A menu opened without an event window (an accessibility action) is counted.
    func menuBeganTracking(_ menu: ObjectIdentifier, eventWindow: NSWindow?) {
        if let eventWindow, !ownsMenuWindow(eventWindow) { return }
        trackedMenus.insert(menu)
    }

    func menuEndedTracking(_ menu: ObjectIdentifier) {
        trackedMenus.remove(menu)
    }

    func startSampling() {
        wantsSampling = true
        startSamplingTaskIfPresent()
    }

    /// Display sleep or a switched-out session pauses edge sampling; it resumes on wake.
    func setSystemAway(_ away: Bool) {
        guard systemIsAway != away else { return }
        systemIsAway = away
        if away {
            samplingTask?.cancel()
            samplingTask = nil
            cancelDwell()
        } else {
            startSamplingTaskIfPresent()
        }
    }

    private func startSamplingTaskIfPresent() {
        guard wantsSampling, !systemIsAway, samplingTask == nil else { return }
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
            // AppKit delivers monitored events on the main thread.
            globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                MainActor.assumeIsolated { self?.requestSample() }
            }
        }
        if localMouseMonitor == nil {
            localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                MainActor.assumeIsolated { self?.requestSample() }
                return event
            }
        }
    }

    /// Coalesces bursts of pointer events into one sample on the next main-actor turn.
    func requestSample() {
        guard !samplePending else { return }
        samplePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            samplePending = false
            sample()
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
        wantsSampling = false
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
