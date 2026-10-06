import Foundation
import Testing
@testable import MyDock

/// Regressions for defects found by the full audit (docs/history/FULL_AUDIT_2026-10-05.md).
@Suite struct AuditRegressionTests {
    private func runtimeApp() -> DockItem {
        var item = DockItem.application(at: URL(fileURLWithPath: "/Applications/Example.app"))
        item.id = RuntimeDockIdentity.uuid("running:app.example")
        return item
    }

    @Test func pinnedRuntimeTilesNeverKeepTheRuntimeIdentity() {
        let running = runtimeApp()
        let pinned = running.withFreshIdentity()
        #expect(pinned.id != running.id)
        #expect(pinned.url == running.url && pinned.type == running.type && pinned.title == running.title)
    }

    @MainActor
    @Test func insertReportsTheIdentityItSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Pins")
        let item = runtimeApp().withFreshIdentity()
        #expect(store.insert(item, before: nil, in: profileID) == item.id)
        // The same identity again is refused rather than saved twice.
        #expect(store.insert(item, before: nil, in: profileID) == nil)
        #expect(store.state.profiles.first { $0.id == profileID }?.items.filter { $0.id == item.id }.count == 1)
    }

    @MainActor
    @Test func dockLayoutToleratesDuplicateItemIdentities() {
        let item = runtimeApp()
        var model = DockRenderModel(profile: DockProfile(name: "Duplicates", kind: .custom, items: []), settings: AppSettings(),
                                    runningApplications: [], windows: [], runningMediaSources: [])
        model.entries = [.item(item, pinned: true), .item(item, pinned: false)]
        #expect(model.positionedEntries(settings: AppSettings(), scale: 1).count == 2)
    }
}
