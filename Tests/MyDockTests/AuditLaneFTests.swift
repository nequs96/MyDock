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
