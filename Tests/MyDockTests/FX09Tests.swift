import AppKit
import SwiftUI
import Testing
@testable import MyDock

/// FX-09: settings disclosure everywhere, the sheet's sample fallback, no repeated reading in Customize,
/// one refresh control, creation-appearance samples, crisp previews, Calendar rows and the low fixes.
@MainActor
struct FX09Tests {
    // MARK: Sheet sample fallback

    @Test func warmingFamiliesFallBackToTheirSampleUntilTheFirstReading() {
        for kind in ["System Activity", "Network Activity"] {
            #expect(WidgetSheetPreviewFallback.usesSample(kind: kind, hasReading: false), "\(kind)")
            #expect(!WidgetSheetPreviewFallback.usesSample(kind: kind, hasReading: true), "\(kind)")
        }
        for kind in ["Clock", "Weather", "Battery", "Stock", "Calendar"] {
            #expect(!WidgetSheetPreviewFallback.usesSample(kind: kind, hasReading: false), "\(kind)")
        }
        #expect(WidgetSheetPreviewFallback.caption("Trend", sample: true) == "Trend · Sample")
        #expect(WidgetSheetPreviewFallback.caption("Trend", sample: false) == "Trend")
    }

    // MARK: Creation appearance

    @Test func samplesDefaultToTheCreationAppearance() {
        for definition in WidgetRegistry.all {
            let creation = DockItem.widget(definition.name).widgetConfiguration?.iconAppearance
            #expect(WidgetCardPreview.creationAppearance(kind: definition.name) == creation, "\(definition.name)")
        }
        #expect(WidgetCardPreview.creationAppearance(kind: "Clock") == .mono)
        // The stored default and decoding are untouched: only new widgets start Mono.
        #expect(WidgetConfiguration().iconAppearance == .soft)
    }

    // MARK: Crisp previews

    @Test func scaledPreviewsFlattenTheirFaceAtTheFinalDensity() {
        #expect(WidgetPreviewRaster.scale(preview: 1, display: 2) == nil)
        #expect(WidgetPreviewRaster.scale(preview: 1.8, display: 2) == 3.6)
        #expect(WidgetPreviewRaster.scale(preview: 0.7, display: 2) == 1.4)
        #expect(WidgetPreviewRaster.scale(preview: .nan, display: 2) == nil)
        #expect(WidgetPreviewRaster.scale(preview: 2, display: 0) == 4)
        #expect(EnvironmentValues().widgetPreviewScale == 1)
    }

    // MARK: Calendar rows

    private func event(start: Date, end: Date, allDay: Bool = false, calendar: String = "Work") -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: UUID().uuidString, title: "Design review", startDate: start, endDate: end,
                              isAllDay: allDay, calendarID: "c", calendarTitle: calendar, meetingURL: nil)
    }

    private var noon: Date { Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date(timeIntervalSince1970: 1_790_000_000))! }

    @Test func calendarRowsMergeStatusTimeAndCalendar() {
        let now = noon
        let time = CalendarEventRowPresentation.time
        let ongoing = event(start: now.addingTimeInterval(-15 * 60), end: now.addingTimeInterval(30 * 60))
        #expect(CalendarEventRowPresentation.detail(ongoing, now: now) == "Now · ends \(time(ongoing.endDate)) · Work")

        let later = event(start: now.addingTimeInterval(45 * 60), end: now.addingTimeInterval(75 * 60))
        #expect(CalendarEventRowPresentation.detail(later, now: now) == "\(time(later.startDate)) · Work · in 45 min")

        let afternoon = event(start: now.addingTimeInterval(3 * 3600 + 15 * 60), end: now.addingTimeInterval(4 * 3600))
        #expect(CalendarEventRowPresentation.detail(afternoon, now: now) == "\(time(afternoon.startDate)) · Work · in 3 hr 15 min")

        let tomorrow = event(start: now.addingTimeInterval(26 * 3600), end: now.addingTimeInterval(27 * 3600))
        let weekday = tomorrow.startDate.formatted(Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated))
        #expect(CalendarEventRowPresentation.detail(tomorrow, now: now) == "\(weekday) \(time(tomorrow.startDate)) · Work")

        let start = Calendar.current.startOfDay(for: now)
        let allDay = event(start: start, end: start.addingTimeInterval(86_400), allDay: true)
        #expect(CalendarEventRowPresentation.detail(allDay, now: now) == "All day · Work")
        let allDayLater = event(start: start.addingTimeInterval(2 * 86_400), end: start.addingTimeInterval(3 * 86_400), allDay: true)
        let laterDay = allDayLater.startDate.formatted(Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated))
        #expect(CalendarEventRowPresentation.detail(allDayLater, now: now) == "\(laterDay) · All day · Work")

        // No full date anywhere, and no dangling separator without a calendar name.
        for row in [ongoing, later, tomorrow] {
            let text = CalendarEventRowPresentation.detail(row, now: now)
            #expect(!text.contains(row.startDate.formatted(date: .abbreviated, time: .omitted)), "\(text)")
        }
        #expect(CalendarEventRowPresentation.detail(event(start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200), calendar: " "), now: now)
                == "\(time(now.addingTimeInterval(600))) · in 10 min")
    }

    // MARK: Mono active toggle

    @Test func monoActiveToggleFillsWithPrimary() {
        #expect(WidgetIcon.fillIsPrimary(treatment: .mono, accent: .auto))
        #expect(WidgetIcon.activeFill(kind: "Trash", treatment: .mono, accent: .auto) == Color.primary)
        #expect(WidgetIcon.activeFill(kind: "Trash", treatment: .mono, accent: .profile(.pink)) == Color.primary)
        // Soft and Color keep the family (or chosen) accent; a mono accent is primary everywhere.
        #expect(WidgetIcon.activeFill(kind: "Trash", treatment: .soft, accent: .auto) == WidgetPalette.accent("Trash"))
        #expect(WidgetIcon.activeFill(kind: "Trash", treatment: .accent, accent: .auto) == WidgetPalette.accent("Trash"))
        #expect(WidgetIcon.activeFill(kind: "Trash", treatment: .soft, accent: .mono) == Color.primary)
    }

    // MARK: One refresh control

    @Test func refreshLabelSaysRetryOnlyWhenStaleOrFailed() {
        #expect(WidgetFreshnessPresentation.refreshLabel(.stale) == "Retry")
        for state in [WidgetFreshnessState.fresh, .updating, .empty] {
            #expect(WidgetFreshnessPresentation.refreshLabel(state) == "Refresh", "\(state)")
        }
        let now = Date()
        func state(updated: TimeInterval?, failed: Bool = false, refreshing: Bool = false) -> WidgetFreshnessState {
            WidgetFreshnessPresentation.state(isRefreshing: refreshing, updatedAt: updated.map { now.addingTimeInterval(-$0) },
                                              failed: failed, now: now, maximumAge: 600)
        }
        #expect(state(updated: 60) == .fresh)
        #expect(state(updated: 900) == .stale)
        #expect(state(updated: 60, failed: true) == .stale)
        #expect(state(updated: nil, failed: true) == .stale)
        #expect(state(updated: nil) == .empty)
        #expect(state(updated: 60, refreshing: true) == .updating)
        #expect(WidgetFreshnessPresentation.status(.stale, updatedAt: nil) == "Couldn’t update")
        #expect(WidgetFreshnessPresentation.status(.updating, updatedAt: nil) == "Updating…")
        #expect(WidgetFreshnessPresentation.status(.fresh, updatedAt: now, now: now) == "Updated just now")
        #expect(WidgetFreshnessPresentation.status(.fresh, updatedAt: now.addingTimeInterval(-300), now: now).hasPrefix("Updated "))
        #expect(WidgetFreshnessPresentation.status(.stale, updatedAt: now).hasPrefix("Saved data · "))
    }

    @Test func familyRefreshComparesItsReadingNotItsClosure() {
        let date = Date()
        let a = WidgetPopoutRefresh(updatedAt: date, isRefreshing: false, failed: false, action: {})
        let b = WidgetPopoutRefresh(updatedAt: date, isRefreshing: false, failed: false, action: { _ = 1 })
        #expect(a == b)
        #expect(a != WidgetPopoutRefresh(updatedAt: date, isRefreshing: true, failed: false, action: {}))
        #expect(a.state(at: date) == .fresh)
        #expect(WidgetPopoutRefreshKey.defaultValue == nil)
    }

    // MARK: Customize and the settings disclosure

    @Test func customizeHidesTheHeroAndKeepsTheDockContext() {
        #expect(WidgetPopoutHeroPolicy.showsHero(customizing: false))
        #expect(!WidgetPopoutHeroPolicy.showsHero(customizing: true))
        #expect(WidgetPopoutContext.resolve(explicit: .dock, showsHero: false) == .dock)
        #expect(WidgetPopoutContext.resolve(explicit: .sheet, showsHero: true) == .sheet)
        // Hosts that set no context keep the earlier rule.
        #expect(WidgetPopoutContext.resolve(explicit: nil, showsHero: false) == .sheet)
        #expect(WidgetPopoutContext.resolve(explicit: nil, showsHero: true) == .dock)
    }

    /// With Customize open the hero hides, but settings still fold away (they are not the sheet's Content).
    @Test func settingsStayFoldedInTheDockWhileTheHeroIsHidden() {
        func height(context: WidgetPopoutContext?, showsHero: Bool) -> CGFloat {
            let view = WidgetPopoutSettingsDisclosure(isExpanded: .constant(false)) { Color.gray.frame(height: 300) }
                .environment(\.widgetPopoutShowsHero, showsHero)
                .environment(\.widgetPopoutContext, context)
                .frame(width: WidgetPopoutMetrics.contentWidth)
            return NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: WidgetPopoutMetrics.contentWidth, height: 10_000)).height
        }
        #expect(height(context: .dock, showsHero: false) < 100)
        #expect(height(context: .sheet, showsHero: false) >= 300)
        #expect(height(context: .sheet, showsHero: true) >= 300)
    }

    // MARK: Low items

    @Test func countdownFooterIsOneSentence() {
        for mode in CountdownMode.allCases {
            for footer in [CountdownCopy.footer(mode: mode, message: nil), CountdownCopy.scheduled(mode: mode)] {
                #expect(footer.filter { $0 == "." }.count == 1 && footer.count <= 60 && !footer.contains("\n"), "\(footer)")
            }
            #expect(CountdownCopy.footer(mode: mode, message: "Alerts are off.") == "Alerts are off.")
            #expect(CountdownCopy.footer(mode: mode, message: "") == CountdownCopy.note(mode: mode))
            #expect(!CountdownCopy.help(mode: mode).isEmpty)
        }
    }

    @Test func unitConverterCaptionDoesNotRepeatTheHero() {
        let caption = UnitConverterPresentation.caption(input: " 1 ", from: "m", hasResult: true)
        #expect(caption == "from 1 m")
        #expect(!caption.contains("ft") && !caption.contains("="))
        #expect(UnitConverterPresentation.caption(input: "x", from: "m", hasResult: false) == "Enter a finite number to convert.")
    }

    @Test func weatherShowsTheForecastLengthOnlyForTheHourlyForecast() {
        #expect(WeatherCopy.showsForecastLength(.hourlyForecast))
        #expect(!WeatherCopy.showsForecastLength(.current))
        #expect(!WeatherCopy.showsForecastLength(.conditions))
    }

    @Test func hydrationSettingsSummarySaysTheCadence() {
        #expect(HydrationSettingsSummary.text(remindersOn: true, interval: 60) == "Every 60 min")
        #expect(HydrationSettingsSummary.text(remindersOn: true, interval: 5) == "Every 30 min")
        #expect(HydrationSettingsSummary.text(remindersOn: false, interval: 60) == "Reminders off")
    }
}
