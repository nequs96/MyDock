import Foundation

/// FIFO permits bound provider work; cancelled waiters never consume capacity.
actor WidgetRefreshLimiter {
    private let maximumConcurrent: Int
    private var running = 0
    private var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []

    init(maximumConcurrent: Int) { self.maximumConcurrent = max(1, maximumConcurrent) }

    func acquire() async throws {
        try Task.checkCancellation()
        if running < maximumConcurrent { running += 1; return }
        let id = UUID()
        let acquired = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled { continuation.resume(returning: false) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
        if !acquired { throw CancellationError() }
    }

    func release() {
        if !waiters.isEmpty { waiters.removeFirst().1.resume(returning: true) }
        else { running = max(0, running - 1) }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(returning: false)
    }
}
