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

    // MARK: Part 2

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // S16-003
    @Test func aSetupSaveThatThrowsIsReportedEvenWhenSetupWasCompletedBefore() {
        let (store, directory) = fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.updateSettings(immediately: true) { $0.onboardingComplete = true }
        let result = OnboardingCompletion.finish(store: store, appliesClearStyle: false) {
            throw EditSessionSaveError.failed("Disk full")
        }
        #expect(result == OnboardingCompletion.Result(error: "Disk full", appliedClearStyle: false))
    }

    // S16-012
    @Test func aReplacementDockStartsWithTrash() {
        #expect(OnboardingView.starterWidgetKinds(["Clock", "Battery"], for: .customMain) == ["Battery", "Clock", "Trash"])
        #expect(OnboardingView.starterWidgetKinds(["Trash"], for: .customMain) == ["Trash"])
        #expect(OnboardingView.starterWidgetKinds(["Clock"], for: .both) == ["Clock"])
        #expect(OnboardingView.starterWidgetKinds([], for: .nativeOnly).isEmpty)
    }

    // S16-005
    @Test func shortcutLabelsNameSpecialKeysAndIgnoreShift() {
        #expect(DockShortcut.label(keyCode: 124, characters: "\u{F703}") == "→")
        #expect(DockShortcut.label(keyCode: 126, characters: "\u{F700}") == "↑")
        #expect(DockShortcut.label(keyCode: 122, characters: "\u{F704}") == "F1")
        #expect(DockShortcut.label(keyCode: 111, characters: "\u{F70F}") == "F12")
        #expect(DockShortcut.label(keyCode: 18, characters: "1") == "1")
        #expect(DockShortcut.label(keyCode: 0, characters: "a") == "A")
        #expect(DockShortcut.label(keyCode: 49, characters: " ") == "Space")
        #expect(DockShortcut.label(keyCode: 200, characters: "\u{F730}") == "Key 200")
    }

    // S16-009
    @Test func presetsShareTheDockExportFormatAndStillReadOldPresets() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = DockProfile(name: "Studio", kind: .custom, items: [.widget("Clock")])
        let library = ProfileLibrary(fileURL: folder.appendingPathComponent("presets.json"))
        #expect(library.record(profile, reason: "Test"))
        let entry = try #require(library.entries.first)
        let exported = try library.exportPreset(entry.id)
        // A preset file also opens with Import Dock….
        let preview = try PortableDockPackage.preview(exported, existingNames: [], targetExists: { _ in true })
        #expect(preview.profile.name == "Studio")

        let other = ProfileLibrary(fileURL: folder.appendingPathComponent("other.json"))
        try other.importPreset(exported)
        try other.importPreset(try PortableDockPackage.makePackage(from: profile, includePersonalData: false))
        try other.importPreset(try JSONEncoder().encode(profile))
        #expect(other.entries.count == 3)
        #expect(other.entries.allSatisfy { $0.profile.name == "Studio" && $0.profile.items.count == 1 })
        do {
            try other.importPreset(Data("{}".utf8))
            Issue.record("An unrelated file must not import")
        } catch {
            #expect(error.localizedDescription == ProfileLibrary.unreadablePreset)
        }
    }

    // S14-031
    @Test func savingAPresetReportsALibraryThatCannotBeWritten() throws {
        let blocked = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: blocked) }
        try Data("blocked".utf8).write(to: blocked)
        let library = ProfileLibrary(fileURL: blocked.appendingPathComponent("presets.json"))
        #expect(!library.record(DockProfile(name: "Studio", kind: .custom, items: [.widget("Clock")]), reason: "Test"))
        #expect(library.errorMessage != nil)
    }

    @Test func locateReportsEveryRepairThatChangedNothing() {
        #expect(SavedCollectionActions.locateFailure(relocation: .relocated([]), update: .accepted) == nil)
        #expect(SavedCollectionActions.locateFailure(relocation: .duplicate(existingName: "Plan.pdf"), update: .unchanged)?.contains("Plan.pdf") == true)
        #expect(SavedCollectionActions.locateFailure(relocation: .notFound, update: .unchanged) != nil)
        #expect(SavedCollectionActions.locateFailure(relocation: nil, update: .rejected("Saving is disabled.")) == "Saving is disabled.")
        #expect(SavedCollectionActions.locateFailure(relocation: .relocated([]), update: .missingTarget) != nil)
    }

    // S14-023
    @Test func droppedURLsAreClassifiedBySchemeAndDockKind() {
        let web = URL(string: "https://example.com/downloads/Tool.app")!
        let app = URL(fileURLWithPath: "/Applications/MyDock Audit Example.APP")
        #expect(!DockDropInsertionPolicy.isApplication(web))
        #expect(DockDropInsertionPolicy.isApplication(app))
        #expect(DockDropInsertionPolicy.items(for: [web], kind: .custom).map(\.type) == [.link])
        #expect(DockDropInsertionPolicy.items(for: [web], kind: .native).isEmpty)
        #expect(DockDropInsertionPolicy.items(for: [app], kind: .native).map(\.type) == [.application])
    }

    // S14-029
    @Test func tileSizeBoundsAreShared() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"customDockSize": 9}"#.utf8))
        #expect(settings.customDockSize == DockAppearanceBounds.size.upperBound)
    }

    // S20-003
    @Test func settingsCopyCallsASavedArrangementADock() {
        for entry in SettingsSearchCatalog.entries {
            #expect(!(entry.title + " " + entry.section).localizedCaseInsensitiveContains("profile"), "\(entry.title)")
            #expect(!entry.title.contains("Apple Dock"), "\(entry.title)")
        }
        for page in MyDockSettingsPage.allCases {
            #expect(!page.designDescription.localizedCaseInsensitiveContains("profile"))
            #expect(!page.designDescription.localizedCaseInsensitiveContains("layouts"))
        }
    }

    // MARK: Part 3

    // S15-016
    @Test func appsAndMoreMatchEveryQueryWordLikeWidgets() {
        #expect(WidgetDiscovery.matchesTerms("Visual Studio Code", query: "visual code"))
        #expect(WidgetDiscovery.matchesTerms("Visual Studio Code", query: ""))
        #expect(!WidgetDiscovery.matchesTerms("Visual Studio Code", query: "visual xcode"))
        let apps = [
            InstalledApplication(url: URL(fileURLWithPath: "/Applications/Visual Studio Code.app"), bundleIdentifier: "com.microsoft.VSCode", name: "Visual Studio Code", version: "1.0"),
            InstalledApplication(url: URL(fileURLWithPath: "/Applications/Maps.app"), bundleIdentifier: "com.apple.Maps", name: "Maps", version: "3.0")
        ]
        #expect(WidgetGalleryModel.applicationEntries(apps, query: "code visual").map(\.title) == ["Visual Studio Code"])
        #expect(WidgetGalleryModel.applicationEntries(apps, query: "vscode").map(\.title) == ["Visual Studio Code"])
        let spacers = WidgetGalleryModel.moreEntries(kind: .custom, query: "gap slim")
        #expect(spacers.count == 1 && spacers.first?.item?.spacerKind == .small)
    }

    // S15-017
    @Test func duplicateAppsWithoutAVersionShowOnlyTheirFolder() {
        let apps = [
            InstalledApplication(url: URL(fileURLWithPath: "/Applications/Tool.app"), bundleIdentifier: "a", name: "Tool", version: ""),
            InstalledApplication(url: URL(fileURLWithPath: "/Volumes/Old/Tool.app"), bundleIdentifier: "b", name: "Tool", version: "2.0")
        ]
        #expect(WidgetGalleryModel.applicationEntries(apps, query: "").map(\.detail) == ["Applications", "Version 2.0 · Old"])
    }

    // S15-023
    @Test func galleryPreviewsFallBackInsteadOfIndexingAnEmptyFamily() {
        let unknown = WidgetGalleryModel.layoutOption(for: "MyDock Audit Unknown Family", layout: .wide)
        #expect(unknown == WidgetLayoutPresets.generic[0])
        #expect(!WidgetGalleryModel.layoutOptions(for: "MyDock Audit Unknown Family").isEmpty)
        for definition in WidgetRegistry.all {
            let first = WidgetGalleryModel.layoutOptions(for: definition.name)[0]
            let supported = definition.capabilities.layouts.map(\.layout)
            for layout in WidgetLayout.allCases {
                let option = WidgetGalleryModel.layoutOption(for: definition.name, layout: layout)
                #expect(option.layout == (supported.contains(layout) ? layout : first.layout), "\(definition.name)")
            }
        }
    }

    // S15-021, S15-022
    @Test func galleryCopyMatchesSingleClickOpeningAndOneNoDockLine() {
        #expect(!WidgetGalleryKeymap.tileHelp(canAdd: true).localizedCaseInsensitiveContains("double-click"))
        #expect(WidgetGalleryModel.noDockMessage == "Choose a Dock to add items.")
    }

    // S16-016
    @Test func starterPresetFallbackNotesNameEveryPreferredApp() {
        for preset in DockStarterPreset.allCases {
            for group in preset.applicationCandidates {
                let preferred = group.first
                #expect(preferred.flatMap { DockStarterPreset.displayNames[$0] } != nil, "\(preset.rawValue): \(group)")
            }
        }
    }

    // S16-014
    @Test func shortcutCatalogListsTheGalleryKeys() {
        let titles = KeyboardShortcutCatalog.groups.flatMap { $0.entries.map(\.title) }
        #expect(titles.contains("Switch between Widgets, Apps and More"))
        #expect(titles.contains("Previous or next size"))
    }
}
