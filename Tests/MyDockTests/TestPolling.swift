import Testing

/// How long a test keeps polling before it gives up. Most suites run on the main actor and share it with hundreds of
/// other tests, so on a loaded CI runner a waiting test, and the work it waits for, may get the actor only every few
/// seconds. A wall-clock deadline alone can then expire before that work has had its turn, so the budget is spent only
/// after both `minimumPolls` polls and `timeout`. A test that really hangs still fails, only later.
struct PollBudget {
    private let minimumPolls: Int
    private let deadline: ContinuousClock.Instant
    private var polls = 0

    init(minimumPolls: Int = 500, timeout: Duration = .seconds(30)) {
        self.minimumPolls = minimumPolls
        deadline = ContinuousClock.now.advanced(by: timeout)
    }

    /// Sleeps 10 ms and returns true, or returns false once the budget is spent. A loop whose condition needs `await`
    /// uses it directly: `while await gate.count == 0, try await budget.wait() {}`.
    mutating func wait() async throws -> Bool {
        guard polls < minimumPolls || ContinuousClock.now < deadline else { return false }
        try await Task.sleep(for: .milliseconds(10))
        polls += 1
        return true
    }
}

/// Waits until `condition` holds, within a `PollBudget`.
func pollUntil(minimumPolls: Int = 500, timeout: Duration = .seconds(30),
               isolation: isolated (any Actor)? = #isolation,
               _ condition: () -> Bool) async throws {
    var budget = PollBudget(minimumPolls: minimumPolls, timeout: timeout)
    while !condition(), try await budget.wait() {}
    try #require(condition())
}
