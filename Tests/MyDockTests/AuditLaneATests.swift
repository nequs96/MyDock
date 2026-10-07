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
}
