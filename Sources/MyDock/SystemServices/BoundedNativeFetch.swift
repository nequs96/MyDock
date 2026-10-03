import Foundation

enum BoundedFetchOutcome<Value: Sendable>: Sendable {
    case value(Value)
    case cancelled
    case timedOut
}

extension BoundedFetchOutcome: Equatable where Value: Equatable {}

/// Resolves exactly once, whichever of completion, cancellation or deadline happens first.
/// The cancel closure of the native request runs for cancellation and timeout, never for completion.
private final class BoundedFetchGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private var continuation: CheckedContinuation<BoundedFetchOutcome<Value>, Never>?
    private var earlyOutcome: BoundedFetchOutcome<Value>?
    private var cancelNative: (@Sendable () -> Void)?
    private var completedWithValue = false

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return finished
    }

    func install(_ continuation: CheckedContinuation<BoundedFetchOutcome<Value>, Never>) {
        lock.lock()
        if let earlyOutcome {
            lock.unlock()
            continuation.resume(returning: earlyOutcome)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func setCancel(_ cancel: @escaping @Sendable () -> Void) {
        lock.lock()
        if finished {
            let shouldCancel = !completedWithValue
            lock.unlock()
            if shouldCancel { cancel() }
            return
        }
        cancelNative = cancel
        lock.unlock()
    }

    func finish(_ outcome: BoundedFetchOutcome<Value>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        if case .value = outcome { completedWithValue = true }
        let continuation = continuation
        self.continuation = nil
        let cancel = cancelNative
        cancelNative = nil
        if continuation == nil { earlyOutcome = outcome }
        lock.unlock()
        if case .value = outcome {} else { cancel?() }
        continuation?.resume(returning: outcome)
    }
}

enum BoundedNativeFetch {
    /// Runs a callback-based native request under a deadline and task cancellation.
    /// `start` receives the completion handler (extra calls are ignored) and returns a closure that cancels the request.
    static func run<Value: Sendable>(
        timeout: TimeInterval,
        isolation: isolated (any Actor)? = #isolation,
        start: (@escaping @Sendable (Value) -> Void) -> @Sendable () -> Void
    ) async -> BoundedFetchOutcome<Value> {
        let gate = BoundedFetchGate<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<BoundedFetchOutcome<Value>, Never>) in
                gate.install(continuation)
                guard !gate.isFinished else { return }
                let cancel = start { value in gate.finish(.value(value)) }
                gate.setCancel(cancel)
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) {
                    gate.finish(.timedOut)
                }
            }
        } onCancel: {
            gate.finish(.cancelled)
        }
    }
}
