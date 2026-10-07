import AppKit
import Combine
import Foundation

/// Timers finish even when their profile is hidden or their popout is closed.
@MainActor
final class WidgetLifecycleCoordinator {
    private weak var store: ProfileStore?
    private var observation: AnyCancellable?
    private var clockObservations: [AnyCancellable] = []
    private let now: () -> Date
    private var jobs: [UUID: Task<Void, Never>] = [:]
    private struct TimerSignature: Equatable {
        var start: Date
        var deadline: Date
        var isFocus: Bool
    }
    private var signatures: [UUID: TimerSignature] = [:]

    init(store: ProfileStore, now: @escaping () -> Date = { .now }) {
        self.store = store
        self.now = now
        observation = store.$state.receive(on: RunLoop.main).sink { [weak self] _ in self?.reconcile() }
        clockObservations = [
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ].map { publisher in
            publisher.receive(on: RunLoop.main).sink { [weak self] _ in self?.rescheduleTimers() }
        }
    }

    /// A sleeping task uses elapsed time; persisted timers use wall-clock deadlines.
    /// Reconcile both after wake or a clock adjustment, including hidden profiles.
    func rescheduleTimers() {
        jobs.values.forEach { $0.cancel() }
        jobs.removeAll()
        signatures.removeAll()
        reconcile()
    }

    private func reconcile() {
        guard let store else { return }
        var active = Set<UUID>()
        for profile in store.state.profiles {
            for item in profile.items {
                guard let c = item.widgetConfiguration else { continue }
                let start = item.widgetKind == "Focus Timer" ? c.focusStartedAt : item.widgetKind == "Countdown" && c.countdownMode == .duration ? c.countdownStartedAt : nil
                guard let start else { continue }
                let isFocus = item.widgetKind == "Focus Timer"
                let duration = isFocus ? Double(c.focusDurationSeconds) - c.focusElapsedBeforeStart : Double(c.countdownDurationSeconds) - c.countdownElapsedBeforeStart
                let signature = TimerSignature(start: start, deadline: start.addingTimeInterval(max(0, duration)), isFocus: isFocus)
                active.insert(item.id)
                guard signatures[item.id] != signature else { continue }
                jobs[item.id]?.cancel(); signatures[item.id] = signature
                let initialRemaining = signature.deadline.timeIntervalSince(now())
                jobs[item.id] = Task { [weak self] in
                    // The sleep measures elapsed time while the deadline is wall-clock: if the wall clock still
                    // lags at wake-up (for example an NTP slew, which posts no clock-change notification), sleep again.
                    // Each sleep runs a few milliseconds past the deadline so the checks below agree despite rounding.
                    var remaining = initialRemaining
                    while remaining > 0 {
                        do { try await Task.sleep(for: .seconds(remaining + 0.01)) } catch { return }
                        guard let self else { return }
                        remaining = signature.deadline.timeIntervalSince(self.now())
                    }
                    guard let self, !Task.isCancelled, signatures[item.id] == signature else { return }
                    self.store?.updateWidgetConfiguration(itemID: item.id, in: profile.id) { c in
                        if item.widgetKind == "Focus Timer", c.focusStartedAt == start, c.focusRemaining(at: self.now()) <= 0 {
                            c.focusElapsedBeforeStart = Double(c.focusDurationSeconds); c.focusStartedAt = nil
                        } else if c.countdownStartedAt == start, c.countdownRemaining(at: self.now()) <= 0 {
                            c.countdownElapsedBeforeStart = Double(c.countdownDurationSeconds); c.countdownStartedAt = nil
                        }
                    }
                }
            }
        }
        for id in Array(jobs.keys) where !active.contains(id) { jobs.removeValue(forKey: id)?.cancel(); signatures[id] = nil }
    }

    deinit { jobs.values.forEach { $0.cancel() } }
}
