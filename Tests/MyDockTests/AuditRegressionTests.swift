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
    @Test func importedDocksNeverCarryAccountAssignmentsOrReadings() throws {
        var stripe = DockItem.widget("Stripe")
        stripe.widgetConfiguration?.stripeAccountID = "acct_audit_private"
        stripe.widgetConfiguration?.shopifyStoreID = "audit-store"
        stripe.widgetConfiguration?.stripeSnapshot = StripeSnapshot(
            accountID: "acct_audit_private", accountName: "Audit Reading", fetchedAt: .now, period: .thirtyDays,
            periodStart: .now, periodEnd: .now, currencies: [], unsupportedSubscriptionItems: 0)
        // A full backup, unlike a reviewed export, still carries the assignment.
        let data = try BackupManager.makeArchive(from: [DockProfile(name: "Shared", kind: .custom, items: [stripe])])
        let preview = try PortableDockPackage.preview(data, existingNames: [], targetExists: { _ in true })
        let configuration = try #require(preview.profile.items.first?.widgetConfiguration)
        #expect(configuration.stripeAccountID.isEmpty && configuration.shopifyStoreID.isEmpty)
        #expect(configuration.stripeSnapshot == nil)
    }

    @Test func testProcessesAreAlwaysIsolated() {
        // However the suite was started, nothing in a test may reach the user's Dock or Keychain.
        #expect(AppRuntimeEnvironment.isIsolated)
        #expect(!AppRuntimeEnvironment.allowsNativeEffects && !AppRuntimeEnvironment.allowsCredentials)
    }

    @Test func providerMinorUnitsFollowEachCurrency() throws {
        #expect(FinancialCurrencyFormatter.majorUnits(from: 1999, currency: "USD") == Decimal(string: "19.99"))
        #expect(FinancialCurrencyFormatter.majorUnits(from: 500, currency: "JPY") == 500)
        #expect(FinancialCurrencyFormatter.majorUnits(from: 5000, currency: "UGX") == 5000)
        #expect(FinancialCurrencyFormatter.majorUnits(from: 12345, currency: "KWD") == Decimal(string: "12.345"))
        #expect(FinancialCurrencyFormatter.majorUnits(from: 12345, currency: "bhd") == Decimal(string: "12.345"))
    }

    @Test func nowPlayingReadsSpotifyMillisecondsAndDecimalCommas() throws {
        let spotify = try #require(try NowPlayingResponseParser.snapshot(
            from: "Song\u{1f}Artist\u{1f}Album\u{1f}playing\u{1f}12,5\u{1f}210000", durationScale: 0.001))
        #expect(spotify.position == 12.5)
        #expect(spotify.duration == 210)
        let music = try #require(try NowPlayingResponseParser.snapshot(from: "Song\nArtist\nAlbum\npaused\n42,25\n244,5"))
        #expect(music.position == 42.25 && music.duration == 244.5)
    }

    @Test func recurringCalendarOccurrencesKeepDistinctIdentities() {
        let monday = Date(timeIntervalSince1970: 1_790_000_000)
        let tuesday = monday.addingTimeInterval(86_400)
        let first = CalendarEventSnapshot.occurrenceID(eventIdentifier: "standup", calendarID: "work", occurrence: monday, title: "Stand-up")
        let second = CalendarEventSnapshot.occurrenceID(eventIdentifier: "standup", calendarID: "work", occurrence: tuesday, title: "Stand-up")
        #expect(first != second)
        #expect(first == CalendarEventSnapshot.occurrenceID(eventIdentifier: "standup", calendarID: "work", occurrence: monday, title: "Other"))
    }

    @Test func airDropAcceptsFilesAndSafeLinksOnly() {
        #expect(AirDropDroppedItemLoader.validatedShareURL(URL(fileURLWithPath: "/tmp/report.pdf")) != nil)
        #expect(AirDropDroppedItemLoader.validatedShareURL(URL(string: "https://example.com/page")!) != nil)
        #expect(AirDropDroppedItemLoader.validatedShareURL(URL(string: "https://user:secret@example.com")!) == nil)
        #expect(AirDropDroppedItemLoader.validatedShareURL(URL(string: "javascript:alert(1)")!) == nil)
    }

    /// S01-002 / S02-002: one Dock that no longer decodes or validates is set aside on its own; the other Docks
    /// and the settings load, and the file as it was is preserved.
    @MainActor
    @Test func oneUnreadableDockIsSetAsideWhileTheOthersLoad() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var state = PersistentState()
        state.profiles = [DockProfile(name: "Work", kind: .custom, items: [.widget("Clock")]),
                          DockProfile(name: "Studio", kind: .custom, items: [.widget("Countdown")])]
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        var profiles = try #require(json["profiles"] as? [[String: Any]])
        var items = try #require(profiles[1]["items"] as? [[String: Any]])
        var configuration = try #require(items[0]["widgetConfiguration"] as? [String: Any])
        configuration["countdownDurationSeconds"] = -5
        items[0]["widgetConfiguration"] = configuration
        profiles[1]["items"] = items
        profiles.append(["id": UUID().uuidString, "name": "Future", "kind": "a-kind-from-a-newer-build"])
        json["profiles"] = profiles
        var settings = try #require(json["settings"] as? [String: Any])
        settings["customDockMaterial"] = "a-material-from-a-newer-build"
        settings["onboardingComplete"] = true
        json["settings"] = settings
        let file = directory.appendingPathComponent("state.json")
        let original = try JSONSerialization.data(withJSONObject: json)
        try original.write(to: file)

        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        #expect(store.state.profiles.map(\.name) == ["Work"])
        #expect(store.state.settings.onboardingComplete && store.state.settings.customDockMaterial == .frosted)
        let warning = try #require(store.persistenceWarning)
        #expect(warning.contains("Studio") && warning.contains("Future"))
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("state.json.recovery-") }
        #expect(preserved.count == 1)
        #expect(try preserved.first.map { try Data(contentsOf: $0) } == original)
    }

    @Test func unknownChoicesInListsAreSkippedRatherThanFailingTheWidget() throws {
        let json = #"{"aiLimitsVisibleProviders":["codex","a-provider-from-a-newer-build","claude"],"nowPlayingEnabledSources":["future","spotify"]}"#
        let configuration = try JSONDecoder().decode(WidgetConfiguration.self, from: Data(json.utf8))
        #expect(configuration.aiLimitsVisibleProviders == [.codex, .claude])
        #expect(configuration.nowPlayingEnabledSources == [.spotify] && configuration.nowPlayingSource == .spotify)
    }

    /// S16-001: every starter app slot names a real bundle identifier (Numbers is com.apple.iWork.Numbers), so a
    /// typo can never again make a preset claim an installed app is missing.
    @Test func starterPresetsNameRealBundleIdentifiers() {
        let reviewed: Set<String> = [
            "com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.Preview",
            "com.apple.Photos", "com.apple.dt.Xcode", "com.apple.TextEdit", "com.apple.Terminal", "com.apple.iWork.Numbers",
            "com.apple.FaceTime", "com.apple.Maps", "com.apple.ActivityMonitor", "com.figma.Desktop", "com.adobe.Photoshop",
            "com.microsoft.VSCode", "com.googlecode.iterm2", "us.zoom.xos", "com.openai.codex"
        ]
        for preset in DockStarterPreset.allCases {
            for identifier in preset.applicationCandidates.joined() {
                #expect(reviewed.contains(identifier), "\(preset): \(identifier)")
            }
        }
        #expect(DockStarterPreset.commerce.applicationCandidates.joined().contains("com.apple.iWork.Numbers"))
    }

    /// S10-001: apps and document packages open like files in the folder popout instead of being browsed.
    @Test func folderPopoutOpensPackagesInsteadOfBrowsingThem() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["Tool.app/Contents", "Notes.rtfd", "Projects"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("x".utf8).write(to: folder.appendingPathComponent("readme.txt"))
        let entries = try FolderContentsReader.entries(at: folder)
        let browsable = Set(entries.filter(\.isDirectory).map(\.url.lastPathComponent))
        #expect(browsable == ["Projects"])
        #expect(entries.first?.url.lastPathComponent == "Projects", "only real folders sort first")
        #expect(entries.count == 4)
    }

    /// S10-003: a reminder due on a day without a time is due all that day, as in Reminders.
    @Test func dateOnlyRemindersAreDueAllDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let afternoon = Date(timeIntervalSince1970: 1_790_000_000)
        let dueDay = calendar.startOfDay(for: afternoon)
        let dateOnly = ReminderSnapshot(id: "r", title: "Pay rent", dueDate: dueDay, calendarID: "c", calendarTitle: "Home",
                                        dueHasTime: false)
        #expect(!RemindersFacePresentation.isOverdue(dateOnly, now: afternoon, calendar: calendar))
        #expect(RemindersFacePresentation.isOverdue(dateOnly, now: dueDay.addingTimeInterval(86_400), calendar: calendar))
        #expect(RemindersFacePresentation.dueText(dateOnly, now: afternoon, calendar: calendar) == "Today")
        var timed = dateOnly
        timed.dueHasTime = true
        #expect(RemindersFacePresentation.isOverdue(timed, now: afternoon, calendar: calendar))
        #expect(RemindersFacePresentation.dueText(timed, now: afternoon, calendar: calendar)?.hasPrefix("Today, ") == true)
        #expect(RemindersFacePresentation.overdueCount([dateOnly, timed], now: afternoon, calendar: calendar) == 1)
    }

    /// S10-002: a one-time alarm records when it rings, so once that passes it no longer reads as armed.
    @Test func aOneTimeAlarmStopsReadingAsArmedOnceItHasRung() throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let once = DockAlarm(title: "Once", hour: 7, minute: 0, repeatWeekdays: [], isEnabled: true).armed(now: now)
        let ring = try #require(once.scheduledFireDate)
        #expect(ring > now)
        #expect(AlarmFacePresentation.next([once], now: now)?.date == ring)
        let later = ring.addingTimeInterval(60)
        #expect(AlarmFacePresentation.next([once], now: later) == nil)
        #expect(!AlarmFacePresentation.isArmed(once, now: later))
        #expect(once.armed(now: later).scheduledFireDate.map { $0 > later } == true, "turning it on again arms the next ring")
        let weekly = DockAlarm(title: "Weekly", hour: 7, minute: 0, repeatWeekdays: [2], isEnabled: true).armed(now: now)
        #expect(weekly.scheduledFireDate == nil && AlarmFacePresentation.isArmed(weekly, now: later))
        let off = DockAlarm(title: "Off", hour: 7, minute: 0, repeatWeekdays: [], isEnabled: false).armed(now: now)
        #expect(off.scheduledFireDate == nil)
    }

    /// S12-002: a EUR-only Stripe account shows EUR instead of "No data" for the USD a new connection starts on,
    /// while a currency the account did report stays the user's choice.
    @Test func stripeShowsTheAccountsOwnCurrencyWhenItNeverReportedTheSelectedOne() {
        func metrics(_ currency: String, revenue: Decimal) -> StripeCurrencyMetrics {
            StripeCurrencyMetrics(currency: currency, revenueMinor: revenue, netAfterFeesMinor: revenue, mrrMinor: 0,
                                  payingSubscribers: 0, availableBalanceMinor: 0, pendingBalanceMinor: 0)
        }
        func snapshot(_ currencies: [StripeCurrencyMetrics]) -> StripeSnapshot {
            StripeSnapshot(accountID: "acct", accountName: "Shop", fetchedAt: .now, period: .thirtyDays, periodStart: .now,
                           periodEnd: .now, currencies: currencies, unsupportedSubscriptionItems: 0)
        }
        var configuration = WidgetConfiguration()
        configuration.stripeCurrency = "USD"
        WidgetDataValue.stripe(snapshot([metrics("EUR", revenue: 900), metrics("GBP", revenue: 100)])).apply(to: &configuration)
        #expect(configuration.stripeCurrency == "EUR")
        configuration.stripeCurrency = "GBP"
        WidgetDataValue.stripe(snapshot([metrics("EUR", revenue: 950)])).apply(to: &configuration)
        #expect(configuration.stripeCurrency == "GBP", "a currency the account reported before stays selected")
    }

    /// S11-001: a trading session stored as UTC midnight keeps its own day wherever the Mac is.
    @Test func stockSessionDatesKeepTheirDayWestOfUTC() throws {
        let session = try #require(ISO8601DateFormatter().date(from: "2026-10-06T00:00:00Z"))
        let english = Locale(identifier: "en_US")
        #expect(StockFaceFormatting.sessionDate(session, locale: english) == "Oct 6, 2026")
        var newYork = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: english, calendar: Calendar(identifier: .gregorian))
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(session.formatted(newYork) == "Oct 5, 2026", "the old formatting showed the previous day")
    }

    /// S11-002: opening a Stock, Watchlist or AI Limits popout reuses a reading newer than the update interval;
    /// only the refresh button forces a fetch, so a market data key's few daily requests last.
    @MainActor
    @Test func openingADataPopoutDoesNotRefetchAFreshReading() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("state.json"), allowsSystemChanges: false)
        var stock = DockItem.widget("Stock")
        stock.widgetConfiguration?.stockSymbol = "AAPL"
        let profileID = try store.createProfile(DockProfile(name: "Markets", kind: .custom, items: [stock]))
        let loads = LoadCounter()
        let coordinator = WidgetDataCoordinator(store: store) { _, _ in
            await loads.increment()
            return .stock(StockMarketSnapshot(symbol: "AAPL", points: [], currency: "USD", fetchedAt: .now))
        }
        await coordinator.refresh(item: stock, profileID: profileID, force: false)
        await coordinator.refresh(item: stock, profileID: profileID, force: false)
        #expect(await loads.count == 1)
        await coordinator.refresh(item: stock, profileID: profileID)
        #expect(await loads.count == 2)
    }

    /// S15-001: Return adds only the result drawn highlighted; a gallery opened without a search adds nothing.
    @MainActor
    @Test func returnAddsOnlyTheHighlightedResult() {
        #expect(WidgetGalleryModel.highlightedIndex(keyboardNavigation: false, hasQuery: false, selected: 0, count: 5) == nil)
        #expect(WidgetGalleryModel.highlightedIndex(keyboardNavigation: false, hasQuery: true, selected: 0, count: 5) == 0)
        #expect(WidgetGalleryModel.highlightedIndex(keyboardNavigation: true, hasQuery: false, selected: 3, count: 5) == 3)
        #expect(WidgetGalleryModel.highlightedIndex(keyboardNavigation: true, hasQuery: true, selected: 9, count: 5) == 4)
        #expect(WidgetGalleryModel.highlightedIndex(keyboardNavigation: true, hasQuery: true, selected: 0, count: 0) == nil)
    }

    @Test func mainDisplayIsThePrimaryDisplayNotTheFocusedOne() {
        // AppKit lists the primary display (menu bar, origin at zero) first.
        let displays: [UInt32] = [7, 8, 9]
        let main = DockDisplaySelection.resolve(displays, selectedID: nil) { $0 }
        #expect(main.display == 7 && !main.isFallback)
        let chosen = DockDisplaySelection.resolve(displays, selectedID: 9) { $0 }
        #expect(chosen.display == 9 && !chosen.isFallback)
        let disconnected = DockDisplaySelection.resolve(displays, selectedID: 42) { $0 }
        #expect(disconnected.display == 7 && disconnected.isFallback)
        let none = DockDisplaySelection.resolve([UInt32](), selectedID: nil) { $0 }
        #expect(none.display == nil && !none.isFallback)
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

private actor LoadCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
