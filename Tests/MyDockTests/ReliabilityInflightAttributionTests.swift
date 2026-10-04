import Foundation
import Testing
@testable import MyDock

private actor AttributionGate {
    private var started = false
    private var onStart: CheckedContinuation<Void, Never>?
    private var onRelease: CheckedContinuation<Void, Never>?
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { onStart = $0 }
    }
    func hold() async {
        started = true; onStart?.resume(); onStart = nil
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
        let coordinator = WidgetDataCoordinator(store: store, queryMaker: { kind, configuration in
            WidgetDataQuery.make(kind: kind, configuration: configuration, now: now, homeDirectory: root, environment: environment)
        }) { query, _ in
            await gate.hold()
            return .limits(.init(fetchedAt: now, readings: [], sourceScope: query.aiSourceScope))
        }
        let refresh = Task { await coordinator.refresh(item: item, profileID: id) }
        await gate.waitForStart()
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
        await gate.waitForStart(); coordinator.connectionsDidChange()
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
        let coordinator = WidgetDataCoordinator(store: store, queryMaker: { kind, configuration in
            WidgetDataQuery.make(kind: kind, configuration: configuration, now: now)
        }) { query, _ in
            await gate.hold()
            return .limits(.init(fetchedAt: Date(timeIntervalSince1970: 1_791_115_200), readings: [], sourceScope: query.aiSourceScope))
        }
        let refresh = Task { await coordinator.refresh(item: item, profileID: id) }
        await gate.waitForStart(); now = now.addingTimeInterval(2)
        await gate.release(); await refresh.value
        #expect(store.runtimeCache.readings(for: item.id)?.aiLimits == nil)
    }

}
