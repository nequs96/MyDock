import AppKit
import EventKit
import SwiftUI

struct CalendarWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CalendarCompactWidgetView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CalendarPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

// MARK: - Pure presentation

enum CalendarFacePresentation {
    /// Which parts of the module show for the family's own layout choice and the Dock layout.
    static func parts(calendarLayout: CalendarWidgetLayout, dockLayout: WidgetLayout) -> (date: Bool, event: Bool) {
        (calendarLayout != .nextEvent || dockLayout != .wide, calendarLayout != .date && dockLayout == .wide)
    }

    /// The one secondary line under an event title, short enough for a 154 pt module.
    static func compactStatus(_ event: CalendarEventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        if event.endDate <= now { return "Ended" }
        if event.isAllDay { return "All day" }
        // An end on another day carries its day, so a multi-day event never seems to end today.
        if event.startDate <= now { return "Now · ends " + NextMeeting.dayAndTime(event.endDate, now: now, calendar: calendar) }
        let minutes = Int(ceil(event.startDate.timeIntervalSince(now) / 60))
        if minutes < 60 { return "In \(max(1, minutes)) min" }
        return NextMeeting.dayAndTime(event.startDate, now: now, calendar: calendar)
    }

    /// The module's text when there is no event to show. Truthful: unavailable access is never shown as "no events",
    /// access that was never asked for is not "Unavailable", and only missing access asks for access.
    static func emptyState(errorMessage: String?, accessAvailable: Bool,
                           failure: EventKitReadFailure = .accessDenied) -> (title: String, detail: String) {
        if errorMessage != nil {
            switch failure {
            case .accessDenied: return ("Unavailable", "Allow access")
            case .selectionUnavailable: return ("Unavailable", "Choose calendars")
            case .other: return ("Unavailable", "Try again")
            }
        }
        // No error and no access: Calendar access has not been requested yet.
        return accessAvailable ? ("No events", "Next 7 days") : ("Calendar", "Allow access")
    }
}

/// What the Calendar popout reads; a change restarts its read once.
struct CalendarReadScope: Equatable {
    var calendarIDs: [String]
    var includeAllDay: Bool
    var layout: CalendarWidgetLayout

    init(_ configuration: WidgetConfiguration) {
        calendarIDs = configuration.selectedCalendarIDs
        includeAllDay = configuration.calendarShowsAllDayEvents
        layout = configuration.calendarLayout
    }
}

enum CalendarEventListPresentation {
    /// The popout's rows: the hero's event first (it carries Join or Open under the hero), then the rest in order.
    static func rows(events: [CalendarEventSnapshot], hero: CalendarEventSnapshot?) -> [CalendarEventSnapshot] {
        guard let hero, events.contains(where: { $0.id == hero.id }) else { return events }
        return [hero] + events.filter { $0.id != hero.id }
    }
}

/// Why an EventKit read failed, so a widget offers the right way out: Privacy & Security only for denied access,
/// and All calendars or All lists when the chosen calendar or list was deleted.
enum EventKitReadFailure: Equatable, Sendable {
    case accessDenied
    case selectionUnavailable
    case other

    init(_ error: Error) {
        switch error as? CalendarRemindersServiceError {
        case .accessDenied?: self = .accessDenied
        case .calendarUnavailable?, .listUnavailable?: self = .selectionUnavailable
        default: self = .other
        }
    }
}

/// One Calendar row's secondary line: status and time merged, then the calendar.
/// Today: "Now · ends 19:30 · Work" or "18:57 · Work · in 45 min". Other days: "Tue 09:00 · Work".
/// All-day: "All day · Work" today, "Tue · All day · Work" otherwise. Never a full date.
enum CalendarEventRowPresentation {
    static func detail(_ event: CalendarEventSnapshot, now: Date, calendar: Calendar = .current) -> String {
        let source = event.calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        func joined(_ parts: [String]) -> String { (parts + (source.isEmpty ? [] : [source])).joined(separator: " · ") }
        let today = calendar.isDate(event.startDate, inSameDayAs: now)
        let weekday = event.startDate.formatted(NextMeeting.weekdayStyle(calendar))
        if event.isAllDay {
            let ongoing = event.startDate <= now && event.endDate > now
            return joined(today || ongoing ? ["All day"] : [weekday, "All day"])
        }
        let start = NextMeeting.time(event.startDate, calendar: calendar)
        if event.endDate <= now { return joined(["Ended"]) }
        if event.startDate <= now { return joined(["Now", "ends " + NextMeeting.dayAndTime(event.endDate, now: now, calendar: calendar)]) }
        if today {
            return [start, source.isEmpty ? nil : source, "in " + relative(event.startDate.timeIntervalSince(now))]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return joined([weekday + " " + start])
    }

    static func time(_ date: Date) -> String { NextMeeting.time(date) }

    /// "45 min", "2 hr", "2 hr 15 min".
    static func relative(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "a while" }
        let minutes = Int(max(1, ceil(seconds / 60)))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) hr" + (minutes % 60 == 0 ? "" : " \(minutes % 60) min")
    }
}

/// The thin leading bar on a Calendar event, as in Apple's Calendar widget: the event calendar's colour.
/// Mono (the Mono accent or the Mono icon treatment, the rule `WidgetIcon.fillIsPrimary` applies) stays monochrome: a neutral bar.
enum CalendarEventBarStyle: Equatable {
    case neutral(emphasized: Bool)
    case calendar(CalendarColorSnapshot)

    static func isMonochrome(accent: WidgetAccent, appearance: WidgetIconAppearance) -> Bool {
        if case .mono = accent { return true }
        return appearance == .mono
    }

    static func resolve(color: CalendarColorSnapshot?, monochrome: Bool, emphasized: Bool = false) -> CalendarEventBarStyle {
        if !monochrome, let color { return .calendar(color) }
        return .neutral(emphasized: emphasized)
    }

    /// Wider under Increase Contrast so the colour stays legible on any material.
    static func width(increasedContrast: Bool) -> CGFloat { increasedContrast ? 4 : 3 }
}

extension CalendarColorSnapshot {
    var swiftUIColor: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

struct CalendarColorBar: View {
    var style: CalendarEventBarStyle
    var height: CGFloat = 30
    @DockAccessibilityStyle() private var accessibility
    private var increased: Bool { accessibility.contrast == .increased }
    var body: some View {
        Capsule().fill(fill)
            .overlay { if increased, case .calendar = style { Capsule().strokeBorder(Color.primary.opacity(0.45), lineWidth: 0.5) } }
            .frame(width: CalendarEventBarStyle.width(increasedContrast: increased), height: height)
            .accessibilityHidden(true)
    }
    private var fill: Color {
        switch style {
        case .calendar(let color): color.swiftUIColor
        case .neutral(let emphasized): Color.primary.opacity(emphasized ? (increased ? 0.7 : 0.55) : (increased ? 0.35 : 0.18))
        }
    }
}

// MARK: - Calendar face

/// The Calendar module: weekday over the day number, and on wide layouts the next event beside it.
struct CalendarDockFace: View {
    var date: Date
    var showsDate = true
    var showsEvent = false
    var event: CalendarEventSnapshot?
    /// The quiet all-day line, shown only when there is no timed event to show.
    var allDayLine: String? = nil
    var emptyTitle = "No events"
    var emptyDetail = "Next 7 days"
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetShowsLabel) private var showsLabel
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetIconAppearance) private var appearance
    private var narrow: Bool { WidgetModuleMetrics.isNarrow(width) }
    private var eventVisible: Bool { showsEvent && !narrow }
    var body: some View {
        HStack(spacing: 10) {
            if showsDate || !eventVisible { dateBlock }
            if eventVisible { eventBlock }
        }
        .frame(maxWidth: .infinity)
        .moduleInsets()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar")
        .accessibilityValue(accessibilityValue)
    }
    private var dateBlock: some View {
        VStack(spacing: 0) {
            if showsLabel {
                Text(date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(DockDesign.Module.label).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(date.formatted(.dateTime.day()))
                .font(narrow ? DockDesign.Module.valueMedium : DockDesign.Module.valueLarge).lineLimit(1)
        }
        .fixedSize()
        .frame(maxWidth: eventVisible ? nil : .infinity)
    }
    /// The calendar colour bar; a neutral bar adds nothing to the module, so Mono and unknown colours omit it.
    private var barStyle: CalendarEventBarStyle {
        CalendarEventBarStyle.resolve(color: event?.calendarColor,
                                      monochrome: CalendarEventBarStyle.isMonochrome(accent: accent, appearance: appearance))
    }
    private var eventBlock: some View {
        HStack(spacing: 6) {
            if case .calendar = barStyle { CalendarColorBar(style: barStyle, height: 28) }
            VStack(alignment: .leading, spacing: 1) {
                Text(event?.title ?? quietTitle ?? emptyTitle).font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(event == nil ? .secondary : .primary).lineLimit(1)
                Text(event.map { CalendarFacePresentation.compactStatus($0, now: date) } ?? (quietTitle == nil ? emptyDetail : "All day"))
                    .font(DockDesign.Module.label).foregroundStyle(.secondary).lineLimit(1)
                    .minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var quietTitle: String? { event == nil ? allDayLine : nil }
    private var accessibilityValue: String {
        let day = date.formatted(date: .complete, time: .omitted)
        guard eventVisible else { return day }
        if let quietTitle { return day + ", All day, " + quietTitle }
        return day + ", " + (event.map { "\($0.title), " + CalendarFacePresentation.compactStatus($0, now: date) } ?? emptyTitle)
    }
}

private struct CalendarCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @Environment(\.widgetLayout) private var dockLayout
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var events: [CalendarEventSnapshot] = []
    @State private var accessAvailable = false
    @State private var errorMessage: String?
    @State private var failure = EventKitReadFailure.accessDenied
    @State private var refreshRequestID = UUID()

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let parts = CalendarFacePresentation.parts(calendarLayout: configuration.calendarLayout, dockLayout: dockLayout)
            let empty = CalendarFacePresentation.emptyState(errorMessage: errorMessage, accessAvailable: accessAvailable,
                                                            failure: failure)
            CalendarDockFace(date: context.date, showsDate: parts.date, showsEvent: parts.event,
                             event: CalendarEventOrdering.compactEvent(from: events, now: context.date),
                             allDayLine: NextMeeting.allDayLine(NextMeeting.allDayToday(from: events, now: context.date)),
                             emptyTitle: empty.title, emptyDetail: empty.detail)
                .frame(width: contentWidth, height: 54)
        }
        // One structured refresh per change of what is read (not per appearance change) and per coalesced EventKit,
        // activation or wake signal.
        .eventKitRefresh(scope: CalendarReadScope(configuration)) { await refreshIfAuthorized() }
        .help(errorMessage ?? "Calendar")
    }

    private func refreshIfAuthorized() async {
        let selectedIDs = configuration.selectedCalendarIDs
        let includeAllDay = configuration.calendarShowsAllDayEvents
        let layout = configuration.calendarLayout
        let requestID = UUID()
        refreshRequestID = requestID
        guard layout != .date else {
            events = []
            accessAvailable = false
            errorMessage = nil
            return
        }
        #if DEBUG
        if CalendarQAFixture.simulatesDeniedAccess {
            events = []
            accessAvailable = false
            errorMessage = CalendarRemindersServiceError.accessDenied.localizedDescription
            failure = .accessDenied
            return
        }
        if let fixture = CalendarQAFixture.current {
            // The production selection applies, so QA never shows what the chosen calendars or all-day setting hide.
            events = CalendarEventOrdering.select(fixture.events(), calendarIDs: selectedIDs, includeAllDay: includeAllDay)
            accessAvailable = true
            errorMessage = nil
            return
        }
        #endif
        guard await CalendarRemindersService.shared.hasCalendarAccess() else {
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            events = []
            accessAvailable = false
            // Not asked yet is not a failure: the module asks to allow access instead of reading "Unavailable".
            errorMessage = EKEventStore.authorizationStatus(for: .event) == .notDetermined ? nil : "Calendar access is unavailable."
            failure = .accessDenied
            return
        }
        do {
            let result = try await CalendarRemindersService.shared.events(calendarIDs: selectedIDs,
                                                                         includeAllDay: includeAllDay)
            let stillAuthorized = await CalendarRemindersService.shared.hasCalendarAccess()
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            guard stillAuthorized else {
                events = []
                accessAvailable = false
                errorMessage = "Calendar access is unavailable."
                failure = .accessDenied
                return
            }
            events = result
            accessAvailable = true
            errorMessage = nil
        } catch {
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            events = []
            accessAvailable = false
            errorMessage = error.localizedDescription
            failure = EventKitReadFailure(error)
        }
    }

    private func currentConfiguration() -> WidgetConfiguration? {
        WidgetConfigurationLookup.current(store: store, itemID: item.id, profileID: profileID)
    }

    private func requestIsCurrent(_ requestID: UUID, selectedIDs: [String],
                                  includeAllDay: Bool, layout: CalendarWidgetLayout) -> Bool {
        guard refreshRequestID == requestID, !Task.isCancelled,
              let current = currentConfiguration() else { return false }
        return current.selectedCalendarIDs == selectedIDs
            && current.calendarShowsAllDayEvents == includeAllDay
            && current.calendarLayout == layout
    }
}

// MARK: - Calendar popout

private struct CalendarPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var calendars: [CalendarListSnapshot] = []
    @State private var events: [CalendarEventSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var failure = EventKitReadFailure.accessDenied
    @State private var refreshRequestID = UUID()
    @State private var showsCalendarList = false
    /// Why the last settings change was not kept, for example while saving is disabled.
    @State private var settingsError: String?
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    /// What the popout shows and which calendars it reads sit behind a final, collapsed disclosure.
    @State private var settingsExpanded = false
    @State private var loadedAt: Date?

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    /// Only the first read replaces the reading with a loading row; later refreshes keep it and the header shows progress.
    private var isFirstLoad: Bool { isLoading && loadedAt == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // With a next event the hero reads "in 12 min" or "now"; otherwise it stays the date.
                if configuration.calendarLayout != .date, errorMessage == nil, !isFirstLoad,
                   let next = NextMeeting.next(from: events, now: context.date) {
                    WidgetPopoutHero(value: NextMeeting.heroValue(next, now: context.date), caption: next.title)
                } else {
                    WidgetPopoutHero(value: context.date.formatted(.dateTime.weekday(.wide).day()),
                                     caption: context.date.formatted(.dateTime.month(.wide).year()))
                }
            }
            if configuration.calendarLayout != .date { eventsSection }
            WidgetPopoutSettingsDisclosure(summary: configuration.calendarLayout.title, isExpanded: $settingsExpanded) {
                settingsSection
                if let settingsError { WidgetPopoutCaption(settingsError, color: WidgetPalette.warning) }
            }
        }
        // The shell's header shows when the events were read and the one refresh control.
        .widgetPopoutRefresh(configuration.calendarLayout == .date ? nil
            : WidgetPopoutRefresh(updatedAt: loadedAt, isRefreshing: isLoading, failed: errorMessage != nil, action: reload))
        // Structured: restarts once per change of what is read (from here or the settings sheet) and once per
        // coalesced EventKit, activation or wake signal, and ends with the popout.
        .eventKitRefresh(scope: CalendarReadScope(configuration)) { await requestAndLoad() }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetPopoutSectionHeader(configuration.calendarLayout == .nextEvent ? "Next Event" : "Upcoming")
            if isFirstLoad {
                GroupedSection {
                    WidgetPopoutRow {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading calendar…").font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let errorMessage {
                GroupedSection {
                    switch failure {
                    case .selectionUnavailable:
                        GroupedRow("Selected calendar unavailable", subtitle: "Choose another calendar or show all calendars.",
                                   symbol: "calendar.badge.exclamationmark", color: WidgetPalette.warning)
                        GroupedRow("Show All Calendars", role: .button) { updateCalendars([]) }
                    case .accessDenied:
                        GroupedRow(errorMessage, subtitle: "You can change Calendar access in System Settings.",
                                   symbol: "calendar.badge.exclamationmark", color: WidgetPalette.warning)
                        GroupedRow("Open Privacy & Security", role: .button) { WidgetPrivacySettings.open(WidgetPrivacySettings.calendars) }
                    case .other:
                        GroupedRow(errorMessage, symbol: "calendar.badge.exclamationmark", color: WidgetPalette.warning)
                    }
                }
            } else if events.isEmpty {
                GroupedSection {
                    GroupedRow("No upcoming events", subtitle: "Nothing in the next seven days for these calendars.", symbol: "calendar", color: .gray)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    // The hero names the next event, so its row leads with only its time, Join and location.
                    let hero = showsHero ? NextMeeting.next(from: events, now: context.date) : nil
                    let visibleEvents = CalendarEventListPresentation.rows(
                        events: configuration.calendarLayout == .nextEvent
                            ? CalendarEventOrdering.compactEvent(from: events, now: context.date).map { [$0] } ?? []
                            : events.filter { $0.endDate > context.date }.sorted { CalendarEventOrdering.precedes($0, $1, now: context.date) },
                        hero: hero)
                    // All-day events never count as "next"; in the next-event layout they get one quiet line.
                    let allDayLine = configuration.calendarLayout == .nextEvent
                        ? NextMeeting.allDayLine(NextMeeting.allDayToday(from: events, now: context.date)) : nil
                    VStack(alignment: .leading, spacing: 6) {
                        if visibleEvents.isEmpty {
                            if allDayLine == nil {
                                GroupedSection {
                                    GroupedRow("No upcoming events in this reading", subtitle: "They refresh every few minutes.")
                                }
                            }
                        } else if visibleEvents.count > 5 {
                            DockScrollView { eventList(visibleEvents, heroID: hero?.id, now: context.date) }.frame(height: 300)
                        } else {
                            eventList(visibleEvents, heroID: hero?.id, now: context.date)
                        }
                        if let allDayLine { WidgetPopoutCaption("All day · " + allDayLine) }
                    }
                }
            }
        }
    }

    private func eventList(_ visibleEvents: [CalendarEventSnapshot], heroID: String?, now: Date) -> some View {
        GroupedSection(separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            ForEach(visibleEvents) { event in eventRow(event, showsTitle: event.id != heroID, now: now) }
        }
    }

    private var barIsMonochrome: Bool {
        CalendarEventBarStyle.isMonochrome(accent: configuration.widgetAccent ?? .auto, appearance: configuration.iconAppearance)
    }

    /// One event: a calendar bar, the title, and one line that merges status, time and calendar.
    /// The hero's event omits the title the hero already shows.
    private func eventRow(_ event: CalendarEventSnapshot, showsTitle: Bool, now: Date) -> some View {
        let ongoing = !event.isAllDay && event.startDate <= now && event.endDate > now
        let detail = CalendarEventRowPresentation.detail(event, now: now)
        return WidgetPopoutRow {
            HStack(spacing: 10) {
                // The calendar's colour; Mono stays neutral, and the neutral bar marks the ongoing event.
                CalendarColorBar(style: CalendarEventBarStyle.resolve(color: event.calendarColor, monochrome: barIsMonochrome, emphasized: ongoing))
                VStack(alignment: .leading, spacing: 1) {
                    if showsTitle {
                        Text(event.title).font(DockDesign.Grouped.titleFont.weight(.medium)).lineLimit(2)
                    }
                    Text(detail)
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityLabel(showsTitle ? detail : event.title + ", " + detail)
                    if let location = NextMeeting.locationText(event) {
                        Text(location).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                // Join only for an event that carries a recognised meeting link; otherwise the event opens in Calendar.
                switch CalendarEventAction.action(for: event) {
                case .join(let url):
                    Button("Join") { openMeeting(url) }.buttonStyle(WidgetRowTextButtonStyle())
                        .accessibilityLabel("Join \(event.title)")
                case .openInCalendar:
                    WidgetRowIconButton(symbol: "calendar", label: "Open \(event.title) in Calendar") { openCalendarApp() }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func openMeeting(_ url: URL) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        NSWorkspace.shared.open(url)
    }

    private func openCalendarApp() {
        guard AppRuntimeEnvironment.allowsNativeEffects,
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private var settingsSection: some View {
        GroupedSection("Calendar", footer: configuration.calendarLayout == .date ? nil : "Next seven days from " + selectedCalendarLabel + ".",
                       separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            GroupedRow("Show") {
                Picker("Show", selection: Binding(get: { configuration.calendarLayout },
                                                  set: { value in updateConfiguration { $0.calendarLayout = value } })) {
                    ForEach(CalendarWidgetLayout.allCases) { layout in Text(layout.title).tag(layout) }
                }
                .labelsHidden().fixedSize().accessibilityLabel("Layout")
            }
            if configuration.calendarLayout != .date {
                Button { showsCalendarList.toggle() } label: {
                    WidgetPopoutRow {
                        HStack(spacing: 6) {
                            Text("Calendars").font(DockDesign.Grouped.titleFont)
                            Spacer(minLength: 8)
                            Text(selectedCalendarSummary).font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                .rotationEffect(.degrees(showsCalendarList ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Calendars")
                .accessibilityValue(selectedCalendarSummary + (showsCalendarList ? ", expanded" : ", collapsed"))
                if showsCalendarList {
                    calendarChoice("All calendars", selected: configuration.selectedCalendarIDs.isEmpty) { updateCalendars([]) }
                    ForEach(calendars) { calendar in
                        calendarChoice(calendar.title, selected: configuration.selectedCalendarIDs.contains(calendar.id)) { toggleCalendar(calendar.id) }
                    }
                }
                GroupedRow("All-day events", isOn: Binding(get: { configuration.calendarShowsAllDayEvents },
                                                           set: { value in updateConfiguration { $0.calendarShowsAllDayEvents = value } }))
            }
        }
    }

    private func calendarChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            WidgetPopoutRow {
                HStack {
                    Text(title).font(DockDesign.Grouped.titleFont).padding(.leading, 12)
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundStyle(DockDesign.accent)
                        .opacity(selected ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var selectedCalendarSummary: String {
        configuration.selectedCalendarIDs.isEmpty ? "All" : "\(configuration.selectedCalendarIDs.count) selected"
    }

    private var selectedCalendarLabel: String {
        let selected = calendars.filter { configuration.selectedCalendarIDs.contains($0.id) }
        guard !configuration.selectedCalendarIDs.isEmpty else { return "All accessible calendars" }
        let missing = configuration.selectedCalendarIDs.count - selected.count
        let names = selected.map(\.title).joined(separator: ", ")
        if missing > 0 { return (names.isEmpty ? "Selected calendars" : names) + " · \(missing) unavailable" }
        return names
    }

    // Each change restarts the read through the task's scope key; nothing here loads on its own.
    private func toggleCalendar(_ id: String) {
        updateConfiguration { value in
            if value.selectedCalendarIDs.contains(id) { value.selectedCalendarIDs.removeAll { $0 == id } }
            else { value.selectedCalendarIDs.append(id) }
        }
    }

    private func updateCalendars(_ ids: [String]) {
        updateConfiguration { $0.selectedCalendarIDs = ids }
    }

    /// A rejected change leaves the setting as it was, and says why.
    private func updateConfiguration(_ update: (inout WidgetConfiguration) -> Void) {
        settingsError = WidgetConfigurationLookup.rejection(store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: update))
    }

    private func reload() { Task { await requestAndLoad() } }

    private func requestAndLoad() async {
        let selectedIDs = configuration.selectedCalendarIDs
        let includeAllDay = configuration.calendarShowsAllDayEvents
        let layout = configuration.calendarLayout
        let requestID = UUID()
        refreshRequestID = requestID
        guard layout != .date else {
            isLoading = false
            calendars = []
            events = []
            errorMessage = nil
            loadedAt = nil
            return
        }
        #if DEBUG
        if CalendarQAFixture.simulatesDeniedAccess {
            calendars = []
            events = []
            errorMessage = CalendarRemindersServiceError.accessDenied.localizedDescription
            failure = .accessDenied
            isLoading = false
            loadedAt = nil
            return
        }
        if let fixture = CalendarQAFixture.current {
            calendars = fixture.calendars
            events = CalendarEventOrdering.select(fixture.events(), calendarIDs: selectedIDs, includeAllDay: includeAllDay)
            errorMessage = nil
            isLoading = false
            loadedAt = .now
            return
        }
        #endif
        isLoading = true
        defer { if refreshRequestID == requestID { isLoading = false } }
        // The calendar choices are read first and kept when only the selection is gone, so another can be chosen here.
        var fetchedCalendars: [CalendarListSnapshot]?
        do {
            try await CalendarRemindersService.shared.requestCalendarAccess()
            fetchedCalendars = try await CalendarRemindersService.shared.calendarLists()
            let fetchedEvents = try await CalendarRemindersService.shared.events(calendarIDs: selectedIDs,
                                                                                includeAllDay: includeAllDay)
            let stillAuthorized = await CalendarRemindersService.shared.hasCalendarAccess()
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            guard stillAuthorized else { throw CalendarRemindersServiceError.accessDenied }
            calendars = fetchedCalendars ?? []
            events = fetchedEvents
            errorMessage = nil
            loadedAt = .now
        } catch {
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            let readFailure = EventKitReadFailure(error)
            errorMessage = error.localizedDescription
            failure = readFailure
            calendars = readFailure == .selectionUnavailable ? (fetchedCalendars ?? calendars) : []
            events = []
            loadedAt = nil
        }
    }

    private func requestIsCurrent(_ requestID: UUID, selectedIDs: [String],
                                  includeAllDay: Bool, layout: CalendarWidgetLayout) -> Bool {
        guard refreshRequestID == requestID, !Task.isCancelled,
              let current = currentConfiguration() else { return false }
        return current.selectedCalendarIDs == selectedIDs
            && current.calendarShowsAllDayEvents == includeAllDay
            && current.calendarLayout == layout
    }

    private func currentConfiguration() -> WidgetConfiguration? {
        WidgetConfigurationLookup.current(store: store, itemID: item.id, profileID: profileID)
    }
}
