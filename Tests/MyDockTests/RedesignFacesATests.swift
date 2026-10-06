import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// RD-09 faces and popouts A: pure presentation helpers, and a non-empty face for every family × layout.
struct RedesignFacesATests {
    static let families = ["Calendar", "Reminders", "Alarm", "Disk Space", "Calculator", "Quick Checklist", "File Shelf", "Text Snippets",
                           "Quick Links", "Unit Converter", "Color Picker", "Now Playing", "Weather", "AirDrop", "Trash"]

    private func event(start: TimeInterval, end: TimeInterval, now: Date, allDay: Bool = false) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: "e", title: "Review", startDate: now.addingTimeInterval(start), endDate: now.addingTimeInterval(end),
                              isAllDay: allDay, calendarID: "c", calendarTitle: "Work", meetingURL: nil)
    }

    @Test func calendarCompactStatusIsShortAndTruthful() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        #expect(CalendarFacePresentation.compactStatus(event(start: -7200, end: -3600, now: now), now: now, calendar: calendar) == "Ended")
        #expect(CalendarFacePresentation.compactStatus(event(start: 0, end: 86_400, now: now, allDay: true), now: now, calendar: calendar) == "All day")
        #expect(CalendarFacePresentation.compactStatus(event(start: -600, end: 1800, now: now), now: now, calendar: calendar).hasPrefix("Now · until "))
        #expect(CalendarFacePresentation.compactStatus(event(start: 45 * 60, end: 75 * 60, now: now), now: now, calendar: calendar) == "In 45 min")
        #expect(CalendarFacePresentation.compactStatus(event(start: 20, end: 600, now: now), now: now, calendar: calendar) == "In 1 min")
        #expect(CalendarFacePresentation.compactStatus(event(start: 26 * 3600, end: 27 * 3600, now: now), now: now, calendar: calendar).hasPrefix("Tomorrow "))
        let later = CalendarFacePresentation.compactStatus(event(start: 4 * 3600, end: 5 * 3600, now: now), now: now, calendar: calendar)
        #expect(!later.hasPrefix("In ") && !later.hasPrefix("Tomorrow"))
    }

    @Test func calendarPartsFollowBothLayouts() {
        func parts(_ calendarLayout: CalendarWidgetLayout, _ dockLayout: WidgetLayout) -> [Bool] {
            let value = CalendarFacePresentation.parts(calendarLayout: calendarLayout, dockLayout: dockLayout)
            return [value.date, value.event]
        }
        #expect(parts(.dateAndNextEvent, .compact) == [true, false])
        #expect(parts(.dateAndNextEvent, .wide) == [true, true])
        #expect(parts(.nextEvent, .wide) == [false, true])
        #expect(parts(.nextEvent, .compact) == [true, false])
        #expect(parts(.date, .wide) == [true, false])
    }

    @Test func calendarEmptyStateNeverHidesMissingAccess() {
        #expect(CalendarFacePresentation.emptyState(errorMessage: "denied", accessAvailable: false).title == "Unavailable")
        #expect(CalendarFacePresentation.emptyState(errorMessage: "denied", accessAvailable: true).title == "Unavailable")
        #expect(CalendarFacePresentation.emptyState(errorMessage: nil, accessAvailable: true).title == "No events")
        #expect(CalendarFacePresentation.emptyState(errorMessage: nil, accessAvailable: false).title == "Calendar")
    }

    @Test func remindersOverdueStateUsesDueDates() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reminders = [ReminderSnapshot(id: "1", title: "Late", dueDate: now.addingTimeInterval(-60), calendarID: "l", calendarTitle: "L"),
                         ReminderSnapshot(id: "2", title: "Soon", dueDate: now.addingTimeInterval(60), calendarID: "l", calendarTitle: "L"),
                         ReminderSnapshot(id: "3", title: "Someday", dueDate: nil, calendarID: "l", calendarTitle: "L")]
        #expect(RemindersFacePresentation.overdueCount(reminders, now: now) == 1)
        #expect(RemindersFacePresentation.isOverdue(reminders[0], now: now))
        #expect(!RemindersFacePresentation.isOverdue(reminders[1], now: now))
        #expect(!RemindersFacePresentation.isOverdue(reminders[2], now: now))
    }

    @Test func alarmNextIgnoresDisabledAlarmsAndSummarisesRepeats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        let alarms = [DockAlarm(title: "Off", hour: 8, minute: 30, repeatWeekdays: [], isEnabled: false),
                      DockAlarm(title: "Noon", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true),
                      DockAlarm(title: "Evening", hour: 18, minute: 0, repeatWeekdays: [], isEnabled: true)]
        #expect(AlarmFacePresentation.next(alarms, now: now)?.alarm.title == "Noon")
        #expect(AlarmFacePresentation.next(alarms.filter { !$0.isEnabled }, now: now) == nil)
        #expect(AlarmFacePresentation.day(now.addingTimeInterval(3600), now: now, calendar: calendar) == "Today")
        #expect(AlarmFacePresentation.day(now.addingTimeInterval(86_400), now: now, calendar: calendar) == "Tomorrow")
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        #expect(AlarmFacePresentation.repeatSummary([], symbols: symbols) == "Once")
        #expect(AlarmFacePresentation.repeatSummary(Array(1...7), symbols: symbols) == "Every day")
        #expect(AlarmFacePresentation.repeatSummary([4, 2], symbols: symbols) == "Mon Wed")
    }

    @Test func trashStateColoursOnlyFullAndNamesEveryState() {
        let empty = TrashFacePresentation(count: 0, errorMessage: nil)
        #expect(!empty.isFull && !empty.isUnavailable && empty.label == "Empty" && empty.symbol == "trash")
        let one = TrashFacePresentation(count: 1, errorMessage: nil)
        #expect(one.isFull && one.label == "1 item" && one.symbol == "trash.fill")
        #expect(TrashFacePresentation(count: 12, errorMessage: nil).label == "12 items")
        let unavailable = TrashFacePresentation(count: 5, errorMessage: "No access")
        #expect(!unavailable.isFull && unavailable.isUnavailable && unavailable.label == "Unavailable")
    }

    @Test func savedCollectionsNeverShowABareNumber() {
        #expect(SavedCollectionFacePresentation.valueText(kind: "Text Snippets", count: 2) == "2 snippets")
        #expect(SavedCollectionFacePresentation.valueText(kind: "Text Snippets", count: 1) == "1 snippet")
        #expect(SavedCollectionFacePresentation.valueText(kind: "File Shelf", count: 0) == "0 files")
        #expect(SavedCollectionFacePresentation.valueText(kind: "Quick Links", count: 3) == "3 links")
        #expect(SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: "Reply", layout: .compact, narrow: false) == "Saved")
        #expect(SavedCollectionFacePresentation.label(kind: "File Shelf", latest: nil, layout: .compact, narrow: false) == "Shelf")
        #expect(SavedCollectionFacePresentation.label(kind: "Quick Links", latest: "Docs", layout: .wide, narrow: false) == "Docs")
        #expect(SavedCollectionFacePresentation.label(kind: "Quick Links", latest: nil, layout: .wide, narrow: false) == "Add a website")
        #expect(SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: "", layout: .wide, narrow: false) == "Save a snippet")
        #expect(SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: "Reply", layout: .wide, narrow: true) == "Snippets")
    }

    @Test func diskLowStateAndPlaybackFormatting() {
        #expect(DiskSpaceSnapshot(name: "D", totalBytes: 100, availableBytes: 5).isLow)
        #expect(!DiskSpaceSnapshot(name: "D", totalBytes: 100, availableBytes: 50).isLow)
        #expect(!DiskSpaceSnapshot(name: "D", totalBytes: 0, availableBytes: 0).isLow)
        #expect(NowPlayingPresentation.timeString(74) == "1:14")
        #expect(NowPlayingPresentation.timeString(.nan) == "0:00")
        #expect(NowPlayingPresentation.timeString(-5) == "0:00")
        #expect(NowPlayingPresentation.progress(position: 50, duration: 100) == 0.5)
        #expect(NowPlayingPresentation.progress(position: 50, duration: 0) == 0)
        #expect(NowPlayingPresentation.progress(position: 500, duration: 100) == 1)
        #expect(NowPlayingPresentation.progress(position: .infinity, duration: 100) == 0)
    }

    @Test func calculatorKeyRolesCoverEveryKey() {
        #expect(CalculatorKeyStyle.Role("=") == .equals)
        for key in ["÷", "×", "−", "+"] { #expect(CalculatorKeyStyle.Role(key) == .operation) }
        for key in ["C", "(", ")", "%"] { #expect(CalculatorKeyStyle.Role(key) == .function) }
        for key in ["0", "7", "."] { #expect(CalculatorKeyStyle.Role(key) == .digit) }
    }

    // MARK: FX-04

    /// Day or night is derived per forecast hour from the sun at the place, not copied from the current reading.
    @Test func weatherDayAndNightAreDerivedPerHour() {
        func utc(_ month: Int, _ day: Int, _ hour: Int) -> Date {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        // Warsaw: midsummer late morning is day, midwinter evening is night.
        #expect(WeatherDaylight.isDay(at: utc(6, 21, 10), latitude: 52.23, longitude: 21.01))
        #expect(!WeatherDaylight.isDay(at: utc(12, 21, 20), latitude: 52.23, longitude: 21.01))
        // Equator, Greenwich: noon and midnight.
        #expect(WeatherDaylight.isDay(at: utc(3, 20, 12), latitude: 0, longitude: 0))
        #expect(!WeatherDaylight.isDay(at: utc(3, 20, 0), latitude: 0, longitude: 0))
        // Tromsø: polar night at midday, midnight sun at midnight.
        #expect(!WeatherDaylight.isDay(at: utc(12, 21, 11), latitude: 69.65, longitude: 18.96))
        #expect(WeatherDaylight.isDay(at: utc(6, 21, 23), latitude: 69.65, longitude: 18.96))
        // Solar noon elevation at the equinox on the equator is close to 90°.
        #expect(WeatherDaylight.solarElevation(at: utc(3, 20, 12), latitude: 0, longitude: 0) > 85)

        // A forecast read during the day still shows night for its night hours, and the reverse.
        let warsaw = WeatherLocation(id: "w", name: "Warsaw", administrativeArea: nil, country: nil, latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw")
        let dayHour = WeatherHour(timestamp: utc(6, 21, 10), temperature: 20, precipitationProbability: nil, weatherCode: 0)
        let nightHour = WeatherHour(timestamp: utc(6, 21, 23), temperature: 14, precipitationProbability: nil, weatherCode: 0)
        let readAtDay = WeatherForecast(temperature: 20, apparentTemperature: 20, relativeHumidity: 50, precipitation: 0, windSpeed: 5, weatherCode: 0,
                                        isDay: true, fetchedAt: utc(6, 21, 9), timeZoneIdentifier: "Europe/Warsaw", hourly: [dayHour, nightHour])
        #expect(WeatherDaylight.isDay(dayHour, forecast: readAtDay, location: warsaw))
        #expect(!WeatherDaylight.isDay(nightHour, forecast: readAtDay, location: warsaw))
        #expect(WeatherCode.symbol(nightHour.weatherCode, isDay: WeatherDaylight.isDay(nightHour, forecast: readAtDay, location: warsaw)) == "moon.stars.fill")
        var readAtNight = readAtDay; readAtNight.isDay = false
        #expect(WeatherDaylight.isDay(dayHour, forecast: readAtNight, location: warsaw))
        // Without a place the current reading is the only truth available.
        #expect(!WeatherDaylight.isDay(dayHour, forecast: readAtNight, location: nil))
    }

    /// Hours read "3 AM" on a 12-hour clock and "03:00" on a 24-hour clock, never a bare "03".
    @Test func weatherHourLabelsFollowTheLocaleClock() {
        func plain(_ text: String) -> String { text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let threeAM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 3))!
        let threePM = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 15))!
        let us = Locale(identifier: "en_US"), uk = Locale(identifier: "en_GB"), de = Locale(identifier: "de_DE")
        #expect(WeatherHourLabel.usesTwelveHourClock(us))
        #expect(!WeatherHourLabel.usesTwelveHourClock(uk) && !WeatherHourLabel.usesTwelveHourClock(de))
        #expect(plain(WeatherHourLabel.text(for: threeAM, timeZoneIdentifier: "UTC", locale: us)) == "3 AM")
        #expect(plain(WeatherHourLabel.text(for: threePM, timeZoneIdentifier: "UTC", locale: us)) == "3 PM")
        #expect(WeatherHourLabel.text(for: threeAM, timeZoneIdentifier: "UTC", locale: uk) == "03:00")
        #expect(WeatherHourLabel.text(for: threePM, timeZoneIdentifier: "UTC", locale: de) == "15:00")
        // The forecast's own time zone decides the hour.
        #expect(WeatherHourLabel.text(for: threeAM, timeZoneIdentifier: "Europe/Warsaw", locale: uk) == "05:00")
        for locale in [us, uk, de] {
            let label = WeatherHourLabel.text(for: threeAM, timeZoneIdentifier: "UTC", locale: locale)
            #expect(label != "03" && label != "3", "\(locale.identifier): \(label)")
        }
        #expect(WeatherCopy.timeZoneFooter(forecastTimeZone: "Europe/Warsaw", current: TimeZone(identifier: "Europe/Warsaw")!) == nil)
        #expect(WeatherCopy.timeZoneFooter(forecastTimeZone: "Asia/Tokyo", current: TimeZone(identifier: "Europe/Warsaw")!) != nil)
    }

    /// One alarm time format: the hero (next fire date) and the row (hour and minute) read the same, and
    /// the list under the hero leaves out the alarm the hero shows.
    @Test func alarmHeroAndRowsShareOneFormatterAndNeverRepeat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 20))!
        let morning = DockAlarm(title: "Morning", hour: 7, minute: 30, repeatWeekdays: [2, 3, 4, 5, 6], isEnabled: true)
        let gym = DockAlarm(title: "Gym", hour: 18, minute: 15, repeatWeekdays: [], isEnabled: false)
        let next = AlarmFacePresentation.next([morning, gym], now: now)
        #expect(next?.alarm.id == morning.id)
        if let next {
            #expect(AlarmFacePresentation.timeText(next.date) == AlarmFacePresentation.timeText(hour: morning.hour, minute: morning.minute))
        }
        for identifier in ["en_US", "en_GB", "de_DE", "ja_JP"] {
            let locale = Locale(identifier: identifier)
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 7, minute: 30))!
            #expect(AlarmFacePresentation.timeText(date, locale: locale) == AlarmFacePresentation.timeText(hour: 7, minute: 30, locale: locale), "\(identifier)")
        }
        // The wall-clock time survives any time zone: 7:30 is never shifted to another hour.
        let utcText = AlarmFacePresentation.timeText(hour: 7, minute: 30, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "UTC")!)
        let tokyoText = AlarmFacePresentation.timeText(hour: 7, minute: 30, locale: Locale(identifier: "en_GB"), timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(utcText == tokyoText && utcText.contains("7") && utcText.contains("30"), "\(utcText) \(tokyoText)")
        #expect(AlarmFacePresentation.listed([morning, gym], excluding: morning.id).map(\.id) == [gym.id])
        #expect(AlarmFacePresentation.listed([morning, gym], excluding: nil).map(\.id) == [morning.id, gym.id])
        #expect(!AlarmCopy.editorFooter.isEmpty && AlarmCopy.editorFooter.filter { $0 == "." }.count == 1)
    }

    /// The Trash hero says only the count and its unit; where the count comes from is said once, by the footer.
    @Test func trashHeroDoesNotRepeatTheCountScope() {
        #expect(TrashFacePresentation.heroValue(count: 12, errorMessage: nil) == "12")
        #expect(TrashFacePresentation.heroCaption(count: 12, errorMessage: nil) == "items")
        #expect(TrashFacePresentation.heroCaption(count: 1, errorMessage: nil) == "item")
        #expect(TrashFacePresentation.heroValue(count: 0, errorMessage: nil) == "Empty")
        #expect(TrashFacePresentation.heroCaption(count: 0, errorMessage: nil) == nil)
        #expect(TrashFacePresentation.heroValue(count: 3, errorMessage: "No access") == "Unavailable")
        #expect(TrashFacePresentation.heroCaption(count: 3, errorMessage: "No access") == nil)
        for count in [0, 1, 12] {
            let caption = TrashFacePresentation.heroCaption(count: count, errorMessage: nil) ?? ""
            #expect(!caption.localizedCaseInsensitiveContains("home Trash"), "\(caption)")
        }
        #expect(TrashCopy.countScope.contains("home Trash"))
    }

    /// Seek buttons show the actual interval when SF Symbols has it, and the plain arrow otherwise.
    @Test func nowPlayingSeekSymbolsMatchTheInterval() {
        let numbered: Set<String> = ["gobackward.15", "goforward.15", "gobackward.30", "goforward.30"]
        #expect(NowPlayingPresentation.seekSymbol(forward: false, seconds: 15, isAvailable: numbered.contains) == "gobackward.15")
        #expect(NowPlayingPresentation.seekSymbol(forward: true, seconds: 30, isAvailable: numbered.contains) == "goforward.30")
        #expect(NowPlayingPresentation.seekSymbol(forward: true, seconds: 25, isAvailable: numbered.contains) == "goforward")
        #expect(NowPlayingPresentation.seekSymbol(forward: false, seconds: 15, isAvailable: { _ in false }) == "gobackward")
        // On this system the 15-second variants exist.
        #expect(NowPlayingPresentation.seekSymbol(forward: false, seconds: 15) == "gobackward.15")
        #expect(NowPlayingPresentation.seekSymbol(forward: true, seconds: 15) == "goforward.15")
    }

    /// The disabled inline "Add" stays perceivable: secondary text rather than a faded accent, with an edge
    /// under Increase Contrast.
    @MainActor
    @Test func inlineAddButtonStaysPerceivableWhenDisabled() {
        #expect(WidgetRowTextButtonStyle.foreground(enabled: false) == Color.secondary)
        #expect(WidgetRowTextButtonStyle.foreground(enabled: true) == DockDesign.accent)
        #expect(WidgetRowTextButtonStyle.showsEdge(contrast: .increased))
        #expect(!WidgetRowTextButtonStyle.showsEdge(contrast: .standard))
    }

    /// Family settings fold away in the Dock popout but are the sheet's Content, always shown.
    @MainActor @Test func settingsDisclosureFoldsInThePopoutAndShowsEverythingInTheSheet() {
        func height(expanded: Bool, inSheet: Bool) -> CGFloat {
            let view = WidgetPopoutSettingsDisclosure(isExpanded: .constant(expanded)) {
                Color.gray.frame(height: 300)
            }
            .environment(\.widgetPopoutShowsHero, !inSheet)
            .frame(width: WidgetPopoutMetrics.contentWidth)
            return NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: WidgetPopoutMetrics.contentWidth, height: 10_000)).height
        }
        #expect(height(expanded: false, inSheet: false) < 100)
        #expect(height(expanded: true, inSheet: false) > 300)
        #expect(height(expanded: false, inSheet: true) >= 300)
        #expect(height(expanded: false, inSheet: true) < height(expanded: true, inSheet: false))
    }

    /// Footers in these families are one short sentence; the detail moves to tooltips.
    @Test func familyFootersAreOneShortSentence() {
        for footer in [QuickCalculatorCopy.footer, AlarmCopy.editorFooter] {
            #expect(footer.filter { $0 == "." }.count <= 1 && footer.count <= 60, "\(footer)")
        }
        #expect(!QuickCalculatorCopy.footerHelp.isEmpty && !AlarmCopy.editorFooterHelp.isEmpty)
    }

    @Test func ownedFamiliesAreRegisteredWithLayouts() {
        for kind in Self.families {
            #expect(WidgetRegistry.definition(named: kind) != nil, "\(kind)")
            #expect(!WidgetPresentationCatalog.options(for: kind).isEmpty, "\(kind)")
        }
    }

    /// Every owned family draws visible content for every advertised layout and on the 54 pt side Dock,
    /// on the plain surface (no background), so an empty face would render no pixels.
    @MainActor @Test func everyFamilyRendersANonEmptyFaceForEveryLayout() throws {
        var matrix = WidgetQAMatrix()
        for kind in Self.families {
            var cases = WidgetPresentationCatalog.options(for: kind).map { ($0.layout, CGFloat($0.width)) }
            cases.append((WidgetPresentationCatalog.options(for: kind).first?.layout == .icon ? .icon : .compact, 54))
            for (layout, width) in cases {
                let face = WidgetCardPreview(kind: kind, width: width, layout: layout)
                    .environment(\.dockWidgetSurface, .plain)
                    .environment(\.colorScheme, .light)
                let pixels = try Self.visiblePixels(face, size: CGSize(width: width, height: 54))
                #expect(pixels > 40, "\(kind) \(layout.rawValue) at \(width) pt drew \(pixels) pixels")
                matrix.record(kind, .layout(layout))
            }
        }
        let missing = matrix.missing(in: WidgetRegistry.all.filter { Self.families.contains($0.name) }).filter { !$0.hasSuffix(WidgetQAState.setup.description) }
        #expect(missing.isEmpty, "\(missing)")
    }

    /// Empty, setup and permission states also draw something truthful.
    @MainActor @Test func emptyAndPermissionFacesAreNotBlank() throws {
        let faces: [(String, AnyView, CGFloat, WidgetLayout)] = [
            ("calendar denied", AnyView(CalendarDockFace(date: .now, showsEvent: true, emptyTitle: "Unavailable", emptyDetail: "Allow access")), 154, .wide),
            ("reminders setup", AnyView(RemindersModuleFace(count: nil, context: "Choose a list")), 88, .compact),
            ("reminders overdue", AnyView(RemindersModuleFace(count: 3, overdue: 1, context: "Errands")), 88, .compact),
            ("alarm off", AnyView(AlarmDockFace(time: nil, title: nil)), 88, .compact),
            ("alarm narrow", AnyView(AlarmDockFace(time: "7:30 AM", title: "Morning")), 54, .compact),
            ("trash empty", AnyView(TrashDockFace(count: 0)), 54, .icon),
            ("trash unavailable", AnyView(TrashDockFace(count: 0, errorMessage: "No")), 88, .compact),
            ("airdrop targeted", AnyView(AirDropDockFace(targeted: true)), 88, .compact),
            ("collection empty", AnyView(SavedCollectionDockFace(item: .widget("Text Snippets"))), 96, .compact)
        ]
        for (name, view, width, layout) in faces {
            let face = WidgetContainer(width: width, kind: "Calendar") { view }
                .environment(\.dockWidgetContentWidth, width)
                .environment(\.widgetLayout, layout)
                .environment(\.dockWidgetSurface, .plain)
            #expect(try Self.visiblePixels(face, size: CGSize(width: width, height: 54)) > 40, "\(name)")
        }
    }

    @MainActor static func visiblePixels<V: View>(_ view: V, size: CGSize) throws -> Int {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: data.count, by: 4).filter { data[$0] > 24 }.count
    }
}
