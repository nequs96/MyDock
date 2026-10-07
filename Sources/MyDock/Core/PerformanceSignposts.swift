import Foundation
import os

/// PR-18 baseline instrumentation. Signposts cost nearly nothing unless Instruments
/// (os_signpost / Points of Interest) is recording. Messages carry only kinds, counts
/// and durations, never titles, paths, bundle IDs or other user content.
enum PerformanceSignposts {
    static let signposter = OSSignposter(subsystem: Product.bundleIdentifier, category: "performance")

    static func begin(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name, id: signposter.makeSignpostID())
    }
    static func end(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }
    static func event(_ name: StaticString) { signposter.emitEvent(name) }

    /// Runs `body` inside a named interval.
    static func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = begin(name)
        defer { end(name, state) }
        return try body()
    }

#if DEBUG
    /// Counts `hosting.rootView` assignments so tests can back MD-E02 (narrow root invalidation).
    @MainActor private(set) static var rootAssignmentCount = 0
    @MainActor static func noteRootAssignment() { rootAssignmentCount += 1 }
    @MainActor static func resetRootAssignmentCount() { rootAssignmentCount = 0 }
#endif
}
