import AppKit
import Foundation
import IOKit.ps
import SwiftUI
import Testing
import UniformTypeIdentifiers
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

    @Test func targetCountdownFacesTurnOverWithTheTargetNotTheClock() throws {
        var countdown = WidgetConfiguration()
        countdown.setCountdownTarget(now.addingTimeInterval(3_930)) // 1h 5m 30s away
        let target = try #require(countdown.countdownTargetDate)
        let anchor = try #require(LocalWidgetTickPolicy.minuteAnchor(kind: "Countdown", configuration: countdown, now: now))
        // The latest tick at or before now, one second after a whole minute to the target passed.
        #expect(anchor <= now && now.timeIntervalSince(anchor) < 60)
        #expect(target.timeIntervalSince(anchor).truncatingRemainder(dividingBy: 60) == 59)
        // Seconds start a minute before the last hour, because the pace is re-read only on the minute.
        #expect(LocalWidgetTickPolicy.interval(kind: "Countdown", configuration: countdown, now: now.addingTimeInterval(300)) == 1)
        #expect(LocalWidgetTickPolicy.minuteAnchor(kind: "Clock", configuration: countdown, now: now) == nil)
        #expect(LocalWidgetTickPolicy.minuteAnchor(kind: "Countdown", configuration: countdown, now: target.addingTimeInterval(1)) == nil)
    }

    @Test func timerFacesSayPausedOnlyForATimerStoppedPartWay() {
        var focus = WidgetConfiguration()
        focus.focusDurationSeconds = 1_500
        #expect(TimerFaceSpeech.value(kind: "Focus Timer", configuration: focus, text: "25:00", at: now) == "25:00")
        focus.startFocusTimer(at: now)
        #expect(TimerFaceSpeech.value(kind: "Focus Timer", configuration: focus, text: "24:00", at: now.addingTimeInterval(60)) == "24:00")
        focus.pauseFocusTimer(at: now.addingTimeInterval(60))
        #expect(TimerFaceSpeech.value(kind: "Focus Timer", configuration: focus, text: "24:00", at: now.addingTimeInterval(120)) == "24:00, paused")
        #expect(TimerFaceSpeech.value(kind: "Stopwatch", configuration: WidgetConfiguration(), text: "00:00", at: now) == "00:00")

        var target = WidgetConfiguration()
        target.setCountdownMode(.targetDate)
        #expect(TimerFaceSpeech.value(kind: "Countdown", configuration: target, text: "0:00", at: now) == "No target date")
        target.setCountdownTarget(now.addingTimeInterval(60))
        #expect(TimerFaceSpeech.value(kind: "Countdown", configuration: target, text: "1:00", at: now) == "1:00")
        #expect(TimerFaceSpeech.value(kind: "Countdown", configuration: target, text: "0:00", at: now.addingTimeInterval(61)) == "Complete")
    }

    // MARK: Weather staleness

    @Test func weatherFaceMarksOldOrFutureForecastsAndLoadsBeforeFailing() {
        // One rule for the face and the popout: older than 30 minutes, a failed refresh, or dated in the future.
        #expect(!WeatherFreshness.isStale(fetchedAt: now.addingTimeInterval(-20 * 60), failed: false, now: now))
        #expect(WeatherFreshness.isStale(fetchedAt: now.addingTimeInterval(-4 * 3_600), failed: false, now: now))
        #expect(WeatherFreshness.isStale(fetchedAt: now.addingTimeInterval(2 * 3_600), failed: false, now: now))
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
        #expect(StockFaceFormatting.faceChangeText(1.234, locale: american) == "+1.2%")
        let germanChange = StockFaceFormatting.faceChangeText(1.234, locale: german) ?? ""
        #expect(germanChange.hasPrefix("+") && germanChange.contains("1,2"), "\(germanChange)")
        #expect(StockFaceFormatting.faceChangeText(-0.8, locale: american)?.contains("0.8") == true)
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

    // MARK: Part 2: market colour, battery state, Disk, World Clock, numbers, Trash, AirDrop

    @Test func anUnchangedMarketPriceIsNotColouredAsAGain() {
        #expect(StockFaceFormatting.changeColor(nil) == Color.secondary)
        #expect(StockFaceFormatting.changeColor(0) == Color.secondary)
        #expect(StockFaceFormatting.changeColor(0.004) == Color.secondary)
        #expect(StockFaceFormatting.changeColor(-0.004) == Color.secondary)
        #expect(StockFaceFormatting.changeColor(Double.nan) == Color.secondary)
        // A rise stays neutral under the T2 accent rule (S11-010); only a real fall is coloured.
        #expect(StockFaceFormatting.changeColor(1.25) == Color.secondary)
        #expect(StockFaceFormatting.changeColor(-0.5) == WidgetPalette.critical)
    }

    @Test func batteryStatusUsesTheWordsMacOSUses() throws {
        func reading(charging: Bool, state: String?, charged: Bool? = nil) throws -> BatteryReading {
            var description: [String: Any] = [
                kIOPSNameKey as String: "InternalBattery-0",
                kIOPSCurrentCapacityKey as String: 80,
                kIOPSMaxCapacityKey as String: 100,
                kIOPSIsChargingKey as String: charging,
                kIOPSTypeKey as String: kIOPSInternalBatteryType as String
            ]
            if let state { description[kIOPSPowerSourceStateKey as String] = state }
            if let charged { description[kIOPSIsChargedKey as String] = charged }
            return try #require(BatteryReader.reading(from: description))
        }
        let ac = kIOPSACPowerValue as String
        let battery = kIOPSBatteryPowerValue as String
        #expect(try reading(charging: true, state: ac).statusText == "Charging")
        #expect(try reading(charging: false, state: ac, charged: true).statusText == "Charged")
        // Plugged in but held (Optimized Battery Charging): macOS says "Not charging".
        #expect(try reading(charging: false, state: ac).statusText == "Not charging")
        // Running on the battery is not "Not charging".
        #expect(try reading(charging: false, state: battery).statusText == "On battery")
        #expect(try reading(charging: false, state: nil).statusText == "On battery")
        // Older call sites keep compiling and read as on battery.
        #expect(BatteryReading(name: "Mouse", percentage: 50, isCharging: false, isInternal: false).statusText == "On battery")
    }

    @Test func batteryPopoutLeadsWithTheMacAndColoursOnlyLowCharge() {
        let mouse = BatteryReading(name: "Mouse", percentage: 15, isCharging: false, isInternal: false)
        let mac = BatteryReading(name: "InternalBattery-0", percentage: 84, isCharging: false, isInternal: true)
        #expect(BatteryPresentation.primaryIndex([mouse, mac]) == 1)
        #expect(BatteryPresentation.primaryIndex([mouse]) == 0)
        #expect(BatteryPresentation.primaryIndex([]) == nil)
        #expect(BatteryPresentation.lowChargeColor(mac) == nil)
        #expect(BatteryPresentation.lowChargeColor(mouse) == WidgetPalette.warning)
        #expect(BatteryPresentation.lowChargeColor(BatteryReading(name: "Mouse", percentage: 8, isCharging: false, isInternal: false)) == WidgetPalette.critical)
        #expect(BatteryPresentation.lowChargeColor(BatteryReading(name: "Mouse", percentage: 8, isCharging: true, isInternal: false)) == nil)
        // VoiceOver reads the display name, not the IOKit name, and the state.
        let spoken = BatteryPresentation.accessibilityValue(mac)
        #expect(spoken.hasPrefix("Mac battery, "))
        #expect(spoken.hasSuffix(", on battery"))
        #expect(!spoken.contains("InternalBattery"))
    }

    @Test func worldClockRowsUseAPluralisedShortDayOffset() {
        #expect(WidgetTimingPresentation.shortDayOffset(0) == "Same day")
        #expect(WidgetTimingPresentation.shortDayOffset(1) == "+1 day")
        #expect(WidgetTimingPresentation.shortDayOffset(2) == "+2 days")
        #expect(WidgetTimingPresentation.shortDayOffset(-1) == "\u{2212}1 day")
        #expect(WidgetTimingPresentation.shortDayOffset(-2) == "\u{2212}2 days")
    }

    @Test func percentagesAndVolumesFollowTheLocale() {
        let us = Locale(identifier: "en_US")
        #expect(DockNumberText.percent(fraction: 0.72, locale: us) == "72%")
        #expect(DockNumberText.percent(fraction: 0.726, locale: us) == "73%")
        // A period's progress never reads 100% before it ends.
        #expect(DockNumberText.percent(fraction: 0.996, roundingDown: true, locale: us) == "99%")
        #expect(DockNumberText.percent(fraction: .nan, locale: us) == "0%")
        let french = DockNumberText.percent(fraction: 0.72, locale: Locale(identifier: "fr_FR"))
        #expect(french.hasPrefix("72") && french != "72%")
        let volume = DockNumberText.milliliters(250, locale: us)
        #expect(volume.hasPrefix("250") && volume.hasSuffix("mL"))
    }

    @Test func stickyNoteLimitIsOneShortLineInByteUnits() {
        let near = StickyNoteLimitText.text(bytes: 1_000_000, limit: 1_048_576)
        let over = StickyNoteLimitText.text(bytes: 1_100_000, limit: 1_048_576)
        #expect(near.hasPrefix("Near the ") && near.hasSuffix(" note limit."))
        #expect(over.hasPrefix("Over the "))
        #expect(!near.contains("UTF-8") && !near.contains("1,048,576"))
    }

    @Test func usageBarsShareOneMeterAtTwoHeights() {
        #expect(UsageBar(fraction: 0.5).height == 3)
        #expect(UsageBar.popoutHeight == 6)
    }

    @Test func emptyTrashCoversEveryVolumeAndOffersAutomationOnDenial() {
        // Items may sit only on an external drive's Trash, which the home count does not see.
        #expect(TrashFacePresentation.canEmpty(count: 0, errorMessage: nil, needsAccess: false))
        #expect(!TrashFacePresentation.canEmpty(count: 0, errorMessage: "Read failed", needsAccess: false))
        #expect(TrashCopy.mayNeedAutomation(AutomationError.permissionDenied))
        #expect(TrashCopy.mayNeedAutomation(NowPlayingParsingError.malformedResponse))
        #expect(!TrashCopy.mayNeedAutomation(AutomationError.failed(exitStatus: 1)))
        let denied = TrashActionError.automationDenied("Not allowed")
        #expect(denied.suggestsAutomationSettings && denied.localizedDescription == "Not allowed")
        #expect(!TrashActionError.failed("Other").suggestsAutomationSettings)
        #expect(TrashCopy.countLabel(1) == "1 item in home Trash")
    }

    @Test func airDropDropsKeepOnlyShareableItems() async {
        let link = NSItemProvider(item: NSURL(string: "https://example.com/page"), typeIdentifier: UTType.url.identifier)
        let mail = NSItemProvider(item: "mailto:someone@example.com" as NSString, typeIdentifier: UTType.url.identifier)
        let accepted: [URL] = await withCheckedContinuation { continuation in
            AirDropDroppedItemLoader.load([(link, UTType.url.identifier), (mail, UTType.url.identifier)]) { urls in
                continuation.resume(returning: urls)
            }
        }
        #expect(accepted.map(\.absoluteString) == ["https://example.com/page"])
        // A drop with nothing shareable completes empty, which the tile answers with a beep.
        let rejected: [URL] = await withCheckedContinuation { continuation in
            AirDropDroppedItemLoader.load([(mail, UTType.url.identifier)]) { urls in
                continuation.resume(returning: urls)
            }
        }
        #expect(rejected.isEmpty)
    }

    @Test func aDarkDockDrawsTheDarkWindowBackgroundWhateverTheSystemAppearance() {
        #expect(DockMaterialSurface.windowBackground(.dark) != DockMaterialSurface.windowBackground(.light))
    }
}
