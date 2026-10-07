import AppKit
import Foundation
import Testing
@testable import MyDock

@MainActor
struct ProfileStoreTests {
    @Test func failedRecoveryBlocksNewApplyAndRetainsOriginalJournal() async throws {
        let original: [[String: Any]] = [["tile-type": "small-spacer-tile"]]
        let backend = FakeDockPreferencesBackend(tiles: original, failingWrites: [1])
        let journal = FakeDockTransactionJournal()
        try journal.begin(snapshot: original, profileID: UUID())
        let controller = NativeDockController(backend: backend, relauncher: FakeDockRelauncher(), journal: journal)
        do { try await controller.recoverInterruptedTransaction(); Issue.record("Recovery should fail") } catch { }
        #expect(controller.health == .recoveryRequired)
        let writes = backend.writeCount
        do { try await controller.apply(DockProfile(name: "Other", kind: .native)); Issue.record("Apply should be blocked") } catch { }
        #expect(backend.writeCount == writes)
        #expect(journal.isPending)
        #expect(try NativeDockSerializer.plistArraysEqual(journal.pendingSnapshot() ?? [], original))
    }

    @Test func nativeDockImportRejectsUnreadableOrUnsupportedLayout() throws {
        let backend = FakeDockPreferencesBackend(tiles: [["tile-type": "unsupported-tile"]])
        let controller = NativeDockController(backend: backend, relauncher: FakeDockRelauncher())
        #expect(throws: NativeDockError.self) { try controller.readCurrentItems() }

        backend.tiles = []
        #expect(try controller.readCurrentItems().isEmpty)
        backend.failReads = true
        #expect(throws: NativeDockError.self) { try controller.readCurrentItems() }
    }

    @Test func starterPresetsUseAvailableAppsAndKnownWidgets() {
        for preset in DockStarterPreset.allCases {
            let items = preset.items()
            #expect(!items.isEmpty)
            #expect(Set(items.map(\.id)).count == items.count)
            for item in items {
                if item.type == .application {
                    #expect(item.url.map { FileManager.default.fileExists(atPath: $0.path) } == true)
                }
                if item.type == .widget {
                    #expect(WidgetRegistry.all.contains { $0.name == item.widgetKind })
                }
            }
        }
    }

    @Test func replacementDockReclaimsReservedSpaceOnSecondaryDisplay() {
        let frame = NSRect(x: -1440, y: -200, width: 1440, height: 900)
        let visible = NSRect(x: -1360, y: -200, width: 1360, height: 875)
        let main = DockSurfaceMetrics.placementArea(frame: frame, visibleFrame: visible, mode: .customMain)
        #expect(main.minX == frame.minX)
        #expect(main.minY == frame.minY)
        #expect(main.maxY == visible.maxY)
        #expect(DockSurfaceMetrics.placementArea(frame: frame, visibleFrame: visible, mode: .both) == visible)
        let bottom = NSRect(x: 0, y: 80, width: 1440, height: 795)
        #expect(DockSurfaceMetrics.placementArea(frame: NSRect(x: 0, y: 0, width: 1440, height: 900), visibleFrame: bottom, mode: .customMain).minY == 0)
    }

    @Test func solidFinishPersists() throws {
        var settings = AppSettings()
        settings.customDockMaterial = .solid
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.customDockMaterial == .solid)
    }

    @Test func spacerKindsSurviveJSONRoundTrip() throws {
        let original = [DockItem.spacer(.small), DockItem.spacer(.regular)]
        let encoded = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode([DockItem].self, from: encoded)

        #expect(restored.map(\.spacerKind) == [.small, .regular])
        #expect(restored[0] != restored[1])
    }

    @Test func profileAndItemsPersistAcrossStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")

        let first = ProfileStore(fileURL: file)
        let profileID = try first.createProfileAndPersist(kind: .custom, name: "Research")
        first.add(.widget("Clock"), to: profileID)
        first.add(.spacer(.small), to: profileID)
        first.setProfileColor(profileID, to: .teal)
        first.updateSettings { $0.customDockSize = 1.25; $0.customDockDisplayID = 12345; $0.customDockDesktopMode = true }
        first.commit()

        let restored = ProfileStore(fileURL: file)
        guard let profile = restored.state.profiles.first(where: { $0.id == profileID }) else {
            Issue.record("Profile wasn't restored")
            return
        }
        #expect(profile.name == "Research")
        #expect(profile.items.map(\.type) == [.widget, .spacer])
        #expect(profile.items.last?.spacerKind == .small)
        #expect(profile.color == DockProfileColor.teal.rawValue)
        #expect(restored.state.settings.activeCustomProfileID == profileID)
        #expect(restored.state.settings.customDockSize == 1.25)
        #expect(restored.state.settings.customDockDisplayID == 12345)
        #expect(restored.state.settings.customDockDesktopMode)
    }

    @Test func clearingActiveCustomProfilePersistsNoneForCustomMainRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Workspace")
        store.setSetupMode(.customMain)

        store.setActiveCustomProfile(nil)

        #expect(store.state.settings.activeCustomProfileID == nil)
        #expect(store.activeCustomProfile == nil)
        #expect(store.state.settings.setupMode == .customMain)
        let restored = ProfileStore(fileURL: file)
        #expect(restored.state.settings.activeCustomProfileID == nil)
        #expect(restored.state.settings.setupMode == .customMain)
        #expect(restored.customProfiles.contains(where: { $0.id == profileID }))
    }

    @Test func failedProfileCreationDoesNotPublishAndCanBeRetried() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let blockedParent = root.appendingPathComponent("not-a-directory")
        try Data("blocker".utf8).write(to: blockedParent)
        let store = ProfileStore(fileURL: blockedParent.appendingPathComponent("state.json"))
        let profileID = store.createProfile(kind: .custom, name: "Draft survives")

        #expect(store.persistenceError != nil)
        #expect(store.hasUnpersistedChanges)
        #expect(store.canRetryPersistence)
        #expect(profileID == nil)
        #expect(store.state.profiles.isEmpty)

        try FileManager.default.removeItem(at: blockedParent)
        try FileManager.default.createDirectory(at: blockedParent, withIntermediateDirectories: true)
        let savedID = try store.createProfileAndPersist(kind: .custom, name: "Draft survives")

        #expect(store.persistenceError == nil)
        #expect(!store.hasUnpersistedChanges)
        #expect(ProfileStore(fileURL: blockedParent.appendingPathComponent("state.json"))
            .state.profiles.contains(where: { $0.id == savedID }))
    }

    @Test func corruptProfileDataIsPreservedBeforeNewStateIsWritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let original = Data("not valid profile JSON".utf8)
        try original.write(to: file)

        let store = ProfileStore(fileURL: file)
        #expect(store.persistenceWarning != nil)
        _ = store.createProfile(kind: .custom)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state.json.recovery-") }
        #expect(recoveryFiles.count == 1)
        #expect(try Data(contentsOf: recoveryFiles[0]) == original)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func futureSchemaIsNeverOverwritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        var futureState = PersistentState()
        futureState.schemaVersion = Product.stateSchemaVersion + 1
        let futureData = try JSONEncoder().encode(futureState)
        try futureData.write(to: file)

        let store = ProfileStore(fileURL: file)
        #expect(store.persistenceWarning != nil)
        // Create is candidate-first: a refused create publishes nothing and returns no identity.
        #expect(store.createProfile(kind: .custom) == nil)
        #expect(store.state.profiles.isEmpty)
        #expect(!store.hasUnpersistedChanges)
        // The throwing API (used by every production caller) surfaces the protection reason.
        #expect(throws: EditSessionSaveError.self) { try store.createProfileAndPersist(kind: .custom) }
        #expect(store.state.profiles.isEmpty)
        #expect(try Data(contentsOf: file) == futureData)
        #expect(store.persistenceWarning != nil)
        #expect(!store.canRetryPersistence)
    }

    @Test func onboardingCreatesSelectedProfilesAndStarterWidgets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let imported = [DockItem.application(at: URL(fileURLWithPath: "/Applications/Preview.app")), .spacer(.small)]

        try store.finishOnboarding(setupMode: .both,
                               customDockPosition: .left,
                               customDockDisplayID: 42,
                               importedNativeItems: imported,
                               starterWidgets: ["Clock", "Battery"])

        #expect(store.state.settings.onboardingComplete)
        #expect(store.state.settings.setupMode == .both)
        #expect(store.state.settings.customDockPosition == .left)
        #expect(store.state.settings.customDockDisplayID == 42)
        #expect(store.nativeProfiles.first?.items == imported)
        #expect(store.customProfiles.first?.items.map(\.widgetKind) == ["Clock", "Battery"])
        #expect(store.state.settings.activeNativeProfileID == store.nativeProfiles.first?.id)
        #expect(store.state.settings.activeCustomProfileID == store.customProfiles.first?.id)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func moveItemPreservesOrderAndSpacerIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom)
        let one = DockItem.widget("Clock")
        let small = DockItem.spacer(.small)
        let regular = DockItem.spacer(.regular)
        store.add(one, to: profileID)
        store.add(small, to: profileID)
        store.add(regular, to: profileID)

        store.moveItems([regular.id], before: one.id, in: profileID)

        let items = store.state.profiles.first { $0.id == profileID }?.items
        #expect(items?.map(\.id) == [regular.id, one.id, small.id])
        #expect(items?.first?.spacerKind == .regular)
        #expect(items?.last?.spacerKind == .small)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func insertItemPlacesRunningAppBeforeDockTarget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom)
        let first = DockItem.widget("Clock")
        let target = DockItem.widget("Weather")
        let inserted = DockItem.application(at: URL(fileURLWithPath: "/Applications/Preview.app"))
        store.add(first, to: profileID)
        store.add(target, to: profileID)

        store.insert(inserted, before: target.id, in: profileID)

        let items = store.state.profiles.first { $0.id == profileID }?.items
        #expect(items?.map(\.id) == [first.id, inserted.id, target.id])
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func shiftRangeSelectionIncludesBothEndpointsInEitherDirection() {
        let ids = (0..<5).map { _ in UUID() }

        #expect(DockItemSelectionPolicy.range(in: ids, from: ids[1], to: ids[3]) == Set(ids[1...3]))
        #expect(DockItemSelectionPolicy.range(in: ids, from: ids[3], to: ids[1]) == Set(ids[1...3]))
        #expect(DockItemSelectionPolicy.range(in: ids, from: UUID(), to: ids[1]).isEmpty)
    }

    @Test func dockProfileDraftCanDiscardUncommittedChanges() {
        let original = DockProfile(name: "Before", kind: .custom, items: [.widget("Clock")])
        var draft = DockProfileDraft(profile: original)
        draft.update {
            $0.name = "After"
            $0.items.append(.widget("Battery"))
        }

        #expect(draft.isDirty)
        #expect(draft.profile.name == "After")
        #expect(draft.profile.items.count == 2)
        draft.discard()
        #expect(!draft.isDirty)
        #expect(draft.profile == original)
    }

    @Test func dockProfileDraftBecomesCleanAfterExplicitSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Before")
        let original = store.state.profiles.first { $0.id == profileID }!
        var draft = DockProfileDraft(profile: original)
        draft.update {
            $0.name = "After"
            $0.items = [.widget("Clock"), .widget("Battery")]
        }
        #expect(draft.isDirty)

        store.replaceProfile(draft.profile)
        draft.markSaved(draft.profile)

        let restored = ProfileStore(fileURL: file)
        #expect(!draft.isDirty)
        #expect(restored.state.profiles.first { $0.id == profileID } == draft.profile)
    }

    @Test func movingSelectedItemsKeepsTheirOrderAndMovesAsAGroup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom)
        let items = ["A", "B", "C", "D", "E"].map(DockItem.widget)
        items.forEach { store.add($0, to: profileID) }
        let selected = [items[1].id, items[3].id]

        store.moveItems(Set(selected), direction: .left, in: profileID)
        #expect(store.state.profiles.first { $0.id == profileID }?.items.map(\.id) == [items[1].id, items[0].id, items[3].id, items[2].id, items[4].id])

        store.moveItems(Set(selected), direction: .right, in: profileID)
        #expect(store.state.profiles.first { $0.id == profileID }?.items == items)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func removeItemsDeletesMultipleDockEntriesInOnePersistedUpdate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Work")
        let first = DockItem.widget("Clock")
        let retained = DockItem.spacer(.small)
        let last = DockItem.widget("Battery")
        store.add(first, to: profileID)
        store.add(retained, to: profileID)
        store.add(last, to: profileID)

        store.removeItems([first.id, last.id], from: profileID)
        store.flush()

        let restored = ProfileStore(fileURL: file)
        #expect(restored.state.profiles.first(where: { $0.id == profileID })?.items == [retained])
        store.removeItems([first.id], from: profileID)
        #expect(store.state.profiles.first(where: { $0.id == profileID })?.items == [retained])
    }

    @Test func widgetConfigurationPersistsAndFocusTimerUsesElapsedTime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Notes")
        let note = DockItem.widget("Sticky Note")
        store.add(note, to: profileID)
        store.updateWidgetConfiguration(itemID: note.id, in: profileID) {
            $0.noteText = "Bring the notebook"
            $0.noteBackground = .blue
        }
        store.flush()

        let restored = ProfileStore(fileURL: file)
        let saved = restored.state.profiles.first { $0.id == profileID }?.items.first
        #expect(saved?.widgetConfiguration?.noteText == "Bring the notebook")
        #expect(saved?.widgetConfiguration?.noteBackground == .blue)

        let start = Date(timeIntervalSince1970: 1_000)
        var timer = WidgetConfiguration()
        timer.focusDurationSeconds = 120
        timer.startFocusTimer(at: start)
        #expect(timer.focusRemaining(at: start.addingTimeInterval(45)) == 75)
        timer.pauseFocusTimer(at: start.addingTimeInterval(45))
        #expect(timer.focusRemaining(at: start.addingTimeInterval(500)) == 75)
        timer.resetFocusTimer()
        #expect(timer.focusRemaining(at: start.addingTimeInterval(500)) == 120)

        var stopwatch = WidgetConfiguration()
        stopwatch.startStopwatch(at: start, clock: nil)
        #expect(stopwatch.stopwatchElapsed(at: start.addingTimeInterval(12), clock: nil) == 12)
        stopwatch.pauseStopwatch(at: start.addingTimeInterval(12), clock: nil)
        #expect(stopwatch.stopwatchElapsed(at: start.addingTimeInterval(500), clock: nil) == 12)

        var countdown = WidgetConfiguration()
        countdown.countdownDurationSeconds = 90
        countdown.startCountdown(at: start)
        #expect(countdown.countdownRemaining(at: start.addingTimeInterval(30)) == 60)
        countdown.pauseCountdown(at: start.addingTimeInterval(30))
        #expect(countdown.countdownRemaining(at: start.addingTimeInterval(500)) == 60)
    }

    @Test func countdownCanTargetAnAbsoluteDateAndSurvivePersistence() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let target = now.addingTimeInterval(90_000)
        var countdown = WidgetConfiguration()
        countdown.setCountdownTarget(target)

        #expect(countdown.countdownMode == .targetDate)
        #expect(countdown.countdownRemaining(at: now) == 90_000)
        #expect(countdown.countdownRemaining(at: target.addingTimeInterval(1)) == 0)
        countdown.startCountdown(at: now)
        countdown.pauseCountdown(at: now.addingTimeInterval(20))
        #expect(countdown.countdownStartedAt == nil)
        #expect(countdown.countdownRemaining(at: now.addingTimeInterval(30)) == 89_970)

        let restored = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(countdown))
        #expect(restored.countdownMode == .targetDate)
        #expect(restored.countdownTargetDate == target)
        #expect(restored.countdownRemaining(at: now.addingTimeInterval(60)) == 89_940)

        countdown.resetCountdown()
        #expect(countdown.countdownTargetDate == nil)
        countdown.setCountdownMode(.duration)
        #expect(countdown.countdownRemaining(at: now) == 300)
    }

    @Test func countdownTargetTextKeepsLongDeadlinesReadable() {
        #expect(targetCountdownText(90_061, compact: true) == "1d")
        #expect(targetCountdownText(90_061, compact: false) == "1d 01:01:01")
        #expect(targetCountdownText(3_661, compact: true) == "1h 1m")
        #expect(targetCountdownText(61, compact: false) == "1:01")
    }

    @Test func stopwatchUsesPersistedMonotonicClockAcrossWallClockChanges() throws {
        let wallStart = Date(timeIntervalSince1970: 1_000)
        let first = StopwatchClockSample(continuousSeconds: 100, bootSessionID: "boot-A")
        var stopwatch = WidgetConfiguration()
        stopwatch.startStopwatch(at: wallStart, clock: first)

        let restored = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(stopwatch))
        let later = StopwatchClockSample(continuousSeconds: 112, bootSessionID: "boot-A")
        #expect(restored.stopwatchElapsed(at: wallStart.addingTimeInterval(-3_600), clock: later) == 12)
        #expect(restored.stopwatchElapsed(at: wallStart.addingTimeInterval(86_400), clock: later) == 12)

        stopwatch.pauseStopwatch(at: wallStart.addingTimeInterval(-3_600), clock: later)
        #expect(stopwatch.stopwatchElapsed(at: wallStart.addingTimeInterval(86_400), clock: nil) == 12)
        #expect(stopwatch.stopwatchClockStart == nil)

        stopwatch.startStopwatch(at: wallStart.addingTimeInterval(50),
                                 clock: StopwatchClockSample(continuousSeconds: 200, bootSessionID: "boot-A"))
        #expect(stopwatch.stopwatchElapsed(at: wallStart.addingTimeInterval(-3_600),
                                          clock: StopwatchClockSample(continuousSeconds: 205, bootSessionID: "boot-A")) == 17)
        stopwatch.resetStopwatch()
        #expect(stopwatch.stopwatchElapsed(at: wallStart, clock: later) == 0)
        #expect(stopwatch.stopwatchClockStart == nil)
    }

    @Test func stopwatchFallsBackToDateAfterRebootOrLegacyDecode() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        var stopwatch = WidgetConfiguration()
        stopwatch.startStopwatch(at: start,
                                 clock: StopwatchClockSample(continuousSeconds: 100, bootSessionID: "boot-A"))
        #expect(stopwatch.stopwatchElapsed(at: start.addingTimeInterval(20),
                                          clock: StopwatchClockSample(continuousSeconds: 5, bootSessionID: "boot-B")) == 20)

        var encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(stopwatch)) as! [String: Any]
        encoded.removeValue(forKey: "stopwatchClockStart")
        let legacy = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONSerialization.data(withJSONObject: encoded))
        #expect(legacy.stopwatchElapsed(at: start.addingTimeInterval(30),
                                        clock: StopwatchClockSample(continuousSeconds: 130, bootSessionID: "boot-A")) == 30)
    }

    @Test func liveStopwatchClockReadsBootScopedContinuousTime() {
        guard let first = StopwatchClock.sample(), let second = StopwatchClock.sample() else {
            Issue.record("The IOKit boot-session clock is unavailable")
            return
        }
        #expect(UUID(uuidString: first.bootSessionID) != nil)
        #expect(second.bootSessionID == first.bootSessionID)
        #expect(second.continuousSeconds >= first.continuousSeconds)
    }

    @Test func stopwatchDisplayHandlesCorruptOrExtremeElapsedValues() {
        #expect(stopwatchText(3_661) == "1:01:01")
        #expect(stopwatchText(-50) == "00:00")
        #expect(stopwatchText(.nan) == "00:00")
        #expect(!stopwatchText(1e100).isEmpty)
        #expect(!stopwatchText(.infinity).isEmpty)
    }

    @Test func hydrationHistoryRevealsOlderDaysOnlyWhenRequested() {
        let days = Array(0..<10)
        #expect(HydrationHistoryPolicy.visibleDays(days, showingOlder: false) == Array(0..<7))
        #expect(HydrationHistoryPolicy.visibleDays(days, showingOlder: true) == days)
        #expect(HydrationHistoryPolicy.visibleDays([1, 2], showingOlder: false) == [1, 2])
    }

    @Test func timeProgressUsesLocalDayBoundariesAcrossDST() {
        var calendar = Calendar(identifier: .gregorian)
        guard let newYork = TimeZone(identifier: "America/New_York") else {
            Issue.record("Test time zone is unavailable")
            return
        }
        calendar.timeZone = newYork
        guard let noon = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12)) else {
            Issue.record("Could not construct DST test date")
            return
        }
        let fraction = TimeProgressCalculator.fraction(for: .day, at: noon, calendar: calendar)
        #expect(abs(fraction - (11.0 / 23.0)) < 0.001)
    }

    @Test func widgetConfigurationDecodesOlderPartialData() throws {
        let data = Data(#"{"noteText":"older backup"}"#.utf8)
        let restored = try JSONDecoder().decode(WidgetConfiguration.self, from: data)
        #expect(restored.noteText == "older backup")
        #expect(restored.focusDurationSeconds == 25 * 60)
        #expect(restored.countdownDurationSeconds == 5 * 60)
        #expect(restored.countdownMode == .duration)
        #expect(restored.countdownTargetDate == nil)
        #expect(restored.timeProgressPeriod == .day)
        #expect(restored.calendarLayout == .dateAndNextEvent)
        #expect(restored.selectedCalendarIDs.isEmpty)
        #expect(restored.remindersLayout == .list)
        #expect(restored.alarms.isEmpty)
        #expect(restored.nowPlayingSource == .appleMusic)
        #expect(restored.nowPlayingEnabledSources == [.appleMusic])
        #expect(restored.nowPlayingLayout == .full)
        #expect(restored.nowPlayingSkipSeconds == 15)
        #expect(!restored.nowPlayingHidesWhenClosed)
        #expect(restored.nowPlayingShowsTrackControls)
        #expect(restored.nowPlayingShowsSeekControls)
        #expect(restored.worldClockAdditionalTimeZoneIDs.isEmpty)
    }

    @Test func countdownNotificationGenerationsPreserveOnlyTheCurrentRequest() {
        let first = UUID()
        let second = UUID()
        #expect(CountdownNotificationService.notificationID(itemID: first) == "mydock.countdown.\(first.uuidString)")
        #expect(CountdownNotificationService.notificationID(itemID: first) != CountdownNotificationService.notificationID(itemID: second))
        let earlierOperation = UUID()
        let currentOperation = UUID()
        var generations = WidgetNotificationGenerationPolicy()
        generations.begin(itemID: first, operationID: earlierOperation)
        generations.begin(itemID: first, operationID: currentOperation)
        #expect(!generations.isCurrent(itemID: first, operationID: earlierOperation))
        #expect(generations.isCurrent(itemID: first, operationID: currentOperation))
        let prefix = CountdownNotificationService.notificationID(itemID: first)
        let earlierID = CountdownNotificationService.notificationID(itemID: first, operationID: earlierOperation)
        let currentID = CountdownNotificationService.notificationID(itemID: first, operationID: currentOperation)
        let anotherWidgetID = CountdownNotificationService.notificationID(itemID: second, operationID: UUID())
        #expect(WidgetNotificationGenerationPolicy.obsoleteIdentifiers(
            [prefix, earlierID, currentID, anotherWidgetID], prefix: prefix, preserving: currentID) ==
            [prefix, earlierID])
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(CountdownNotificationService.isFutureTarget(now.addingTimeInterval(1), now: now))
        #expect(!CountdownNotificationService.isFutureTarget(now, now: now))
        #expect(!CountdownNotificationService.isFutureTarget(now.addingTimeInterval(-1), now: now))
    }

    @Test func calendarAndReminderWidgetConfigurationPersistsInBackup() throws {
        var calendarItem = DockItem.widget("Calendar")
        calendarItem.widgetConfiguration?.selectedCalendarIDs = ["work", "family"]
        calendarItem.widgetConfiguration?.calendarLayout = .agenda
        calendarItem.widgetConfiguration?.calendarShowsAllDayEvents = true
        var remindersItem = DockItem.widget("Reminders")
        remindersItem.widgetConfiguration?.selectedReminderCalendarID = "personal"
        remindersItem.widgetConfiguration?.remindersLayout = .nextReminder
        let profile = DockProfile(name: "Schedule", kind: .custom, items: [calendarItem, remindersItem])

        let archive = try BackupManager.makeArchive(from: [profile])
        let items = try BackupManager.readArchive(archive).importedProfiles[0].items

        #expect(items[0].widgetConfiguration?.selectedCalendarIDs == ["work", "family"])
        #expect(items[0].widgetConfiguration?.calendarLayout == .agenda)
        #expect(items[0].widgetConfiguration?.calendarShowsAllDayEvents == true)
        #expect(items[1].widgetConfiguration?.selectedReminderCalendarID == "personal")
        #expect(items[1].widgetConfiguration?.remindersLayout == .nextReminder)
    }

    @Test func worldClockCityListSurvivesBackupAndAvoidsPrimaryDuplicate() throws {
        var item = DockItem.widget("World Clock")
        item.widgetConfiguration?.worldClockTimeZoneID = "Europe/Warsaw"
        item.widgetConfiguration?.worldClockAdditionalTimeZoneIDs = ["Asia/Tokyo", "America/New_York"]
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "World", kind: .custom, items: [item])])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration

        #expect(restored?.worldClockTimeZoneID == "Europe/Warsaw")
        #expect(restored?.worldClockAdditionalTimeZoneIDs == ["Asia/Tokyo", "America/New_York"])
    }

    @Test func worldClockCitySearchAndDayOffsetsCoverArbitraryZones() throws {
        #expect(WorldClockCityCatalog.matches("Tokyo").contains { $0.id == "Asia/Tokyo" })
        #expect(WorldClockCityCatalog.matches("America/Los_Angeles").contains { $0.id == "America/Los_Angeles" })
        #expect(WorldClockCityCatalog.matches(" ").isEmpty)
        let instant = Date(timeIntervalSince1970: 1_704_083_400) // 2024-01-01 02:30 UTC
        let warsaw = try #require(TimeZone(identifier: "Europe/Warsaw"))
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(WorldClockCityCatalog.dayOffset(from: warsaw, to: newYork, at: instant) == -1)
        #expect(WorldClockCityCatalog.dayOffset(from: warsaw, to: tokyo, at: instant) == 0)
    }

    @Test func localClockFormattingFollowsLocaleAndTimeZone() throws {
        let instant = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:05:00Z"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let warsaw = try #require(TimeZone(identifier: "Europe/Warsaw"))
        let twentyFourHour = LocalClockFormatter.time(for: instant,
                                                       locale: Locale(identifier: "en_GB"),
                                                       timeZone: warsaw)
        let twelveHour = LocalClockFormatter.time(for: instant,
                                                   locale: Locale(identifier: "en_US"),
                                                   timeZone: warsaw)

        #expect(twentyFourHour.contains("13:05"))
        #expect(twelveHour.contains("1:05"))
        #expect(twelveHour.localizedCaseInsensitiveContains("pm"))
        #expect(LocalClockFormatter.time(for: instant, locale: Locale(identifier: "en_GB"), timeZone: utc).contains("12:05"))

        let localDate = LocalClockFormatter.date(for: instant,
                                                 locale: Locale(identifier: "en_GB"),
                                                 timeZone: warsaw)
        #expect(localDate.contains("Thursday"))
        #expect(localDate.contains("2026"))
    }

    @Test func marketSeriesParserBuildsOrderedDailySnapshotAndChange() throws {
        let payload = #"{"Meta Data":{"2. Symbol":"AAPL"},"Time Series (Daily)":{"2026-09-22":{"1. open":"101.00","2. high":"104.00","3. low":"100.00","4. close":"103.50","5. volume":"1250000"},"2026-09-23":{"1. open":"103.50","2. high":"106.00","3. low":"102.00","4. close":"105.00","5. volume":"1500000"}}}"#
        let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = try MarketDataParser.dailySnapshot(from: Data(payload.utf8), expectedSymbol: "AAPL", currency: "EUR", fetchedAt: fetchedAt)

        #expect(snapshot.points.count == 2)
        #expect(snapshot.points[0].close == 103.5)
        #expect(snapshot.points[1].close == 105)
        #expect(snapshot.latest?.volume == 1_500_000)
        #expect(snapshot.change == 1.5)
        #expect(snapshot.changePercent == 1.5 / 103.5 * 100)
        #expect(snapshot.currency == "EUR")
        #expect(snapshot.fetchedAt == fetchedAt)
    }

    @Test func marketSymbolSearchParserAndTickerValidationAreSafe() throws {
        let payload = #"{"bestMatches":[{"1. symbol":"AAPL","2. name":"Apple Inc.","3. type":"Equity","4. region":"United States","8. currency":"USD"},{"1. symbol":"BRK.B","2. name":"Berkshire Hathaway Inc.","3. type":"Equity","4. region":"United States","8. currency":"USD"},{"1. symbol":"BAD&KEY","2. name":"Unsafe","8. currency":"USD"}]}"#
        let results = try MarketDataParser.searchResults(from: Data(payload.utf8))
        #expect(results.map(\.symbol) == ["AAPL", "BRK.B"])
        #expect(results.first?.name == "Apple Inc.")
        #expect(results.first?.currency == "USD")
        #expect(!MarketDataParser.isValidSymbol("AAPL&apikey=secret"))
        #expect(!MarketDataParser.isValidSymbol(""))
    }

    @Test func marketProviderLimitResponseIsSurfacedAsLimitError() {
        let data = Data(#"{"Information":"Thank you for using Alpha Vantage! Our standard API call frequency is 25 requests per day."}"#.utf8)
        do {
            _ = try MarketDataParser.searchResults(from: data)
            Issue.record("Expected rate limit response to throw")
        } catch let error as MarketDataError {
            if case .providerLimit = error {} else { Issue.record("Expected providerLimit, got \(error)") }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test func stockAndWatchlistSettingsSurviveBackup() throws {
        var item = DockItem.widget("Watchlist")
        item.widgetConfiguration?.stockRange = .year
        item.widgetConfiguration?.stockRefreshIntervalMinutes = 720
        item.widgetConfiguration?.stockShowsVolume = true
        item.widgetConfiguration?.watchlistSelectedSymbol = "AAPL"
        item.widgetConfiguration?.watchlistStocks = [WatchlistStock(symbol: "AAPL", name: "Apple Inc.", customName: "My Apple", currency: "USD", snapshot: nil)]
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Markets", kind: .custom, items: [item])])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration

        #expect(restored?.stockRange == .year)
        #expect(restored?.stockRefreshIntervalMinutes == 720)
        #expect(restored?.stockShowsVolume == true)
        #expect(restored?.watchlistSelectedSymbol == "AAPL")
        #expect(restored?.watchlistStocks.first?.currency == "USD")
        #expect(restored?.watchlistStocks.first?.displayName == "My Apple")

        let legacy = #"{"symbol":"MSFT","name":"Microsoft","currency":"USD","snapshot":null}"#
        let legacyStock = try JSONDecoder().decode(WatchlistStock.self, from: Data(legacy.utf8))
        #expect(legacyStock.customName == nil)
        #expect(legacyStock.displayName == "Microsoft")
    }

    @Test func marketFinanceLinksValidateAndEncodeTickerSymbols() {
        #expect(MarketFinanceURL.url(for: " brk.b ")?.absoluteString == "https://finance.yahoo.com/quote/BRK.B")
        #expect(MarketFinanceURL.url(for: "AAPL/other") == nil)
        #expect(MarketFinanceURL.url(for: "") == nil)
    }

    @Test func calendarDateRefreshAppliesOnlyToCalendarApplications() {
        var calendar = DockItem.application(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        calendar.bundleIdentifier = CalendarAppIconPolicy.bundleIdentifier
        #expect(CalendarAppIconPolicy.requiresDateRefresh(calendar))
        #expect(!CalendarAppIconPolicy.requiresDateRefresh(.application(at: URL(fileURLWithPath: "/Applications/Notes.app"))))
        #expect(!CalendarAppIconPolicy.requiresDateRefresh(.widget("Calendar")))
    }

    @Test func nativeProfileColorSurvivesBackup() throws {
        let profile = DockProfile(name: "Blue Hour", kind: .native, items: [.spacer(.small)])
        var colored = profile
        colored.color = DockProfileColor.purple.rawValue
        let archive = try BackupManager.makeArchive(from: [colored])
        let restored = try BackupManager.readArchive(archive).importedProfiles.first
        #expect(restored?.kind == .native)
        #expect(restored?.color == DockProfileColor.purple.rawValue)
    }

    @Test func calendarCompactOrderingPrefersOngoingAndTimedMeetings() {
        let now = Date(timeIntervalSince1970: 10_000)
        let allDay = CalendarEventSnapshot(id: "all-day", title: "Holiday", startDate: now, endDate: now.addingTimeInterval(86_400), isAllDay: true, calendarID: "family", calendarTitle: "Family", meetingURL: nil)
        let soon = CalendarEventSnapshot(id: "soon", title: "Planning", startDate: now.addingTimeInterval(600), endDate: now.addingTimeInterval(3_600), isAllDay: false, calendarID: "work", calendarTitle: "Work", meetingURL: nil)
        let ongoing = CalendarEventSnapshot(id: "ongoing", title: "Stand-up", startDate: now.addingTimeInterval(-600), endDate: now.addingTimeInterval(600), isAllDay: false, calendarID: "work", calendarTitle: "Work", meetingURL: nil)

        #expect(CalendarEventOrdering.compactEvent(from: [allDay, soon], now: now)?.id == "soon")
        #expect(CalendarEventOrdering.compactEvent(from: [soon, ongoing, allDay], now: now)?.id == "ongoing")
    }

    @Test func alarmConfigurationSurvivesBackupWhileImportedScheduleStartsDisabled() throws {
        let alarm = DockAlarm(title: "Wake up", hour: 7, minute: 15, repeatWeekdays: [2, 4, 6], isEnabled: true)
        var item = DockItem.widget("Alarm")
        item.widgetConfiguration?.alarms = [alarm]
        let profile = DockProfile(name: "Morning", kind: .custom, items: [item])
        let archive = try BackupManager.makeArchive(from: [profile])
        let restoredAlarm = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration?.alarms.first
        #expect(restoredAlarm?.title == alarm.title)
        #expect(restoredAlarm?.hour == alarm.hour)
        #expect(restoredAlarm?.repeatWeekdays == alarm.repeatWeekdays)
        #expect(restoredAlarm?.isEnabled == false)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2024, month: 2, day: 4, hour: 8, minute: 30))!
        let once = AlarmSchedule.nextFireDate(hour: 7, minute: 15, now: now, calendar: calendar)
        let monday = AlarmSchedule.nextFireDate(hour: 7, minute: 15, repeatWeekdays: [2], now: now, calendar: calendar)
        let sunday = AlarmSchedule.nextFireDate(hour: 9, minute: 0, repeatWeekdays: [1], now: now, calendar: calendar)
        #expect(once == calendar.date(from: DateComponents(year: 2024, month: 2, day: 5, hour: 7, minute: 15)))
        #expect(monday == calendar.date(from: DateComponents(year: 2024, month: 2, day: 5, hour: 7, minute: 15)))
        #expect(sunday == calendar.date(from: DateComponents(year: 2024, month: 2, day: 4, hour: 9, minute: 0)))
        #expect(AlarmSchedule.nextFireDate(hour: 25, minute: 0, now: now, calendar: calendar) == nil)
    }

    @Test func alarmReconciliationRequiresOneCompleteNotificationGeneration() {
        let widgetID = UUID()
        let weekly = DockAlarm(title: "Weekdays", hour: 8, minute: 30, repeatWeekdays: [2, 4], isEnabled: true)
        let first = UUID()
        let second = UUID()
        let monday = AlarmNotificationService.repeatingID(widgetID: widgetID,
                                                           alarmID: weekly.id,
                                                           operationID: first,
                                                           weekday: 2)
        let thursdayFromOtherGeneration = AlarmNotificationService.repeatingID(widgetID: widgetID,
                                                                               alarmID: weekly.id,
                                                                               operationID: second,
                                                                               weekday: 4)
        #expect(!AlarmNotificationService.isScheduled(widgetID: widgetID,
                                                      alarm: weekly,
                                                      pending: [monday, thursdayFromOtherGeneration]))
        let thursday = AlarmNotificationService.repeatingID(widgetID: widgetID,
                                                             alarmID: weekly.id,
                                                             operationID: first,
                                                             weekday: 4)
        #expect(AlarmNotificationService.isScheduled(widgetID: widgetID,
                                                     alarm: weekly,
                                                     pending: [monday, thursday]))
        let prefix = AlarmNotificationService.notificationPrefix(widgetID: widgetID, alarmID: weekly.id)
        #expect(AlarmNotificationService.isScheduled(widgetID: widgetID,
                                                     alarm: weekly,
                                                     pending: [prefix + ".2", prefix + ".4"]))

        let once = DockAlarm(title: "Once", hour: 9, minute: 0, repeatWeekdays: [], isEnabled: true)
        let onceID = AlarmNotificationService.oneTimeID(widgetID: widgetID,
                                                        alarmID: once.id,
                                                        operationID: first)
        #expect(AlarmNotificationService.isScheduled(widgetID: widgetID,
                                                     alarm: once,
                                                     pending: [onceID]))
        #expect(!AlarmNotificationService.isScheduled(widgetID: UUID(),
                                                      alarm: once,
                                                      pending: [onceID]))
    }

    @Test func duplicatingProfileDisablesAlarmsWithOriginalNotificationIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Morning")
        var alarmItem = DockItem.widget("Alarm")
        alarmItem.widgetConfiguration?.alarms = [DockAlarm(title: "Wake", hour: 7, minute: 0, repeatWeekdays: [2], isEnabled: true)]
        store.add(alarmItem, to: profileID)
        try store.duplicateProfile(profileID)

        let copy = store.state.profiles.last
        #expect(copy?.items.first?.id != alarmItem.id)
        #expect(copy?.items.first?.widgetConfiguration?.alarms.first?.isEnabled == false)
    }

    @Test func duplicateWidgetCopiesConfigurationButDisablesNotificationSchedules() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Widgets")
        var note = DockItem.widget("Sticky Note")
        note.widgetConfiguration?.noteText = "Keep this detail"
        store.add(note, to: profileID)
        var alarm = DockItem.widget("Alarm")
        alarm.widgetConfiguration?.alarms = [DockAlarm(title: "Wake", hour: 7, minute: 0, repeatWeekdays: [], isEnabled: true)]
        store.add(alarm, to: profileID)

        let noteCopyID = try #require(store.duplicateWidget(note.id, in: profileID))
        let alarmCopyID = try #require(store.duplicateWidget(alarm.id, in: profileID))
        let copiedItems = store.state.profiles.first(where: { $0.id == profileID })?.items ?? []
        let copiedNote = try #require(copiedItems.first(where: { $0.id == noteCopyID }))
        let copiedAlarm = try #require(copiedItems.first(where: { $0.id == alarmCopyID }))

        #expect(noteCopyID != note.id)
        #expect(copiedNote.widgetConfiguration?.noteText == "Keep this detail")
        #expect(copiedAlarm.widgetConfiguration?.alarms.first?.isEnabled == false)
        #expect(copiedItems.first(where: { $0.id == alarm.id })?.widgetConfiguration?.alarms.first?.isEnabled == true)
    }

    @Test func widgetSetupDraftsSurviveViewRecreationButStayOutOfProfilesAndClearOnRemoval() throws {
        let itemID = UUID()
        let otherItemID = UUID()
        let drafts = WidgetSetupDraftStore.shared
        // Register cleanup before writing to the shared store, so a failure cannot leak drafts into other tests.
        defer { drafts.clearDrafts(for: itemID) }
        drafts.updateStripeDraft(for: itemID) {
            $0.accountName = "Revenue account"
            $0.restrictedKey = "rk_test_memory_only"
        }
        drafts.updatePaddleDraft(for: itemID) {
            $0.accountName = "Billing account"
            $0.apiKey = "pdl_memory_only"
        }
        drafts.updateShopifyDraft(for: itemID) {
            $0.domain = "store.myshopify.com"
            $0.clientID = "client_memory_only"
            $0.clientSecret = "secret_memory_only"
        }
        let city = WeatherLocation(id: "warsaw", name: "Warsaw", administrativeArea: "Masovian", country: "Poland",
                                   latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw")
        drafts.updateWeatherDraft(for: itemID) {
            $0.searchText = "Warsaw"
            $0.isChangingLocation = true
            $0.searchResults = [city]
        }

        // A newly reconstructed popout asks the same owner for the existing draft.
        #expect(drafts.stripeDraft(for: itemID).restrictedKey == "rk_test_memory_only")
        #expect(drafts.paddleDraft(for: itemID).apiKey == "pdl_memory_only")
        #expect(drafts.shopifyDraft(for: itemID).clientSecret == "secret_memory_only")
        #expect(drafts.weatherDraft(for: itemID).searchResults == [city])
        #expect(drafts.stripeDraft(for: otherItemID).isPristine)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Setup drafts")
        var stripeWidget = DockItem.widget("Stripe")
        stripeWidget.id = itemID
        store.add(stripeWidget, to: profileID)
        let stateJSON = String(decoding: try JSONEncoder().encode(store.state), as: UTF8.self)
        let backupJSON = String(decoding: try BackupManager.makeArchive(from: store.state.profiles), as: UTF8.self)
        for secret in ["rk_test_memory_only", "pdl_memory_only", "client_memory_only", "secret_memory_only"] {
            #expect(!stateJSON.contains(secret))
            #expect(!backupJSON.contains(secret))
        }

        store.removeItem(itemID, from: profileID)
        #expect(drafts.stripeDraft(for: itemID).isPristine)
        #expect(drafts.paddleDraft(for: itemID).isPristine)
        #expect(drafts.shopifyDraft(for: itemID).isPristine)
        #expect(drafts.weatherDraft(for: itemID).isPristine)
    }

    @Test func pendingStickyNoteDraftFlushesBeforeQuitAndClearsOnRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Notes")
        let note = DockItem.widget("Sticky Note")
        store.add(note, to: profileID)
        let drafts = WidgetSetupDraftStore.shared
        defer { drafts.clearDrafts(for: note.id) }

        drafts.updateNoteDraft("Older edit", for: note.id, in: profileID)
        drafts.updateNoteDraft("Latest edit", for: note.id, in: profileID)
        try drafts.saveNote("Older edit", for: note.id, in: profileID, to: store)
        #expect(drafts.hasPendingNotes)
        drafts.flushNotes(to: store)
        #expect(!drafts.hasPendingNotes)
        let restored = ProfileStore(fileURL: file)
        #expect(restored.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == note.id })?.widgetConfiguration?.noteText == "Latest edit")

        drafts.updateNoteDraft("Discarded edit", for: note.id, in: profileID)
        store.removeItem(note.id, from: profileID)
        #expect(!drafts.hasPendingNotes)
    }

    @Test func disconnectingSharedProviderAccountClearsEveryReferencingWidget() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let firstProfile = try store.createProfileAndPersist(kind: .custom, name: "First finance Dock")
        let secondProfile = try store.createProfileAndPersist(kind: .custom, name: "Second finance Dock")

        func connectedWidget(_ kind: String, id: String) -> DockItem {
            var item = DockItem.widget(kind)
            switch kind {
            case "Stripe": item.widgetConfiguration?.stripeAccountID = id
            case "Paddle": item.widgetConfiguration?.paddleAccountID = id
            case "Shopify": item.widgetConfiguration?.shopifyStoreID = id
            default: break
            }
            return item
        }

        var stripeFirst = connectedWidget("Stripe", id: "stripe-shared")
        stripeFirst.widgetConfiguration?.stripeSnapshot = StripeSnapshot(
            accountID: "stripe-shared", accountName: "Shared", fetchedAt: .now,
            period: .sevenDays, periodStart: .now, periodEnd: .now,
            currencies: [], unsupportedSubscriptionItems: 0)
        let stripeSecond = connectedWidget("Stripe", id: "stripe-shared")
        let stripeOther = connectedWidget("Stripe", id: "stripe-other")
        var paddleFirst = connectedWidget("Paddle", id: "paddle-shared")
        paddleFirst.widgetConfiguration?.paddleSnapshot = PaddleSnapshot(
            accountID: "paddle-shared", accountName: "Shared", fetchedAt: .now,
            period: .sevenDays, currency: "USD", points: [], updatedAt: .now)
        let paddleSecond = connectedWidget("Paddle", id: "paddle-shared")
        var shopifyFirst = connectedWidget("Shopify", id: "shopify-shared")
        shopifyFirst.widgetConfiguration?.shopifySnapshot = ShopifySnapshot(
            storeID: "shopify-shared", storeName: "Shared", storeDomain: "shared.myshopify.com",
            fetchedAt: .now, period: .monthToDate, periodStart: .now, periodEnd: .now,
            timeZoneID: "UTC", currency: "USD", orderValue: 0, orderCount: 0,
            dailyPoints: [], productBreakdown: [], trafficBreakdown: [],
            productBreakdownIncompleteOrders: 0, trafficAttributedOrders: 0)
        let shopifySecond = connectedWidget("Shopify", id: "shopify-shared")
        for item in [stripeFirst, paddleFirst, shopifyFirst] { store.add(item, to: firstProfile) }
        for item in [stripeSecond, stripeOther, paddleSecond, shopifySecond] { store.add(item, to: secondProfile) }

        store.clearConnectionReferences(.stripe("stripe-shared"))
        store.clearConnectionReferences(.paddle("paddle-shared"))
        store.clearConnectionReferences(.shopify("shopify-shared"))
        let restored = ProfileStore(fileURL: file)
        let items = Dictionary(uniqueKeysWithValues: restored.state.profiles.flatMap(\.items).map { ($0.id, $0) })
        #expect(items[stripeFirst.id]?.widgetConfiguration?.stripeAccountID == "")
        #expect(items[stripeFirst.id]?.widgetConfiguration?.stripeSnapshot == nil)
        #expect(items[stripeSecond.id]?.widgetConfiguration?.stripeAccountID == "")
        #expect(items[stripeOther.id]?.widgetConfiguration?.stripeAccountID == "stripe-other")
        #expect(items[paddleFirst.id]?.widgetConfiguration?.paddleAccountID == "")
        #expect(items[paddleFirst.id]?.widgetConfiguration?.paddleSnapshot == nil)
        #expect(items[paddleSecond.id]?.widgetConfiguration?.paddleAccountID == "")
        #expect(items[shopifyFirst.id]?.widgetConfiguration?.shopifyStoreID == "")
        #expect(items[shopifyFirst.id]?.widgetConfiguration?.shopifySnapshot == nil)
        #expect(items[shopifySecond.id]?.widgetConfiguration?.shopifyStoreID == "")
    }

    @Test func duplicatingProfileResetsCountdownRunState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Timers")
        var countdown = DockItem.widget("Countdown")
        countdown.widgetConfiguration?.countdownDurationSeconds = 600
        countdown.widgetConfiguration?.startCountdown(at: Date(timeIntervalSince1970: 100))
        store.add(countdown, to: profileID)
        try store.duplicateProfile(profileID)

        let copiedConfiguration = store.state.profiles.last?.items.first?.widgetConfiguration
        #expect(copiedConfiguration?.countdownDurationSeconds == 600)
        #expect(copiedConfiguration?.countdownStartedAt == nil)
        #expect(copiedConfiguration?.countdownRemaining(at: Date(timeIntervalSince1970: 500)) == 600)
        try? FileManager.default.removeItem(at: directory)
    }

    @Test func duplicatingDateCountdownKeepsTargetConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Deadlines")
        let target = Date(timeIntervalSince1970: 2_000_000_000)
        var countdown = DockItem.widget("Countdown")
        countdown.widgetConfiguration?.setCountdownTarget(target)
        store.add(countdown, to: profileID)

        try store.duplicateProfile(profileID)

        let copiedItem = store.state.profiles.last?.items.first
        #expect(copiedItem?.id != countdown.id)
        #expect(copiedItem?.widgetConfiguration?.countdownMode == .targetDate)
        #expect(copiedItem?.widgetConfiguration?.countdownTargetDate == target)
    }

    @Test func hydrationHistoryTracksIncompleteVolumesAndUndoPreservesEntry() {
        var calendar = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") { calendar.timeZone = utc }
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        var configuration = WidgetConfiguration()
        let firstLogged = configuration.logHydrationDrink(at: today)
        #expect(firstLogged)
        configuration.hydrationTrackAmounts = false
        let secondLogged = configuration.logHydrationDrink(at: today.addingTimeInterval(60))
        #expect(secondLogged)
        configuration.hydrationTrackAmounts = true

        #expect(configuration.hydrationEntriesToday(at: today, calendar: calendar).count == 2)
        #expect(configuration.hydrationVolumeSummary(at: today, calendar: calendar) == "At least \(DockNumberText.milliliters(250)) · incomplete")

        guard let unknown = configuration.hydrationEntries.last else {
            Issue.record("Expected the time-only drink entry")
            return
        }
        configuration.removeHydrationEntry(id: unknown.id)
        configuration.undoHydrationRemoval()
        let restored = configuration.hydrationEntries.first { $0.id == unknown.id }
        #expect(restored?.timestamp == unknown.timestamp)
        #expect(restored?.amountML == nil)

        configuration.hydrationSaveHistory = false
        let thirdLogged = configuration.logHydrationDrink(at: today.addingTimeInterval(120))
        #expect(!thirdLogged)
        #expect(configuration.hydrationEntries.count == 2)
    }

    @Test func hydrationReminderGenerationPreventsOlderSchedulesFromWinning() {
        var generations = WidgetNotificationGenerationPolicy()
        let itemID = UUID()
        let first = UUID()
        let second = UUID()
        generations.begin(itemID: itemID, operationID: first)
        #expect(generations.isCurrent(itemID: itemID, operationID: first))
        generations.begin(itemID: itemID, operationID: second)
        #expect(!generations.isCurrent(itemID: itemID, operationID: first))
        #expect(generations.isCurrent(itemID: itemID, operationID: second))
        #expect(HydrationReminderService.notificationID(for: itemID, operationID: first) !=
                HydrationReminderService.notificationID(for: itemID, operationID: second))
        #expect(HydrationReminderService.notificationPrefix(for: itemID) == "mydock.hydration.\(itemID.uuidString)")
    }

    @Test func batteryReaderHandlesMissingAndOutOfRangeValues() {
        let reading = BatteryReader.reading(from: [
            "Name": "MacBook",
            "Current Capacity": 142,
            "Max Capacity": 100,
            "Is Charging": true,
            "Type": "InternalBattery"
        ])
        #expect(reading?.percentage == 100)
        #expect(reading?.isCharging == true)
        #expect(reading?.isInternal == true)
        #expect(BatteryReader.reading(from: ["Name": "Unknown"]) == nil)
        #expect(BatteryReader.reading(from: ["Current Capacity": 20, "Max Capacity": 0]) == nil)
    }

    @Test func cpuUsageUsesTickDeltasAndIgnoresUnchangedSamples() {
        let previous = HostCPUTicks(user: 20, system: 20, idle: 50, nice: 10)
        let current = HostCPUTicks(user: 70, system: 30, idle: 80, nice: 20)
        #expect(CPUUsageCalculator.percentage(from: previous, to: current) == 70)
        #expect(CPUUsageCalculator.percentage(from: previous, to: previous) == nil)
    }

    @Test func perCoreCPUUsageCalculatesEachLogicalProcessorIndependently() {
        let previous = [
            HostCPUTicks(user: 10, system: 0, idle: 90, nice: 0),
            HostCPUTicks(user: 50, system: 0, idle: 50, nice: 0)
        ]
        let current = [
            HostCPUTicks(user: 30, system: 0, idle: 170, nice: 0),
            HostCPUTicks(user: 90, system: 0, idle: 110, nice: 0)
        ]

        #expect(PerCoreCPUUsageCalculator.percentages(previous: previous, current: current) == [20, 40])
        #expect(PerCoreCPUUsageCalculator.percentages(previous: previous, current: [current[0]]) == nil)
    }

    @Test func systemActivityReaderReturnsLiveCoreThermalAndLoadSnapshot() {
        let reading = SystemActivityReader.read()
        #expect(reading != nil)
        #expect(reading?.perCoreCPUTicks?.isEmpty == false)
        #expect(reading?.loadAverage != nil)
        #expect((reading?.systemUptime ?? 0) > 0)
        #expect((reading?.memory.totalBytes ?? 0) > 0)
        #expect((reading?.memory.activeBytes ?? 0) > 0)
        #expect((reading?.startupVolume?.totalBytes ?? 0) > 0)
    }

    @Test func storageScannerCountsVisibleFilesAndSortsLargestFirst() throws {
        final class ProgressSink: @unchecked Sendable {
            private let lock = NSLock()
            private var value: StorageScanProgress?
            func record(_ progress: StorageScanProgress) {
                lock.lock(); value = progress; lock.unlock()
            }
            var latest: StorageScanProgress? {
                lock.lock(); defer { lock.unlock() }; return value
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("small.bin"))
        try Data(repeating: 2, count: 120).write(to: root.appendingPathComponent("large.bin"))
        try Data(repeating: 3, count: 500).write(to: root.appendingPathComponent(".hidden.bin"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Folder", isDirectory: true), withIntermediateDirectories: true)
        try Data(repeating: 4, count: 20).write(to: root.appendingPathComponent("Folder/nested.bin"))

        let progress = ProgressSink()
        let result = try StorageScanner.scan(at: root, onProgress: { progress.record($0) })

        #expect(result.scannedFileCount == 3)
        #expect(result.scannedBytes == 150)
        #expect(result.largestFiles.map(\.name) == ["large.bin", "nested.bin", "small.bin"])
        #expect(progress.latest?.scannedFileCount == result.scannedFileCount)
        #expect(progress.latest?.scannedBytes == result.scannedBytes)
    }

    @Test func storageScannerHonorsCancellationBeforeReading() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cancellation = StorageScanCancellationFlag()
        cancellation.cancel()
        do {
            _ = try StorageScanner.scan(at: root, cancellation: cancellation)
            Issue.record("Cancelled scan unexpectedly completed")
        } catch StorageScanner.ScanError.cancelled {
            #expect(cancellation.isCancelled)
        }
    }

    @Test func systemActivitySamplingStopsWhenDockIsHiddenOrUnused() {
        #expect(SystemActivitySamplingPolicy.shouldSample(dockIsVisible: true, subscriberCount: 1))
        #expect(!SystemActivitySamplingPolicy.shouldSample(dockIsVisible: false, subscriberCount: 1))
        #expect(!SystemActivitySamplingPolicy.shouldSample(dockIsVisible: true, subscriberCount: 0))
    }

    @Test func networkRatesUseElapsedTimeAndHandleCounterWrap() {
        let before = NetworkCountersReading(uptime: 10,
                                            interfaces: [NetworkInterfaceCounters(name: "en0", receivedBytes: 1_000, sentBytes: 400, addresses: ["192.0.2.10"])])
        let after = NetworkCountersReading(uptime: 12,
                                           interfaces: [NetworkInterfaceCounters(name: "en0", receivedBytes: 2_000, sentBytes: 800, addresses: ["192.0.2.10"])])
        let rates = NetworkRateCalculator.rates(previous: before, current: after)
        #expect(rates.first?.receivedBytesPerSecond == 500)
        #expect(rates.first?.sentBytesPerSecond == 200)
        #expect(rates.first?.addresses == ["192.0.2.10"])
        #expect(NetworkRateCalculator.counterDelta(from: UInt64(UInt32.max) - 5, to: 3) == 9)

        let unavailableBefore = NetworkCountersReading(uptime: 1, interfaces: [NetworkInterfaceCounters(name: "en7", receivedBytes: nil, sentBytes: nil, addresses: [])])
        let unavailableAfter = NetworkCountersReading(uptime: 2, interfaces: [NetworkInterfaceCounters(name: "en7", receivedBytes: nil, sentBytes: nil, addresses: [])])
        #expect(NetworkRateCalculator.rates(previous: unavailableBefore, current: unavailableAfter).first?.receivedBytesPerSecond == nil)
    }

    @Test func runningApplicationFilterOmitsPinnedAgentsAndTerminatedApps() {
        func app(_ bundleID: String, _ name: String, regular: Bool = true, terminated: Bool = false) -> RunningApplicationDescriptor {
            RunningApplicationDescriptor(bundleIdentifier: bundleID, name: name,
                                         bundleURL: URL(fileURLWithPath: "/Applications/\(name).app"),
                                         isRegularApplication: regular, isTerminated: terminated)
        }
        let values = [
            app("com.example.pinned", "Pinned"),
            app("com.example.agent", "Agent", regular: false),
            app("com.example.closed", "Closed", terminated: true),
            app("com.example.zebra", "Zebra"),
            app("com.example.alpha", "Alpha")
        ]

        let visible = RunningApplicationFilter.visible(values, excluding: ["com.example.pinned"])

        #expect(visible.map(\.name) == ["Alpha", "Zebra"])
        #expect(visible.first?.isRegularApplication == true)
        #expect(visible.last?.isRegularApplication == true)
    }

    @Test func windowPreviewsMatchOnlyUniqueVisibleWindowTitles() {
        let visible = DockWindowDescriptor(processID: 42, windowIndex: 0, bundleIdentifier: "com.example.app",
                                           applicationName: "Example", title: "Document", isMinimized: false,
                                           accessibilityIdentifier: "window-one")
        var minimized = visible
        minimized.windowIndex = 1
        minimized.accessibilityIdentifier = "window-two"
        minimized.title = "Hidden"
        minimized.isMinimized = true
        let candidate = WindowPreviewCandidate(windowID: 7, processID: 42, title: "Document",
                                               isOnScreen: true, width: 800, height: 600)

        let matches = WindowPreviewMatchingPolicy.matchedWindowIDs(descriptors: [visible, minimized],
                                                                    candidates: [candidate])
        #expect(matches == [visible.id: 7])
        #expect(WindowPreviewMatchingPolicy.matchedWindowIDs(descriptors: [visible],
            candidates: [candidate, WindowPreviewCandidate(windowID: 8, processID: 42, title: "Document",
                                                            isOnScreen: true, width: 800, height: 600)]).isEmpty)
        #expect(WindowPreviewMatchingPolicy.matchedWindowIDs(descriptors: [visible],
            candidates: [WindowPreviewCandidate(windowID: 9, processID: 42, title: "Document",
                                                isOnScreen: false, width: 800, height: 600)]).isEmpty)
    }

    @Test func autoHideRevealPolicyKeepsDockVisibleForDockHandleAndPopout() {
        let dock = NSRect(x: 100, y: 100, width: 300, height: 70)
        let handle = NSRect(x: 230, y: 20, width: 40, height: 6)
        let popout = NSRect(x: 150, y: 175, width: 200, height: 160)

        #expect(CustomDockVisibilityPolicy.shouldReveal(mouseLocation: NSPoint(x: 200, y: 120), expandedFrame: dock, revealFrame: handle))
        #expect(CustomDockVisibilityPolicy.shouldReveal(mouseLocation: NSPoint(x: 250, y: 23), expandedFrame: dock, revealFrame: handle))
        #expect(CustomDockVisibilityPolicy.shouldReveal(mouseLocation: NSPoint(x: 175, y: 185), expandedFrame: dock, revealFrame: handle, popoutFrames: [popout]))
        #expect(!CustomDockVisibilityPolicy.shouldReveal(mouseLocation: NSPoint(x: 700, y: 500), expandedFrame: dock, revealFrame: handle))
        #expect(CustomDockVisibilityPolicy.showsSystemTrash(isEnabled: true, hasProfileTrashWidget: false))
        #expect(!CustomDockVisibilityPolicy.showsSystemTrash(isEnabled: false, hasProfileTrashWidget: false))
        #expect(!CustomDockVisibilityPolicy.showsSystemTrash(isEnabled: true, hasProfileTrashWidget: true))
        #expect(WindowAccessibilityService.shouldMinimizeFocusedApp(toggleEnabled: true, clickedBundleIdentifier: "com.example.app", frontmostBundleIdentifier: "com.example.app", hasFocusedWindow: true))
        #expect(!WindowAccessibilityService.shouldMinimizeFocusedApp(toggleEnabled: false, clickedBundleIdentifier: "com.example.app", frontmostBundleIdentifier: "com.example.app", hasFocusedWindow: true))
        #expect(!WindowAccessibilityService.shouldMinimizeFocusedApp(toggleEnabled: true, clickedBundleIdentifier: "com.example.app", frontmostBundleIdentifier: "com.example.other", hasFocusedWindow: true))
        #expect(!WindowAccessibilityService.shouldMinimizeFocusedApp(toggleEnabled: true, clickedBundleIdentifier: "com.example.app", frontmostBundleIdentifier: "com.example.app", hasFocusedWindow: false))
    }

    @Test func dockOverflowJumpControlsOnlyAppearWhenContentExceedsViewport() {
        #expect(!DockOverflowPolicy.needsJumpControls(contentLength: 300, viewportLength: 300))
        #expect(!DockOverflowPolicy.needsJumpControls(contentLength: 300.5, viewportLength: 300))
        #expect(DockOverflowPolicy.needsJumpControls(contentLength: 302, viewportLength: 300))
    }

    @Test func dockPopoutTabsKeepTheirOriginalAnchorAndRecoverWhenClosed() {
        let first = UUID()
        let second = UUID()
        var selection = DockPopoutSelection()

        selection.toggle(first)
        selection.toggle(second)
        #expect(selection.anchorID == first)
        #expect(selection.activeID == second)
        #expect(selection.tabIDs == [first, second])

        selection.select(first)
        #expect(selection.anchorID == first)
        #expect(selection.activeID == first)
        selection.close(first)
        #expect(selection.anchorID == second)
        #expect(selection.activeID == second)
        selection.close(second)
        #expect(selection.anchorID == nil)
        #expect(selection.tabIDs.isEmpty)
    }

    @Test func folderIconCustomizationRoundTripsAndOlderItemsDecode() throws {
        let legacy = #"{"id":"00000000-0000-0000-0000-000000000001","type":"folder","title":"Projects","url":"file:///tmp/Projects"}"#
        let restoredLegacy = try JSONDecoder().decode(DockItem.self, from: Data(legacy.utf8))
        #expect(!restoredLegacy.hasCustomFolderIcon)
        #expect(restoredLegacy.folderIconColor == nil)
        #expect(!restoredLegacy.showsFolderLabel)
        #expect(restoredLegacy.displayName == "Projects")

        var customized = DockItem.file(at: URL(fileURLWithPath: "/tmp/Projects"), isFolder: true)
        #expect(customized.title == "Projects")
        customized.folderCustomName = "Client Work"
        customized.showFolderLabel = true
        customized.folderIconColor = .purple
        customized.folderIconLetter = "P"
        customized.folderIconNumber = "12"
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Folder Icons", kind: .custom, items: [customized])])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0]
        #expect(restored.folderIconColor == .purple)
        #expect(restored.folderIconLetter == "P")
        #expect(restored.folderIconNumber == "12")
        #expect(restored.folderCustomName == "Client Work")
        #expect(restored.showsFolderLabel)
        #expect(restored.displayName == "Client Work")
        #expect(restored.hasCustomFolderIcon)

        var resetName = restored
        resetName.folderCustomName = "   "
        #expect(resetName.displayName == "Projects")

        let dottedFolder = DockItem.file(at: URL(fileURLWithPath: "/tmp/Archive.2026"), isFolder: true)
        #expect(dottedFolder.displayName == "Archive.2026")
    }

    @Test func dockRevealEdgeRequiresDwellWhileDockAndPopoutsRevealImmediately() {
        let dock = NSRect(x: 100, y: 20, width: 300, height: 80)
        let reveal = NSRect(x: 220, y: 0, width: 40, height: 6)
        let popout = NSRect(x: 150, y: 175, width: 200, height: 160)

        #expect(!CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: NSPoint(x: 240, y: 3), expandedFrame: dock))
        #expect(CustomDockVisibilityPolicy.isAtRevealEdge(mouseLocation: NSPoint(x: 240, y: 3), revealFrame: reveal))
        #expect(CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: NSPoint(x: 200, y: 40), expandedFrame: dock))
        #expect(CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: NSPoint(x: 175, y: 185), expandedFrame: dock, popoutFrames: [popout]))
    }

    @Test func refreshIntervalsAreBoundedAndRejectNonFiniteValues() {
        #expect(RefreshSchedulePolicy.normalizedInterval(0) == 1)
        #expect(RefreshSchedulePolicy.normalizedInterval(12) == 12)
        #expect(RefreshSchedulePolicy.normalizedInterval(.infinity) == 60)
        #expect(RefreshSchedulePolicy.normalizedInterval(100_000) == 86_400)
    }

    @Test func customDockCanHideOnlyForAnOverlappingVisibleSystemDock() {
        let customDock = NSRect(x: 100, y: 20, width: 300, height: 80)
        let overlappingSystemDock = NSRect(x: 200, y: 0, width: 500, height: 100)
        let separateSystemDock = NSRect(x: 800, y: 0, width: 400, height: 100)

        #expect(SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: customDock,
                                                             systemDockFrames: [overlappingSystemDock]))
        #expect(!SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: customDock,
                                                              systemDockFrames: [separateSystemDock]))
        #expect(!SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: customDock,
                                                              systemDockFrames: []))
    }

    @Test func perpendicularTrackpadSwipeCyclesDockProfilesAndRejectsWheelNoise() {
        #expect(DockProfileSwipePolicy.destinationIndex(currentIndex: 0, perpendicularDelta: 60, parallelDelta: 10, profileCount: 3) == 1)
        #expect(DockProfileSwipePolicy.destinationIndex(currentIndex: 0, perpendicularDelta: -60, parallelDelta: 10, profileCount: 3) == 2)
        #expect(DockProfileSwipePolicy.destinationIndex(currentIndex: 2, perpendicularDelta: 55, parallelDelta: 5, profileCount: 3) == 0)
        #expect(DockProfileSwipePolicy.destinationIndex(currentIndex: 0, perpendicularDelta: 47, parallelDelta: 0, profileCount: 3) == nil)
        #expect(DockProfileSwipePolicy.destinationIndex(currentIndex: 0, perpendicularDelta: 80, parallelDelta: 70, profileCount: 3) == nil)
        #expect(DockProfileSwipePolicy.destinationIndex(currentIndex: 0, perpendicularDelta: 80, parallelDelta: 5, profileCount: 1) == nil)
    }

    @Test func folderContentsReaderSortsFoldersBeforeFilesAndSkipsHiddenItems() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let childFolder = root.appendingPathComponent("A Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("Z File.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden"))
        defer { try? FileManager.default.removeItem(at: root) }

        let entries = try FolderContentsReader.entries(at: root)

        #expect(entries.map(\.name) == ["A Folder", "Z File.txt"])
        #expect(entries.first?.isDirectory == true)
        #expect(entries.last?.isDirectory == false)
    }

    @Test func appFolderWidgetConfigurationSurvivesBackupRoundTrip() throws {
        var folder = DockItem.widget("App Folder")
        let calculator = AppFolderApplication(url: URL(fileURLWithPath: "/System/Applications/Calculator.app"))
        folder.widgetConfiguration?.appFolderName = "Utilities"
        folder.widgetConfiguration?.appFolderColor = "teal"
        folder.widgetConfiguration?.appFolderLetter = "ut"
        folder.widgetConfiguration?.appFolderApplications = [calculator]
        let profile = DockProfile(name: "Tools", kind: .custom, items: [folder])

        let archive = try BackupManager.makeArchive(from: [profile])
        let restored = try BackupManager.readArchive(archive).importedProfiles.first?.items.first?.widgetConfiguration

        #expect(restored?.appFolderName == "Utilities")
        #expect(restored?.appFolderColor == "teal")
        #expect(restored?.appFolderLetter == "UT")
        #expect(restored?.appFolderApplications == [calculator])
        #expect(calculator.hasExistingBundlePath)
        #expect(!AppFolderApplication(url: URL(fileURLWithPath: "/missing/MyDock-Example.app")).hasExistingBundlePath)
    }

    @Test func shortcutWidgetSelectionPersistsAndCatalogParserIsStable() throws {
        var shortcut = DockItem.widget("Shortcuts")
        shortcut.widgetConfiguration?.selectedShortcutName = "Open Notes"
        let profile = DockProfile(name: "Launchers", kind: .custom, items: [shortcut])
        let archive = try BackupManager.makeArchive(from: [profile])
        let restoredName = try BackupManager.readArchive(archive).importedProfiles.first?.items.first?.widgetConfiguration?.selectedShortcutName

        #expect(restoredName == "Open Notes")
        #expect(ShortcutCatalogParser.parse("\nZulu\nAlpha\nZulu\n") == ["Alpha", "Zulu"])
    }

    @Test func countdownTargetDateSurvivesProfileBackup() throws {
        let target = Date(timeIntervalSince1970: 2_000_000_000)
        var countdown = DockItem.widget("Countdown")
        countdown.widgetConfiguration?.setCountdownTarget(target)
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Deadlines", kind: .custom, items: [countdown])])
        let restored = try BackupManager.readArchive(archive).importedProfiles.first?.items.first?.widgetConfiguration

        #expect(restored?.countdownMode == .targetDate)
        #expect(restored?.countdownTargetDate == target)
    }

    @Test func globalShortcutBindingsPersistOutsideProfileBackupsAndRejectDuplicates() throws {
        let defaults = ValidationDefaults()
        let profileID = UUID()
        let binding = DockShortcut(keyCode: 12,
                                   modifierMask: DockShortcut.commandMask | DockShortcut.optionMask,
                                   keyLabel: "Q")
        let store = DockShortcutStore(defaults: defaults)
        try store.set(binding, for: profileID)

        let reloaded = DockShortcutStore(defaults: defaults)
        #expect(reloaded.shortcut(for: profileID) == binding)
        #expect(binding.displayString == "⌥⌘Q")

        let duplicate = DockShortcut(keyCode: 12,
                                     modifierMask: DockShortcut.commandMask | DockShortcut.optionMask,
                                     keyLabel: "Q")
        var duplicateRejected = false
        do { try store.set(duplicate, for: UUID()) } catch { duplicateRejected = true }
        #expect(duplicateRejected)

        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Shortcut", kind: .custom)])
        #expect(String(decoding: archive, as: UTF8.self).contains("keyCode") == false)
    }

    @Test func backupRestoreAddsIndependentCopiesAndReportsMissingPaths() throws {
        let missingPath = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).app")
        var note = DockItem.widget("Sticky Note")
        note.widgetConfiguration?.noteText = "Pack a charger"
        var hydration = DockItem.widget("Hydration")
        hydration.widgetConfiguration?.hydrationRemindersEnabled = true
        var appFolder = DockItem.widget("App Folder")
        appFolder.widgetConfiguration?.appFolderName = "Work"
        let nestedMissingPath = FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).app")
        appFolder.widgetConfiguration?.appFolderApplications = [AppFolderApplication(url: nestedMissingPath)]
        let profile = DockProfile(name: "Travel", kind: .custom,
                                  items: [.application(at: missingPath), note, hydration, appFolder])
        let archive = try BackupManager.makeArchive(from: [profile])
        let report = try BackupManager.readArchive(archive)

        #expect(report.importedProfiles.count == 1)
        #expect(report.importedProfiles[0].id != profile.id)
        #expect(report.importedProfiles[0].items[0].id != profile.items[0].id)
        #expect(report.missingItems.count == 2)
        #expect(report.missingItems[0].contains(missingPath.path))
        #expect(report.missingItems[1].contains(nestedMissingPath.path))
        #expect(report.importedProfiles[0].items[1].widgetConfiguration?.noteText == "Pack a charger")
        #expect(report.importedProfiles[0].items[2].widgetConfiguration?.hydrationRemindersEnabled == false)
    }

    @Test func backupImportBoundsFileReadBeforeDecoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiveURL = directory.appendingPathComponent("MyDock-Backup.json")
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Portable", kind: .custom)])
        try archive.write(to: archiveURL)
        #expect(try BackupManager.readArchive(from: archiveURL).importedProfiles.count == 1)
        #expect(try BackupManager.boundedArchiveData(from: archiveURL, maximumBytes: archive.count) == archive)
        #expect(throws: BackupError.self) {
            try BackupManager.boundedArchiveData(from: archiveURL, maximumBytes: archive.count - 1)
        }
        #expect(throws: BackupError.self) {
            try BackupManager.boundedArchiveData(from: directory)
        }
    }

    @Test func backupRejectsInvalidLinkScheme() {
        let item = DockItem(type: .link, title: "unsafe", url: URL(fileURLWithPath: "/tmp/unsafe"))
        let profile = DockProfile(name: "Links", kind: .custom, items: [item])
        #expect(throws: BackupError.self) { try BackupManager.makeArchive(from: [profile]) }
        let credentialLink = DockItem(type: .link, title: "credential URL",
                                      url: URL(string: "https://user:secret@example.com/path"))
        #expect(throws: BackupError.self) {
            try BackupManager.makeArchive(from: [DockProfile(name: "Links", kind: .custom,
                                                              items: [credentialLink])])
        }
    }

    @Test func backupRejectsRemoteAppFolderApplication() {
        var folder = DockItem.widget("App Folder")
        folder.widgetConfiguration?.appFolderApplications = [
            AppFolderApplication(url: URL(string: "https://example.com/NotAnApp.app")!)
        ]
        let profile = DockProfile(name: "Invalid", kind: .custom, items: [folder])
        #expect(throws: BackupError.self) { try BackupManager.makeArchive(from: [profile]) }
    }

    @Test func linkPolicyRequiresSafeWebDestination() {
        #expect(DockLinkPolicy.validatedURL(" https://example.com/path ")?.host == "example.com")
        #expect(DockLinkPolicy.validatedURL("http://localhost:8080")?.scheme == "http")
        #expect(DockLinkPolicy.validatedURL("file:///tmp/private") == nil)
        #expect(DockLinkPolicy.validatedURL("mailto:user@example.com") == nil)
        #expect(DockLinkPolicy.validatedURL("https://user:secret@example.com") == nil)
        #expect(DockLinkPolicy.validatedURL("example.com") == nil)
        #expect(DockLinkPolicy.validatedURL("https://") == nil)
    }

    @Test func linkNameAndSymbolRoundTripThroughBackupAndLegacyDecode() throws {
        var link = DockItem.link(URL(string: "https://example.com/docs")!, title: "Reference", icon: .docText)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                   pixelsWide: 1,
                                                   pixelsHigh: 1,
                                                   bitsPerSample: 8,
                                                   samplesPerPixel: 4,
                                                   hasAlpha: true,
                                                   isPlanar: false,
                                                   colorSpaceName: .deviceRGB,
                                                   bytesPerRow: 0,
                                                   bitsPerPixel: 0))
        let siteIcon = try #require(bitmap.representation(using: .png, properties: [:]))
        link.linkFaviconData = siteIcon
        let profile = DockProfile(name: "Links", kind: .custom, items: [link])
        let restored = try BackupManager.readArchive(BackupManager.makeArchive(from: [profile]))
            .importedProfiles[0].items[0]

        #expect(restored.title == "Reference")
        #expect(restored.url?.absoluteString == "https://example.com/docs")
        #expect(restored.linkIcon == .docText)
        #expect(restored.linkFaviconData == SiteFaviconFetcher.normalizedPNG(from: siteIcon))

        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","type":"link","title":"Old link","url":"https://example.com"}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(DockItem.self, from: legacy)
        #expect(decodedLegacy.title == "Old link")
        #expect(decodedLegacy.linkIcon == nil)
    }

    @Test func siteIconDiscoveryAllowsOnlySafeHTTPSOrigins() {
        #expect(SiteFaviconFetcher.faviconURL(for: URL(string: "https://example.com/path")!)?.absoluteString == "https://example.com/favicon.ico")
        #expect(SiteFaviconFetcher.faviconURL(for: URL(string: "http://example.com/path")!) == nil)
        #expect(SiteFaviconFetcher.faviconURL(for: URL(string: "https://127.0.0.1/path")!) == nil)
        #expect(SiteFaviconFetcher.faviconURL(for: URL(string: "https://192.168.1.2/path")!) == nil)
        #expect(SiteFaviconFetcher.faviconURL(for: URL(string: "https://service.local/path")!) == nil)
        #expect(SiteFaviconFetcher.faviconURL(for: URL(string: "https://user:secret@example.com/path")!) == nil)
    }

    @Test func backupRejectsMalformedSiteIconData() {
        var item = DockItem.link(URL(string: "https://example.com")!, title: "Example")
        item.linkFaviconData = Data([0, 1, 2, 3])
        let profile = DockProfile(name: "Links", kind: .custom, items: [item])
        #expect(throws: BackupError.self) { try BackupManager.makeArchive(from: [profile]) }
    }

    @Test func missingLocalDockItemsHaveDetectableTargets() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("fixture".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(!AppLauncher.isMissingTarget(.file(at: file)))
        #expect(AppLauncher.isMissingTarget(.file(at: file.appendingPathExtension("missing"))))
        #expect(!AppLauncher.isMissingTarget(.widget("Clock")))
    }

    @Test func weatherForecastPayloadDecodesCurrentAndHourlyData() throws {
        let payload = Data(#"{"current":{"temperature_2m":18.4,"relative_humidity_2m":62,"apparent_temperature":17.9,"precipitation":0.2,"weather_code":2,"is_day":1,"wind_speed_10m":12.5},"hourly":{"time":[1727193600,1727197200],"temperature_2m":[18.4,19.1],"precipitation_probability":[10,20],"weather_code":[2,1]},"timezone":"Europe/Warsaw"}"#.utf8)
        let location = WeatherLocation(id: "city-1", name: "Warsaw", administrativeArea: "Masovian", country: "Poland", latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw")
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let forecast = try OpenMeteoWeatherProvider.decodeForecast(payload, location: location, fetchedAt: fetchedAt)

        #expect(forecast.temperature == 18.4)
        #expect(forecast.apparentTemperature == 17.9)
        #expect(forecast.relativeHumidity == 62)
        #expect(forecast.weatherCode == 2)
        #expect(forecast.isDay)
        #expect(forecast.hourly.count == 2)
        #expect(forecast.hourly[1].temperature == 19.1)
        #expect(forecast.hourly[1].precipitationProbability == 20)
        #expect(forecast.timeZoneIdentifier == "Europe/Warsaw")
        #expect(location.displayName == "Warsaw, Masovian, Poland")
    }

    @Test func weatherConfigurationAndCachedForecastSurviveBackupRoundTrip() throws {
        let location = WeatherLocation(id: "geonames-123", name: "Warsaw", administrativeArea: "Masovian", country: "Poland", latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw")
        let cached = WeatherForecast(temperature: 21, apparentTemperature: 20, relativeHumidity: 55, precipitation: 0, windSpeed: 9, weatherCode: 1, isDay: true, fetchedAt: Date(timeIntervalSince1970: 1_700_000_000), timeZoneIdentifier: "Europe/Warsaw", hourly: [])
        var item = DockItem.widget("Weather")
        item.widgetConfiguration?.cardWidth = .wide
        item.widgetConfiguration?.weatherLocation = location
        item.widgetConfiguration?.weatherUnit = .fahrenheit
        item.widgetConfiguration?.weatherLayout = .hourlyForecast
        item.widgetConfiguration?.weatherForecastHours = 6
        item.widgetConfiguration?.weatherBackground = .translucent
        item.widgetConfiguration?.cachedWeatherForecast = cached
        let profile = DockProfile(name: "Forecast", kind: .custom, items: [item])

        let archive = try BackupManager.makeArchive(from: [profile])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration

        #expect(restored?.weatherLocation == location)
        #expect(restored?.cardWidth == .wide)
        #expect(restored?.weatherUnit == .fahrenheit)
        #expect(restored?.weatherLayout == .hourlyForecast)
        #expect(restored?.weatherForecastHours == 6)
        #expect(restored?.weatherBackground == .translucent)
        #expect(restored?.cachedWeatherForecast == nil) // PR-13: forecasts are runtime cache, excluded from backups
    }

    @Test func airDropLinkValidatorAcceptsWebLinksAndRejectsOtherSchemes() {
        #expect(AirDropLinkValidator.validatedURL(" https://example.com/path ")?.host == "example.com")
        #expect(AirDropLinkValidator.validatedURL("http://localhost:8080")?.scheme == "http")
        #expect(AirDropLinkValidator.validatedURL("file:///tmp/private") == nil)
        #expect(AirDropLinkValidator.validatedURL("mailto:user@example.com") == nil)
        #expect(AirDropLinkValidator.validatedURL("example.com") == nil)
        #expect(AirDropLinkValidator.validatedURL("https://") == nil)
    }

    @Test func trashSnapshotCountsHiddenAndVisibleTopLevelItems() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("one".utf8).write(to: directory.appendingPathComponent("one.txt"))
        try Data("hidden".utf8).write(to: directory.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("folder", isDirectory: true), withIntermediateDirectories: false)
        // Finder's own bookkeeping is not something the user trashed.
        try Data().write(to: directory.appendingPathComponent(".DS_Store"))
        try Data().write(to: directory.appendingPathComponent(".localized"))

        #expect(try TrashContentsReader.itemCount(at: directory) == 3)
        #expect(try TrashContentsReader.itemCount(at: directory.appendingPathComponent("missing")) == 0)
        #expect(WidgetRegistry.all.contains(where: { $0.name == "Trash" }))
    }

    @Test func nowPlayingConfigurationSurvivesBackupRoundTrip() throws {
        var item = DockItem.widget("Now Playing")
        item.widgetConfiguration?.nowPlayingSource = .spotify
        item.widgetConfiguration?.nowPlayingEnabledSources = [.appleMusic, .spotify]
        item.widgetConfiguration?.nowPlayingLayout = .mini
        item.widgetConfiguration?.nowPlayingSkipSeconds = 30
        item.widgetConfiguration?.nowPlayingHidesWhenClosed = true
        item.widgetConfiguration?.nowPlayingShowsTrackControls = false
        item.widgetConfiguration?.nowPlayingShowsSeekControls = false
        let profile = DockProfile(name: "Music", kind: .custom, items: [item])

        let archive = try BackupManager.makeArchive(from: [profile])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration

        #expect(restored?.nowPlayingSource == .spotify)
        #expect(restored?.nowPlayingEnabledSources == [.appleMusic, .spotify])
        #expect(restored?.nowPlayingLayout == .mini)
        #expect(restored?.nowPlayingSkipSeconds == 30)
        #expect(restored?.nowPlayingHidesWhenClosed == true)
        #expect(restored?.nowPlayingShowsTrackControls == false)
        #expect(restored?.nowPlayingShowsSeekControls == false)
        #expect(!NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: true, source: .spotify,
                                                      runningSources: [.appleMusic]))
        #expect(NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: true, source: .spotify,
                                                     runningSources: [.spotify]))
        #expect(NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: false, source: .spotify,
                                                     runningSources: []))
        #expect(NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: true,
                                                      enabledSources: [.appleMusic, .spotify],
                                                      runningSources: [.appleMusic]))
        #expect(!NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: true,
                                                       enabledSources: [.spotify],
                                                       runningSources: [.appleMusic]))
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: true, kinds: [.compact]) == 15)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: true, kinds: [.compact, .popout]) == 5)
        // PR-14: a visible popout refreshes even while the Dock is hidden; compact-only does not.
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: false, kinds: [.popout]) == 5)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: false, kinds: [.compact]) == nil)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: false, kinds: [.compact, .popout]) == 5)
    }

    @Test func nowPlayingFollowsTheEnabledPlayerThatIsPlaying() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let musicPaused = NowPlayingSnapshot(title: "Paused", artist: "Artist", album: "", isPlaying: false,
                                             position: 0, duration: 200, updatedAt: now, artworkURL: nil)
        let spotifyPlaying = NowPlayingSnapshot(title: "Playing", artist: "Artist", album: "", isPlaying: true,
                                                position: 20, duration: 200, updatedAt: now.addingTimeInterval(1), artworkURL: nil)
        #expect(NowPlayingSourcePolicy.activeSource(preferred: .appleMusic,
                                                    enabledSources: [.appleMusic, .spotify],
                                                    snapshots: [.appleMusic: musicPaused, .spotify: spotifyPlaying]) == .spotify)
        #expect(NowPlayingSourcePolicy.activeSource(preferred: .spotify,
                                                    enabledSources: [.appleMusic, .spotify],
                                                    snapshots: [.appleMusic: musicPaused]) == .spotify)
        #expect(NowPlayingSourcePolicy.activeSource(preferred: .spotify,
                                                    enabledSources: [], snapshots: [:]) == nil)
        #expect(NowPlayingSourcePolicy.activeSource(preferred: .appleMusic,
                                                    enabledSources: [.appleMusic, .spotify],
                                                    snapshots: [.appleMusic: spotifyPlaying, .spotify: spotifyPlaying]) == .appleMusic)
    }

    @Test func nowPlayingResponseParserReadsPlaybackStateAndTimes() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = try NowPlayingResponseParser.snapshot(
            from: "Midnight City\nM83\nHurry Up, We're Dreaming\nplaying\n42.5\n244",
            updatedAt: updatedAt
        )

        #expect(snapshot?.title == "Midnight City")
        #expect(snapshot?.artist == "M83")
        #expect(snapshot?.album == "Hurry Up, We're Dreaming")
        #expect(snapshot?.isPlaying == true)
        #expect(snapshot?.position == 42.5)
        #expect(snapshot?.duration == 244)
        #expect(snapshot?.updatedAt == updatedAt)
        let withArtwork = try NowPlayingResponseParser.snapshot(
            from: "Midnight City\nM83\nHurry Up\nplaying\n42.5\n244\nhttps://i.scdn.co/image/abc123")
        #expect(withArtwork?.artworkURL?.host == "i.scdn.co")
        #expect(NowPlayingArtwork.spotifyURL(from: "https://localhost/image/abc123") == nil)
        #expect(NowPlayingArtwork.spotifyURL(from: "https://i.scdn.co/image/abc123?token=secret") == nil)
        #expect(NowPlayingArtwork.thumbnail(from: Data([0, 1, 2, 3])) == nil)
        #expect(try NowPlayingResponseParser.snapshot(from: "") == nil)
        #expect(throws: NowPlayingParsingError.self) { try NowPlayingResponseParser.snapshot(from: "missing fields") }
    }

    @Test func chartSelectionClampsToVisibleMarketPoints() {
        #expect(MarketChartSelection.index(forX: -20, width: 100, pointCount: 5) == 0)
        #expect(MarketChartSelection.index(forX: 50, width: 100, pointCount: 5) == 2)
        #expect(MarketChartSelection.index(forX: 130, width: 100, pointCount: 5) == 4)
        #expect(MarketChartSelection.index(forX: .greatestFiniteMagnitude, width: 100, pointCount: 5) == 4)
        #expect(MarketChartSelection.index(forX: 50, width: 100, pointCount: 1) == 0)
        #expect(MarketChartSelection.index(forX: 50, width: 0, pointCount: 5) == nil)
        #expect(MarketChartSelection.index(forX: 50, width: 100, pointCount: 0) == nil)
    }

    @Test func nativeDockSerializerPreservesSpacerKindsAndAppOrder() throws {
        let appURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let snapshot = [NativeDockTestFixtures.applicationTile(appURL)]
        let items = [DockItem.spacer(.small), DockItem(type: .application, title: "Calculator", url: appURL), DockItem.spacer(.regular)]
        let tiles = try NativeDockSerializer.tiles(for: items, using: snapshot)
        let restored = NativeDockSerializer.items(from: tiles)

        #expect(restored.map(\.spacerKind) == [.small, nil, .regular])
        #expect(restored[1].url?.standardizedFileURL.path == appURL.path)
        #expect(NativeDockSerializer.signatures(from: tiles).count == 3)
    }

    @Test func nativeDockAutoSaveTracksOnlyExternalSupportedChanges() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = try store.createProfileAndPersist(kind: .native, name: "Work")
        let appURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let pinnedApp = DockItem(type: .application, title: "Calculator", url: appURL)
        store.replaceItems([pinnedApp], in: profileID)
        store.updateSettings { $0.automaticallySaveNativeDockChanges = true }

        let backend = FakeDockPreferencesBackend(tiles: [NativeDockTestFixtures.applicationTile(appURL)])
        let relauncher = FakeDockRelauncher()
        let controller = NativeDockController(backend: backend, relauncher: relauncher,
                                              journal: FakeDockTransactionJournal())
        let monitor = NativeDockAutoSaveMonitor(store: store, controller: controller,
                                                 backend: backend, pollingInterval: nil)
        monitor.configure(enabled: true, profileID: profileID)
        await monitor.refreshNow()

        backend.tiles = [["tile-type": "small-spacer-tile"], NativeDockTestFixtures.applicationTile(appURL)]
        await monitor.refreshNow()
        let changed = store.nativeProfiles.first { $0.id == profileID }?.items
        #expect(changed?.map(\.spacerKind) == [.small, nil])
        #expect(changed?.last?.id == pinnedApp.id)
        #expect(backend.writeCount == 0)
        #expect(relauncher.restartCount == 0)

        try await controller.apply(DockProfile(name: "Another", kind: .native, items: [.spacer(.regular)]))
        await monitor.refreshNow()
        #expect(store.nativeProfiles.first { $0.id == profileID }?.items.map(\.spacerKind) == [.small, nil])

        backend.tiles = [["tile-type": "unknown-tile"]]
        await monitor.refreshNow()
        #expect(monitor.errorMessage != nil)
        #expect(store.nativeProfiles.first { $0.id == profileID }?.items.map(\.spacerKind) == [.small, nil])

        monitor.configure(enabled: false, profileID: nil)
        backend.tiles = [["tile-type": "spacer-tile"]]
        await monitor.refreshNow()
        #expect(store.nativeProfiles.first { $0.id == profileID }?.items.map(\.spacerKind) == [.small, nil])
    }

    @Test func nativeDockApplyUsesFixtureBackendAndClearsJournal() async throws {
        let appURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let original = [NativeDockTestFixtures.applicationTile(appURL), ["tile-type": "spacer-tile"]]
        let backend = FakeDockPreferencesBackend(tiles: original)
        let relauncher = FakeDockRelauncher()
        let journal = FakeDockTransactionJournal()
        let freezeProvider = FakeDockSwitchFreezeProvider()
        let controller = NativeDockController(backend: backend, relauncher: relauncher, journal: journal,
                                              freezeProvider: freezeProvider)
        let profile = DockProfile(name: "Test", kind: .native, items: [.spacer(.small), DockItem(type: .application, title: "Calculator", url: appURL)])

        try await controller.apply(profile)

        #expect(NativeDockSerializer.signatures(from: backend.tiles) == ["spacer:small", "application:\(appURL.path)"])
        #expect(relauncher.restartCount == 1)
        #expect(journal.isPending == false)
        #expect(freezeProvider.beginCount == 1)
        #expect(freezeProvider.endCount == 1)
    }

    @Test func nativeDockApplyRollsBackAfterPreferenceWriteFailure() async {
        let appURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let original = [NativeDockTestFixtures.applicationTile(appURL), ["tile-type": "small-spacer-tile"]]
        let backend = FakeDockPreferencesBackend(tiles: original, failingWrites: [1])
        let relauncher = FakeDockRelauncher()
        let journal = FakeDockTransactionJournal()
        let freezeProvider = FakeDockSwitchFreezeProvider()
        let controller = NativeDockController(backend: backend, relauncher: relauncher, journal: journal,
                                              freezeProvider: freezeProvider)
        let profile = DockProfile(name: "Test", kind: .native, items: [.spacer(.regular)])
        var failed = false

        do { try await controller.apply(profile) } catch { failed = true }

        #expect(failed)
        #expect(NativeDockSerializer.plistArraysEqual(backend.tiles, original))
        #expect(relauncher.restartCount == 1)
        #expect(journal.isPending == false)
        #expect(freezeProvider.beginCount == 1)
        #expect(freezeProvider.endCount == 1)
    }

    @Test func rapidNativeDockAppliesFinishOnNewestRequestedProfile() async throws {
        let appURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let backend = FakeDockPreferencesBackend(tiles: [NativeDockTestFixtures.applicationTile(appURL)])
        let relauncher = FakeDockRelauncher(delay: .milliseconds(10))
        let journal = FakeDockTransactionJournal()
        let controller = NativeDockController(backend: backend, relauncher: relauncher, journal: journal)
        let first = DockProfile(name: "First", kind: .native, items: [.spacer(.small)])
        let last = DockProfile(name: "Last", kind: .native, items: [.spacer(.regular)])
        let firstTask = Task { @MainActor in try await controller.apply(first) }
        await Task.yield()
        let lastTask = Task { @MainActor in try await controller.apply(last) }

        try await firstTask.value
        try await lastTask.value

        #expect(NativeDockSerializer.signatures(from: backend.tiles) == ["spacer:regular"])
        #expect(relauncher.restartCount == 2)
    }

    @Test func stripeParserKeepsCurrenciesSeparateAndCalculatesSubscriptionMetrics() throws {
        let balance = Data(#"{"available":[{"currency":"usd","amount":10000},{"currency":"eur","amount":2500}],"pending":[{"currency":"usd","amount":500}]}"#.utf8)
        let transactions = try stripeRows(#"{"data":[{"id":"txn_charge","type":"charge","created":2000,"currency":"usd","amount":1000,"fee":59,"net":941},{"id":"txn_refund","type":"refund","created":2100,"currency":"usd","amount":-200,"fee":0,"net":-200},{"id":"txn_eur","type":"charge","created":2200,"currency":"eur","amount":2500,"fee":100,"net":2400},{"id":"txn_reversal","type":"payment_reversal","created":2300,"currency":"usd","amount":-100,"fee":0,"net":-100},{"id":"txn_old","type":"charge","created":1200,"currency":"usd","amount":900,"fee":20,"net":880},{"id":"txn_payout","type":"payout","created":2200,"currency":"usd","amount":-1000,"fee":0,"net":-1000}]}"#)
        let subscriptions = try stripeRows(#"{"data":[{"id":"sub_one","status":"active","customer":"cus_one","items":{"data":[{"quantity":2,"price":{"currency":"usd","unit_amount":1000,"billing_scheme":"per_unit","recurring":{"interval":"month","interval_count":1,"usage_type":"licensed"}}}]}},{"id":"sub_two","status":"active","customer":"cus_one","items":{"data":[{"quantity":1,"price":{"currency":"usd","unit_amount":2000,"billing_scheme":"per_unit","recurring":{"interval":"month","interval_count":1,"usage_type":"licensed"}}}]}},{"id":"sub_three","status":"active","customer":"cus_two","items":{"data":[{"quantity":1,"price":{"currency":"eur","unit_amount":12000,"billing_scheme":"per_unit","recurring":{"interval":"year","interval_count":1,"usage_type":"licensed"}}}]}},{"id":"sub_due","status":"past_due","customer":"cus_due","items":{"data":[{"quantity":1,"price":{"currency":"usd","unit_amount":1000,"billing_scheme":"per_unit","recurring":{"interval":"month","interval_count":1,"usage_type":"licensed"}}}]}},{"id":"sub_trial","status":"trialing","customer":"cus_trial","items":{"data":[{"quantity":1,"price":{"currency":"usd","unit_amount":5000,"billing_scheme":"per_unit","recurring":{"interval":"month","interval_count":1,"usage_type":"licensed"}}}]}},{"id":"sub_metered","status":"active","customer":"cus_three","items":{"data":[{"quantity":1,"price":{"currency":"usd","unit_amount":10,"billing_scheme":"per_unit","recurring":{"interval":"month","interval_count":1,"usage_type":"metered"}}}]}}]}"#)
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1500), end: Date(timeIntervalSince1970: 2500))

        let snapshot = try StripeSnapshotParser.snapshot(accountID: "fixture-account",
                                                         accountName: "Acme Store",
                                                         balanceData: balance,
                                                         transactionRows: transactions,
                                                         subscriptionRows: subscriptions,
                                                         period: .thirtyDays,
                                                         interval: interval,
                                                         now: Date(timeIntervalSince1970: 2500))

        #expect(snapshot.accountID == "fixture-account")
        #expect(snapshot.accountName == "Acme Store")
        #expect(snapshot.currencyCodes == ["EUR", "USD"])
        let usd = try #require(snapshot.metrics(for: "USD"))
        #expect(usd.revenueMinor == 700)
        #expect(usd.netAfterFeesMinor == 641)
        #expect(usd.mrrMinor == 5000)
        #expect(usd.mrrMinor * 12 == 60000)
        #expect(usd.payingSubscribers == 2)
        #expect(usd.arpuMinor == 2500)
        #expect(usd.availableBalanceMinor == 10000)
        #expect(usd.pendingBalanceMinor == 500)
        let eur = try #require(snapshot.metrics(for: "EUR"))
        #expect(eur.revenueMinor == 2500)
        #expect(eur.mrrMinor == 1000)
        #expect(eur.payingSubscribers == 1)
        #expect(snapshot.unsupportedSubscriptionItems == 1)
    }

    @Test func stripeWidgetSettingsAndLastSuccessfulSnapshotSurviveBackup() throws {
        var widget = DockItem.widget("Stripe")
        widget.widgetConfiguration?.stripeDisplayName = "Store Revenue"
        widget.widgetConfiguration?.stripeColor = "teal"
        widget.widgetConfiguration?.stripeAccountID = "acct_example"
        widget.widgetConfiguration?.stripeMetric = .mrr
        widget.widgetConfiguration?.stripeCurrency = "EUR"
        widget.widgetConfiguration?.stripePeriod = .ninetyDays
        widget.widgetConfiguration?.stripeSnapshot = StripeSnapshot(accountID: "acct_example",
                                                                     accountName: "Example Store",
                                                                     fetchedAt: Date(timeIntervalSince1970: 100),
                                                                     period: .ninetyDays,
                                                                     periodStart: Date(timeIntervalSince1970: 0),
                                                                     periodEnd: Date(timeIntervalSince1970: 100),
                                                                     currencies: [StripeCurrencyMetrics(currency: "EUR",
                                                                                                        revenueMinor: 1200,
                                                                                                        netAfterFeesMinor: 1100,
                                                                                                        mrrMinor: 800,
                                                                                                        payingSubscribers: 2,
                                                                                                        availableBalanceMinor: 3000,
                                                                                                        pendingBalanceMinor: 100)],
                                                                     unsupportedSubscriptionItems: 0)
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Finance", kind: .custom, items: [widget])])
        let archiveText = String(decoding: archive, as: UTF8.self)
        let restored = try #require(BackupManager.readArchive(archive).importedProfiles.first?.items.first?.widgetConfiguration)

        #expect(restored.stripeDisplayName == "Store Revenue")
        #expect(restored.stripeColor == "teal")
        #expect(restored.stripeAccountID == "acct_example")
        #expect(restored.stripeMetric == .mrr)
        #expect(restored.stripeCurrency == "EUR")
        #expect(restored.stripePeriod == .ninetyDays)
        #expect(restored.stripeSnapshot == nil) // PR-13: readings are runtime cache, excluded from backups
        #expect(!archiveText.contains("rk_"))
    }

    @Test func stripeKeyPolicyAcceptsOnlyRestrictedKeyPrefix() {
        #expect(StripeAPIKeyStore.isRestrictedKey("rk_live_example"))
        #expect(StripeAPIKeyStore.isRestrictedKey("rk_test_example"))
        #expect(!StripeAPIKeyStore.isRestrictedKey("sk_live_example"))
        #expect(!StripeAPIKeyStore.isRestrictedKey("rk_live_example with-space"))
        #expect(!StripeAPIKeyStore.isRestrictedKey("rk_"))
    }

    @Test func stripeProviderUsesBearerAuthAndKeepsCredentialOutOfURL() async throws {
        let transport = StripeFixtureTransport()
        let result = try await StripeAPIProvider(transport: transport).snapshot(apiKey: "rk_test_fixture",
                                                                                 accountID: "fixture-account",
                                                                                 accountName: "Fixture Store",
                                                                                 period: .thirtyDays,
                                                                                 now: Date(timeIntervalSince1970: 2_500),
                                                                                 calendar: Calendar(identifier: .gregorian))
        let requests = await transport.capturedRequests()

        #expect(result.accountID == "fixture-account")
        #expect(result.accountName == "Fixture Store")
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer rk_test_fixture" })
        #expect(requests.allSatisfy { !($0.url?.absoluteString.contains("rk_test_fixture") ?? true) })
        #expect(requests.contains { $0.url?.path == "/v1/balance_transactions" })
        #expect(requests.contains { $0.url?.path == "/v1/subscriptions" })
    }

    @Test func stripeProviderRejectsPartialTotalsAtPaginationCap() async throws {
        let provider = StripeAPIProvider(transport: StripeFixtureTransport(transactionHasMore: true), maximumPages: 1)
        do {
            _ = try await provider.snapshot(apiKey: "rk_test_fixture",
                                            accountID: "fixture-account",
                                            accountName: "Fixture Store",
                                            period: .thirtyDays,
                                            now: Date(timeIntervalSince1970: 2_500),
                                            calendar: Calendar(identifier: .gregorian))
            Issue.record("A capped Stripe transaction list must not produce partial totals")
        } catch let error as StripeDataError {
            if case .paginationLimit = error { } else { Issue.record("Expected paginationLimit, got \(error)") }
        }
    }

    @Test func stripePeriodUsesInjectedLocalCalendarForDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let date = try #require(calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12)))
        let interval = StripePeriod.today.interval(endingAt: date, calendar: calendar)

        #expect(calendar.component(.hour, from: interval.start) == 0)
        #expect(calendar.component(.day, from: interval.start) == 10)
        #expect(date.timeIntervalSince(interval.start) == 11 * 60 * 60)
    }

    @Test func paddleMetricsParserCombinesRevenueMRRAndSubscribersByUTCDate() throws {
        let revenue = paddleMetricFixture(currency: "USD", values: #"[{"timestamp":"2026-09-22T00:00:00Z","amount":"1000","count":2},{"timestamp":"2026-09-23T00:00:00Z","amount":"2500","count":3}]"#)
        let mrr = paddleMetricFixture(currency: "USD", values: #"[{"timestamp":"2026-09-22T00:00:00Z","amount":"10000"},{"timestamp":"2026-09-23T00:00:00Z","amount":"12000"}]"#)
        let subscribers = paddleMetricFixture(values: #"[{"timestamp":"2026-09-22T00:00:00Z","count":3},{"timestamp":"2026-09-23T00:00:00Z","count":4}]"#)

        let snapshot = try PaddleMetricsParser.snapshot(revenueData: revenue,
                                                       mrrData: mrr,
                                                       subscriberData: subscribers,
                                                       accountID: "paddle-fixture",
                                                       accountName: "Billing",
                                                       period: .sevenDays,
                                                       now: Date(timeIntervalSince1970: 1_800_000_000))

        #expect(snapshot.accountName == "Billing")
        #expect(snapshot.currency == "USD")
        #expect(snapshot.points.count == 2)
        #expect(snapshot.totalNetRevenueMinor == 3500)
        #expect(snapshot.latestMRRMinor == 12000)
        #expect(snapshot.latestARRMinor == 144000)
        #expect(snapshot.latestActiveSubscribers == 4)
        #expect(snapshot.points[0].netRevenueMinor == 1000)
    }

    @Test func paddleRejectsMismatchedCurrencyInsteadOfConverting() throws {
        let revenue = paddleMetricFixture(currency: "USD", values: #"[{"timestamp":"2026-09-23T00:00:00Z","amount":"1000","count":2}]"#)
        let mrr = paddleMetricFixture(currency: "EUR", values: #"[{"timestamp":"2026-09-23T00:00:00Z","amount":"10000"}]"#)
        let subscribers = paddleMetricFixture(values: #"[{"timestamp":"2026-09-23T00:00:00Z","count":3}]"#)

        do {
            _ = try PaddleMetricsParser.snapshot(revenueData: revenue,
                                                mrrData: mrr,
                                                subscriberData: subscribers,
                                                accountID: "paddle-fixture",
                                                accountName: "Billing",
                                                period: .today)
            Issue.record("Paddle metrics in different currencies must not be combined")
        } catch let error as PaddleDataError {
            if case .currencyMismatch = error { } else { Issue.record("Expected currencyMismatch, got \(error)") }
        }
    }

    @Test func paddleBillingKeyPolicyRequiresCurrentServerAPIKeyFormat() {
        #expect(PaddleAPIKeyStore.isBillingKey("pdl_live_apikey_01gtgztp8f4kek3yd4g1wrksa3_q6TGTJyvoIz7LDtXT65bX7_AQO"))
        #expect(PaddleAPIKeyStore.isBillingKey("pdl_sdbx_apikey_aaaaaaaaaaaaaaaaaaaaaaaaaa_BBBBBBBBBBBBBBBBBBBBBB_ccc"))
        #expect(!PaddleAPIKeyStore.isBillingKey("legacy-paddle-key"))
        #expect(!PaddleAPIKeyStore.isBillingKey("pdl_live_apikey_short"))
    }

    @Test func paddleWidgetSettingsAndMetricHistorySurviveBackup() throws {
        var item = DockItem.widget("Paddle")
        item.widgetConfiguration?.paddleDisplayName = "Billing"
        item.widgetConfiguration?.paddleColor = "orange"
        item.widgetConfiguration?.paddleAccountID = "paddle-fixture"
        item.widgetConfiguration?.paddleMetric = .arr
        item.widgetConfiguration?.paddlePeriod = .ninetyDays
        item.widgetConfiguration?.paddleShowsChart = false
        item.widgetConfiguration?.paddleSnapshot = PaddleSnapshot(accountID: "paddle-fixture",
                                                                   accountName: "Billing",
                                                                   fetchedAt: Date(timeIntervalSince1970: 1_800_000_000),
                                                                   period: .ninetyDays,
                                                                   currency: "USD",
                                                                   points: [PaddleMetricPoint(date: Date(timeIntervalSince1970: 1_799_000_000),
                                                                                              netRevenueMinor: 300,
                                                                                              mrrMinor: 1_000,
                                                                                              activeSubscribers: 2)],
                                                                   updatedAt: Date(timeIntervalSince1970: 1_799_900_000))
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Billing", kind: .custom, items: [item])])
        let text = String(decoding: archive, as: UTF8.self)
        let restored = try #require(BackupManager.readArchive(archive).importedProfiles.first?.items.first?.widgetConfiguration)

        #expect(restored.paddleDisplayName == "Billing")
        #expect(restored.paddleColor == "orange")
        #expect(restored.paddleAccountID == "paddle-fixture")
        #expect(restored.paddleMetric == .arr)
        #expect(restored.paddlePeriod == .ninetyDays)
        #expect(!restored.paddleShowsChart)
        #expect(restored.paddleSnapshot == nil) // PR-13: readings are runtime cache, excluded from backups
        #expect(!text.contains("pdl_live_apikey_"))
    }

    @Test func paddlePeriodsUseUTCDateBoundaries() throws {
        let formatter = ISO8601DateFormatter()
        let now = try #require(formatter.date(from: "2026-09-24T22:30:00Z"))
        let today = PaddlePeriod.today.utcBounds(endingAt: now)
        let week = PaddlePeriod.sevenDays.utcBounds(endingAt: now)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"

        #expect(dateFormatter.string(from: today.from) == "2026-09-24")
        #expect(dateFormatter.string(from: today.to) == "2026-09-25")
        #expect(dateFormatter.string(from: week.from) == "2026-09-18")
    }

    @Test func paddleProviderUsesCorrectEnvironmentBearerAuthAndNoCredentialInURL() async throws {
        let transport = PaddleFixtureTransport()
        let result = try await PaddleAPIProvider(transport: transport).snapshot(apiKey: "pdl_sdbx_apikey_aaaaaaaaaaaaaaaaaaaaaaaaaa_BBBBBBBBBBBBBBBBBBBBBB_ccc",
                                                                                accountID: "paddle-fixture",
                                                                                accountName: "Billing",
                                                                                period: .sevenDays,
                                                                                now: Date(timeIntervalSince1970: 1_800_000_000))
        let requests = await transport.capturedRequests()

        #expect(result.currency == "USD")
        #expect(requests.count == 3)
        #expect(requests.allSatisfy { $0.url?.host == "sandbox-api.paddle.com" })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer pdl_sdbx_apikey_") == true })
        #expect(requests.allSatisfy { !($0.url?.absoluteString.contains("apikey_") ?? true) })
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "Paddle-Version") == "1" })
    }

    @Test func shopifyDomainPolicyAcceptsOnlyMyShopifyStoreHosts() throws {
        #expect(try ShopifyAPIProvider.normalizedDomain("  my-store ") == "my-store.myshopify.com")
        #expect(try ShopifyAPIProvider.normalizedDomain("https://my-store.myshopify.com/") == "my-store.myshopify.com")
        for invalid in ["", "admin.shopify.com", "shop.myshopify.com.evil.test", "https://user@shop.myshopify.com", "-bad.myshopify.com"] {
            #expect(throws: ShopifyDataError.self) { try ShopifyAPIProvider.normalizedDomain(invalid) }
        }
    }

    @Test func shopifyPeriodUsesStoreLocalCalendarBoundariesAcrossDST() throws {
        let now = ISO8601DateFormatter().date(from: "2026-03-31T10:00:00Z")!
        let interval = try ShopifyPeriod.sevenDays.interval(endingAt: now, timeZoneID: "Europe/Warsaw")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        let start = calendar.dateComponents([.year, .month, .day, .hour], from: interval.start)
        #expect(start.year == 2026)
        #expect(start.month == 3)
        #expect(start.day == 25)
        #expect(start.hour == 0)
        #expect(interval.end == now)
        #expect(throws: ShopifyDataError.self) {
            try ShopifyPeriod.today.interval(endingAt: now, timeZoneID: "Not/A_Zone")
        }
    }

    @Test func shopifyParserUsesCurrentTotalsAndExcludesTestAndCanceledOrders() throws {
        let fixtureStore = ShopifyConnectedStore(id: "shop-a", name: "Acme", domain: "acme.myshopify.com",
                                                 timeZoneID: "America/New_York", currency: "USD", color: "green")
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_086_400))
        let day = interval.start.addingTimeInterval(30_000)
        let orders = [
            ShopifyOrderRecord(createdAt: day, cancelledAt: nil, isTest: false, amount: Decimal(string: "12.50")!, currency: "USD",
                               lineItems: [.init(name: "Mug", currentQuantity: 2)], lineItemsTruncated: false, trafficSource: "Google"),
            ShopifyOrderRecord(createdAt: day.addingTimeInterval(60), cancelledAt: nil, isTest: false, amount: .zero, currency: "USD",
                               lineItems: [.init(name: "Returned Book", currentQuantity: 0)], lineItemsTruncated: false, trafficSource: nil),
            ShopifyOrderRecord(createdAt: day.addingTimeInterval(120), cancelledAt: nil, isTest: true, amount: 99, currency: "USD",
                               lineItems: [.init(name: "Test", currentQuantity: 1)], lineItemsTruncated: false, trafficSource: "Direct"),
            ShopifyOrderRecord(createdAt: day.addingTimeInterval(180), cancelledAt: day, isTest: false, amount: 50, currency: "USD",
                               lineItems: [.init(name: "Canceled", currentQuantity: 4)], lineItemsTruncated: false, trafficSource: "Direct")
        ]
        let snapshot = try ShopifySnapshotParser.snapshot(orders: orders, store: fixtureStore, period: .thirtyDays,
                                                          interval: interval, now: interval.end)
        #expect(snapshot.orderCount == 2)
        #expect(snapshot.orderValue == Decimal(string: "12.50"))
        #expect(snapshot.averageOrderValue == Decimal(string: "6.25"))
        #expect(snapshot.productBreakdown == [ShopifyBreakdownEntry(name: "Mug", units: 2, orders: 0)])
        #expect(snapshot.trafficBreakdown == [ShopifyBreakdownEntry(name: "Google", units: 0, orders: 1)])
        #expect(snapshot.trafficAttributedOrders == 1)
        #expect(snapshot.dailyPoints.first?.orders == 2)
    }

    @Test func shopifyParserRefusesMixedCurrencyAndAOVWithoutOrders() throws {
        let fixtureStore = ShopifyConnectedStore(id: "shop-a", name: "Acme", domain: "acme.myshopify.com",
                                                 timeZoneID: "UTC", currency: "USD", color: "green")
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), end: Date(timeIntervalSince1970: 1_800_086_400))
        let empty = try ShopifySnapshotParser.snapshot(orders: [], store: fixtureStore, period: .today, interval: interval)
        #expect(empty.orderCount == 0)
        #expect(empty.averageOrderValue == nil)
        let eur = ShopifyOrderRecord(createdAt: interval.start.addingTimeInterval(1), cancelledAt: nil, isTest: false,
                                     amount: 1, currency: "EUR", lineItems: [], lineItemsTruncated: false, trafficSource: nil)
        #expect(throws: ShopifyDataError.currencyMismatch) {
            try ShopifySnapshotParser.snapshot(orders: [eur], store: fixtureStore, period: .today, interval: interval)
        }
    }

    @Test func shopifyWidgetConfigurationAndSnapshotSurviveBackupWithoutCredentials() throws {
        var item = DockItem.widget("Shopify")
        item.widgetConfiguration?.shopifyDisplayName = "Main Store"
        item.widgetConfiguration?.shopifyColor = "teal"
        item.widgetConfiguration?.shopifyStoreID = "store-one"
        item.widgetConfiguration?.shopifyMetric = .averageOrderValue
        item.widgetConfiguration?.shopifyPeriod = .monthToDate
        item.widgetConfiguration?.shopifyShowsChart = false
        item.widgetConfiguration?.shopifySnapshot = ShopifySnapshot(storeID: "store-one", storeName: "Main Store",
                                                                     storeDomain: "main.myshopify.com", fetchedAt: .now,
                                                                     period: .monthToDate, periodStart: .now.addingTimeInterval(-86_400),
                                                                     periodEnd: .now, timeZoneID: "UTC", currency: "USD",
                                                                     orderValue: 25, orderCount: 2,
                                                                     dailyPoints: [.init(date: .now, orderValue: 25, orders: 2)],
                                                                     productBreakdown: [], trafficBreakdown: [],
                                                                     productBreakdownIncompleteOrders: 0, trafficAttributedOrders: 0)
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Store", kind: .custom, items: [item])])
        let text = String(decoding: archive, as: UTF8.self)
        let restored = try #require(BackupManager.readArchive(archive).importedProfiles.first?.items.first?.widgetConfiguration)
        #expect(restored.shopifyDisplayName == "Main Store")
        #expect(restored.shopifyColor == "teal")
        #expect(restored.shopifyStoreID == "store-one")
        #expect(restored.shopifyMetric == .averageOrderValue)
        #expect(restored.shopifyPeriod == .monthToDate)
        #expect(!restored.shopifyShowsChart)
        #expect(restored.shopifySnapshot == nil) // PR-13: readings are runtime cache, excluded from backups
        #expect(!text.contains("private-client-secret"))
        #expect(!text.contains("shpat_"))
    }

    @Test func shopifyProviderUsesClientCredentialsAndGraphQLPagination() async throws {
        let transport = ShopifyFixtureTransport()
        let provider = ShopifyAPIProvider(transport: transport, pageSize: 2)
        let connection = try await provider.connect(domain: "acme", clientID: "client-id", clientSecret: "private-client-secret", color: "blue")
        let result = try await provider.snapshot(store: connection.store, credential: connection.credential, period: .today,
                                                 now: ISO8601DateFormatter().date(from: "2026-09-24T16:00:00Z")!)
        let requests = await transport.capturedRequests()
        #expect(connection.store.domain == "acme.myshopify.com")
        #expect(connection.store.timeZoneID == "America/New_York")
        #expect(result.snapshot.orderCount == 2)
        #expect(result.snapshot.orderValue == Decimal(string: "17.5"))
        // The access token, store metadata, two totals pages and one page of recent-order details.
        #expect(requests.count == 5)
        #expect(requests.first?.url?.path == "/admin/oauth/access_token")
        #expect(requests.filter { $0.url?.path.contains("graphql.json") == true }.allSatisfy {
            $0.value(forHTTPHeaderField: "X-Shopify-Access-Token") == "fixture-access-token"
        })
        #expect(requests.filter { $0.url?.path.contains("graphql.json") == true }.allSatisfy {
            $0.url?.path == "/admin/api/\(ShopifyAPIProvider.apiVersion)/graphql.json"
        })
        #expect(requests.allSatisfy { !($0.url?.absoluteString.contains("private-client-secret") ?? true) })
        #expect(requests[0].httpBody.map { String(decoding: $0, as: UTF8.self).contains("private-client-secret") } == true)
    }

    @Test func shopifyProviderRejectsTotalsAtOrderCapInsteadOfReturningPartialData() async throws {
        let provider = ShopifyAPIProvider(transport: ShopifyFixtureTransport(alwaysHasMoreOrders: true), pageSize: 1, maximumOrders: 1)
        let connection = try await provider.connect(domain: "acme.myshopify.com", clientID: "id", clientSecret: "secret", color: "green")
        do {
            _ = try await provider.snapshot(store: connection.store, credential: connection.credential, period: .today, now: .now)
            Issue.record("A capped order list must not produce partial Shopify totals")
        } catch let error as ShopifyDataError {
            #expect(error == .tooManyOrders)
        }
    }

    @Test func codexLimitParserReadsWindowsAndLeavesMissingPercentagesUnavailable() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let body = #"{"jsonrpc":"2.0","id":2,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":37,"windowDurationMins":300,"resetsAt":1800003600},"secondary":{"usedPercent":82,"windowDurationMins":10080,"resetsAt":1800600000}}}}"#
        let reading = try CodexRateLimitParser.reading(from: Data(body.utf8), now: now)
        #expect(reading.availability == .available)
        #expect(reading.plan == "plus")
        #expect(reading.windows.count == 2)
        #expect(reading.windows[0].usedPercent == 37)
        #expect(reading.windows[0].remainingPercent == 63)
        #expect(reading.windows[0].resetsAt == Date(timeIntervalSince1970: 1_800_003_600))
        #expect(reading.windows[1].durationMinutes == 10_080)

        let unlimited = try CodexRateLimitParser.reading(from: Data(#"{"result":{"rateLimits":{"primary":{"windowDurationMins":300}}}}"#.utf8), now: now)
        #expect(unlimited.availability == .unavailable)
        #expect(unlimited.windows.first?.usedPercent == nil)
        #expect(unlimited.windows.first?.remainingPercent == nil)
        #expect(unlimited.message != nil)

        let fractional = try CodexRateLimitParser.reading(from: Data(#"{"result":{"rateLimits":{"primary":{"usedPercent":37.6},"secondary":{"usedPercent":true}}}}"#.utf8), now: now)
        #expect(fractional.availability == .available)
        #expect(fractional.windows.first?.usedPercent == 38)
        #expect(fractional.windows.last?.usedPercent == nil)
    }

    @Test func aiLimitsCollectorKeepsOtherProvidersVisibleWhenCodexFails() async {
        struct FailingCodex: AILimitProviderAdapter {
            let provider: AIProvider = .codex
            func read(now: Date) async throws -> AIProviderLimitReading {
                throw AIUsageError.codexCLIUnavailable
            }
        }
        struct WorkingClaude: AILimitProviderAdapter {
            let provider: AIProvider = .claude
            func read(now: Date) async throws -> AIProviderLimitReading {
                AIProviderLimitReading(provider: provider, availability: .available, plan: nil,
                                       windows: [AILimitWindow(name: "Weekly", usedPercent: 24,
                                                               resetsAt: nil, durationMinutes: 10_080)],
                                       updatedAt: now, message: nil)
            }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = await AILimitsCollector.collect(providers: [.codex, .claude, .cursor], now: now,
                                                       adapters: [FailingCodex(), WorkingClaude()])
        #expect(snapshot.fetchedAt == now)
        #expect(snapshot.readings.map(\.provider) == [.codex, .claude, .cursor])
        #expect(snapshot.reading(for: .codex)?.availability == .setupRequired)
        #expect(snapshot.reading(for: .codex)?.windows.isEmpty == true)
        #expect(snapshot.reading(for: .claude)?.windows.first?.remainingPercent == 76)
        #expect(snapshot.reading(for: .cursor)?.availability == .unavailable)
        #expect(snapshot.reading(for: .grok) == nil)
    }

    @Test func aiLimitsCollectorStopsStartingReadersAfterCancellation() async {
        actor Probe {
            private var startedProviders = Set<AIProvider>()
            func markStarted(_ provider: AIProvider) { startedProviders.insert(provider) }
            func hasStarted(_ provider: AIProvider) -> Bool { startedProviders.contains(provider) }
        }
        struct WaitingCodex: AILimitProviderAdapter {
            let probe: Probe
            let provider: AIProvider = .codex
            func read(now: Date) async throws -> AIProviderLimitReading {
                await probe.markStarted(provider)
                try await Task.sleep(nanoseconds: 30_000_000_000)
                return AIProviderLimitReading(provider: provider, availability: .available,
                                              plan: nil, windows: [], updatedAt: now, message: nil)
            }
        }
        struct TrackingClaude: AILimitProviderAdapter {
            let probe: Probe
            let provider: AIProvider = .claude
            func read(now: Date) async throws -> AIProviderLimitReading {
                await probe.markStarted(provider)
                return AIProviderLimitReading(provider: provider, availability: .available,
                                              plan: nil, windows: [], updatedAt: now, message: nil)
            }
        }

        let probe = Probe()
        let worker = Task {
            await AILimitsCollector.collect(providers: [.codex, .claude],
                                            adapters: [WaitingCodex(probe: probe), TrackingClaude(probe: probe)])
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !(await probe.hasStarted(.codex)) {
            guard ContinuousClock.now < deadline else { Issue.record("The Codex reader never started"); break }
            await Task.yield()
        }
        worker.cancel()
        _ = await worker.value
        let startedClaude = await probe.hasStarted(.claude)
        #expect(!startedClaude)
    }

    @Test func claudeStatusLineLimitsAreReadLocallyAndExpiredSamplesAreHidden() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = #"{"updated_at":1800000000,"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},"seven_day":{"used_percentage":41.2,"resets_at":1800600000},"spend_limit":{"used_percentage":125.3,"resets_at":1802000000}}}"#
        let reading = try ClaudeStatusLineLimitParser.reading(from: Data(sample.utf8), now: now)
        #expect(reading.provider == .claude)
        #expect(reading.availability == .available)
        #expect(reading.windows.map(\.usedPercent) == [24, 41, 125])
        #expect(reading.windows.map(\.durationMinutes) == [300, 10_080, nil])
        #expect(reading.windows[0].remainingPercent == 76)
        #expect(reading.windows[0].resetsAt == Date(timeIntervalSince1970: 1_800_003_600))

        let stale = try ClaudeStatusLineLimitParser.reading(from: Data(sample.utf8),
                                                             now: now.addingTimeInterval(31 * 60))
        #expect(stale.availability == .unavailable)
        #expect(stale.windows.isEmpty)
        #expect(stale.updatedAt == now)
    }

    @Test func claudeStatusLineLimitAdapterReadsOnlyItsBoundedRegularFile() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let directory = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = #"{"updated_at":1800000000,"rate_limits":{"five_hour":{"used_percentage":23.5}}}"#
        try Data(sample.utf8).write(to: directory.appendingPathComponent("mydock-rate-limits.json"))

        let reading = try await ClaudeStatusLineLimitAdapter(homeDirectory: home).read(now: now)
        #expect(reading.availability == .available)
        #expect(reading.windows.first?.usedPercent == 24)

        let commandValue = try #require(AIProvider.claude.statusLineSetupCommand)
        let shellCommand = try JSONDecoder().decode(String.self, from: Data(commandValue.utf8))
        #expect(shellCommand.contains("mydock-rate-limits.json"))
        #expect(shellCommand.contains("rate_limits"))
    }

    @Test func codexActivityCountsUsageDeltasAndActiveSessionDaysWithoutRetainingTranscript() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDirectory = home.appendingPathComponent(".codex/sessions/2026/09/24", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessionDirectory.appendingPathComponent("codex-session.jsonl")
        let rows: [[String: Any]] = [
            ["type": "session_meta", "payload": ["session_id": "fixture-session"]],
            ["type": "event_msg", "timestamp": "2026-09-23T22:00:00Z", "payload": [
                "type": "token_count", "info": ["total_token_usage": ["total_tokens": 120, "input_tokens": 80, "cached_input_tokens": 20, "output_tokens": 40]]]],
            ["type": "event_msg", "timestamp": "2026-09-24T10:00:00Z", "payload": [
                "type": "token_count", "info": ["total_token_usage": ["total_tokens": 200, "input_tokens": 100, "cached_input_tokens": 30, "output_tokens": 70]]]],
            ["type": "item_completed", "timestamp": "2026-09-24T10:05:00Z", "payload": [
                "item": ["type": "function_call", "content": "PRIVATE_PROMPT_SENTINEL"]]]
        ]
        try writeJSONLines(rows, to: file)
        try FileManager.default.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: "2026-09-24T10:06:00Z")!], ofItemAtPath: file.path)
        let now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        let snapshot = AIActivityReader.read(provider: .codex, range: .sevenDays, now: now,
                                            timeZone: TimeZone(secondsFromGMT: 0)!, homeDirectory: home)

        #expect(snapshot.available)
        #expect(!snapshot.partial)
        #expect(snapshot.totals.totalTokens == 200)
        #expect(snapshot.totals.inputTokens == 100)
        #expect(snapshot.totals.cachedInputTokens == 30)
        #expect(snapshot.totals.outputTokens == 70)
        #expect(snapshot.totals.sessions == 1) // MD-P10: one session across two days is one distinct session in the range
        #expect(snapshot.totals.toolCalls == 1)
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("PRIVATE_PROMPT_SENTINEL"))
    }

    @Test func claudeActivityCountsUsageRequestsToolsAndDistinctSessionDays() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDirectory = home.appendingPathComponent(".claude/projects/fixture", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessionDirectory.appendingPathComponent("claude-session.jsonl")
        let rows: [[String: Any]] = [
            ["type": "assistant", "sessionId": "claude-fixture", "timestamp": "2026-09-23T22:00:00Z", "message": [
                "usage": ["input_tokens": 100, "cache_read_input_tokens": 20, "cache_creation_input_tokens": 5, "output_tokens": 30],
                "content": [["type": "tool_use", "name": "Read"], ["type": "text", "text": "PRIVATE_TRANSCRIPT_SENTINEL"]]]],
            ["type": "assistant", "sessionId": "claude-fixture", "timestamp": "2026-09-24T10:00:00Z", "message": [
                "usage": ["input_tokens": 50, "cache_read_input_tokens": 10, "cache_creation_input_tokens": 0, "output_tokens": 15],
                "content": [["type": "text", "text": "private content"]]]]
        ]
        try writeJSONLines(rows, to: file)
        try FileManager.default.setAttributes([.modificationDate: ISO8601DateFormatter().date(from: "2026-09-24T10:01:00Z")!], ofItemAtPath: file.path)
        let now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        let snapshot = AIActivityReader.read(provider: .claude, range: .sevenDays, now: now,
                                            timeZone: TimeZone(secondsFromGMT: 0)!, homeDirectory: home)

        #expect(snapshot.available)
        #expect(!snapshot.partial)
        #expect(snapshot.totals.totalTokens == 230)
        #expect(snapshot.totals.inputTokens == 150)
        #expect(snapshot.totals.cachedInputTokens == 35)
        #expect(snapshot.totals.outputTokens == 45)
        #expect(snapshot.totals.requests == 2)
        #expect(snapshot.totals.sessions == 1) // MD-P10: one session across two days is one distinct session in the range
        #expect(snapshot.totals.toolCalls == 1)
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("PRIVATE_TRANSCRIPT_SENTINEL"))
    }

    @Test func grokActivityIsExplicitlyEstimatedAndSymlinkedSessionIsIgnored() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionDirectory = home.appendingPathComponent(".grok/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = sessionDirectory.appendingPathComponent("grok-session.json")
        try Data(#"{"usage":{"stats":{"saved_context_tokens":60,"pre_compaction_tokens":40,"total_tokens":300}}}"#.utf8).write(to: file)
        let modifiedAt = ISO8601DateFormatter().date(from: "2026-09-24T10:00:00Z")!
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: file.path)
        let externalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDirectory) }
        let externalFile = externalDirectory.appendingPathComponent("outside.json")
        try Data(#"{"usage":{"stats":{"saved_context_tokens":999999}}}"#.utf8).write(to: externalFile)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: externalFile.path)
        try FileManager.default.createSymbolicLink(at: sessionDirectory.appendingPathComponent("external.json"), withDestinationURL: externalFile)
        let now = ISO8601DateFormatter().date(from: "2026-09-24T12:00:00Z")!
        let snapshot = AIActivityReader.read(provider: .grok, range: .today, now: now,
                                            timeZone: TimeZone(secondsFromGMT: 0)!, homeDirectory: home)

        #expect(snapshot.available)
        #expect(snapshot.estimated)
        #expect(snapshot.partial)
        #expect(snapshot.totals.totalTokens == 100)
        #expect(snapshot.totals.sessions == 1)
        #expect(snapshot.totals.totalTokens < 999_999)
    }

    @Test func aiWidgetConfigurationAndSnapshotsSurviveBackupWithoutCredentials() throws {
        var item = DockItem.widget("AI Limits")
        item.widgetConfiguration?.aiLimitsVisibleProviders = [.codex, .claude]
        item.widgetConfiguration?.aiLimitsProviderOrder = [.claude, .codex, .grok, .cursor, .geminiCLI, .copilot, .antigravity]
        item.widgetConfiguration?.aiLimitsCompactProvider = .claude
        item.widgetConfiguration?.aiLimitsRepresentation = .used
        item.widgetConfiguration?.aiLimitsLayout = .rings
        item.widgetConfiguration?.aiLimitsSnapshot = AILimitsSnapshot(fetchedAt: .now,
            readings: [AIProviderLimitReading(provider: .codex, availability: .available, plan: "plus",
                                               windows: [.init(name: "Included · 5 hours", usedPercent: 31, resetsAt: nil, durationMinutes: 300)],
                                               updatedAt: .now, message: nil)])
        var activityItem = DockItem.widget("AI Activity")
        activityItem.widgetConfiguration?.aiActivityProvider = .claude
        activityItem.widgetConfiguration?.aiActivityRange = .thirtyDays
        activityItem.widgetConfiguration?.aiActivityChartStyle = .bars
        activityItem.widgetConfiguration?.aiActivitySnapshot = AIActivitySnapshot(provider: .claude, range: .thirtyDays,
            fetchedAt: .now, sourceDescription: "Local records", available: true, estimated: false, partial: false,
            message: nil, points: [], totals: AIActivityDailyPoint(date: .now, sessions: 2, toolCalls: 1, totalTokens: 300,
                cachedInputTokens: 50, inputTokens: 150, outputTokens: 100, requests: 4, reportedCostUSD: nil))
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "AI", kind: .custom, items: [item, activityItem])])
        let archiveText = String(decoding: archive, as: UTF8.self)
        let restored = try #require(BackupManager.readArchive(archive).importedProfiles.first?.items)
        let limits = try #require(restored[0].widgetConfiguration)
        let activity = try #require(restored[1].widgetConfiguration)

        #expect(limits.aiLimitsVisibleProviders == [.codex, .claude])
        #expect(limits.aiLimitsCompactProvider == .claude)
        #expect(limits.aiLimitsRepresentation == .used)
        #expect(limits.aiLimitsSnapshot == nil) // PR-13: readings are runtime cache, excluded from backups
        #expect(activity.aiActivityProvider == .claude)
        #expect(activity.aiActivityRange == .thirtyDays)
        #expect(activity.aiActivityChartStyle == .bars)
        #expect(activity.aiActivitySnapshot == nil)
        #expect(!archiveText.contains("PRIVATE_PROMPT"))
        #expect(!archiveText.contains("sk-ant-"))
        #expect(!archiveText.contains("gho_"))
        #expect(!archiveText.contains("client-secret"))

        let oldConfig = try JSONDecoder().decode(WidgetConfiguration.self, from: Data("{}".utf8))
        #expect(oldConfig.aiLimitsVisibleProviders == [.codex, .claude, .grok])
        #expect(oldConfig.aiActivityProvider == .codex)
    }

    @Test func aiActivityRangesUseLocalCalendarDaysAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Warsaw"))
        let now = try #require(ISO8601DateFormatter().date(from: "2026-03-31T10:00:00Z"))
        let range = AIActivityRange.sevenDays.interval(endingAt: now, calendar: calendar)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: range.start)

        #expect(components.year == 2026)
        #expect(components.month == 3)
        #expect(components.day == 25)
        #expect(components.hour == 0)
        #expect(range.end == now)
        #expect(AIActivityRange.today.chartInterval(endingAt: now, calendar: calendar).duration < 7 * 86_400)
    }

    @Test func focusFilterNilSelectionDoesNotRestoreOrSelectAProfile() throws {
        let selected = UUID()
        #expect(FocusDockSelectionPolicy.profileIDToApply(selected.uuidString) == selected)
        #expect(FocusDockSelectionPolicy.profileIDToApply(nil) == nil)
        #expect(FocusDockSelectionPolicy.profileIDToApply("not-a-profile") == nil)
    }

    @Test func appSettingsDecodeLegacyShapeAndPersistDesktopMode() throws {
        let legacy = #"{"customDockPosition":"left","customDockSize":1.2,"automaticallyHideCustomDock":true,"showRunningApps":false}"#
        let restoredLegacy = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        #expect(restoredLegacy.customDockPosition == .left)
        #expect(restoredLegacy.customDockSize == 1.2)
        #expect(restoredLegacy.automaticallyHideCustomDock)
        #expect(restoredLegacy.showRevealHandle)
        #expect(!restoredLegacy.hideCustomDockWhenSystemDockAppears)
        #expect(!restoredLegacy.customDockDesktopMode)
        #expect(restoredLegacy.customDockMaterial == .frosted)
        #expect(restoredLegacy.showWidgetLabels)
        #expect(restoredLegacy.customDockItemSpacing == 8)
        #expect(restoredLegacy.customDockCornerRadius == 24)
        #expect(restoredLegacy.customDockTintStrength == 0.08)
        #expect(restoredLegacy.customDockWidgetStyle == .cards)
        #expect(!restoredLegacy.smoothNativeDockSwitches)
        #expect(!restoredLegacy.automaticallySaveNativeDockChanges)
        #expect(!restoredLegacy.showActiveProfileNameInMenuBar)
        #expect(!restoredLegacy.showWindowPreviews)
        #expect(!restoredLegacy.showRunningApps)
        #expect(restoredLegacy.lastSettingsPage == .dock)

        var current = AppSettings()
        current.showRevealHandle = false
        current.customDockDesktopMode = true
        current.hideCustomDockWhenSystemDockAppears = true
        current.customDockMaterial = .liquidGlass
        current.showWidgetLabels = false
        current.smoothNativeDockSwitches = true
        current.showWindowPreviews = true
        current.showActiveProfileNameInMenuBar = true
        current.customDockItemSpacing = 14
        current.customDockCornerRadius = 30
        current.customDockTintStrength = 0.21
        current.customDockWidgetStyle = .compact
        current.lastSettingsPage = .shortcuts
        let restoredCurrent = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current))
        #expect(restoredCurrent.customDockDesktopMode)
        #expect(!restoredCurrent.showRevealHandle)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).hideCustomDockWhenSystemDockAppears)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).customDockMaterial == .liquidGlass)
        #expect(!restoredCurrent.showWidgetLabels)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).smoothNativeDockSwitches)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).showWindowPreviews)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).showActiveProfileNameInMenuBar)
        #expect(restoredCurrent.customDockItemSpacing == 14)
        #expect(restoredCurrent.customDockCornerRadius == 30)
        #expect(restoredCurrent.customDockTintStrength == 0.21)
        #expect(restoredCurrent.customDockWidgetStyle == .compact)
        #expect(restoredCurrent.lastSettingsPage == .shortcuts)

        current.customDockMaterial = .liquidGlassClear
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).customDockMaterial == .liquidGlassClear)

        let unbounded = #"{"customDockSize":999,"customDockItemSpacing":50,"customDockCornerRadius":3,"customDockTintStrength":2}"#
        let restoredUnbounded = try JSONDecoder().decode(AppSettings.self, from: Data(unbounded.utf8))
        #expect(restoredUnbounded.customDockSize == 1.5)
        // Global decode clamps to DockAppearanceBounds (spacing 0...30, corner 0...50, tint 0...0.5).
        #expect(restoredUnbounded.customDockItemSpacing == 30)
        #expect(restoredUnbounded.customDockCornerRadius == 3)
        #expect(restoredUnbounded.customDockTintStrength == 0.5)
    }

    @Test func settingsSidebarKeepsLegacyDockPageAndPersistsNewPages() throws {
        #expect(MyDockSettingsPage.allCases.count == 7)
        #expect(MyDockSettingsPage.dock.title == "Dock Setup")
        #expect(MyDockSettingsPage.appearance.searchTerms.contains("density"))
        #expect(MyDockSettingsPage.behavior.searchTerms.contains("auto hide"))
        #expect(try JSONDecoder().decode(MyDockSettingsPage.self, from: Data("\"dock\"".utf8)) == .dock)

        var settings = AppSettings()
        settings.lastSettingsPage = .appearance
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(restored.lastSettingsPage == .appearance)
    }

    @Test func dockSurfaceMetricsMatchRenderedTileGeometry() {
        let items = [DockItem.widget("Clock"), DockItem.spacer(.small), DockItem.widget("Battery")]
        // The panel sizes itself from the render model: items, the 14 pt pinned-end grip, spacing
        // between entries and 2 pt of edge slack. Clock Compact is 104 wide (MD-U03), Battery 90.
        func length(_ items: [DockItem], _ settings: AppSettings, scale: CGFloat = 1) -> CGFloat {
            DockRenderModel(profile: DockProfile(name: "P", kind: .custom, items: items), settings: settings,
                            unpinnedRunningApplications: [], windows: [], runningMediaSources: [])
                .contentLength(settings: settings, scale: scale)
        }
        var settings = AppSettings()
        settings.showRunningApps = false
        settings.showTrash = false
        settings.customDockWidgetStyle = .compact
        #expect(length(items, settings) == 242)
        settings.customDockWidgetStyle = .cards
        #expect(length(items, settings) == 242)
        settings.customDockItemSpacing = 14
        #expect(length(items, settings) == 260)
        #expect(length(items, settings, scale: 1.5) == 389)
        settings.customDockPosition = .left
        #expect(length(items, settings) == 174)
        settings.customDockPosition = .bottom
        settings.showTrash = true
        // The system Trash (54) joins only when the Dock has no Trash widget of its own.
        #expect(length([], settings) == 84)
        #expect(length([.widget("Trash")], settings) == 84)
    }

    @Test func adaptiveLayoutPersistsWithoutLabelOrIconWidthCoupling() throws {
        var widget = DockItem.widget("Weather")
        var settings = AppSettings()
        #expect(DockSurfaceMetrics.itemLength(widget, settings: settings, scale: 1) == 132)
        widget.widgetConfiguration?.widgetLayout = .wide
        widget.widgetConfiguration?.iconAppearance = .mono
        #expect(DockSurfaceMetrics.itemLength(widget, settings: settings, scale: 1) == 184)
        let restored = try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(widget))
        #expect(restored.widgetConfiguration?.widgetLayout == .wide)
        #expect(restored.widgetConfiguration?.iconAppearance == .mono)
        settings.showWidgetLabels = false
        settings.customDockWidgetStyle = .compact
        #expect(DockSurfaceMetrics.itemLength(widget, settings: settings, scale: 1) == 184)
        settings.customDockPosition = .left
        #expect(DockSurfaceMetrics.itemLength(widget, settings: settings, scale: 1) == 54)
    }

    @Test func menuBarProfileTitleReflectsTheSelectedDockModes() {
        let native = DockProfile(name: "Work", kind: .native)
        let custom = DockProfile(name: "Research", kind: .custom)
        var state = PersistentState()
        state.profiles = [native, custom]
        state.settings.activeNativeProfileID = native.id
        state.settings.activeCustomProfileID = custom.id

        state.settings.setupMode = .nativeOnly
        #expect(MenuBarProfileTitle.title(in: state) == "Work")
        state.settings.setupMode = .customMain
        #expect(MenuBarProfileTitle.title(in: state) == "Research")
        state.settings.setupMode = .both
        #expect(MenuBarProfileTitle.title(in: state) == "Work · Research")
        #expect(MenuBarProfileTitle.toolTip(in: state).contains("macOS Dock: Work; Custom Dock: Research"))

        state.settings.activeCustomProfileID = nil
        #expect(MenuBarProfileTitle.title(in: state) == "Work")
        state.settings.activeNativeProfileID = nil
        #expect(MenuBarProfileTitle.title(in: state) == nil)

        var longName = DockProfile(name: String(repeating: "A", count: 80), kind: .custom)
        longName.id = custom.id
        state.profiles = [native, longName]
        state.settings.activeCustomProfileID = custom.id
        #expect(MenuBarProfileTitle.title(in: state)?.count == 28)
        #expect(MenuBarProfileTitle.title(in: state)?.hasSuffix("…") == true)
        #expect(MenuBarProfileTitle.toolTip(in: state).contains(String(repeating: "A", count: 80)))
    }

    @Test func customMainModeRestoresTheOriginalAppleDockAutoHideAfterRestart() async throws {
        let defaults = ValidationDefaults()
        let backend = FakeDockAutoHideBackend(value: false)
        let relauncher = FakeDockRelauncher()
        let controller = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)

        try await controller.setCustomDockMain(true)
        #expect(backend.value == true)
        #expect(backend.settings == .replacement)
        #expect(controller.hasPendingRestore)
        #expect(relauncher.restartCount == 1)

        let restartedController = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)
        try await restartedController.restoreBeforeExit()
        #expect(backend.value == false)
        #expect(backend.settings.revealDelay == nil)
        #expect(backend.settings.noBouncing == nil)
        #expect(!restartedController.hasPendingRestore)
        #expect(relauncher.restartCount == 2)
    }

    @Test func customMainModePreservesAnUnsetDockPreferenceAndKeepsRecoveryAfterRestoreFailure() async throws {
        let defaults = ValidationDefaults()
        let backend = FakeDockAutoHideBackend(value: nil)
        let controller = NativeDockAutoHideController(backend: backend, relauncher: FakeDockRelauncher(), defaults: defaults)

        try await controller.setCustomDockMain(true)
        #expect(backend.value == true)
        backend.failingWrites = [2]
        do {
            try await controller.restoreBeforeExit()
            Issue.record("A failed preference restore must be reported")
        } catch {
            #expect(controller.hasPendingRestore)
            #expect(backend.value == true)
            #expect(controller.errorMessage?.contains("could not be restored") == true)
        }
        backend.failingWrites = []
        try await controller.restoreBeforeExit()
        #expect(backend.value == nil)
        #expect(!controller.hasPendingRestore)
        #expect(controller.errorMessage == nil)
    }

    @Test func replacementRestoresAllOriginalPreferencesAndDoesNotRestartWhenUnchanged() async throws {
        let defaults = ValidationDefaults()
        let backend = FakeDockAutoHideBackend(value: true, revealDelay: 0.35, noBouncing: false)
        let original = backend.settings
        let relauncher = FakeDockRelauncher()
        let controller = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)
        try await controller.setCustomDockMain(true)
        #expect(backend.settings == .replacement)
        #expect(relauncher.restartCount == 1)
        try await controller.setCustomDockMain(true)
        #expect(relauncher.restartCount == 1)
        let restarted = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)
        try await restarted.restoreBeforeExit()
        #expect(backend.settings == original)
        #expect(!restarted.hasPendingRestore)
    }

    @Test func replacementMigratesThePreviousAutoHideRecoveryRecordBeforeSuppressingHover() async throws {
        let defaults = ValidationDefaults()
        defaults.set(try JSONSerialization.data(withJSONObject: ["version": 1, "originalValue": false]),
                     forKey: "nativeDockAutoHideRecoveryRecord")
        let backend = FakeDockAutoHideBackend(value: true, revealDelay: 0.2, noBouncing: nil)
        let controller = NativeDockAutoHideController(backend: backend, relauncher: FakeDockRelauncher(), defaults: defaults)
        try await controller.setCustomDockMain(true)
        #expect(backend.settings == .replacement)
        let record = try #require(defaults.data(forKey: "nativeDockAutoHideRecoveryRecord"))
        let decoded = try #require(JSONSerialization.jsonObject(with: record) as? [String: Any])
        #expect(decoded["version"] as? Int == 2)
        try await controller.restoreBeforeExit()
        #expect(backend.settings == NativeDockVisibilitySettings(autoHide: false, revealDelay: 0.2, noBouncing: nil))
        #expect(!controller.hasPendingRestore)
    }

    @Test func previousAutoHideRecordCanRestoreWithoutChangingUnownedPreferences() async throws {
        let defaults = ValidationDefaults()
        defaults.set(try JSONSerialization.data(withJSONObject: ["version": 1]), forKey: "nativeDockAutoHideRecoveryRecord")
        let backend = FakeDockAutoHideBackend(value: true, revealDelay: 2, noBouncing: false)
        let controller = NativeDockAutoHideController(backend: backend, relauncher: FakeDockRelauncher(), defaults: defaults)
        try await controller.restoreBeforeExit()
        #expect(backend.settings == NativeDockVisibilitySettings(autoHide: nil, revealDelay: 2, noBouncing: false))
    }
}

private func writeJSONLines(_ rows: [[String: Any]], to url: URL) throws {
    let data = try rows.map { try JSONSerialization.data(withJSONObject: $0) }.reduce(into: Data()) { result, line in
        result.append(line)
        result.append(0x0A)
    }
    try data.write(to: url, options: .atomic)
}

private func stripeRows(_ json: String) throws -> [[String: Any]] {
    let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    return root?["data"] as? [[String: Any]] ?? []
}

private func paddleMetricFixture(currency: String? = nil, values: String) -> Data {
    let currencyField = currency.map { "\"currency_code\":\"\($0)\"," } ?? ""
    return Data("{\"data\":{\(currencyField)\"updated_at\":\"2026-09-24T23:00:00Z\",\"timeseries\":\(values)}}".utf8)
}

private actor StripeFixtureTransport: StripeDataTransport {
    private var requests: [URLRequest] = []
    private var transactionPage = 0
    private let transactionHasMore: Bool

    init(transactionHasMore: Bool = false) {
        self.transactionHasMore = transactionHasMore
    }

    func response(for request: URLRequest) async throws -> StripeHTTPResponse {
        requests.append(request)
        let data: Data
        switch request.url?.path {
        case "/v1/balance":
            data = Data(#"{"available":[],"pending":[]}"#.utf8)
        case "/v1/balance_transactions" where transactionHasMore:
            transactionPage += 1
            data = Data("{\"has_more\":true,\"data\":[{\"id\":\"txn_\(transactionPage)\"}]}".utf8)
        case "/v1/balance_transactions", "/v1/subscriptions":
            data = Data(#"{"has_more":false,"data":[]}"#.utf8)
        default:
            data = Data("{}".utf8)
        }
        return StripeHTTPResponse(statusCode: 200, data: data)
    }

    func capturedRequests() -> [URLRequest] { requests }
}

private actor PaddleFixtureTransport: PaddleDataTransport {
    private var requests: [URLRequest] = []

    func response(for request: URLRequest) async throws -> PaddleHTTPResponse {
        requests.append(request)
        let data: Data
        switch request.url?.path {
        case "/metrics/revenue":
            data = paddleMetricFixture(currency: "USD", values: #"[{"timestamp":"2026-09-22T00:00:00Z","amount":"1000","count":2},{"timestamp":"2026-09-23T00:00:00Z","amount":"2500","count":3}]"#)
        case "/metrics/monthly-recurring-revenue":
            data = paddleMetricFixture(currency: "USD", values: #"[{"timestamp":"2026-09-22T00:00:00Z","amount":"10000"},{"timestamp":"2026-09-23T00:00:00Z","amount":"12000"}]"#)
        case "/metrics/active-subscribers":
            data = paddleMetricFixture(values: #"[{"timestamp":"2026-09-22T00:00:00Z","count":3},{"timestamp":"2026-09-23T00:00:00Z","count":4}]"#)
        default:
            data = Data("{}".utf8)
        }
        return PaddleHTTPResponse(statusCode: 200, data: data)
    }

    func capturedRequests() -> [URLRequest] { requests }
}

private actor ShopifyFixtureTransport: ShopifyDataTransport {
    private var requests: [URLRequest] = []
    private var orderPage = 0
    private let alwaysHasMoreOrders: Bool

    init(alwaysHasMoreOrders: Bool = false) {
        self.alwaysHasMoreOrders = alwaysHasMoreOrders
    }

    func response(for request: URLRequest) async throws -> ShopifyHTTPResponse {
        requests.append(request)
        guard let path = request.url?.path else { return ShopifyHTTPResponse(statusCode: 400, data: Data()) }
        switch path {
        case "/admin/oauth/access_token":
            return ShopifyHTTPResponse(statusCode: 200,
                                       data: Data(#"{"access_token":"fixture-access-token","expires_in":86399,"scope":"read_orders"}"#.utf8))
        case "/admin/api/\(ShopifyAPIProvider.apiVersion)/graphql.json":
            let requestObject = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any]
            let query = requestObject?["query"] as? String ?? ""
            if query.contains("StoreMetadata") {
                return ShopifyHTTPResponse(statusCode: 200,
                                           data: Data(#"{"data":{"shop":{"name":"Acme Store","ianaTimezone":"America/New_York","currencyCode":"USD"}}}"#.utf8))
            }
            orderPage += 1
            let pageInfo: [String: Any]
            let nodes: [[String: Any]]
            if orderPage == 1 {
                nodes = [Self.order(createdAt: "2026-09-24T11:00:00Z", amount: "12.50", title: "Mug", quantity: 2, source: "Google")]
                pageInfo = ["hasNextPage": true, "endCursor": "cursor-one"]
            } else {
                nodes = [Self.order(createdAt: "2026-09-24T15:30:00Z", amount: "5.00", title: "Book", quantity: 1, source: nil)]
                pageInfo = ["hasNextPage": alwaysHasMoreOrders, "endCursor": alwaysHasMoreOrders ? "cursor-two" : NSNull()]
            }
            let body: [String: Any] = ["data": ["orders": ["nodes": nodes, "pageInfo": pageInfo]]]
            return ShopifyHTTPResponse(statusCode: 200, data: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        default:
            return ShopifyHTTPResponse(statusCode: 404, data: Data())
        }
    }

    func capturedRequests() -> [URLRequest] { requests }

    private static func order(createdAt: String, amount: String, title: String, quantity: Int, source: String?) -> [String: Any] {
        let visit: [String: Any]? = source.map { ["source": $0, "utmParameters": ["source": $0, "medium": "organic", "campaign": "fixture"]] }
        return [
            "id": "gid://shopify/Order/\(createdAt)",
            "createdAt": createdAt,
            "test": false,
            "currentTotalPriceSet": ["shopMoney": ["amount": amount, "currencyCode": "USD"]],
            "lineItems": ["nodes": [["name": title, "currentQuantity": quantity]], "pageInfo": ["hasNextPage": false]],
            "customerJourneySummary": ["firstVisit": visit as Any? ?? NSNull(), "lastVisit": visit as Any? ?? NSNull()]
        ]
    }
}

@MainActor
private enum NativeDockTestFixtures {
    static func applicationTile(_ url: URL) -> [String: Any] {
        [
            "GUID": 42,
            "tile-type": "file-tile",
            "tile-data": [
                "book": Data(),
                "bundle-identifier": "com.apple.calculator",
                "dock-extra": false,
                "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
                "file-label": "Calculator",
                "file-mod-date": 0,
                "file-type": 41,
                "is-beta": false,
                "parent-mod-date": 0
            ] as [String: Any]
        ]
    }
}

@MainActor
private final class FakeDockPreferencesBackend: DockPreferencesBackend {
    var tiles: [[String: Any]]
    var failReads = false
    var failingWrites: Set<Int>
    private(set) var writeCount = 0

    init(tiles: [[String: Any]], failingWrites: Set<Int> = []) {
        self.tiles = tiles
        self.failingWrites = failingWrites
    }

    func readCurrentTiles() throws -> [[String: Any]] {
        if failReads { throw NativeDockError.preferencesUnavailable }
        return tiles
    }

    func writeTiles(_ tiles: [[String: Any]]) throws {
        writeCount += 1
        if failingWrites.contains(writeCount) { throw NativeDockError.preferencesUnavailable }
        self.tiles = tiles
    }
}

@MainActor
private final class FakeDockRelauncher: DockRelaunching {
    private(set) var restartCount = 0
    var delay: Duration

    init(delay: Duration = .zero) { self.delay = delay }

    func restartDock() async throws {
        restartCount += 1
        if delay > .zero { try await Task.sleep(for: delay) }
    }
}

@MainActor
private final class FakeDockTransactionJournal: DockTransactionJournal {
    private(set) var isPending = false
    private var snapshot: [[String: Any]]?

    func begin(snapshot: [[String: Any]], profileID: UUID) throws {
        self.snapshot = snapshot
        isPending = true
    }

    func pendingSnapshot() throws -> [[String: Any]]? { snapshot }

    func clear() throws {
        snapshot = nil
        isPending = false
    }
}

@MainActor
private final class FakeDockAutoHideBackend: DockAutoHidePreferencesBackend {
    var settings: NativeDockVisibilitySettings
    var value: Bool? {
        get { settings.autoHide }
        set { settings.autoHide = newValue }
    }
    var failingWrites: Set<Int> = []
    private(set) var writeCount = 0

    init(value: Bool?, revealDelay: Double? = nil, noBouncing: Bool? = nil) {
        settings = NativeDockVisibilitySettings(autoHide: value, revealDelay: revealDelay, noBouncing: noBouncing)
    }

    func readVisibilitySettings() throws -> NativeDockVisibilitySettings { settings }

    func writeVisibilitySettings(_ settings: NativeDockVisibilitySettings) throws {
        writeCount += 1
        if failingWrites.contains(writeCount) { throw NativeDockError.preferencesUnavailable }
        self.settings = settings
    }
}

@MainActor
private final class FakeDockSwitchFreezeProvider: DockSwitchFreezeProviding {
    private(set) var beginCount = 0
    private(set) var endCount = 0
    private var activeSession: UUID?

    func beginIfEnabled() async -> UUID? {
        beginCount += 1
        let session = UUID()
        activeSession = session
        return session
    }

    func end(_ sessionID: UUID) {
        if activeSession == sessionID {
            activeSession = nil
            endCount += 1
        }
    }
}
