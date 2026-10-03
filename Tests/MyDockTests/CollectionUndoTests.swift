import Foundation
import Testing
@testable import MyDock

struct CollectionUndoTests {
    private func entries(_ count: Int) -> [QuickChecklistEntry] { (0..<count).map { QuickChecklistEntry(title: "Task \($0)") } }

    @Test func restoresRemovedEntryAtOriginalPosition() throws {
        var list = entries(4)
        let removed = try #require(RemovedEntries.capture([list[1].id], from: list, message: "Removed"))
        let original = list
        list.remove(at: 1)
        #expect(removed.restore(into: &list, capacity: 100) == 1)
        #expect(list == original)
    }

    @Test func restoresMultipleEntriesInOrderAndClampsIndexes() throws {
        var list = entries(5)
        let original = list
        let removed = try #require(RemovedEntries.capture(Set([list[0].id, list[3].id, list[4].id]), from: list, message: "Cleared"))
        list = [list[1], list[2]]
        // An intervening edit shortens the list further.
        list.removeLast()
        #expect(removed.restore(into: &list, capacity: 100) == 3)
        #expect(list.map(\.id) == [original[0].id, original[1].id, original[3].id, original[4].id])
    }

    @Test func neverDuplicatesOrOverwritesInterveningEdits() throws {
        var list = entries(3)
        let removed = try #require(RemovedEntries.capture([list[1].id], from: list, message: "Removed"))
        // Entry was re-added and edited before Undo; Undo must not duplicate or revert it.
        var edited = list[1]; edited.title = "Edited"
        list = [list[0], edited, list[2]]
        #expect(removed.restore(into: &list, capacity: 100) == 0)
        #expect(list.count == 3 && list[1].title == "Edited")
    }

    @Test func respectsCapacityAndEmptyCapture() throws {
        var list = entries(3)
        let removed = try #require(RemovedEntries.capture(Set(list.map(\.id)), from: list, message: "Cleared"))
        list = [QuickChecklistEntry(title: "New")]
        #expect(removed.restore(into: &list, capacity: 2) == 1)
        #expect(list.count == 2)
        #expect(RemovedEntries<QuickChecklistEntry>.capture([UUID()], from: list, message: "x") == nil)
    }

    @Test func undoExpiresAfterItsLifetime() throws {
        let list = entries(1)
        let removed = try #require(RemovedEntries.capture([list[0].id], from: list, message: "Removed"))
        #expect(!removed.isExpired())
        #expect(removed.isExpired(at: removed.createdAt.addingTimeInterval(RemovedEntries<QuickChecklistEntry>.lifetime + 1)))
    }
}
