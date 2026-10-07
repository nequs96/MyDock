import Foundation
import Testing
@testable import MyDock

struct N2UtilityRepairTests {
    private func tempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("N2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func locateReplacesURLAndBookmarkKeepingIdentityAndPosition() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt"), c = dir.appendingPathComponent("c.txt"), newB = dir.appendingPathComponent("newB.txt")
        for url in [a, c, newB] { try Data("x".utf8).write(to: url) }
        let missing = ShelfFile(url: dir.appendingPathComponent("gone.txt"))
        let entries = [ShelfFile(url: a), missing, ShelfFile(url: c)]
        guard case let .relocated(updated) = FileShelfPolicy.relocating(missing.id, to: newB, in: entries) else { Issue.record("expected relocation"); return }
        #expect(updated.map(\.id) == entries.map(\.id))
        #expect(updated[1].url == newB.standardizedFileURL)
        #expect(updated[1].bookmark != nil)
        #expect(updated[0] == entries[0] && updated[2] == entries[2])
        #expect(FileManager.default.fileExists(atPath: newB.path))
    }

    @Test func locateRejectsDuplicatesAndMissingTargetsWithoutChangingEntries() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: a)
        let missing = ShelfFile(url: dir.appendingPathComponent("gone.txt"))
        let entries = [ShelfFile(url: a), missing]
        #expect(FileShelfPolicy.relocating(missing.id, to: a, in: entries) == .duplicate(existingName: "a.txt"))
        #expect(FileShelfPolicy.relocating(missing.id, to: dir.appendingPathComponent("nope.txt"), in: entries) == .notFound)
        #expect(FileShelfPolicy.relocating(missing.id, to: URL(string: "https://example.com")!, in: entries) == .notFileURL)
        #expect(FileShelfPolicy.relocating(UUID(), to: a, in: entries) == .notFound)
    }

    @Test func missingEntriesStayAndRetryReportsAvailabilityWithoutRemoving() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let entry = ShelfFile(url: dir.appendingPathComponent("drive-file.txt"))
        #expect(!FileShelfPolicy.isAvailable(entry))
        #expect(FileShelfPolicy.refreshingStaleBookmarks([entry]) == nil)
        try Data("x".utf8).write(to: dir.appendingPathComponent("drive-file.txt"))
        #expect(FileShelfPolicy.isAvailable(entry))
    }

    @Test func staleBookmarksRegenerateOnlyWhenFileResolves() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("moved.txt"), moved = dir.appendingPathComponent("moved-new.txt")
        try Data("x".utf8).write(to: original)
        let entry = ShelfFile(url: original)
        try FileManager.default.moveItem(at: original, to: moved)
        // Inject the bookmark resolution so the stale branch always runs, whatever the host reports.
        let stale: (ShelfFile) -> (url: URL, isStale: Bool) = { _ in (moved, true) }
        let refreshed = try #require(FileShelfPolicy.refreshingStaleBookmarks([entry], resolve: stale))
        #expect(refreshed[0].id == entry.id)
        #expect(refreshed[0].url == moved.standardizedFileURL)
        #expect(FileShelfPolicy.refreshingStaleBookmarks([entry], fileExists: { _ in false }, resolve: stale) == nil)
        #expect(FileShelfPolicy.refreshingStaleBookmarks([entry], resolve: { _ in (moved, false) }) == nil)
    }

    @Test func trashCopyStatesTrueScope() {
        #expect(TrashCopy.emptyConfirmationTitle.contains("all volumes"))
        #expect(TrashCopy.emptyConfirmationMessage.contains("not counted"))
        #expect(TrashCopy.countScope.contains("home Trash"))
        #expect(TrashCopy.countLabel(1) == "1 item in home Trash" && TrashCopy.countLabel(3).contains("home Trash"))
        #expect(TrashCopy.emptyFailureMessage(for: AutomationError.permissionDenied).contains("Automation"))
        #expect(TrashCopy.emptyFailureMessage(for: AutomationError.failed(exitStatus: 1)).contains("may not have been deleted"))
        #expect(TrashCopy.emptyFailureMessage(for: TrashActionError.failed("Custom")) == "Custom")
    }

    @Test func focusAvailabilityDetectsAppIntentsMetadata() throws {
        let dir = try tempDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
        let app = dir.appendingPathComponent("Fake.app")
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        #expect(!FocusFilterAvailability.hasIntentMetadata(bundleURL: app))
        #expect(FocusFilterAvailability.guidance(bundleURL: app) == FocusFilterAvailability.unavailableGuidance)
        #expect(!FocusFilterAvailability.unavailableGuidance.contains("Xcode"))
        try FileManager.default.createDirectory(at: resources.appendingPathComponent("Metadata.appintents"), withIntermediateDirectories: true)
        #expect(FocusFilterAvailability.hasIntentMetadata(bundleURL: app))
        #expect(FocusFilterAvailability.guidance(bundleURL: app).contains("Add Filter"))
    }
}
