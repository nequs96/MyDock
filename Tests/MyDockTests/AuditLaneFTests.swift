import EventKit
import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// Audit lane F: personal, data, system and business widget families.
@Suite struct AuditLaneFTests {
    // MARK: Calendar and Reminders

    @Test func deletedSelectionIsNotReportedAsAPermissionProblem() {
        #expect(EventKitReadFailure(CalendarRemindersServiceError.accessDenied) == .accessDenied)
        #expect(EventKitReadFailure(CalendarRemindersServiceError.calendarUnavailable) == .selectionUnavailable)
        #expect(EventKitReadFailure(CalendarRemindersServiceError.listUnavailable) == .selectionUnavailable)
        #expect(EventKitReadFailure(CancellationError()) == .other)
        #expect(CalendarFacePresentation.emptyState(errorMessage: "x", accessAvailable: false).detail == "Allow access")
        #expect(CalendarFacePresentation.emptyState(errorMessage: "x", accessAvailable: false, failure: .selectionUnavailable).detail == "Choose calendars")
        #expect(CalendarFacePresentation.emptyState(errorMessage: "x", accessAvailable: false, failure: .other).detail != "Allow access")
        // A reminder list is called a list, not a calendar.
        let listMessage = CalendarRemindersServiceError.listUnavailable.localizedDescription
        #expect(listMessage.contains("list") && !listMessage.contains("calendar"))
    }

    @MainActor @Test func eventKitSignalsCoalesceIntoOneRefresh() async throws {
        let center = NotificationCenter()
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: true)
        let monitor = EventKitChangeMonitor(delay: .milliseconds(50), center: center, workspaceCenter: center, scheduler: scheduler)
        for _ in 0..<5 { monitor.signal() }
        try await waitUntil { monitor.generation >= 1 }
        #expect(monitor.generation == 1)
        // A posted store change reaches the monitor through the main actor and counts once.
        center.post(name: .EKEventStoreChanged, object: nil)
        try await waitUntil { monitor.generation >= 2 }
        #expect(monitor.generation == 2)
    }

    @MainActor @Test func eventKitSignalWaitsWhileNothingIsVisible() async throws {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let center = NotificationCenter()
        let monitor = EventKitChangeMonitor(delay: .milliseconds(10), center: center, workspaceCenter: center, scheduler: scheduler)
        monitor.signal()
        // The signal parks on the scheduler instead of refreshing a hidden Dock.
        try await waitUntil { scheduler.subscriptionCount == 1 }
        #expect(monitor.generation == 0)
        scheduler.setDockVisible(true)
        scheduler.fireDueSubscriptions(now: .now.addingTimeInterval(5))
        try await waitUntil { monitor.generation == 1 }
        try await waitUntil { scheduler.subscriptionCount == 0 }
    }

    // MARK: Saved collections

    @Test func unnamedSnippetTextNeverReachesTheDockFace() {
        var configuration = WidgetConfiguration()
        configuration.textSnippets = [TextSnippet(title: "", text: "sk_live_secret token for billing")]
        let latest = SavedCollectionFacePresentation.latest(kind: "Text Snippets", configuration: configuration)
        #expect(latest == nil)
        let label = SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: latest, layout: .wide, narrow: false, count: 1)
        #expect(label == "Saved")
        #expect(!label.contains("secret"))
        // Only the popout shows a preview of an unnamed snippet.
        #expect(configuration.textSnippets[0].displayTitle.hasPrefix("sk_live_secret"))
        #expect(TextSnippet(title: " Reply ", text: "Thanks").displayTitle == "Reply")
        // Other collections keep naming their latest entry.
        configuration.quickLinks = [QuickLink(title: "Docs", url: URL(string: "https://example.com")!)]
        #expect(SavedCollectionFacePresentation.latest(kind: "Quick Links", configuration: configuration) == "Docs")
    }

    @Test func shelfAvailabilityResolvesEachEntryOnce() {
        let present = ShelfFile(url: URL(fileURLWithPath: "/nonexistent-mydock-audit/present.pdf"))
        let missing = ShelfFile(url: URL(fileURLWithPath: "/nonexistent-mydock-audit/missing.pdf"))
        let calls = CallCounter()
        let resolved = ShelfFileAvailability.resolve([present, missing]) { url in
            calls.increment()
            return url.lastPathComponent == "present.pdf"
        }
        #expect(calls.value == 2)
        #expect(resolved[present.id]?.exists == true)
        #expect(resolved[missing.id]?.exists == false)
        #expect(resolved[missing.id]?.url.lastPathComponent == "missing.pdf")
    }

    // MARK: Dock tiles

    @Test func thumbnailBucketsChangeOnlyAtResolutionSteps() {
        #expect(DockFileThumbnailBucket.pixelSize(for: 48) == 128)
        #expect(DockFileThumbnailBucket.pixelSize(for: 48.7) == 128)
        #expect(DockFileThumbnailBucket.pixelSize(for: 64) == 128)
        #expect(DockFileThumbnailBucket.pixelSize(for: 65) == 256)
        #expect(DockFileThumbnailBucket.pixelSize(for: 400) == 512)
    }

    @Test func calendarIconPolicyTrustsTheSavedIdentifier() {
        var item = DockItem.application(at: URL(fileURLWithPath: "/System/Applications/Calendar.app"))
        item.bundleIdentifier = "com.example.notcalendar"
        #expect(!CalendarAppIconPolicy.requiresDateRefresh(item))
        item.bundleIdentifier = CalendarAppIconPolicy.bundleIdentifier
        #expect(CalendarAppIconPolicy.requiresDateRefresh(item))
    }

    // MARK: Alarm

    @Test func alarmChipsFollowTheLocaleWeekAndStayDistinct() {
        var monday = Calendar(identifier: .gregorian)
        monday.locale = Locale(identifier: "en_GB")
        monday.firstWeekday = 2
        let chips = AlarmFacePresentation.weekdayChips(calendar: monday)
        #expect(chips.map(\.weekday) == [2, 3, 4, 5, 6, 7, 1])
        #expect(chips.first?.name == "Monday")
        #expect(AlarmFacePresentation.orderedWeekdays(firstWeekday: 1) == [1, 2, 3, 4, 5, 6, 7])
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        #expect(AlarmFacePresentation.repeatSummary([1, 2], symbols: symbols, firstWeekday: 2) == "Mon Sun")
        #expect(AlarmFacePresentation.repeatSummary([1, 2], symbols: symbols, firstWeekday: 1) == "Sun Mon")
        var chinese = Calendar(identifier: .gregorian)
        chinese.locale = Locale(identifier: "zh_CN")
        #expect(Set(AlarmFacePresentation.weekdayChips(calendar: chinese).map(\.letter)).count == 7)
    }

    // MARK: Markets

    @Test func marketFaceChangeUsesTheTestedFormat() {
        #expect(StockFaceFormatting.faceChangeText(1.24, locale: Locale(identifier: "en_US")) == "+1.2%")
        #expect(StockFaceFormatting.faceChangeText(1.24, locale: Locale(identifier: "pl_PL"))?.contains("+1,2") == true)
        #expect(StockFaceFormatting.faceChangeText(nil) == nil)
        #expect(StockFaceFormatting.faceChangeText(Double.nan) == nil)
        #expect(StockFaceFormatting.percentText(1.25, locale: Locale(identifier: "en_US")) == "+1.25%")
    }

    // MARK: Weather

    @Test func weatherStalenessMatchesThePopoutRule() {
        let now = Date(timeIntervalSince1970: 100_000)
        #expect(!WeatherFreshness.isStale(fetchedAt: nil, failed: true, now: now))
        #expect(!WeatherFreshness.isStale(fetchedAt: now.addingTimeInterval(-60), failed: false, now: now))
        #expect(WeatherFreshness.isStale(fetchedAt: now.addingTimeInterval(-60), failed: true, now: now))
        #expect(WeatherFreshness.isStale(fetchedAt: now.addingTimeInterval(-31 * 60), failed: false, now: now))
    }

    @MainActor @Test func weatherForecastPublishesAsARuntimeReading() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-LaneF-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(fileURL: dir.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var item = DockItem.widget("Weather")
        item.widgetConfiguration?.weatherLocation = WeatherLocation(id: "city-1", name: "Warsaw", administrativeArea: nil, country: "Poland",
                                                                     latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw")
        let profileID = try store.createProfile(.init(name: "P", kind: .custom, items: [item]))
        let historyCount = store.history.entries.count
        let forecast = WeatherForecast(temperature: 18, apparentTemperature: 17, relativeHumidity: 60, precipitation: 0, windSpeed: 6,
                                       weatherCode: 1, isDay: true, fetchedAt: Date(timeIntervalSince1970: 5_000),
                                       timeZoneIdentifier: "Europe/Warsaw", hourly: [])
        let result = store.publishRuntimeReadings(itemID: item.id, in: profileID) { $0.cachedWeatherForecast = forecast }
        #expect(result == .accepted)
        // The reading is shown without becoming authored state or history, so it never depends on saving.
        #expect(store.presentationItem(store.state.profiles[0].items[0]).widgetConfiguration?.cachedWeatherForecast == forecast)
        #expect(store.state.profiles[0].items[0].widgetConfiguration?.cachedWeatherForecast == nil)
        #expect(store.history.entries.count == historyCount)
    }

    // MARK: AI

    @Test func estimatedTokenTotalsAreMarked() throws {
        var snapshot = try #require(AIActivityPreviewData.item().widgetConfiguration?.aiActivitySnapshot)
        snapshot.estimated = true
        snapshot.partial = true
        #expect(AIFacePresentation.marked("644M", snapshot: snapshot) == "~644M")
        snapshot.estimated = false
        #expect(AIFacePresentation.marked("644M", snapshot: snapshot) == "644M+")
        snapshot.partial = false
        #expect(AIFacePresentation.marked("644M", snapshot: snapshot) == "644M")
    }

    @Test func retainedLimitReadingShowsItsOwnSuccessTime() {
        let when = Date(timeIntervalSince1970: 1_000)
        let retained = AIProviderLimitReading(provider: .copilot, availability: .available,
                                              windows: [.init(name: "Monthly credits", usedPercent: 28)],
                                              updatedAt: when, message: "Plan", lastRefreshError: "Network unavailable")
        let subtitle = AILimitsStalePresentation.subtitle(for: retained)
        #expect(subtitle?.hasPrefix("Stale · last successful reading " + when.formatted(date: .abbreviated, time: .shortened)) == true)
        #expect(subtitle?.hasSuffix("Network unavailable") == true)
        let current = AIProviderLimitReading(provider: .copilot, availability: .available, windows: [], message: "Plan")
        #expect(AILimitsStalePresentation.subtitle(for: current) == "Plan")
    }

    // MARK: Business

    @Test func unconnectedBusinessWidgetOffersSavedConnections() {
        #expect(BusinessSetupPresentation.offersExistingConnections(accountID: "", hasSavedReading: false, connectionCount: 2))
        #expect(!BusinessSetupPresentation.offersExistingConnections(accountID: "", hasSavedReading: false, connectionCount: 0))
        // Connected or showing a saved reading: the settings already hold the account picker.
        #expect(!BusinessSetupPresentation.offersExistingConnections(accountID: "acct", hasSavedReading: false, connectionCount: 2))
        #expect(!BusinessSetupPresentation.offersExistingConnections(accountID: "", hasSavedReading: true, connectionCount: 2))
    }

    // MARK: System Activity

    @Test func storageScanSkipsSubtreesCountedAsTheirOwnLocation() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Keep", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Library", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("Keep/a.bin"))
        try Data(repeating: 2, count: 100).write(to: root.appendingPathComponent("Library/b.bin"))
        try Data(repeating: 3, count: 1).write(to: root.appendingPathComponent("c.bin"))

        let all = try StorageScanner.scan(at: root)
        #expect(all.scannedFileCount == 3)
        let disjoint = try StorageScanner.scan(at: root, excluding: [root.appendingPathComponent("Library", isDirectory: true)])
        #expect(disjoint.scannedFileCount == 2)
        #expect(disjoint.scannedBytes == 11)
        #expect(!disjoint.largestFiles.contains { $0.name == "b.bin" })
    }

    // MARK: Part 2: system rates and Now Playing

    @Test func networkRatesShareOneClampAndNeverTrap() {
        #expect(NetworkRateText.full(2_048) == SystemDetailFormatting.rate(2_048))
        #expect(NetworkRateText.full(nil) == "—")
        #expect(NetworkRateText.full(-1) == "—")
        #expect(NetworkRateText.full(.nan) == "—")
        #expect(NetworkRateText.full(1e19).hasSuffix("/s"))
        #expect(NetworkRateText.full(.greatestFiniteMagnitude).hasSuffix("/s"))
        #expect(NetworkRateText.short(.greatestFiniteMagnitude).hasSuffix("G"))
        #expect(NetworkRateText.short(-5) == "0")
    }

    @Test func nowPlayingTicksAndShowsHours() {
        #expect(NowPlayingPresentation.timeString(74) == "1:14")
        #expect(NowPlayingPresentation.timeString(4_530) == "1:15:30")
        #expect(NowPlayingPresentation.timeString(3_600) == "1:00:00")
        let polled = Date(timeIntervalSince1970: 1_000)
        let playing = NowPlayingSnapshot(title: "T", artist: "A", album: "", isPlaying: true, position: 30, duration: 35,
                                         updatedAt: polled, artworkURL: nil)
        #expect(NowPlayingPresentation.position(playing, now: polled.addingTimeInterval(3)) == 33)
        // Never past the end, and never backwards for a clock that is behind the poll.
        #expect(NowPlayingPresentation.position(playing, now: polled.addingTimeInterval(60)) == 35)
        #expect(NowPlayingPresentation.position(playing, now: polled.addingTimeInterval(-5)) == 30)
        var paused = playing
        paused.isPlaying = false
        #expect(NowPlayingPresentation.position(paused, now: polled.addingTimeInterval(3)) == 30)
    }

    // MARK: Part 2: Calendar and Reminders

    @Test func calendarModuleAsksForAccessBeforeItWasRequested() {
        let empty = CalendarFacePresentation.emptyState(errorMessage: nil, accessAvailable: false)
        #expect(empty.title == "Calendar" && empty.detail == "Allow access")
        #expect(CalendarFacePresentation.emptyState(errorMessage: "denied", accessAvailable: false).title == "Unavailable")
    }

    @Test func ongoingMultiDayEventsNameTheirEndDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        let conference = CalendarEventSnapshot(id: "c", title: "Conference", startDate: now.addingTimeInterval(-3_600),
                                               endDate: now.addingTimeInterval(56 * 3_600), isAllDay: false,
                                               calendarID: "w", calendarTitle: "Work", meetingURL: nil)
        let end = NextMeeting.dayAndTime(conference.endDate, now: now, calendar: calendar)
        #expect(end != NextMeeting.time(conference.endDate, calendar: calendar))
        #expect(CalendarFacePresentation.compactStatus(conference, now: now, calendar: calendar) == "Now · ends " + end)
        #expect(CalendarEventRowPresentation.detail(conference, now: now, calendar: calendar) == "Now · ends \(end) · Work")
    }

    @Test func calendarHeroEventLeadsTheRows() {
        func event(_ id: String) -> CalendarEventSnapshot {
            CalendarEventSnapshot(id: id, title: id, startDate: .now, endDate: .now.addingTimeInterval(60), isAllDay: false,
                                  calendarID: "c", calendarTitle: "", meetingURL: nil)
        }
        let rows = [event("declined"), event("next"), event("later")]
        #expect(CalendarEventListPresentation.rows(events: rows, hero: event("next")).map(\.id) == ["next", "declined", "later"])
        #expect(CalendarEventListPresentation.rows(events: rows, hero: nil).map(\.id) == ["declined", "next", "later"])
        #expect(CalendarEventListPresentation.rows(events: rows, hero: event("other")).map(\.id) == ["declined", "next", "later"])
    }

    @Test func calendarReadScopeChangesOnlyForWhatIsRead() {
        var configuration = WidgetConfiguration()
        let initial = CalendarReadScope(configuration)
        configuration.widgetAccent = .mono
        #expect(CalendarReadScope(configuration) == initial)
        configuration.calendarShowsAllDayEvents.toggle()
        #expect(CalendarReadScope(configuration) != initial)
    }

    @Test func remindersModuleNamesItsList() {
        let lists = [ReminderListSnapshot(id: "a", title: "Errands")]
        #expect(RemindersFacePresentation.listTitle(selectedID: "", lists: []) == "All lists")
        #expect(RemindersFacePresentation.listTitle(selectedID: "a", lists: lists) == "Errands")
        #expect(RemindersFacePresentation.listTitle(selectedID: "gone", lists: lists) == "Reminders")
    }

    @Test func rejectedConfigurationChangesAreReported() {
        #expect(WidgetConfigurationLookup.rejection(.rejected("Saving is disabled.")) == "Saving is disabled.")
        #expect(WidgetConfigurationLookup.rejection(.accepted) == nil)
        #expect(WidgetConfigurationLookup.rejection(.unchanged) == nil)
    }

    #if DEBUG
    @Test func calendarFixtureAllDayEventSpansWholeDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for hour in [1, 9, 23] {
            let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: hour))!
            let events = CalendarQAFixture.meetings.events(now: now, calendar: calendar)
            let holiday = try #require(events.first { $0.id == "qa-holiday" })
            #expect(holiday.startDate == calendar.startOfDay(for: now))
            #expect(holiday.endDate == calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
            // The production selection hides it when all-day events are off.
            #expect(!CalendarEventOrdering.select(events, calendarIDs: [], includeAllDay: false, now: now).contains { $0.isAllDay })
            #expect(CalendarEventOrdering.select(events, calendarIDs: ["qa-home"], includeAllDay: true, now: now).map(\.id) == ["qa-holiday"])
        }
    }

    @Test func remindersFixtureStatesMatchTheirNames() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let list = RemindersQAFixture.list.reminders(now: now)
        #expect(list.count == 3)
        #expect(RemindersFacePresentation.overdueCount(list, now: now) == 1)
        #expect(Set(list.map(\.calendarID)).isSubset(of: Set(RemindersQAFixture.list.lists.map(\.id))))
        #expect(RemindersQAFixture.empty.reminders(now: now).isEmpty && !RemindersQAFixture.empty.lists.isEmpty)
        #expect(RemindersQAFixture.denied.reminders(now: now).isEmpty && RemindersQAFixture.denied.lists.isEmpty)
    }
    #endif

    // MARK: Part 2: saved collections and alarms

    @Test func savedCollectionNamesAreClampedByBytes() {
        #expect(SavedCollectionLimits.clamped("abc", bytes: 2) == "ab")
        let thumbs = SavedCollectionLimits.clamped(String(repeating: "👍", count: 200), bytes: SavedCollectionLimits.titleBytes)
        #expect(thumbs.utf8.count == 400 && thumbs.count == 100)
        // A character is never cut in half.
        #expect(SavedCollectionLimits.clamped("👨‍👩‍👧", bytes: 10).isEmpty)
        #expect(SavedCollectionLimits.snippetUsage(String(repeating: "a", count: 100)) == nil)
        #expect(SavedCollectionLimits.snippetUsage(String(repeating: "a", count: 36_001)) != nil)
        // The limits are the validator's.
        var configuration = WidgetConfiguration()
        configuration.textSnippets = [TextSnippet(title: thumbs, text: String(repeating: "a", count: SavedCollectionLimits.snippetTextBytes))]
        #expect((try? ProfileSemanticValidator.validate(configuration)) != nil)
        configuration.textSnippets = [TextSnippet(title: thumbs + "a", text: "a")]
        #expect((try? ProfileSemanticValidator.validate(configuration)) == nil)
    }

    @Test func shelfReportsFilesItDidNotAdd() {
        #expect(FileShelfPolicy.skippedMessage(chosen: 3, added: 3) == nil)
        #expect(FileShelfPolicy.skippedMessage(chosen: 5, added: 3)?.hasPrefix("2 files were not added") == true)
        #expect(FileShelfPolicy.skippedMessage(chosen: 1, added: 0)?.hasPrefix("1 file was not added") == true)
    }

    @Test func removedAlarmRestoresInPlace() throws {
        let alarms = [DockAlarm(title: "A", hour: 7, minute: 0, repeatWeekdays: [], isEnabled: true),
                      DockAlarm(title: "B", hour: 8, minute: 0, repeatWeekdays: [2], isEnabled: true)]
        let removed = try #require(RemovedEntries.capture([alarms[0].id], from: alarms, message: "Removed A."))
        var remaining = Array(alarms.dropFirst())
        #expect(removed.restore(into: &remaining, capacity: AlarmCopy.capacity) == 1)
        #expect(remaining.map(\.title) == ["A", "B"])
    }

    // MARK: Part 2: AI and markets

    @Test func narrowTokenValuesPromoteAtScaleBoundaries() {
        let us = Locale(identifier: "en_US")
        #expect(AIFacePresentation.compactTokens(12, locale: us) == "12")
        #expect(AIFacePresentation.compactTokens(999_499, locale: us) == "999K")
        #expect(AIFacePresentation.compactTokens(999_500, locale: us) == "1M")
        #expect(AIFacePresentation.compactTokens(999_999_999, locale: us) == "1B")
        #expect(AIFacePresentation.compactTokens(1_500_000_000_000, locale: us) == "1500B")
    }

    @Test func limitWindowTitlesAreWholeWords() {
        func title(_ name: String, _ minutes: Int?) -> String {
            AIFacePresentation.compactWindowTitle(for: AILimitWindow(name: name, usedPercent: 10, durationMinutes: minutes))
        }
        #expect(title("Spend limit", nil) == "Spend")
        #expect(title("Session", nil) == "Session")
        #expect(title("Monthly AI credits", nil) == "Month")
        #expect(title("x", 60) == "1h")
        #expect(title("x", 120) == "2h")
        #expect(title("x", 300) == "5h")
        #expect(title("x", 10_080) == "7d")
        #expect(title("x", 45) == "45m")
    }

    @Test func marketHeroLabelsItsCloseAndColoursByRange() {
        let day: TimeInterval = 86_400
        let points = [100.0, 104, 103].enumerated().map { StockMarketPoint(date: Date(timeIntervalSince1970: Double($0.offset) * day), close: $0.element, volume: 0) }
        #expect(StockFaceFormatting.rangeChange(points) == 3)
        #expect(StockFaceFormatting.rangeChange(Array(points.prefix(1))) == nil)
        #expect(StockFaceFormatting.closeCaption(points[2].date).hasPrefix("Close · "))
    }

    @Test func yahooLinksUseYahooExchangeSuffixes() {
        func path(_ symbol: String) -> String? { MarketFinanceURL.url(for: symbol)?.path }
        #expect(path("TSCO.LON") == "/quote/TSCO.L")
        #expect(path("SHOP.TRT") == "/quote/SHOP.TO")
        #expect(path("ABC.TRV") == "/quote/ABC.V")
        #expect(path("SAP.DEX") == "/quote/SAP.DE")
        #expect(path("RELIANCE.BSE") == "/quote/RELIANCE.BO")
        #expect(path("600000.SHH") == "/quote/600000.SS")
        #expect(path("000001.SHZ") == "/quote/000001.SZ")
        #expect(path("aapl") == "/quote/AAPL")
        #expect(path("BRK.B") == "/quote/BRK.B")
    }

    // MARK: Part 3: pickers, weather, system and business

    @Test func decodedPickerValuesAlwaysHaveAMatchingOption() throws {
        func decode(_ json: String) throws -> WidgetConfiguration { try JSONDecoder().decode(WidgetConfiguration.self, from: Data(json.utf8)) }
        #expect(try decode(#"{"stockRefreshIntervalMinutes":90}"#).stockRefreshIntervalMinutes == 60)
        #expect(try decode(#"{"stockRefreshIntervalMinutes":500}"#).stockRefreshIntervalMinutes == 360)
        #expect(try decode(#"{"stockRefreshIntervalMinutes":5000}"#).stockRefreshIntervalMinutes == 1_440)
        #expect(try decode(#"{"stockRefreshIntervalMinutes":720}"#).stockRefreshIntervalMinutes == 720)
        #expect(try decode("{}").stockRefreshIntervalMinutes == 360)
        // Extreme values from a damaged file snap like any other instead of overflowing.
        for minutes in [Int.min, -5, 0, 59, 61, 100, 1_000, 99_999, Int.max] {
            #expect(WidgetConfiguration.stockRefreshIntervalOptions.contains(WidgetConfiguration.snappedStockRefreshInterval(minutes)))
        }
        // AI Activity offers only providers with a local activity source.
        #expect(try decode(#"{"aiActivityProvider":"cursor"}"#).aiActivityProvider == .codex)
        #expect(try decode(#"{"aiActivityProvider":"grok"}"#).aiActivityProvider == .grok)
        #expect(AIProvider.localActivityProviders == [.codex, .claude, .grok])
    }

    @Test func weatherConditionsUseTheTemperatureUnitsSystem() {
        let us = Locale(identifier: "en_US")
        let mph = WeatherConditionsFormatting.wind(kilometersPerHour: 16.09344, unit: .fahrenheit, locale: us)
        #expect(mph.hasPrefix("10") && mph.hasSuffix("mph"))
        let kmh = WeatherConditionsFormatting.wind(kilometersPerHour: 12.4, unit: .celsius, locale: us)
        #expect(kmh.hasPrefix("12") && kmh.hasSuffix("km/h"))
        let inches = WeatherConditionsFormatting.precipitation(millimeters: 2.54, unit: .fahrenheit, locale: us)
        #expect(inches.hasPrefix("0.1") && inches.hasSuffix("in"))
        let millimeters = WeatherConditionsFormatting.precipitation(millimeters: 0.2, unit: .celsius, locale: us)
        #expect(millimeters.hasPrefix("0.2") && millimeters.hasSuffix("mm"))
    }

    @Test func cachedWeatherHourFormattersKeepTheirPlace() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let uk = Locale(identifier: "en_GB")
        let utc = WeatherHourLabel.text(for: date, timeZoneIdentifier: "UTC", locale: uk)
        #expect(WeatherHourLabel.text(for: date, timeZoneIdentifier: "UTC", locale: uk) == utc)
        #expect(WeatherHourLabel.text(for: date, timeZoneIdentifier: "Asia/Tokyo", locale: uk) != utc)
    }

    @Test func memoryPressureSeedsFromTheKernelLevel() {
        #expect(MemoryPressureCondition.condition(sysctlLevel: 1) == .normal)
        #expect(MemoryPressureCondition.condition(sysctlLevel: 2) == .warning)
        #expect(MemoryPressureCondition.condition(sysctlLevel: 4) == .critical)
        #expect(MemoryPressureCondition.condition(sysctlLevel: 0) == nil)
    }

    @Test func systemFaceAndHeroShareStateColourAndSpeakTheSecondaryMetric() {
        #expect(SystemActivityState.color(cpu: nil) == Color.primary)
        #expect(SystemActivityState.color(cpu: 40) == Color.primary)
        #expect(SystemActivityState.color(cpu: 80) == WidgetPalette.warning)
        #expect(SystemActivityState.color(cpu: 95) == WidgetPalette.critical)
        let us = Locale(identifier: "en_US")
        let memory = HostMemoryReading(usedBytes: 9_000_000_000, totalBytes: 16_000_000_000, swapUsedBytes: nil, activeBytes: 0, wiredBytes: 0,
                                       compressedBytes: 0, inactiveBytes: 0, freeBytes: 0, purgeableBytes: 0)
        let load = SystemLoadAverage(oneMinute: 2.4, fiveMinutes: 2, fifteenMinutes: 1)
        let withMemory = SystemActivityFormatting.accessibilityValue(cpu: 42, secondary: .memory, memory: memory, load: load, locale: us)
        #expect(withMemory.hasPrefix("42 percent, memory ") && withMemory.hasSuffix(" used"))
        #expect(SystemActivityFormatting.accessibilityValue(cpu: 42, secondary: .load, memory: memory, load: load, locale: us) == "42 percent, load average 2.40")
        #expect(SystemActivityFormatting.accessibilityValue(cpu: nil, secondary: .none, memory: memory, load: load, locale: us) == "Sampling")
    }

    @Test func uptimeAndFileCountsFollowTheLocale() {
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        #expect(SystemActivityFormatting.uptime(92_000, locale: us).hasPrefix("1d"))
        #expect(SystemActivityFormatting.uptime(3 * 3_600 + 12 * 60, locale: us).hasPrefix("3h"))
        let result = StorageScanResult(rootPath: "/", scannedFileCount: 12_345, scannedBytes: 1_000, largestFiles: [], skippedEntries: 0, wasCapped: false)
        #expect(SystemStorageExplorerFormatting.summary(result, locale: us).hasPrefix("12,345 files · "))
        #expect(SystemStorageExplorerFormatting.summary(result, locale: de).hasPrefix("12.345 files · "))
        var single = result; single.scannedFileCount = 1; single.wasCapped = true
        let partial = SystemStorageExplorerFormatting.summary(single, locale: us)
        #expect(partial.hasPrefix("Partial · 1 file · ") && partial.hasSuffix("scan limit reached"))
    }

    @Test func staleNetworkFooterNeverSaysJustNow() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let footer = SystemDetailFormatting.freshness(updatedAt: now.addingTimeInterval(-20), failed: false, now: now,
                                                      maximumAge: SystemDetailSections.networkMaximumAge)
        #expect(footer.hasPrefix("Last reading ") && !footer.contains("just now"))
        // A failed read is stale at once, even for a reading taken this second.
        let failed = SystemDetailFormatting.freshness(updatedAt: now, failed: true, now: now, maximumAge: SystemDetailSections.networkMaximumAge)
        #expect(failed.hasPrefix("Last reading ") && !failed.contains("just now"))
        // Network Activity has no content without its hero, so the settings sheet shows none.
        #expect(!WidgetSheetHeroPolicy.showsContent(kind: "Network Activity", inSheet: true))
    }

    @Test func compactCurrencyFollowsTheLocaleAndPromotesAfterRounding() {
        let us = Locale(identifier: "en_US"), de = Locale(identifier: "de_DE")
        #expect(FacesBFinancialFormatting.compact(-2_400, currency: "USD", narrow: false, locale: us) == "-$2.4K")
        #expect(FacesBFinancialFormatting.compact(2_400, currency: "USD", narrow: false, locale: us) == "$2.4K")
        let euros = FacesBFinancialFormatting.compact(2_400, currency: "EUR", narrow: false, locale: de)
        #expect(euros.hasPrefix("2,4K") && euros.hasSuffix("€"))
        #expect(FacesBFinancialFormatting.compact(999_960, currency: nil, narrow: true, locale: us) == "1M")
        #expect(FacesBFinancialFormatting.compact(Decimal(string: "999.999")!, currency: nil, narrow: true, locale: us) == "1K")
        #expect(FacesBFinancialFormatting.compact(999_000, currency: nil, narrow: true, locale: us) == "999K")
    }

    @Test func pointInTimeMetricsDoNotClaimAPeriod() {
        #expect(!StripeMetric.revenue.isPointInTime && !StripeMetric.netAfterFees.isPointInTime)
        #expect(StripeMetric.allCases.filter(\.isPointInTime) == [.mrr, .arr, .payingSubscribers, .arpu, .availableBalance, .pendingBalance])
        #expect(PaddleMetric.allCases.filter(\.isPointInTime) == [.mrr, .arr, .activeSubscribers])
    }

    @Test func claudeLimitsBridgeUsesPlutil() {
        let bridge = ClaudeLimitsSetup.bridgeCommand(directory: URL(fileURLWithPath: "/tmp/mydock-test", isDirectory: true), previousCommand: nil)
        #expect(bridge.hasPrefix(ClaudeLimitsSetup.marker))
        #expect(bridge.contains("/usr/bin/plutil -extract rate_limits json"))
    }

    // MARK: Helpers

    @MainActor private func waitUntil(timeout: Duration = .seconds(5), _ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                Issue.record("Condition not met before the deadline")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A thread-safe call count for closures the code under test may call synchronously.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}
