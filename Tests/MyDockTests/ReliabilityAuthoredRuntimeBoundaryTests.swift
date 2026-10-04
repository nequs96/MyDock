import Combine
import Foundation
import Testing
@testable import MyDock

/// PR-13 phase 2: edit sessions merge authored fields only, and provider refreshes are not edit or history events.
@MainActor
struct ReliabilityAuthoredRuntimeBoundaryTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-Boundary-\(UUID().uuidString)")
    }

    private func quote(close: Double, at seconds: TimeInterval, symbol: String = "AAPL") -> StockMarketSnapshot {
        let date = Date(timeIntervalSince1970: seconds)
        return StockMarketSnapshot(symbol: symbol, points: [.init(date: date, close: close, volume: 1)], currency: "USD", fetchedAt: date)
    }

    private func makeStore(_ dir: URL) throws -> (ProfileStore, UUID, DockItem) {
        let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("Stock")
        item.widgetConfiguration?.stockSymbol = "AAPL"
        let id = try store.createProfile(.init(name: "P", kind: .custom, items: [item]))
        return (store, id, item)
    }

    @Test func refreshWhileDraftOpenIsNotDirtyNotConflictAndSurvivesSave() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, id, item) = try makeStore(dir)
        let original = try #require(store.state.profiles.first)
        store.editSessions.load(original)
        var draft = try #require(store.editSessions.drafts[id])
        draft.update { $0.name = "Renamed" }
        store.editSessions.set(draft, for: id)
        #expect(store.editSessions.hasUnsavedChanges)

        // A refresh lands while the draft is open: it does not alter the draft or the authored profile.
        let fresh = quote(close: 9, at: 5_000)
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in .stock(fresh) }
        await coordinator.refresh(item: item, profileID: id)
        #expect(store.state.profiles.first == original)
        #expect(store.editSessions.drafts[id]?.profile == draft.profile)

        let historyCount = store.history.entries.count
        let saved = try #require(try store.editSessions.save(id))
        #expect(saved.name == "Renamed")
        #expect(!store.editSessions.hasUnsavedChanges)
        #expect(store.history.entries.count == historyCount + 1) // the authored rename only
        #expect(store.state.profiles[0].items[0].widgetConfiguration?.stockSnapshot == nil)
        #expect(store.presentationItem(store.state.profiles[0].items[0]).widgetConfiguration?.stockSnapshot == fresh)
        #expect(store.runtimeCache.readings(for: item.id)?.stock?.value == fresh)
    }

    @Test func cleanDraftStaysCleanAfterRefreshAndStaleDraftReadingsAreNeverWritten() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, id, item) = try makeStore(dir)
        // A draft built from the display projection holds an old reading; strip-on-update keeps it authored-only.
        let stale = quote(close: 1, at: 1_000)
        store.publishRuntimeReadings(itemID: item.id, in: id) { $0.stockSnapshot = stale }
        var draft = DockProfileDraft(profile: store.presentationProfile(store.state.profiles[0]))
        #expect(!draft.isDirty)
        #expect(draft.profile.items[0].widgetConfiguration?.stockSnapshot == nil)
        store.publishRuntimeReadings(itemID: item.id, in: id) { $0.stockSnapshot = quote(close: 2, at: 2_000) }
        #expect(!draft.isDirty)
        draft.update { $0.name = "Edited" }
        store.replaceProfile(try draft.merged(with: store.state.profiles[0]))
        #expect(store.presentationItem(item).widgetConfiguration?.stockSnapshot?.points.first?.close == 2)
    }

    @Test func publishRuntimeReadingsIsCacheOnlyAndRecordsNoHistoryOrCommit() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, id, item) = try makeStore(dir)
        store.flush()
        let authored = store.state
        let historyCount = store.history.entries.count
        var authoredPublications = 0
        let observation = store.$state.dropFirst().sink { _ in authoredPublications += 1 }
        // An authored change smuggled into a provider update is ignored.
        let result = store.publishRuntimeReadings(itemID: item.id, in: id) {
            $0.stockSnapshot = quote(close: 3, at: 3_000); $0.noteText = "smuggled"
        }
        #expect(result == .accepted)
        #expect(store.state == authored)
        #expect(authoredPublications == 0)
        #expect(!store.hasUnpersistedChanges)
        #expect(!store.editSessions.hasUnsavedChanges)
        #expect(store.history.entries.count == historyCount)
        #expect(store.presentationItem(item).widgetConfiguration?.noteText != "smuggled")
        #expect(store.presentationItem(item).widgetConfiguration?.stockSnapshot != nil)
        #expect(store.publishRuntimeReadings(itemID: UUID(), in: id) { _ in } == .missingTarget)
        withExtendedLifetime(observation) {}
    }

    @Test func switchingSymbolAndDeletingWidgetNeverShowsAnotherIdentityReading() throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let (store, id, item) = try makeStore(dir)
        store.publishRuntimeReadings(itemID: item.id, in: id) { $0.stockSnapshot = quote(close: 3, at: 3_000) }
        store.updateWidgetConfiguration(itemID: item.id, in: id) { $0.stockSymbol = "MSFT" }
        #expect(store.presentationItem(store.state.profiles[0].items[0]).widgetConfiguration?.stockSnapshot == nil)
        store.removeItem(item.id, from: id)
        #expect(store.runtimeCache.readings(for: item.id) == nil)
    }
}
