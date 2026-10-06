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

    @MainActor
    @Test func dockLayoutToleratesDuplicateItemIdentities() {
        let item = runtimeApp()
        var model = DockRenderModel(profile: DockProfile(name: "Duplicates", kind: .custom, items: []), settings: AppSettings(),
                                    runningApplications: [], windows: [], runningMediaSources: [])
        model.entries = [.item(item, pinned: true), .item(item, pinned: false)]
        #expect(model.positionedEntries(settings: AppSettings(), scale: 1).count == 2)
    }
}
