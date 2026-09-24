import Foundation

/// Shares one run-loop timer across transient widget and system refreshes.
/// Consumers keep no timer of their own and are removed when their task ends.
@MainActor
final class RefreshScheduler {
    static let shared = RefreshScheduler()

    private struct Subscription {
        var interval: TimeInterval
        var nextFire: Date
        var continuation: AsyncStream<Date>.Continuation
    }

    private var subscriptions: [UUID: Subscription] = [:]
    private var timer: Timer?
    private var dockIsVisible = true

    private init() {}

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

    private func remove(_ identifier: UUID) {
        subscriptions.removeValue(forKey: identifier)
        scheduleNextTick()
    }

    private func scheduleNextTick() {
        timer?.invalidate()
        timer = nil
        guard dockIsVisible, !subscriptions.isEmpty else { return }
        let now = Date()
        let delay = subscriptions.values.map { $0.nextFire.timeIntervalSince(now) }.min() ?? 1
        let nextTimer = Timer(timeInterval: max(0.01, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireDueSubscriptions() }
        }
        timer = nextTimer
        RunLoop.main.add(nextTimer, forMode: .common)
    }

    private func fireDueSubscriptions() {
        guard dockIsVisible else { return }
        let now = Date()
        for identifier in Array(subscriptions.keys) {
            guard var subscription = subscriptions[identifier], subscription.nextFire <= now else { continue }
            subscription.continuation.yield(now)
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
}
