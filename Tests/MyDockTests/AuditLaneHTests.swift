import Foundation
import Testing
@testable import MyDock

/// Audit lane H: the Dock manager, the Add Item gallery and their sheets.
@MainActor
@Suite struct AuditLaneHTests {
    private func fixture() -> (ProfileStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false), directory)
    }

    // MARK: S14-003

    @Test func anEmptyDockNameIsASaveFailureNotAMergeConflict() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try store.createProfileAndPersist(kind: .custom, name: "Original")
        let original = try #require(store.state.profiles.first { $0.id == id })
        var draft = DockProfileDraft(profile: original)
        draft.update { $0.name = "   " }
        store.editSessions.set(draft, for: id)
        do {
            try store.editSessions.save(id)
            Issue.record("A Dock without a name must not save")
        } catch let error as EditSessionSaveError {
            #expect(error.localizedDescription == "A Dock needs a name.")
        } catch {
            Issue.record("Expected a plain save failure, got \(error)")
        }
        #expect(store.state.profiles.first { $0.id == id }?.name == "Original")
        #expect(store.editSessions.drafts[id]?.profile.name == "   ")
    }

    // MARK: S14-019

    @Test func saveFeedbackCopyComesFromItsState() {
        #expect(ProfileSaveFeedback.saving.title == "Saving…")
        #expect(ProfileSaveFeedback.saved.title == "Saved")
        #expect(ProfileSaveFeedback.failed.title == "Couldn’t save · Retry")
    }

    @Test func browseActionsFollowTheDockKind() {
        #expect(DockBrowseAction.available(for: .custom) == [.application, .folder, .file, .link])
        #expect(DockBrowseAction.available(for: .native) == [.application])
        let custom = WidgetGalleryModel.moreEntries(kind: .custom, query: "").compactMap(\.browseAction)
        #expect(custom == DockBrowseAction.available(for: .custom))
        let native = WidgetGalleryModel.moreEntries(kind: .native, query: "").compactMap(\.browseAction)
        #expect(native == [.application])
        #expect(WidgetGalleryModel.moreEntries(kind: .custom, query: "website").compactMap(\.browseAction) == [.link])
        #expect(Set(DockBrowseAction.allCases.map(\.title)).count == DockBrowseAction.allCases.count)
    }

    // MARK: S14-016

    @Test func creatingADockWithoutActivationLeavesTheLiveDockAlone() throws {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = try store.createProfileAndPersist(kind: .custom, name: "Live")
        store.updateSettings(immediately: true) { $0.setupMode = .nativeOnly }
        let created = try store.createProfile(DockProfile(name: "Created", kind: .custom), activate: false)
        #expect(store.state.profiles.contains { $0.id == created })
        #expect(store.state.settings.activeCustomProfileID == live)
        #expect(store.state.settings.setupMode == .nativeOnly)
    }

    // MARK: S14-011

    @Test func folderCustomizationIsNormalisedTheSameWayEverywhere() {
        #expect(FolderCustomizationPolicy.name("  Client Work  ") == "Client Work")
        #expect(FolderCustomizationPolicy.name("   ") == nil)
        #expect(FolderCustomizationPolicy.editingName("Client ") == "Client ")
        #expect(FolderCustomizationPolicy.editingName("  ") == nil)
        #expect(FolderCustomizationPolicy.letter(" p") == "P")
        #expect(FolderCustomizationPolicy.letter("ab") == "A")
        #expect(FolderCustomizationPolicy.letter(" ") == nil)
        #expect(FolderCustomizationPolicy.number("12a3") == "123")
        #expect(FolderCustomizationPolicy.number("98765") == "987")
        #expect(FolderCustomizationPolicy.number("abc") == nil)
    }

    // MARK: S15-002

    @Test func gridRowsStartANewRowForSuggestedAndEverySection() {
        let rows = WidgetGalleryModel.gridRows(heroIDs: ["h1", "h2", "h3"], heroColumns: 3,
                                               sections: [["a", "b", "c", "d"], ["e", "f", "g"]], columns: 3)
        #expect(rows == [["h1", "h2", "h3"], ["a", "b", "c"], ["d"], ["e", "f", "g"]])
        #expect(WidgetGalleryModel.gridRows(heroIDs: [], heroColumns: 4, sections: [[]], columns: 3).isEmpty)
    }

    @Test func arrowKeysFollowTheRowsAsDrawn() {
        let rows = [["h1", "h2", "h3"], ["a", "b", "c"], ["d"], ["e", "f", "g"]]
        // Down keeps the column, clamped to a short row; it never skips into the wrong section column.
        #expect(WidgetGalleryModel.movedID(from: "h1", direction: .down, rows: rows) == "a")
        #expect(WidgetGalleryModel.movedID(from: "c", direction: .down, rows: rows) == "d")
        #expect(WidgetGalleryModel.movedID(from: "d", direction: .down, rows: rows) == "e")
        #expect(WidgetGalleryModel.movedID(from: "f", direction: .up, rows: rows) == "d")
        #expect(WidgetGalleryModel.movedID(from: "d", direction: .up, rows: rows) == "a")
        // Left and right follow the reading order across rows and stop at the ends.
        #expect(WidgetGalleryModel.movedID(from: "c", direction: .right, rows: rows) == "d")
        #expect(WidgetGalleryModel.movedID(from: "e", direction: .left, rows: rows) == "d")
        #expect(WidgetGalleryModel.movedID(from: "h1", direction: .left, rows: rows) == "h1")
        #expect(WidgetGalleryModel.movedID(from: "g", direction: .right, rows: rows) == "g")
        #expect(WidgetGalleryModel.movedID(from: "h2", direction: .up, rows: rows) == "h2")
        #expect(WidgetGalleryModel.movedID(from: "g", direction: .down, rows: rows) == "g")
        #expect(WidgetGalleryModel.movedID(from: "missing", direction: .down, rows: rows) == nil)
    }

    // MARK: S15-003

    @Test func addedIdentitiesMatchThePerItemCheck() {
        let profile = DockProfile(name: "Work", kind: .custom, items: [.widget("Clock"), .spacer(.small)])
        let keys = WidgetGalleryModel.addedIdentities(in: profile)
        #expect(keys == ["widget:Clock"])
        for item in [DockItem.widget("Clock"), .widget("Weather"), .spacer(.small)] {
            #expect(WidgetGalleryModel.isAdded(item, addedIdentities: keys, recentlyAdded: [])
                    == WidgetGalleryModel.isAdded(item, in: profile, recentlyAdded: []))
        }
        #expect(WidgetGalleryModel.isAdded(.widget("Weather"), addedIdentities: keys, recentlyAdded: ["widget:Weather"]))
        #expect(!WidgetGalleryModel.isAdded(.spacer(.small), addedIdentities: keys, recentlyAdded: []))
    }
}
