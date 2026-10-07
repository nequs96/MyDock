import Testing

/// Waits until `condition` holds, polling every 10 ms. Most suites run on the main actor and share it with hundreds of
/// other tests, so on a loaded CI runner a waiting test, and the work it waits for, may get the actor only every few
/// seconds. A wall-clock deadline alone can then expire before that work has had its turn, so giving up takes both
/// `minimumPolls` polls and `timeout`. A test that really hangs still fails, only later.
func pollUntil(minimumPolls: Int = 500, timeout: Duration = .seconds(30),
               isolation: isolated (any Actor)? = #isolation,
               _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var polls = 0
    while !condition(), polls < minimumPolls || ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
        polls += 1
    }
    try #require(condition())
}
