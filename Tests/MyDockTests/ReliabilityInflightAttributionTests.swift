import Foundation
import Testing
@testable import MyDock

private actor AttributionGate {
    struct StartTimeout: Error {}
    private var started = false
    private var onRelease: CheckedContinuation<Void, Never>?
    /// Polls within a `PollBudget`, so a loader that is never called fails the test instead of hanging the run.
    func waitForStart() async throws {
        var budget = PollBudget()
        while !started {
            guard try await budget.wait() else { throw StartTimeout() }
        }
    }
    func hold() async {
        started = true
        await withCheckedContinuation { onRelease = $0 }
    }
    func release() { onRelease?.resume(); onRelease = nil }
}

@MainActor
struct ReliabilityInflightAttributionTests {
    @Test func responseFromOldRootCannotBeRelabeledOrCachedForNewRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Attribution-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("AI Limits")
        item.widgetConfiguration?.aiLimitsVisibleProviders = [.claude]
        let id = try store.createProfile(.init(name: "Fixture", kind: .custom, items: [item]))
        var environment = ["CLAUDE_CONFIG_DIR": root.appendingPathComponent("A").path]
        let now = Date(timeIntervalSince1970: 1_791_115_200)
        let gate = AttributionGate()
        let coordinator = WidgetDataCoordinator(store: store, loader: { query, _ in
            await gate.hold()
            return .limits(.init(fetchedAt: now, readings: [], sourceScope: query.aiSourceScope))
        }, queryMaker: { kind, configuration in
            WidgetDataQuery.make(kind: kind, configuration: configuration, now: now, homeDirectory: root, environment: environment)
        })
        let refresh = Task { await coordinator.refresh(item: item, profileID: id) }
        try await gate.waitForStart()
        environment["CLAUDE_CONFIG_DIR"] = root.appendingPathComponent("B").path
        await gate.release(); await refresh.value
        #expect(store.runtimeCache.readings(for: item.id)?.aiLimits == nil)
        #expect(coordinator.refreshing.isEmpty)
    }

    @Test func connectionInvalidationRejectsAnUncooperativeOldResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Authority-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let item = DockItem.widget("AI Limits")
        let id = try store.createProfile(.init(name: "Fixture", kind: .custom, items: [item]))
        let gate = AttributionGate()
        let coordinator = WidgetDataCoordinator(store: store) { query, _ in
            await gate.hold()
            return .limits(.init(fetchedAt: .now, readings: [], sourceScope: query.aiSourceScope))
        }
        let refresh = Task { await coordinator.refresh(item: item, profileID: id) }
        try await gate.waitForStart(); coordinator.connectionsDidChange()
        await gate.release(); await refresh.value
        #expect(store.runtimeCache.readings(for: item.id)?.aiLimits == nil)
    }
    @Test func oldMonthResponseIsNotAttributedToTheNewMonth() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Period-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("AI Limits")
        item.widgetConfiguration?.aiLimitsVisibleProviders = [.copilot]
        let id = try store.createProfile(.init(name: "Fixture", kind: .custom, items: [item]))
        let formatter = ISO8601DateFormatter()
        var now = try #require(formatter.date(from: "2026-10-31T23:59:59Z"))
        let gate = AttributionGate()
        let coordinator = WidgetDataCoordinator(store: store, loader: { query, _ in
            await gate.hold()
            return .limits(.init(fetchedAt: Date(timeIntervalSince1970: 1_791_115_200), readings: [], sourceScope: query.aiSourceScope))
        }, queryMaker: { kind, configuration in
            WidgetDataQuery.make(kind: kind, configuration: configuration, now: now)
        })
        let refresh = Task { await coordinator.refresh(item: item, profileID: id) }
        try await gate.waitForStart(); now = now.addingTimeInterval(2)
        await gate.release(); await refresh.value
        #expect(store.runtimeCache.readings(for: item.id)?.aiLimits == nil)
    }

}
