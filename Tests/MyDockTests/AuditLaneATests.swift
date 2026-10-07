import Foundation
import Testing
@testable import MyDock

/// Lane A audit fixes: models, persistence, backup and data services. Fixture files in a temporary folder only.
@MainActor
@Suite struct AuditLaneATests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-AuditLaneA-\(UUID().uuidString)", isDirectory: true)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }

    // MARK: S01-003

    @Test func newWorldClockStartsOnAnotherPlaceInsteadOfAFixedCity() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let date = try #require(ISO8601DateFormatter().date(from: "2026-01-15T12:00:00Z"))
        #expect(WorldClockCityCatalog.initialZoneID(current: newYork, at: date) == "Europe/London")
        #expect(WorldClockCityCatalog.initialZoneID(current: london, at: date) == "America/New_York")

        let zoneID = try #require(DockItem.widget("World Clock").widgetConfiguration?.worldClockTimeZoneID)
        let zone = try #require(TimeZone(identifier: zoneID))
        #expect(zoneID != "Europe/Warsaw")
        #expect(zone.secondsFromGMT(for: .now) != TimeZone.current.secondsFromGMT(for: .now))
        // Saved widgets without the key keep decoding to the previous default.
        let old = try JSONDecoder().decode(WidgetConfiguration.self, from: Data("{}".utf8))
        #expect(old.worldClockTimeZoneID == "Europe/Warsaw")
    }

    // MARK: S01-004, S01-013

    @Test func calculatorAcceptsTheLocaleDecimalComma() throws {
        #expect(try QuickCalculator.calculate("2,5*4", decimalSeparator: ",") == 10)
        #expect(try QuickCalculator.calculate("2.5 × 4", decimalSeparator: ",") == 10)
        #expect(throws: (any Error).self) { try QuickCalculator.calculate("2,5*4", decimalSeparator: ".") }
        let polish = Locale(identifier: "pl_PL")
        let separator = try #require(polish.decimalSeparator)
        #expect(try QuickCalculator.calculate("1" + separator + "5 + 1", decimalSeparator: separator) == 2.5)
    }

    @Test func calculatorPercentWorksLikeAHandheldCalculator() throws {
        let addition = try QuickCalculator.calculate("50 + 10%")
        let subtraction = try QuickCalculator.calculate("50 − 10%")
        let product = try QuickCalculator.calculate("200 × 15%")
        let alone = try QuickCalculator.calculate("10%")
        #expect(abs(addition - 55) < 1e-9)
        #expect(abs(subtraction - 45) < 1e-9)
        #expect(abs(product - 30) < 1e-9)
        #expect(abs(alone - 0.1) < 1e-12)
    }

    // MARK: S01-005

    @Test func timerValuesShowHoursFromOneHour() {
        #expect(TimerValueFormatter.text(3_599) == "59:59")
        #expect(TimerValueFormatter.text(3_600) == "1:00:00")
        #expect(TimerValueFormatter.text(7_200) == "2:00:00")
        #expect(TimerValueFormatter.text(5_025) == "1:23:45")
        #expect(TimerValueFormatter.text(86_400) == "24:00:00")
    }

    // MARK: S01-006

    @Test func privacyCopyMatchesWhatBackupsContain() throws {
        let line = try #require(PrivacyHelpCopy.privacyPoints.first { $0.hasPrefix("Backups") })
        #expect(line.contains("never include credentials, permissions or cached readings"))
        #expect(!line.contains("adds notes and cached readings"))

        var stripe = DockItem.widget("Stripe")
        stripe.widgetConfiguration?.stripeSnapshot = StripeSnapshot(
            accountID: "acct_lane_a", accountName: "Lane A", fetchedAt: .now, period: .thirtyDays,
            periodStart: .now, periodEnd: .now, currencies: [], unsupportedSubscriptionItems: 0)
        let data = try BackupManager.makeArchive(from: [DockProfile(name: "Backup", kind: .custom, items: [stripe])])
        let restored = try #require(try BackupManager.readArchive(data).importedProfiles.first)
        #expect(restored.items.first?.widgetConfiguration?.stripeSnapshot == nil)
    }

    // MARK: S01-007

    @Test func savedSearchResolvesOnlyTheShownShelfFiles() {
        var shelf = DockItem.widget("File Shelf")
        let folder = temporaryFolder()
        shelf.widgetConfiguration?.shelfFiles = (0..<20).map { ShelfFile(url: folder.appendingPathComponent("Report \($0).pdf")) }
        let profile = DockProfile(name: "Work", kind: .custom, items: [shelf])
        var checks = 0
        let results = SavedCollectionSearch.results(in: [profile], query: "report", limit: 3) { _ in checks += 1; return false }
        #expect(results.count == 3)
        #expect(checks == 3)
        #expect(results.allSatisfy { $0.kind == .file && $0.isMissing && $0.title.hasPrefix("Report") })
    }

    // MARK: S01-008

    @Test func marketWidgetsNeedAnAPIKeyConnection() throws {
        for name in ["Stock", "Watchlist"] {
            let definition = try #require(WidgetRegistry.definition(named: name))
            #expect(definition.capabilities.needsConnection && definition.capabilities.usesProviderKey)
            #expect(!WidgetDiscoveryFilter.noConnection.includes(definition))
            #expect(WidgetDiscovery.setupSummary(definition).contains("API key"))
            #expect(WidgetSheetDataSummary.make(kind: name, configuration: WidgetConfiguration()).source == "Online")
        }
        #expect(WidgetSheetDataSummary.make(kind: "Stripe", configuration: WidgetConfiguration()).source == "Connected account")

        let data = try PortableDockPackage.makePackage(from: DockProfile(name: "Markets", kind: .custom, items: [.widget("Stock")]),
                                                       includePersonalData: false)
        let preview = try PortableDockPackage.preview(data, existingNames: [], targetExists: { _ in true })
        #expect(preview.reconnections.map(\.title) == ["Stock"])
        #expect(preview.reconnections.first?.fallback.contains("API key") == true)
    }

    // MARK: S01-012

    @Test func tokenCountsRoundBeforeChoosingTheUnit() {
        #expect(AIActivityFormatting.tokens(999) == "999")
        #expect(AIActivityFormatting.tokens(1_049) == "1K")
        #expect(AIActivityFormatting.tokens(999_950) == "1M")
        #expect(AIActivityFormatting.tokens(999_999_999) == "1B")
        #expect(AIActivityFormatting.tokens(1_234_567, fractionDigits: 2) == Double(1.23).formatted(.number.precision(.fractionLength(0...2))) + "M")
    }

    // MARK: S01-014

    @Test func hydrationHistoryPrunesOldAndExcessEntries() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        var configuration = WidgetConfiguration()
        configuration.hydrationEntries = [HydrationEntry(timestamp: now.addingTimeInterval(-500 * 86_400), amountML: 250),
                                          HydrationEntry(timestamp: now.addingTimeInterval(-10 * 86_400), amountML: 250)]
        #expect(configuration.logHydrationDrink(at: now))
        #expect(configuration.hydrationEntries.map(\.timestamp) == [now.addingTimeInterval(-10 * 86_400), now])

        let maximum = WidgetConfiguration.hydrationMaximumEntries
        configuration.hydrationEntries = (1...maximum).map { HydrationEntry(timestamp: now.addingTimeInterval(-Double($0) * 60), amountML: nil) }
        let oldest = configuration.hydrationEntries.map(\.timestamp).min()
        #expect(configuration.logHydrationDrink(at: now))
        #expect(configuration.hydrationEntries.count == maximum)
        #expect(configuration.hydrationEntries.last?.timestamp == now)
        #expect(!configuration.hydrationEntries.contains { $0.timestamp == oldest })
    }

    // MARK: S02-003

    @Test func libraryDropsOnlyInvalidEntriesAndSetsUnreadableFilesAside() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var invalid = DockItem.widget("Focus Timer")
        invalid.widgetConfiguration?.focusDurationSeconds = ProfileSemanticValidator.maximumTimerDuration + 1
        let entries = [ProfileLibraryEntry(reason: "Before profile edit", profile: DockProfile(name: "Good", kind: .custom, items: [])),
                       ProfileLibraryEntry(reason: "Before profile edit", profile: DockProfile(name: "Stale", kind: .custom, items: [invalid]))]
        let mixed = folder.appendingPathComponent("mixed.json")
        try JSONEncoder().encode(entries).write(to: mixed)
        let library = ProfileLibrary(fileURL: mixed)
        #expect(library.entries.map(\.profile.name) == ["Good"])
        #expect(library.errorMessage == nil)

        let corrupt = folder.appendingPathComponent("corrupt.json")
        try Data("not a library".utf8).write(to: corrupt)
        let recovered = ProfileLibrary(fileURL: corrupt)
        #expect(recovered.entries.isEmpty)
        #expect(recovered.errorMessage != nil)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("corrupt.json.recovery-") })
        recovered.record(DockProfile(name: "After", kind: .custom, items: []), reason: "Before deletion")
        #expect(recovered.entries.count == 1)
        #expect(recovered.errorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: corrupt.path))
    }

    @Test func aFailedLibraryWriteDoesNotStopLaterSnapshots() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let blocker = folder.appendingPathComponent("blocker")
        try Data().write(to: blocker)
        let library = ProfileLibrary(fileURL: blocker.appendingPathComponent("history.json"))
        library.record(DockProfile(name: "First", kind: .custom, items: []), reason: "Before profile edit")
        #expect(library.errorMessage != nil)
        try FileManager.default.removeItem(at: blocker)
        library.record(DockProfile(name: "Second", kind: .custom, items: []), reason: "Before profile edit")
        #expect(library.entries.map(\.profile.name) == ["Second", "First"])
        #expect(library.errorMessage == nil)
        #expect(FileManager.default.fileExists(atPath: blocker.appendingPathComponent("history.json").path))
    }

    // MARK: S02-004

    @Test func abandonedStateTemporariesAreRemovedOnlyWhenOld() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date.now
        let old = folder.appendingPathComponent(".mydock-state-\(UUID().uuidString).tmp")
        let fresh = folder.appendingPathComponent(".mydock-state-\(UUID().uuidString).tmp")
        let state = folder.appendingPathComponent("state.json")
        for file in [old, fresh, state] { try Data("{}".utf8).write(to: file) }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: old.path)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-120)], ofItemAtPath: state.path)
        RevisionedStateWriter.removeAbandonedTemporaries(in: folder, now: now)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: state.path))
    }

    // MARK: S02-005

    @Test func importPreviewDerivesPersonalDataFromTheContent() throws {
        var note = DockItem.widget("Sticky Note")
        note.widgetConfiguration?.noteText = "Private"
        let profile = DockProfile(name: "Notes", kind: .custom, items: [note])
        // The manifest claims no personal data; the preview must not trust it.
        let data = try BackupManager.makeArchive(from: [profile], dockPackage: DockPackageManifest(includesPersonalData: false,
                                                                                                   summary: DockContentSummary(profile: profile)))
        let preview = try PortableDockPackage.preview(data, existingNames: [], targetExists: { _ in true })
        #expect(preview.includesPersonalData)

        let sanitized = try PortableDockPackage.makePackage(from: profile, includePersonalData: false)
        #expect(try PortableDockPackage.preview(sanitized, existingNames: [], targetExists: { _ in true }).includesPersonalData == false)
    }

    // MARK: S02-008

    @Test func presentationFollowsItemsAddedAfterAnEarlierLookup() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Revenue")
        var stripe = DockItem.widget("Stripe")
        stripe.widgetConfiguration?.stripeAccountID = "acct_lane_a"
        // An unowned item is projected unchanged; the ownership set is then cached.
        #expect(store.presentationItem(stripe) == stripe)
        store.add(stripe, to: profileID)
        let snapshot = StripeSnapshot(accountID: "acct_lane_a", accountName: "Lane A", fetchedAt: .now, period: .thirtyDays,
                                      periodStart: .now, periodEnd: .now, currencies: [], unsupportedSubscriptionItems: 0)
        #expect(store.publishRuntimeReadings(itemID: stripe.id, in: profileID) { $0.stripeSnapshot = snapshot } == .accepted)
        #expect(store.presentationItem(stripe).widgetConfiguration?.stripeSnapshot == snapshot)
    }

    // MARK: S02-009

    @Test func timerFinishesWhenTheWallClockLagsTheSleep() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Timers")
        let focus = DockItem.widget("Focus Timer")
        store.add(focus, to: profileID)
        // A wall clock that runs at half speed, as during a slew: each sleep ends before the wall-clock deadline.
        let base = Date.now
        let started = ContinuousClock.now
        let slowNow: () -> Date = {
            let elapsed = ContinuousClock.now - started
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return base.addingTimeInterval(seconds / 2)
        }
        store.updateWidgetConfiguration(itemID: focus.id, in: profileID) {
            $0.focusDurationSeconds = 60
            $0.focusElapsedBeforeStart = 59.8
            $0.startFocusTimer(at: slowNow())
        }
        let coordinator = WidgetLifecycleCoordinator(store: store, now: slowNow)
        coordinator.rescheduleTimers()
        try await waitUntil {
            store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == focus.id }?.widgetConfiguration?.focusStartedAt == nil
        }
        let configuration = try #require(store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == focus.id }?.widgetConfiguration)
        #expect(configuration.focusElapsedBeforeStart == 60)
    }

    // MARK: S03-005, S03-007

    @Test func failuresNeverRetrySoonerThanTheNormalCadence() {
        #expect(WidgetDataCoordinator.nextRefreshDelay(interval: 300, failures: nil) == 300)
        #expect(WidgetDataCoordinator.nextRefreshDelay(interval: 300, failures: 1) == 300)
        #expect(WidgetDataCoordinator.nextRefreshDelay(interval: 300, failures: 2) == 300)
        #expect(WidgetDataCoordinator.nextRefreshDelay(interval: 300, failures: 3) == 480)
        #expect(WidgetDataCoordinator.nextRefreshDelay(interval: 300, failures: 12) == 3_600)
        #expect(WidgetDataCoordinator.nextRefreshDelay(interval: 21_600, failures: 2) == 21_600)
    }

    @Test func watchlistStoppedByTheProviderLimitSaysSo() {
        let limited = WidgetDataValue.watchlist([:], failedSymbols: ["AAPL", "MSFT"], limitReached: true)
        #expect(limited.partialError?.contains("request limit") == true)
        let partial = WidgetDataValue.watchlist([:], failedSymbols: ["AAPL"], limitReached: false)
        #expect(partial.partialError?.contains("AAPL") == true)
    }

    // MARK: Part 2 — S01-015

    @Test func privateTextExclusionAlsoReplacesAlarmTitles() throws {
        var alarm = DockItem.widget("Alarm")
        alarm.widgetConfiguration?.alarms = [DockAlarm(title: "Take medication", hour: 8, minute: 0, repeatWeekdays: [], isEnabled: true)]
        let profile = DockProfile(name: "Health", kind: .custom, items: [alarm])
        let sanitized = try #require(ProfileSanitizer.sanitize(profile).items.first?.widgetConfiguration?.alarms.first)
        #expect(sanitized.title == ProfileSanitizer.genericAlarmTitle)
        #expect(!sanitized.isEnabled)
        let withText = try #require(ProfileSanitizer.sanitize(profile, includeNotes: true).items.first?.widgetConfiguration?.alarms.first)
        #expect(withText.title == "Take medication")
    }

    /// Every stored widget field is either cleared by `ProfileSanitizer` or deliberately kept. A new field must be added
    /// to one list, which forces a decision about whether it holds private or machine-local data.
    @Test func sanitizerClassifiesEveryWidgetField() {
        let stripped: Set<String> = [
            "noteText", "checklistEntries", "textSnippets", "shelfFiles", "quickLinks", "stripeAccountID",
            "stripeSnapshot", "paddleAccountID", "paddleSnapshot", "shopifyStoreID", "shopifySnapshot",
            "stockSnapshot", "watchlistStocks", "aiLimitsSnapshot", "aiActivitySnapshot", "hydrationEntries",
            "hydrationLastRemovedEntry", "hydrationRemindersEnabled", "selectedCalendarIDs",
            "selectedReminderCalendarID", "selectedShortcutName", "weatherLocation", "cachedWeatherForecast",
            "focusElapsedBeforeStart", "focusStartedAt", "stopwatchElapsedBeforeStart", "stopwatchStartedAt",
            "stopwatchClockStart", "countdownElapsedBeforeStart", "countdownStartedAt", "countdownTargetDate",
            "alarms"
        ]
        let kept: Set<String> = [
            "cardWidth", "iconStyle", "widgetLayout", "iconAppearance", "widgetAccent", "showsLabel", "glassTint",
            "aiActivitySecondaryMetric", "systemSecondaryMetric", "systemShowsNetwork", "systemShowsStorage",
            "savedColors", "noteBackground", "focusDurationSeconds", "worldClockTimeZoneID",
            "worldClockAdditionalTimeZoneIDs", "stockSymbol", "stockName", "stockCurrency", "stockRange",
            "stockRefreshIntervalMinutes", "stockShowsVolume", "watchlistSelectedSymbol", "stripeDisplayName",
            "stripeColor", "stripeMetric", "stripeCurrency", "stripePeriod", "paddleDisplayName", "paddleColor",
            "paddleMetric", "paddlePeriod", "paddleShowsChart", "shopifyDisplayName", "shopifyColor",
            "shopifyMetric", "shopifyPeriod", "shopifyShowsChart", "aiLimitsLayout", "aiLimitsRepresentation",
            "aiLimitsVisibleProviders", "aiLimitsProviderOrder", "aiLimitsCompactProvider",
            "aiCopilotMonthlyCreditAllowance", "aiActivityProvider", "aiActivityRange", "aiActivityChartStyle",
            "countdownDurationSeconds", "countdownMode", "timeProgressPeriod", "hydrationSaveHistory",
            "hydrationTrackAmounts", "hydrationDefaultAmountML", "hydrationReminderIntervalMinutes", "appFolderName",
            "appFolderColor", "appFolderLetter", "appFolderApplications", "calendarLayout",
            "calendarShowsAllDayEvents", "remindersLayout", "nowPlayingSource", "nowPlayingEnabledSources",
            "nowPlayingLayout", "nowPlayingSkipSeconds", "nowPlayingHidesWhenClosed", "nowPlayingShowsTrackControls",
            "nowPlayingShowsSeekControls", "weatherUnit", "weatherLayout", "weatherForecastHours", "weatherBackground"
        ]
        let fields = Set(Mirror(reflecting: WidgetConfiguration()).children.compactMap(\.label))
        #expect(stripped.isDisjoint(with: kept))
        let unclassified = fields.subtracting(stripped).subtracting(kept).sorted()
        #expect(unclassified.isEmpty, "Classify these WidgetConfiguration fields in ProfileSanitizer: \(unclassified)")
        #expect(stripped.union(kept).subtracting(fields).isEmpty)
    }

    // MARK: S01-016

    @Test func oversizedTextAndIconsLoadBoundedButAreRejectedOnWrite() throws {
        var link = DockItem.link(try #require(URL(string: "https://example.com")), title: String(repeating: "t", count: 600))
        link.linkFaviconData = Data(count: ProfileSemanticValidator.maximumFaviconBytes + 1)
        #expect(throws: ProfileValidationError.self) {
            try ProfileSemanticValidator.validate([DockProfile(name: "Links", kind: .custom, items: [link])])
        }
        let decoded = try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(link))
        #expect(decoded.title.count == ProfileSemanticValidator.maximumNameLength)
        #expect(decoded.linkFaviconData == nil)
        try ProfileSemanticValidator.validate([DockProfile(name: "Links", kind: .custom, items: [decoded])])

        var configuration = WidgetConfiguration()
        configuration.appFolderName = String(repeating: "f", count: 300)
        configuration.alarms = [DockAlarm(title: String(repeating: "a", count: 300), hour: 7, minute: 0, repeatWeekdays: [], isEnabled: false)]
        configuration.selectedCalendarIDs = (0..<250).map { "calendar-\($0)" }
        configuration.aiLimitsVisibleProviders = [.codex, .codex, .claude]
        #expect(throws: ProfileValidationError.self) { try ProfileSemanticValidator.validate(configuration) }
        let bounded = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(bounded.appFolderName.count == ProfileSemanticValidator.maximumShortTextLength)
        #expect(bounded.alarms.first?.title.count == ProfileSemanticValidator.maximumShortTextLength)
        #expect(bounded.selectedCalendarIDs.count == ProfileSemanticValidator.maximumCalendarSelections)
        #expect(bounded.aiLimitsVisibleProviders == [.codex, .claude])
    }

    // MARK: S01-019

    @Test func lockFailuresReportTheRealPOSIXError() {
        let diskFull = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError,
                               userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))])
        #expect(SingleInstanceLock.posixCode(of: diskFull) == ENOSPC)
        #expect(SingleInstanceLock.posixCode(of: NSError(domain: NSPOSIXErrorDomain, code: Int(EROFS))) == EROFS)
        #expect(SingleInstanceLock.posixCode(of: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)) == EIO)
    }

    // MARK: S01-020

    @Test func stockRangesUseFamiliarLabelsAndKeepStoredValues() {
        #expect(StockChartRange.allCases.map(\.title) == ["1W", "1M", "3M", "5M"])
        #expect(StockChartRange.allCases.map(\.rawValue) == ["week", "month", "threeMonths", "year"])
    }

    // MARK: S01-021

    @Test func snippetPopoutAndPaletteFindTheSameSnippets() {
        let entries = [TextSnippet(title: "Quarterly Report", text: "Numbers for the board"),
                       TextSnippet(title: "", text: "Café opening hours"),
                       TextSnippet(title: "Support reply", text: "Thanks for writing")]
        var item = DockItem.widget(SavedCollectionSearch.snippetsKind)
        item.widgetConfiguration?.textSnippets = entries
        let profile = DockProfile(name: "Writing", kind: .custom, items: [item])
        for query in ["port", "rep", "QUART numb", "cafe", "thanks", "zzz"] {
            let popout = Set(SavedSnippetSearch.results(entries, query: query).map(\.id))
            let palette = Set(SavedCollectionSearch.results(in: [profile], query: query, limit: 50).map(\.entryID))
            #expect(popout == palette, "Query \(query)")
        }
        #expect(SavedSnippetSearch.results(entries, query: "port").isEmpty)
        #expect(SavedSnippetSearch.results(entries, query: " ").map(\.id) == entries.map(\.id))
    }

    // MARK: S02-012

    @Test func onboardingShowsTheActualSaveError() throws {
        struct DiskUnavailable: LocalizedError { var errorDescription: String? { "The disk is not available." } }
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let result = OnboardingCompletion.finish(store: store, appliesClearStyle: false) { throw DiskUnavailable() }
        #expect(result.error == "The disk is not available.")
        #expect(!store.state.settings.onboardingComplete)
    }

    // MARK: S02-013

    @Test func duplicatesAndRestoresGetUniqueNames() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let work = try store.createProfileAndPersist(kind: .custom, name: "Work")
        let first = try store.duplicateProfile(work)
        let second = try store.duplicateProfile(work)
        func name(_ id: UUID) -> String? { store.state.profiles.first { $0.id == id }?.name }
        #expect(name(first) == "Work Copy")
        #expect(name(second) == "Work Copy 2")
        try store.importProfiles([DockProfile(name: "Work", kind: .custom), DockProfile(name: "work", kind: .custom)])
        #expect(store.state.profiles.suffix(2).map(\.name) == ["Work 2", "work 3"])

        var long = store.state.profiles[0]
        long.name = String(repeating: "L", count: ProfileSemanticValidator.maximumNameLength)
        try store.replaceProfiles([long])
        let longCopy = try store.duplicateProfile(long.id)
        #expect((name(longCopy)?.count ?? .max) <= ProfileSemanticValidator.maximumNameLength)
    }

    // MARK: S02-014

    @Test func restoreDuplicateAndRecoveryShareOneNewIdentityRule() throws {
        var countdown = DockItem.widget("Countdown")
        countdown.widgetConfiguration?.countdownDurationSeconds = 600
        countdown.widgetConfiguration?.startCountdown(at: Date(timeIntervalSince1970: 100))
        var alarm = DockItem.widget("Alarm")
        alarm.widgetConfiguration?.alarms = [DockAlarm(title: "Wake", hour: 7, minute: 0, repeatWeekdays: [], isEnabled: true)]
        var water = DockItem.widget("Hydration")
        water.widgetConfiguration?.hydrationRemindersEnabled = true
        let missing = DockItem.file(at: URL(fileURLWithPath: "/MyDockAuditFixtureMissing/notes.txt"))
        let profile = DockProfile(name: "Day", kind: .custom, items: [countdown, alarm, water, missing])

        let archive = try BackupManager.makeArchive(from: [profile])
        let restored = try #require(BackupManager.readArchive(archive).importedProfiles.first)
        let recovered = ProfileSanitizer.newIdentity(profile)
        for copy in [restored, recovered] {
            #expect(Set(copy.items.map(\.id)).isDisjoint(with: profile.items.map(\.id)))
            #expect(copy.items[0].widgetConfiguration?.countdownStartedAt == nil)
            #expect(copy.items[0].widgetConfiguration?.countdownDurationSeconds == 600)
            #expect(copy.items[1].widgetConfiguration?.alarms.first?.isEnabled == false)
            #expect(copy.items[2].widgetConfiguration?.hydrationRemindersEnabled == false)
        }
        #expect(try BackupManager.readArchive(archive).missingItems.isEmpty == false)
        #expect(try BackupManager.readArchive(archive, computeMissing: false).missingItems.isEmpty)
    }

    // MARK: S02-016

    @Test func rejectedProfileEditsLeaveHistoryUntouched() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let id = try store.createProfileAndPersist(kind: .custom, name: "Main")
        var invalid = try #require(store.state.profiles.first { $0.id == id })
        invalid.name = String(repeating: "x", count: ProfileSemanticValidator.maximumNameLength + 1)
        let before = store.history.entries.count
        #expect(throws: ProfileValidationError.self) { try store.replaceProfiles([invalid]) }
        #expect(store.history.entries.count == before)
        #expect(store.state.profiles.first { $0.id == id }?.name == "Main")
    }

    // MARK: S02-017

    @Test func restoringFromRecoveryKeepsTheCurrentDock() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let main = try store.createProfileAndPersist(kind: .custom, name: "Main")
        store.setSetupMode(.nativeOnly)
        let restored = try store.createProfile(DockProfile(name: "Old layout", kind: .custom), activate: false)
        #expect(store.state.profiles.contains { $0.id == restored })
        #expect(store.state.settings.activeCustomProfileID == main)
        #expect(store.state.settings.setupMode == .nativeOnly)
    }

    // MARK: S02-019

    @Test func privateFilesAreWrittenWithPrivatePermissionsAndNoLeftovers() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let nested = folder.appendingPathComponent("drafts", isDirectory: true)
        let file = nested.appendingPathComponent("data.json")
        try PrivateAtomicFile.write(Data("first".utf8), to: file)
        try PrivateAtomicFile.write(Data("second".utf8), to: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "second")
        let fileMode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        let folderMode = try FileManager.default.attributesOfItem(atPath: nested.path)[.posixPermissions] as? NSNumber
        #expect(fileMode?.intValue == 0o600)
        #expect(folderMode?.intValue == 0o700)
        #expect(try FileManager.default.contentsOfDirectory(atPath: nested.path) == ["data.json"])

        let library = ProfileLibrary(fileURL: folder.appendingPathComponent("presets.json"))
        library.record(DockProfile(name: "Preset", kind: .custom, items: []), reason: "Saved preset")
        let libraryMode = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent("presets.json").path)[.posixPermissions] as? NSNumber
        #expect(libraryMode?.intValue == 0o600)
    }

    // MARK: S02-021

    @Test func theDraftCountLimitSaysSo() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let drafts = DockUtilityDraftStore(fileURL: folder.appendingPathComponent("drafts.json"), write: { _, _ in })
        let profileID = UUID()
        for index in 0..<100 {
            try drafts.update(DockUtilityFormDraft(editingID: nil, title: "Draft \(index)", body: ""), itemID: UUID(), in: profileID, kind: .snippet)
        }
        #expect(throws: DockUtilityDraftError.tooMany) {
            try drafts.update(DockUtilityFormDraft(editingID: nil, title: "One more", body: ""), itemID: UUID(), in: profileID, kind: .snippet)
        }
    }

    // MARK: S02-023

    @Test func oneConflictingDraftDoesNotHoldBackTheOthers() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProfileStore(fileURL: folder.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let conflicting = try store.createProfileAndPersist(kind: .custom, name: "Work")
        let clean = try store.createProfileAndPersist(kind: .custom, name: "Home")
        for (id, name) in [(conflicting, "Work draft"), (clean, "Home draft")] {
            var draft = DockProfileDraft(profile: try #require(store.state.profiles.first { $0.id == id }))
            draft.update { $0.name = name }
            store.editSessions.set(draft, for: id)
        }
        store.renameProfile(conflicting, to: "Work elsewhere")
        #expect(throws: EditSessionSaveError.self) { try store.editSessions.saveAll() }
        #expect(store.state.profiles.first { $0.id == clean }?.name == "Home draft")
        #expect(store.editSessions.drafts[clean]?.isDirty == false)
        #expect(store.state.profiles.first { $0.id == conflicting }?.name == "Work elsewhere")
        #expect(store.editSessions.drafts[conflicting]?.isDirty == true)
    }

    // MARK: S18-022

    @Test func libraryRetentionCapsAndPresetChecks() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let history = folder.appendingPathComponent("history.json")
        let entries = [ProfileLibraryEntry(recordedAt: .now.addingTimeInterval(-86_400), reason: "Before profile edit",
                                           profile: DockProfile(name: "Recent", kind: .custom, items: [])),
                       ProfileLibraryEntry(recordedAt: .now.addingTimeInterval(-15 * 86_400), reason: "Before profile edit",
                                           profile: DockProfile(name: "Expired", kind: .custom, items: []))]
        try JSONEncoder().encode(entries).write(to: history)
        #expect(ProfileLibrary(fileURL: history, retentionDays: 14).entries.map(\.profile.name) == ["Recent"])

        let capped = ProfileLibrary(fileURL: folder.appendingPathComponent("capped.json"), maximumEntries: 2)
        for name in ["One", "Two", "Three"] { capped.record(DockProfile(name: name, kind: .custom, items: []), reason: "Saved preset") }
        #expect(capped.entries.map(\.profile.name) == ["Three", "Two"])

        #expect(throws: EditSessionSaveError.self) {
            try capped.importPreset(JSONEncoder().encode(DockProfile(name: "System", kind: .native, items: [])))
        }
        #expect(throws: ProfileValidationError.self) { try capped.importPreset(Data(count: 8 * 1_024 * 1_024 + 1)) }

        let corrupt = folder.appendingPathComponent("corrupt.json")
        try Data("not a library".utf8).write(to: corrupt)
        let recovered = ProfileLibrary(fileURL: corrupt)
        let aside = try #require(try FileManager.default.contentsOfDirectory(atPath: folder.path).first { $0.hasPrefix("corrupt.json.recovery-") })
        recovered.clear()
        #expect(try Data(contentsOf: folder.appendingPathComponent(aside)) == Data("not a library".utf8))
    }

    // MARK: S19-009

    @Test func onlyWidgetsThatScheduleNotificationsDeclareThePermission() {
        let declared = WidgetRegistry.all.filter { $0.capabilities.permissions.contains(.notifications) }.map(\.name).sorted()
        #expect(declared == ["Alarm", "Countdown", "Hydration"])
    }
}
