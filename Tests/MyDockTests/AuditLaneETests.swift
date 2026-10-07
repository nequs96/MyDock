import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// Audit lane E: widget foundation and core widget families.
@MainActor
@Suite struct AuditLaneETests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Glyph contrast on filled circles

    @Test func filledGlyphsKeepThreeToOneContrastInBothAppearances() {
        let black = WidgetRoundButtonPalette.RGB(red: 0, green: 0, blue: 0)
        for family in WidgetPalette.Family.allCases {
            for dark in [false, true] {
                let (r, g, b) = dark ? family.rgb.dark : family.rgb.light
                let fill = WidgetRoundButtonPalette.RGB(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                let glyph = WidgetIcon.onFillIsBlack(treatment: .accent, accent: .auto, dark: dark) ? black : WidgetRoundButtonPalette.white
                #expect(WidgetRoundButtonPalette.contrast(glyph, fill) >= 3, "\(family) dark: \(dark)")
            }
        }
        for color in DockProfileColor.allCases {
            let fill = WidgetPalette.profileRGB(color)
            for dark in [false, true] {
                let glyph = WidgetIcon.onFillIsBlack(treatment: .soft, accent: .profile(color), dark: dark) ? black : WidgetRoundButtonPalette.white
                #expect(WidgetRoundButtonPalette.contrast(glyph, fill) >= 3, "\(color) dark: \(dark)")
            }
        }
        // A primary fill still inverts: black glyph on the light primary of Dark Mode, white on black.
        #expect(WidgetIcon.onFillIsBlack(treatment: .mono, accent: .auto, dark: true))
        #expect(!WidgetIcon.onFillIsBlack(treatment: .mono, accent: .auto, dark: false))
    }

    // MARK: Local face tick pace

    @Test func localFacesTickOnlyAsOftenAsTheirTextChanges() {
        let c = WidgetConfiguration()
        #expect(LocalWidgetTickPolicy.interval(kind: "Sticky Note", configuration: c, now: now) == nil)
        #expect(LocalWidgetTickPolicy.interval(kind: "Quick Checklist", configuration: c, now: now) == nil)
        #expect(LocalWidgetTickPolicy.interval(kind: "Calculator", configuration: c, now: now) == nil)
        #expect(LocalWidgetTickPolicy.interval(kind: "Stock", configuration: c, now: now) == nil)
        #expect(LocalWidgetTickPolicy.interval(kind: "Clock", configuration: c, now: now) == 60)
        #expect(LocalWidgetTickPolicy.interval(kind: "Hydration", configuration: c, now: now) == 60)

        var stopwatch = WidgetConfiguration()
        #expect(LocalWidgetTickPolicy.interval(kind: "Stopwatch", configuration: stopwatch, now: now) == nil)
        stopwatch.stopwatchStartedAt = now
        #expect(LocalWidgetTickPolicy.interval(kind: "Stopwatch", configuration: stopwatch, now: now) == 1)

        var focus = WidgetConfiguration()
        focus.focusDurationSeconds = 1_500
        #expect(LocalWidgetTickPolicy.interval(kind: "Focus Timer", configuration: focus, now: now) == nil)
        focus.focusStartedAt = now
        #expect(LocalWidgetTickPolicy.interval(kind: "Focus Timer", configuration: focus, now: now) == 1)
        // A finished session stops ticking.
        #expect(LocalWidgetTickPolicy.interval(kind: "Focus Timer", configuration: focus, now: now.addingTimeInterval(2_000)) == nil)

        var target = WidgetConfiguration()
        target.setCountdownMode(.targetDate)
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: target, now: now) == nil)
        target.setCountdownTarget(now.addingTimeInterval(2 * 3_600))
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: target, now: now) == 60)
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: target, now: now.addingTimeInterval(3_600 + 1_800)) == 1)
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: target, now: now.addingTimeInterval(3 * 3_600)) == nil)

        var duration = WidgetConfiguration()
        duration.setCountdownMode(.duration)
        duration.countdownDurationSeconds = 300
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: duration, now: now) == nil)
        duration.startCountdown(at: now)
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: duration, now: now.addingTimeInterval(10)) == 1)
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: duration, now: now.addingTimeInterval(400)) == nil)
    }

    // MARK: Weather staleness

    @Test func weatherFaceMarksOldOrFutureForecastsAndLoadsBeforeFailing() {
        #expect(!WeatherFaceFreshness.isStale(fetchedAt: now.addingTimeInterval(-3_600), now: now))
        #expect(WeatherFaceFreshness.isStale(fetchedAt: now.addingTimeInterval(-4 * 3_600), now: now))
        #expect(WeatherFaceFreshness.isStale(fetchedAt: now.addingTimeInterval(2 * 3_600), now: now))
        #expect(WeatherFaceFreshness.placeholder(hasLocation: false, failed: false) == "Set city")
        #expect(WeatherFaceFreshness.placeholder(hasLocation: true, failed: false) == "Loading")
        #expect(WeatherFaceFreshness.placeholder(hasLocation: true, failed: true) == "Unavailable")
    }

    // MARK: Freshness edge cases

    @Test func futureTimestampsAreNeverFreshOrDescribedAsComingUp() {
        #expect(WidgetFreshnessPresentation.state(isRefreshing: false, updatedAt: now.addingTimeInterval(30), failed: false,
                                                  now: now, maximumAge: 600) == .fresh)
        #expect(WidgetFreshnessPresentation.state(isRefreshing: false, updatedAt: now.addingTimeInterval(600), failed: false,
                                                  now: now, maximumAge: 600) == .stale)
        let future = now.addingTimeInterval(600)
        #expect(WidgetFreshnessPresentation.relativeText(future, now: now) == future.formatted(date: .abbreviated, time: .shortened))
        #expect(WidgetFreshnessPresentation.relativeText(now.addingTimeInterval(-30), now: now) == "just now")
        #expect(WidgetFreshnessPresentation.status(.fresh, updatedAt: now.addingTimeInterval(-30), now: now) == "Updated just now")
    }

    @Test func aWatchlistWithANeverLoadedTickerHasNoCompleteReading() {
        let old = StockMarketSnapshot(symbol: "AAPL", points: [], currency: "USD", fetchedAt: now.addingTimeInterval(-600))
        let recent = StockMarketSnapshot(symbol: "MSFT", points: [], currency: "USD", fetchedAt: now)
        let loaded = [WatchlistStock(symbol: "AAPL", name: "Apple", currency: "USD", snapshot: old),
                      WatchlistStock(symbol: "MSFT", name: "Microsoft", currency: "USD", snapshot: recent)]
        #expect(WidgetFreshnessPresentation.watchlistFetchedAt(loaded) == old.fetchedAt)
        let partial = loaded + [WatchlistStock(symbol: "NVDA", name: "NVIDIA", currency: "USD", snapshot: nil)]
        #expect(WidgetFreshnessPresentation.watchlistFetchedAt(partial) == nil)
        #expect(WidgetFreshnessPresentation.watchlistFetchedAt([]) == nil)
    }

    // MARK: Locale-aware face numbers

    @Test func faceNumbersFollowTheLocaleDecimalSeparator() {
        let german = Locale(identifier: "de_DE")
        let american = Locale(identifier: "en_US")
        #expect(NetworkRateText.short(2_400_000, locale: german) == "2,4M")
        #expect(NetworkRateText.short(2_400_000, locale: american) == "2.4M")
        #expect(NetworkRateText.short(148_000, locale: german) == "148K")
        #expect(MarketFaceText.change(1.234, locale: american) == "+1.2%")
        let germanChange = MarketFaceText.change(1.234, locale: german)
        #expect(germanChange.hasPrefix("+") && germanChange.contains("1,2"), "\(germanChange)")
        #expect(MarketFaceText.change(-0.8, locale: american).contains("0.8"))
    }

    // MARK: Collection undo

    @Test func undoOfferIsMeasuredFromRemovalAndLastsLongerWithVoiceOver() throws {
        let list = [QuickChecklistEntry(title: "One"), QuickChecklistEntry(title: "Two")]
        var removed = try #require(RemovedEntries.capture([list[0].id], from: list, message: "Removed"))
        removed.createdAt = now
        let lifetime = RemovedEntries<QuickChecklistEntry>.lifetime
        #expect(removed.remainingLifetime(at: now.addingTimeInterval(5)) == lifetime - 5)
        #expect(removed.remainingLifetime(at: now.addingTimeInterval(5), extended: true) == 2 * lifetime - 5)
        #expect(removed.remainingLifetime(at: now.addingTimeInterval(lifetime + 1)) == 0)
        #expect(removed.isExpired(at: now.addingTimeInterval(lifetime + 1)))
        #expect(!removed.isExpired(at: now.addingTimeInterval(lifetime + 1), extended: true))
        #expect(UndoNoticeCopy.announcement("Removed.") == "Removed. Undo available.")
    }

    // MARK: Countdown hero

    @Test func countdownHeroReadsStatesAsStatusAndNumbersWithContext() {
        var target = WidgetConfiguration()
        target.setCountdownMode(.targetDate)
        let unset = CountdownHeroPresentation.hero(target, at: now)
        #expect(unset.value == "Choose a target date" && unset.caption == nil)
        #expect(WidgetPopoutHeroStyle.automatic(for: unset.value) == .status)
        #expect(CountdownHeroPresentation.settingsSummary(target) == "No target")
        target.setCountdownTarget(now.addingTimeInterval(90))
        let counting = CountdownHeroPresentation.hero(target, at: now)
        #expect(counting.value == "1:30")
        #expect(counting.caption?.hasPrefix("until ") == true)
        #expect(CountdownHeroPresentation.deadline(target) == now.addingTimeInterval(90))
        let complete = CountdownHeroPresentation.hero(target, at: now.addingTimeInterval(100))
        #expect(complete.value == "Complete")
        #expect(WidgetPopoutHeroStyle.automatic(for: complete.value) == .status)

        var duration = WidgetConfiguration()
        duration.setCountdownMode(.duration)
        duration.countdownDurationSeconds = 300
        #expect(CountdownHeroPresentation.hero(duration, at: now).caption == "Ready")
        #expect(CountdownHeroPresentation.settingsSummary(duration) == "5 min")
        #expect(CountdownHeroPresentation.deadline(duration) == nil)
        duration.startCountdown(at: now)
        #expect(CountdownHeroPresentation.deadline(duration) == now.addingTimeInterval(300))
        let running = CountdownHeroPresentation.hero(duration, at: now.addingTimeInterval(60))
        #expect(running.value == "4:00" && running.caption == "remaining")
        let finished = CountdownHeroPresentation.hero(duration, at: now.addingTimeInterval(400))
        #expect(finished.value == "0:00" && finished.caption == "Complete · Reset to start again")
        duration.pauseCountdown(at: now.addingTimeInterval(120))
        #expect(CountdownHeroPresentation.hero(duration, at: now.addingTimeInterval(500)).caption == "Paused")
    }

    // MARK: Hydration

    @Test func hydrationOffersOneActionThatMatchesItsSettings() {
        #expect(HydrationLogAction.title(saveHistory: true, remindersOn: true) == "Log Drink")
        #expect(HydrationLogAction.title(saveHistory: true, remindersOn: false) == "Log Drink")
        #expect(HydrationLogAction.title(saveHistory: false, remindersOn: true) == "Restart Reminder")
        #expect(HydrationLogAction.isEnabled(saveHistory: false, remindersOn: true))
        #expect(!HydrationLogAction.isEnabled(saveHistory: false, remindersOn: false))
    }

    // MARK: Sticky Note persistence

    @Test func savingAnUnchangedNoteWritesNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AuditLaneETests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("state.json")
        let note = DockItem.widget("Sticky Note")
        let store = ProfileStore(fileURL: file, allowsSystemChanges: false)
        let profileID = try store.createProfile(DockProfile(name: "Notes", kind: .custom, items: [note]))
        let drafts = WidgetSetupDraftStore()
        try drafts.saveNote("Hello", for: note.id, in: profileID, to: store)
        #expect(ProfileStore(fileURL: file, allowsSystemChanges: false).activeCustomProfile?.items.first?.widgetConfiguration?.noteText == "Hello")

        // Opening and closing the popout saves the same text again: no write reaches the disk.
        try FileManager.default.removeItem(at: file)
        drafts.updateNoteDraft("Hello", for: note.id, in: profileID)
        try drafts.saveNote("Hello", for: note.id, in: profileID, to: store)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(!drafts.hasPendingNotes)

        // A real edit is still written.
        try drafts.saveNote("Hello again", for: note.id, in: profileID, to: store)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
