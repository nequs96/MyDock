import AppKit
import Foundation
import Testing
@testable import MyDock

@MainActor
struct ProfileStoreTests {
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
        let profileID = first.createProfile(kind: .custom, name: "Research")
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
        _ = store.createProfile(kind: .custom)
        #expect(try Data(contentsOf: file) == futureData)
        #expect(store.persistenceError == nil)
    }

    @Test func onboardingCreatesSelectedProfilesAndStarterWidgets() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let imported = [DockItem.application(at: URL(fileURLWithPath: "/Applications/Preview.app")), .spacer(.small)]

        store.finishOnboarding(setupMode: .both,
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

    @Test func moveItemPreservesOrderAndSpacerIdentity() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = store.createProfile(kind: .custom)
        let one = DockItem.widget("Clock")
        let small = DockItem.spacer(.small)
        let regular = DockItem.spacer(.regular)
        store.add(one, to: profileID)
        store.add(small, to: profileID)
        store.add(regular, to: profileID)

        store.moveItem(regular.id, before: one.id, in: profileID)

        let items = store.state.profiles.first { $0.id == profileID }?.items
        #expect(items?.map(\.id) == [regular.id, one.id, small.id])
        #expect(items?.first?.spacerKind == .regular)
        #expect(items?.last?.spacerKind == .small)
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

    @Test func dockProfileDraftBecomesCleanAfterExplicitSave() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let store = ProfileStore(fileURL: file)
        let profileID = store.createProfile(kind: .custom, name: "Before")
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

    @Test func movingSelectedItemsKeepsTheirOrderAndMovesAsAGroup() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = store.createProfile(kind: .custom)
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
        let profileID = store.createProfile(kind: .custom, name: "Work")
        let first = DockItem.widget("Clock")
        let retained = DockItem.spacer(.small)
        let last = DockItem.widget("Battery")
        store.add(first, to: profileID)
        store.add(retained, to: profileID)
        store.add(last, to: profileID)

        store.removeItems([first.id, last.id], from: profileID)

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
        let profileID = store.createProfile(kind: .custom, name: "Notes")
        let note = DockItem.widget("Sticky Note")
        store.add(note, to: profileID)
        store.updateWidgetConfiguration(itemID: note.id, in: profileID) {
            $0.noteText = "Bring the notebook"
            $0.noteBackground = .blue
        }

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
        stopwatch.startStopwatch(at: start)
        #expect(stopwatch.stopwatchElapsed(at: start.addingTimeInterval(12)) == 12)
        stopwatch.pauseStopwatch(at: start.addingTimeInterval(12))
        #expect(stopwatch.stopwatchElapsed(at: start.addingTimeInterval(500)) == 12)

        var countdown = WidgetConfiguration()
        countdown.countdownDurationSeconds = 90
        countdown.startCountdown(at: start)
        #expect(countdown.countdownRemaining(at: start.addingTimeInterval(30)) == 60)
        countdown.pauseCountdown(at: start.addingTimeInterval(30))
        #expect(countdown.countdownRemaining(at: start.addingTimeInterval(500)) == 60)
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
        #expect(restored.timeProgressPeriod == .day)
        #expect(restored.calendarLayout == .dateAndNextEvent)
        #expect(restored.selectedCalendarIDs.isEmpty)
        #expect(restored.remindersLayout == .list)
        #expect(restored.alarms.isEmpty)
        #expect(restored.nowPlayingSource == .appleMusic)
        #expect(restored.nowPlayingLayout == .full)
        #expect(restored.nowPlayingSkipSeconds == 15)
        #expect(!restored.nowPlayingHidesWhenClosed)
        #expect(restored.worldClockAdditionalTimeZoneIDs.isEmpty)
    }

    @Test func countdownNotificationsUseWidgetScopedIdentifiers() {
        let first = UUID()
        let second = UUID()
        #expect(CountdownNotificationService.notificationID(itemID: first) == "mydock.countdown.\(first.uuidString)")
        #expect(CountdownNotificationService.notificationID(itemID: first) != CountdownNotificationService.notificationID(itemID: second))
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
        item.widgetConfiguration?.watchlistStocks = [WatchlistStock(symbol: "AAPL", name: "Apple Inc.", currency: "USD", snapshot: nil)]
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Markets", kind: .custom, items: [item])])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration

        #expect(restored?.stockRange == .year)
        #expect(restored?.stockRefreshIntervalMinutes == 720)
        #expect(restored?.stockShowsVolume == true)
        #expect(restored?.watchlistSelectedSymbol == "AAPL")
        #expect(restored?.watchlistStocks.first?.currency == "USD")
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

    @Test func duplicatingProfileDisablesAlarmsWithOriginalNotificationIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = store.createProfile(kind: .custom, name: "Morning")
        var alarmItem = DockItem.widget("Alarm")
        alarmItem.widgetConfiguration?.alarms = [DockAlarm(title: "Wake", hour: 7, minute: 0, repeatWeekdays: [2], isEnabled: true)]
        store.add(alarmItem, to: profileID)
        store.duplicateProfile(profileID)

        let copy = store.state.profiles.last
        #expect(copy?.items.first?.id != alarmItem.id)
        #expect(copy?.items.first?.widgetConfiguration?.alarms.first?.isEnabled == false)
    }

    @Test func duplicatingProfileResetsCountdownRunState() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"))
        let profileID = store.createProfile(kind: .custom, name: "Timers")
        var countdown = DockItem.widget("Countdown")
        countdown.widgetConfiguration?.countdownDurationSeconds = 600
        countdown.widgetConfiguration?.startCountdown(at: Date(timeIntervalSince1970: 100))
        store.add(countdown, to: profileID)
        store.duplicateProfile(profileID)

        let copiedConfiguration = store.state.profiles.last?.items.first?.widgetConfiguration
        #expect(copiedConfiguration?.countdownDurationSeconds == 600)
        #expect(copiedConfiguration?.countdownStartedAt == nil)
        #expect(copiedConfiguration?.countdownRemaining(at: Date(timeIntervalSince1970: 500)) == 600)
        try? FileManager.default.removeItem(at: directory)
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
        #expect(configuration.hydrationVolumeSummary(at: today, calendar: calendar) == "At least 250 mL · incomplete")

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

    @Test func dockMagnificationIsLocalizedAndHonorsAccessibilityMotionSetting() {
        #expect(abs(DockMagnification.scale(for: 4, focusedIndex: 4, enabled: true, reduceMotion: false) - 1.38) < 0.001)
        #expect(abs(DockMagnification.scale(for: 3, focusedIndex: 4, enabled: true, reduceMotion: false) - 1.2) < 0.001)
        #expect(abs(DockMagnification.scale(for: 2, focusedIndex: 4, enabled: true, reduceMotion: false) - 1.08) < 0.001)
        #expect(DockMagnification.scale(for: 1, focusedIndex: 4, enabled: true, reduceMotion: false) == 1)
        #expect(DockMagnification.scale(for: 4, focusedIndex: 4, isWidget: true, enabled: true, reduceMotion: false) < 1.38)
        #expect(DockMagnification.scale(for: 4, focusedIndex: 4, enabled: false, reduceMotion: false) == 1)
        #expect(DockMagnification.scale(for: 4, focusedIndex: 4, enabled: true, reduceMotion: true) == 1)
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

        var customized = DockItem.file(at: URL(fileURLWithPath: "/tmp/Projects"), isFolder: true)
        customized.folderIconColor = .purple
        customized.folderIconLetter = "P"
        customized.folderIconNumber = "12"
        let archive = try BackupManager.makeArchive(from: [DockProfile(name: "Folder Icons", kind: .custom, items: [customized])])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0]
        #expect(restored.folderIconColor == .purple)
        #expect(restored.folderIconLetter == "P")
        #expect(restored.folderIconNumber == "12")
        #expect(restored.hasCustomFolderIcon)
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

        #expect(CustomDockVisibilityPolicy.shouldHideForSystemDock(customDockFrame: customDock,
                                                                   systemDockFrames: [overlappingSystemDock]))
        #expect(!CustomDockVisibilityPolicy.shouldHideForSystemDock(customDockFrame: customDock,
                                                                    systemDockFrames: [separateSystemDock]))
        #expect(!CustomDockVisibilityPolicy.shouldHideForSystemDock(customDockFrame: customDock,
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

    @Test func globalShortcutBindingsPersistOutsideProfileBackupsAndRejectDuplicates() throws {
        let suiteName = "MyDockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        #expect(restored?.weatherUnit == .fahrenheit)
        #expect(restored?.weatherLayout == .hourlyForecast)
        #expect(restored?.weatherForecastHours == 6)
        #expect(restored?.weatherBackground == .translucent)
        #expect(restored?.cachedWeatherForecast == cached)
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

        #expect(try TrashContentsReader.itemCount(at: directory) == 3)
        #expect(WidgetRegistry.all.contains(where: { $0.name == "Trash" }))
    }

    @Test func nowPlayingConfigurationSurvivesBackupRoundTrip() throws {
        var item = DockItem.widget("Now Playing")
        item.widgetConfiguration?.nowPlayingSource = .spotify
        item.widgetConfiguration?.nowPlayingLayout = .mini
        item.widgetConfiguration?.nowPlayingSkipSeconds = 30
        item.widgetConfiguration?.nowPlayingHidesWhenClosed = true
        let profile = DockProfile(name: "Music", kind: .custom, items: [item])

        let archive = try BackupManager.makeArchive(from: [profile])
        let restored = try BackupManager.readArchive(archive).importedProfiles[0].items[0].widgetConfiguration

        #expect(restored?.nowPlayingSource == .spotify)
        #expect(restored?.nowPlayingLayout == .mini)
        #expect(restored?.nowPlayingSkipSeconds == 30)
        #expect(restored?.nowPlayingHidesWhenClosed == true)
        #expect(!NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: true, source: .spotify,
                                                      runningSources: [.appleMusic]))
        #expect(NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: true, source: .spotify,
                                                     runningSources: [.spotify]))
        #expect(NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: false, source: .spotify,
                                                     runningSources: []))
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: true, kinds: [.compact]) == 15)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: true, kinds: [.compact, .popout]) == 5)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: false, kinds: [.popout]) == nil)
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
        #expect(restored.stripeSnapshot?.metrics(for: "EUR")?.mrrMinor == 800)
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
        #expect(restored.paddleSnapshot?.latestARRMinor == 12000)
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
        #expect(restored.shopifySnapshot?.averageOrderValue == Decimal(string: "12.5"))
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
        #expect(requests.count == 4)
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
        #expect(snapshot.totals.sessions == 2)
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
        #expect(snapshot.totals.sessions == 2)
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
        #expect(limits.aiLimitsSnapshot?.reading(for: .codex)?.windows.first?.usedPercent == 31)
        #expect(activity.aiActivityProvider == .claude)
        #expect(activity.aiActivityRange == .thirtyDays)
        #expect(activity.aiActivityChartStyle == .bars)
        #expect(activity.aiActivitySnapshot?.totals.totalTokens == 300)
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
        #expect(!restoredLegacy.hideCustomDockWhenSystemDockAppears)
        #expect(!restoredLegacy.customDockDesktopMode)
        #expect(restoredLegacy.customDockMaterial == .frosted)
        #expect(!restoredLegacy.smoothNativeDockSwitches)
        #expect(!restoredLegacy.showWindowPreviews)
        #expect(!restoredLegacy.showRunningApps)

        var current = AppSettings()
        current.customDockDesktopMode = true
        current.hideCustomDockWhenSystemDockAppears = true
        current.customDockMaterial = .liquidGlass
        current.smoothNativeDockSwitches = true
        current.showWindowPreviews = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).customDockDesktopMode)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).hideCustomDockWhenSystemDockAppears)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).customDockMaterial == .liquidGlass)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).smoothNativeDockSwitches)
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(current)).showWindowPreviews)
    }

    @Test func customMainModeRestoresTheOriginalAppleDockAutoHideAfterRestart() async throws {
        let suiteName = "MyDock.AutoHideTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let backend = FakeDockAutoHideBackend(value: false)
        let relauncher = FakeDockRelauncher()
        let controller = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)

        try await controller.setCustomDockMain(true)
        #expect(backend.value == true)
        #expect(controller.hasPendingRestore)
        #expect(relauncher.restartCount == 1)

        let restartedController = NativeDockAutoHideController(backend: backend, relauncher: relauncher, defaults: defaults)
        try await restartedController.restoreBeforeExit()
        #expect(backend.value == false)
        #expect(!restartedController.hasPendingRestore)
        #expect(relauncher.restartCount == 2)
    }

    @Test func customMainModePreservesAnUnsetDockPreferenceAndKeepsRecoveryAfterRestoreFailure() async throws {
        let suiteName = "MyDock.AutoHideTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
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
        }
        backend.failingWrites = []
        try await controller.restoreBeforeExit()
        #expect(backend.value == nil)
        #expect(!controller.hasPendingRestore)
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
    var failingWrites: Set<Int>
    private(set) var writeCount = 0

    init(tiles: [[String: Any]], failingWrites: Set<Int> = []) {
        self.tiles = tiles
        self.failingWrites = failingWrites
    }

    func readCurrentTiles() throws -> [[String: Any]] { tiles }

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
    var value: Bool?
    var failingWrites: Set<Int> = []
    private(set) var writeCount = 0

    init(value: Bool?) { self.value = value }

    func readAutoHideSetting() throws -> Bool? { value }

    func writeAutoHideSetting(_ value: Bool?) throws {
        writeCount += 1
        if failingWrites.contains(writeCount) { throw NativeDockError.preferencesUnavailable }
        self.value = value
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
