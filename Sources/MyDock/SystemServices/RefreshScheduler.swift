import Combine
import Foundation

/// Shares one run-loop timer across transient widget and system refreshes.
/// Consumers keep no timer of their own and are removed when their task ends.
/// Timers carry a tolerance and nearly due subscriptions fire together, so the OS can coalesce
/// wake-ups; nothing fires while the displays sleep or the session is switched out.
@MainActor
final class RefreshScheduler {
    static let shared: RefreshScheduler = {
        let scheduler = RefreshScheduler()
        scheduler.presenceObservation = SystemPresenceMonitor.shared.$isAway.removeDuplicates().sink { [weak scheduler] away in
            MainActor.assumeIsolated { scheduler?.setSystemAway(away) }
        }
        return scheduler
    }()

    private struct Subscription {
        var interval: TimeInterval
        var nextFire: Date
        var continuation: AsyncStream<Date>.Continuation
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var timer: Timer?
    private var dockIsVisible = true
    private var systemIsAway = false
    private var presenceObservation: AnyCancellable?
    private var demand = RefreshDemandLedger()
    /// Number of tick yields delivered to subscribers. Used by fixtures to prove zero work when idle.
    private(set) var deliveredTickCount = 0

    private init() {}

    /// Fixture entry point; production code uses `shared`.
    static func makeForTesting(dockVisible: Bool) -> RefreshScheduler {
        let scheduler = RefreshScheduler()
        scheduler.dockIsVisible = dockVisible
        return scheduler
    }

    /// True while the Dock or any other visible consumer (popout, editor) needs refreshes.
    var isActive: Bool { !systemIsAway && RefreshDemandLedger.isActive(dockVisible: dockIsVisible, demand: demand) }
    var subscriptionCount: Int { subscriptions.count }
    var hasArmedTimer: Bool { timer != nil }

    /// Registers a visible non-Dock consumer. Release the token when the consumer disappears.
    func acquireDemand(_ kind: RefreshDemandKind) -> RefreshDemandToken {
        let identifier = demand.acquire(kind)
        scheduleNextTick()
        return RefreshDemandToken(identifier: identifier, kind: kind)
    }

    func release(_ token: RefreshDemandToken?) {
        guard let token, demand.release(token.identifier) else { return }
        scheduleNextTick()
    }

    /// Acquires or releases `token` so that it is held exactly while `active` is true.
    func setDemand(_ token: inout RefreshDemandToken?, kind: RefreshDemandKind, active: Bool) {
        if active, token == nil {
            token = acquireDemand(kind)
        } else if !active, token != nil {
            release(token)
            token = nil
        }
    }

    func ticks(every interval: TimeInterval) -> AsyncStream<Date> {
        let normalizedInterval = RefreshSchedulePolicy.normalizedInterval(interval)
        let identifier = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            subscriptions[identifier] = Subscription(interval: normalizedInterval,
                                                     nextFire: .now.addingTimeInterval(normalizedInterval),
                                                     continuation: continuation)
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.remove(identifier) }
            }
            scheduleNextTick()
        }
    }

    func setDockVisible(_ visible: Bool) {
        guard dockIsVisible != visible else { return }
        dockIsVisible = visible
        scheduleNextTick()
    }

    /// Display sleep or a switched-out session: nobody can see a reading, so no subscription fires.
    func setSystemAway(_ away: Bool) {
        guard systemIsAway != away else { return }
        systemIsAway = away
        scheduleNextTick()
    }

    private func remove(_ identifier: UUID) {
        subscriptions.removeValue(forKey: identifier)
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.invalidate()
        timer = nil
        guard isActive, !subscriptions.isEmpty else { return }
        let now = Date()
        let delay = subscriptions.values.map { $0.nextFire.timeIntervalSince(now) }.min() ?? 1
        let nextTimer = Timer(timeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireDueSubscriptions() }
        }
        nextTimer.tolerance = RefreshSchedulePolicy.timerTolerance(forDelay: delay)
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    private func fireDueSubscriptions() { fireDueSubscriptions(now: Date()) }

    func fireDueSubscriptions(now: Date) {
        guard isActive else { return }
        for identifier in Array(subscriptions.keys) {
            // Subscriptions due within their coalescing window fire with this wake-up instead of arming their own.
            guard var subscription = subscriptions[identifier],
                  subscription.nextFire.timeIntervalSince(now) <= RefreshSchedulePolicy.coalescingWindow(forInterval: subscription.interval)
            else { continue }
            subscription.continuation.yield(now)
            deliveredTickCount += 1
            subscription.nextFire = now.addingTimeInterval(subscription.interval)
            subscriptions[identifier] = subscription
        }
        scheduleNextTick()
    }
}

enum RefreshSchedulePolicy {
    static func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
        guard interval.isFinite else { return 60 }
        return min(max(interval, 1), 24 * 60 * 60)
    }

    /// How early a subscription may fire so it shares a wake-up with another one.
    static func coalescingWindow(forInterval interval: TimeInterval) -> TimeInterval {
        min(1, max(0, interval) * 0.1)
    }

    /// Lets the OS batch the scheduler's timer with other wake-ups.
    static func timerTolerance(forDelay delay: TimeInterval) -> TimeInterval {
        min(1, max(0.1, delay * 0.1))
    }
}

/// Kinds of visible consumer that justify refreshing while the Dock itself is hidden.
enum RefreshDemandKind: Hashable, Sendable {
    case popout
    case editor
}

struct RefreshDemandToken: Equatable, Sendable {
    let identifier: UUID
    let kind: RefreshDemandKind
}

/// Pure bookkeeping of typed visible-consumer demand.
struct RefreshDemandLedger: Equatable {
    private(set) var tokens: [UUID: RefreshDemandKind] = [:]

    var isEmpty: Bool { tokens.isEmpty }
    func count(of kind: RefreshDemandKind) -> Int { tokens.values.filter { $0 == kind }.count }

    mutating func acquire(_ kind: RefreshDemandKind) -> UUID {
        let identifier = UUID()
        tokens[identifier] = kind
        return identifier
    }

    /// Returns false when the token was already released, so double release is harmless.
    @discardableResult
    mutating func release(_ identifier: UUID) -> Bool {
        tokens.removeValue(forKey: identifier) != nil
    }

    static func isActive(dockVisible: Bool, demand: RefreshDemandLedger) -> Bool {
        dockVisible || !demand.isEmpty
    }
}
