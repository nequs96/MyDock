import AppKit
import Combine

/// Whether anyone can see this login session: the displays are awake and the session is not switched out.
/// Periodic work (the shared refresh scheduler, Dock reveal sampling) pauses while the session is away.
@MainActor
final class SystemPresenceMonitor: ObservableObject {
    static let shared = SystemPresenceMonitor()

    @Published private(set) var isAway = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var observations: [AnyCancellable] = []

    private init() {
        let center = NSWorkspace.shared.notificationCenter
        observations = [
            center.publisher(for: NSWorkspace.screensDidSleepNotification).receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.update(screensAsleep: true) } },
            center.publisher(for: NSWorkspace.screensDidWakeNotification).receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.update(screensAsleep: false) } },
            center.publisher(for: NSWorkspace.sessionDidResignActiveNotification).receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.update(sessionInactive: true) } },
            center.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification).receive(on: RunLoop.main)
                .sink { [weak self] _ in MainActor.assumeIsolated { self?.update(sessionInactive: false) } }
        ]
    }

    private func update(screensAsleep: Bool? = nil, sessionInactive: Bool? = nil) {
        if let screensAsleep { self.screensAsleep = screensAsleep }
        if let sessionInactive { self.sessionInactive = sessionInactive }
        let away = self.screensAsleep || self.sessionInactive
        if isAway != away { isAway = away }
    }
}
