import AppKit
import Combine
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

struct RemindersWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersCompactWidgetView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersPopoutWidgetView(store: store, item: item, profileID: profileID))
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
        if event.startDate <= now { return "Now · until " + event.endDate.formatted(date: .omitted, time: .shortened) }
        let minutes = Int(ceil(event.startDate.timeIntervalSince(now) / 60))
        if minutes < 60 { return "In \(max(1, minutes)) min" }
        return NextMeeting.dayAndTime(event.startDate, now: now, calendar: calendar)
    }

    /// The module's text when there is no event to show. Truthful: unavailable access is never shown as "no events",
    /// and only denied access asks for access.
    static func emptyState(errorMessage: String?, accessAvailable: Bool,
                           failure: EventKitReadFailure = .accessDenied) -> (title: String, detail: String) {
        if errorMessage != nil {
            switch failure {
            case .accessDenied: return ("Unavailable", "Allow access")
            case .selectionUnavailable: return ("Unavailable", "Choose calendars")
            case .other: return ("Unavailable", "Try again")
            }
        }
        return accessAvailable ? ("No events", "Next 7 days") : ("Calendar", "Choose calendars")
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
        let weekday = event.startDate.formatted(Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated))
        if event.isAllDay {
            let ongoing = event.startDate <= now && event.endDate > now
            return joined(today || ongoing ? ["All day"] : [weekday, "All day"])
        }
        let start = time(event.startDate)
        if event.endDate <= now { return joined(["Ended"]) }
        if event.startDate <= now { return joined(["Now", "ends " + time(event.endDate)]) }
        if today {
            return [start, source.isEmpty ? nil : source, "in " + relative(event.startDate.timeIntervalSince(now))]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return joined([weekday + " " + start])
    }

    static func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }

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

enum RemindersFacePresentation {
    static func overdueCount(_ reminders: [ReminderSnapshot], now: Date, calendar: Calendar = .current) -> Int {
        reminders.filter { isOverdue($0, now: now, calendar: calendar) }.count
    }

    /// A date-only reminder is due for the whole day, as in Reminders, so it is overdue only once that day ends.
    static func isOverdue(_ reminder: ReminderSnapshot, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due = reminder.dueDate else { return false }
        guard !reminder.dueHasTime,
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: due)) else { return due < now }
        return now >= endOfDay
    }

    /// "Today", "Tomorrow", "Yesterday" or a short date (with the year only outside this year), plus the time only
    /// when the reminder has one.
    static func dueText(_ reminder: ReminderSnapshot, now: Date, calendar: Calendar = .current) -> String? {
        guard let due = reminder.dueDate else { return nil }
        let day: String
        if calendar.isDate(due, inSameDayAs: now) {
            day = "Today"
        } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            day = "Tomorrow"
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(due, inSameDayAs: yesterday) {
            day = "Yesterday"
        } else if calendar.isDate(due, equalTo: now, toGranularity: .year) {
            day = due.formatted(.dateTime.day().month(.abbreviated))
        } else {
            day = due.formatted(date: .abbreviated, time: .omitted)
        }
        return reminder.dueHasTime ? day + ", " + due.formatted(date: .omitted, time: .shortened) : day
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
    @ObservedObject private var eventKitChanges = EventKitChangeMonitor.shared
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
        // One structured refresh per configuration change and per coalesced EventKit, activation or wake signal.
        .task(id: EventKitRefreshKey(value: configuration, generation: eventKitChanges.generation)) {
            await refreshIfAuthorized()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfAuthorized()
            }
        }
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
            events = fixture.events()
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
            errorMessage = "Calendar access is unavailable."
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
        guard let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id }) else { return nil }
        return currentItem.widgetConfiguration ?? WidgetConfiguration()
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
    @ObservedObject private var eventKitChanges = EventKitChangeMonitor.shared
    @State private var calendars: [CalendarListSnapshot] = []
    @State private var events: [CalendarEventSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var failure = EventKitReadFailure.accessDenied
    @State private var refreshRequestID = UUID()
    @State private var layoutSelection = CalendarWidgetLayout.dateAndNextEvent
    @State private var showAllDaySelection = false
    @State private var showsCalendarList = false
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
            }
        }
        // The shell's header shows when the events were read and the one refresh control.
        .widgetPopoutRefresh(configuration.calendarLayout == .date ? nil
            : WidgetPopoutRefresh(updatedAt: loadedAt, isRefreshing: isLoading, failed: errorMessage != nil, action: reload))
        .onAppear { layoutSelection = configuration.calendarLayout }
        .onChange(of: layoutSelection) { updateLayout($0) }
        .onChange(of: item.widgetConfiguration?.calendarLayout) { layoutSelection = $0 ?? .dateAndNextEvent }
        .onAppear { showAllDaySelection = configuration.calendarShowsAllDayEvents }
        .onChange(of: showAllDaySelection) { value in
            updateConfiguration { $0.calendarShowsAllDayEvents = value }
            reload()
        }
        .onChange(of: item.widgetConfiguration?.calendarShowsAllDayEvents) { showAllDaySelection = $0 ?? false }
        // Structured: restarts once per coalesced EventKit, activation or wake signal and ends with the popout.
        .task(id: eventKitChanges.generation) {
            await requestAndLoad()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await requestAndLoad()
            }
        }
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
                                   symbol: "calendar.badge.exclamationmark", color: .orange)
                        GroupedRow("Show All Calendars", role: .button) { updateCalendars([]) }
                    case .accessDenied:
                        GroupedRow(errorMessage, subtitle: "You can change Calendar access in System Settings.",
                                   symbol: "calendar.badge.exclamationmark", color: .orange)
                        GroupedRow("Open Privacy & Security", role: .button) { WidgetPrivacySettings.open(WidgetPrivacySettings.calendars) }
                    case .other:
                        GroupedRow(errorMessage, symbol: "calendar.badge.exclamationmark", color: .orange)
                    }
                }
            } else if events.isEmpty {
                GroupedSection {
                    GroupedRow("No upcoming events", subtitle: "Nothing in the next seven days for these calendars.", symbol: "calendar", color: .gray)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let visibleEvents = configuration.calendarLayout == .nextEvent
                        ? CalendarEventOrdering.compactEvent(from: events, now: context.date).map { [$0] } ?? []
                        : events.filter { $0.endDate > context.date }.sorted { CalendarEventOrdering.precedes($0, $1, now: context.date) }
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
                            DockScrollView { eventList(visibleEvents, now: context.date) }.frame(height: 300)
                        } else {
                            eventList(visibleEvents, now: context.date)
                        }
                        if let allDayLine { WidgetPopoutCaption("All day · " + allDayLine) }
                    }
                }
            }
        }
    }

    private func eventList(_ visibleEvents: [CalendarEventSnapshot], now: Date) -> some View {
        GroupedSection(separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            ForEach(visibleEvents) { event in eventRow(event, now: now) }
        }
    }

    private var barIsMonochrome: Bool {
        CalendarEventBarStyle.isMonochrome(accent: configuration.widgetAccent ?? .auto, appearance: configuration.iconAppearance)
    }

    /// One event: a calendar bar, the title, and one line that merges status, time and calendar.
    private func eventRow(_ event: CalendarEventSnapshot, now: Date) -> some View {
        let ongoing = !event.isAllDay && event.startDate <= now && event.endDate > now
        return WidgetPopoutRow {
            HStack(spacing: 10) {
                // The calendar's colour; Mono stays neutral, and the neutral bar marks the ongoing event.
                CalendarColorBar(style: CalendarEventBarStyle.resolve(color: event.calendarColor, monochrome: barIsMonochrome, emphasized: ongoing))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(DockDesign.Grouped.titleFont.weight(.medium)).lineLimit(2)
                    Text(CalendarEventRowPresentation.detail(event, now: now))
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    if let location = NextMeeting.locationText(event) {
                        Text(location).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                // Join only for an event that carries a recognised meeting link; otherwise the event opens in Calendar.
                switch CalendarEventAction.action(for: event) {
                case .join(let url):
                    Button("Join") { openMeeting(url) }.buttonStyle(GalleryGlassButtonStyle())
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
                Picker("Show", selection: $layoutSelection) {
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
                GroupedRow("All-day events", isOn: $showAllDaySelection)
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

    private func updateLayout(_ layout: CalendarWidgetLayout) {
        updateConfiguration { $0.calendarLayout = layout }
        reload()
    }

    private func toggleCalendar(_ id: String) {
        updateConfiguration { value in
            if value.selectedCalendarIDs.contains(id) { value.selectedCalendarIDs.removeAll { $0 == id } }
            else { value.selectedCalendarIDs.append(id) }
        }
        reload()
    }

    private func updateCalendars(_ ids: [String]) {
        updateConfiguration { $0.selectedCalendarIDs = ids }
        reload()
    }

    private func updateConfiguration(_ update: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: update)
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
            events = fixture.events()
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
        guard let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id }) else { return nil }
        return currentItem.widgetConfiguration ?? WidgetConfiguration()
    }
}

// MARK: - Reminders face

/// The Reminders module: the open count with "to do", the list name on wide layouts, and an overdue mark.
struct RemindersModuleFace: View {
    /// nil: not set up or access unavailable.
    var count: Int?
    var overdue = 0
    var context: String
    @Environment(\.widgetLayout) private var layout
    @Environment(\.widgetShowsLabel) private var showsLabel
    @Environment(\.dockWidgetContentWidth) private var width
    private var narrow: Bool { WidgetModuleMetrics.isNarrow(width) }
    private let kind = "Reminders"
    var body: some View {
        Group {
            if let count {
                VStack(alignment: narrow || !showsLabel ? .center : .leading, spacing: DockDesign.Module.lineSpacing - 1) {
                    if showsLabel {
                        HStack(spacing: 4) {
                            if !narrow { WidgetIcon(kind: kind, size: WidgetModuleMetrics.labelGlyph, enclosed: false) }
                            Text(labelText).font(DockDesign.Module.label)
                                .foregroundStyle(overdue > 0 ? WidgetPalette.critical : Color.secondary)
                                .lineLimit(1).minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
                        }
                    }
                    HStack(spacing: 4) {
                        ModuleValue(value: "\(count)", unit: narrow ? "" : "to do", size: narrow ? .medium : .large)
                        if overdue > 0 && !showsLabel {
                            Circle().fill(WidgetPalette.critical).frame(width: 6, height: 6).accessibilityHidden(true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: narrow || !showsLabel ? .center : .leading)
            } else {
                ModuleStack(kind: kind, label: "Reminders", value: "Set up", size: .small, showsGlyph: layout == .wide)
            }
        }
        .moduleInsets()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reminders")
        .accessibilityValue(count.map { "\($0) to do" + (overdue > 0 ? ", \(overdue) overdue" : "") } ?? "Not set up")
    }
    private var labelText: String {
        if overdue > 0 { return narrow ? "Late" : "\(overdue) overdue" }
        return layout == .wide && !narrow ? context : "To do"
    }
}

private struct RemindersCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var eventKitChanges = EventKitChangeMonitor.shared
    @State private var count = 0
    @State private var overdue = 0
    @State private var hasAccess = false
    @State private var errorMessage: String?
    @State private var refreshRequestID = UUID()

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    var body: some View {
        RemindersModuleFace(count: hasAccess && errorMessage == nil ? count : nil, overdue: overdue,
                            context: errorMessage != nil ? "Unavailable" : hasAccess ? "Selected reminders" : "Choose a list")
        .frame(width: contentWidth, height: 54)
        // One structured refresh per list change and per coalesced EventKit, activation or wake signal.
        .task(id: EventKitRefreshKey(value: configuration.selectedReminderCalendarID, generation: eventKitChanges.generation)) {
            await refreshIfAuthorized()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfAuthorized()
            }
        }
        .help(errorMessage ?? "Reminders")
    }

    private func refreshIfAuthorized() async {
        let selectedListID = configuration.selectedReminderCalendarID
        let requestID = UUID()
        refreshRequestID = requestID
        #if DEBUG
        if let fixture = RemindersQAFixture.override {
            let result = fixture.reminders()
            count = result.count
            overdue = RemindersFacePresentation.overdueCount(result, now: .now)
            hasAccess = fixture != .denied
            errorMessage = fixture == .denied ? CalendarRemindersServiceError.accessDenied.localizedDescription : nil
            return
        }
        #endif
        guard await CalendarRemindersService.shared.hasRemindersAccess() else {
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            count = 0
            overdue = 0
            hasAccess = false
            errorMessage = "Reminders access is unavailable."
            return
        }
        do {
            let result = try await CalendarRemindersService.shared.reminders(calendarID: selectedListID)
            let stillAuthorized = await CalendarRemindersService.shared.hasRemindersAccess()
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            guard stillAuthorized else {
                count = 0
                overdue = 0
                hasAccess = false
                errorMessage = "Reminders access is unavailable."
                return
            }
            count = result.count
            overdue = RemindersFacePresentation.overdueCount(result, now: .now)
            hasAccess = true
            errorMessage = nil
        } catch {
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            count = 0
            overdue = 0
            hasAccess = false
            errorMessage = error.localizedDescription
        }
    }

    private func currentConfiguration() -> WidgetConfiguration? {
        guard let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id }) else { return nil }
        return currentItem.widgetConfiguration ?? WidgetConfiguration()
    }

    private func requestIsCurrent(_ requestID: UUID, selectedListID: String) -> Bool {
        guard refreshRequestID == requestID, !Task.isCancelled,
              let current = currentConfiguration() else { return false }
        return current.selectedReminderCalendarID == selectedListID
    }
}

// MARK: - Reminders popout

private struct RemindersPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject private var eventKitChanges = EventKitChangeMonitor.shared
    @State private var lists: [ReminderListSnapshot] = []
    @State private var reminders: [ReminderSnapshot] = []
    @State private var newReminderTitle = ""
    @State private var lastCompletedIdentifier: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var failure = EventKitReadFailure.accessDenied
    @State private var actionErrorMessage: String?
    @State private var refreshRequestID = UUID()
    @State private var layoutSelection = RemindersWidgetLayout.list
    @State private var selectedList = ""
    @State private var isAddingReminder = false
    @State private var isChangingCompletion = false
    @State private var loadedAt: Date?
    /// The list and layout sit behind a final, collapsed disclosure.
    @State private var settingsExpanded = false

    /// Separators start at the reminder text, past the completion circle.
    private static let rowSeparatorInset = DockDesign.Grouped.rowHorizontalPadding + 20 + 10

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    /// Only the first read replaces the reading with a loading row; later refreshes keep it and the header shows progress.
    private var isFirstLoad: Bool { isLoading && loadedAt == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            if isFirstLoad {
                GroupedSection {
                    WidgetPopoutRow {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading reminders…").font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if let errorMessage {
                GroupedSection {
                    switch failure {
                    case .selectionUnavailable:
                        GroupedRow("Selected list unavailable", subtitle: "Choose another list or show all lists.",
                                   symbol: "checklist", color: .orange)
                        GroupedRow("Show All Lists", role: .button) { selectedList = "" }
                    case .accessDenied:
                        GroupedRow(errorMessage, subtitle: "You can change access in System Settings.", symbol: "checklist", color: .orange)
                        GroupedRow("Open Privacy & Security", role: .button) { WidgetPrivacySettings.open(WidgetPrivacySettings.reminders) }
                    case .other:
                        GroupedRow(errorMessage, symbol: "checklist", color: .orange)
                    }
                }
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let overdue = RemindersFacePresentation.overdueCount(reminders, now: context.date)
                    VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
                        WidgetPopoutHero(value: "\(reminders.count)",
                                         caption: (reminders.count == 1 ? "reminder to do" : "reminders to do") + (overdue > 0 ? " · \(overdue) overdue" : ""))
                        if configuration.remindersLayout != .count {
                            if reminders.isEmpty {
                                GroupedSection {
                                    GroupedRow("No incomplete reminders", subtitle: "Add a reminder here or in the Reminders app.", symbol: "checkmark.circle", color: .gray)
                                }
                            } else {
                                let shown = configuration.remindersLayout == .nextReminder ? Array(reminders.prefix(1)) : reminders
                                if shown.count > 6 {
                                    DockScrollView { reminderList(shown, now: context.date) }.frame(height: 260)
                                } else {
                                    reminderList(shown, now: context.date)
                                }
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                GroupedSection {
                    WidgetPopoutRow {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 19)).foregroundStyle(DockDesign.accent)
                                .frame(width: 20).accessibilityHidden(true)
                            TextField("New reminder", text: $newReminderTitle)
                                .textFieldStyle(.plain)
                                .onSubmit(addReminder)
                            if isAddingReminder { ProgressView().controlSize(.small).accessibilityLabel("Adding reminder") }
                            Button("Add", action: addReminder)
                                .buttonStyle(WidgetRowTextButtonStyle())
                                .disabled(isAddingReminder || newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                if let lastCompletedIdentifier {
                    HStack {
                        Text("Reminder completed.").font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                        Spacer()
                        Button("Undo completion") { undoCompletion(lastCompletedIdentifier) }
                            .buttonStyle(.borderless).controlSize(.small).disabled(isChangingCompletion)
                    }
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                }
                if let actionErrorMessage {
                    WidgetPopoutCaption(actionErrorMessage, color: Color(nsColor: .systemRed))
                }
            }

            WidgetPopoutSettingsDisclosure(summary: lists.first { $0.id == selectedList }?.title ?? "All lists", isExpanded: $settingsExpanded) {
                GroupedSection("Reminders", footer: "Changes here update your Reminders lists.",
                               separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    GroupedRow("List") {
                        Picker("List", selection: $selectedList) {
                            Text("All lists").tag("")
                            ForEach(lists) { list in Text(list.title).tag(list.id) }
                        }
                        .labelsHidden().fixedSize().accessibilityLabel("List")
                    }
                    GroupedRow("Show") {
                        Picker("Layout", selection: $layoutSelection) {
                            ForEach(RemindersWidgetLayout.allCases) { layout in Text(layout.title).tag(layout) }
                        }
                        .labelsHidden().fixedSize().accessibilityLabel("Layout")
                    }
                }
            }
        }
        .widgetPopoutRefresh(WidgetPopoutRefresh(updatedAt: loadedAt, isRefreshing: isLoading, failed: errorMessage != nil, action: reload))
        .onAppear { layoutSelection = configuration.remindersLayout }
        .onChange(of: layoutSelection) { updateLayout($0) }
        .onChange(of: configuration.remindersLayout) { layoutSelection = $0 }
        .onAppear { selectedList = configuration.selectedReminderCalendarID }
        .onChange(of: selectedList) { updateList($0) }
        .onChange(of: configuration.selectedReminderCalendarID) { selectedList = $0 }
        // Structured: restarts once per coalesced EventKit, activation or wake signal and ends with the popout.
        .task(id: eventKitChanges.generation) {
            await requestAndLoad()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await requestAndLoad()
            }
        }
    }

    private func reminderList(_ shown: [ReminderSnapshot], now: Date) -> some View {
        GroupedSection(separatorInset: Self.rowSeparatorInset) {
            ForEach(shown) { reminder in reminderRow(reminder, now: now) }
        }
    }

    private func reminderRow(_ reminder: ReminderSnapshot, now: Date) -> some View {
        let overdue = RemindersFacePresentation.isOverdue(reminder, now: now)
        return WidgetPopoutRow {
            HStack(spacing: 10) {
                Button { complete(reminder) } label: {
                    Image(systemName: "circle").font(.system(size: 19)).foregroundStyle(.secondary).frame(width: 20)
                }
                .buttonStyle(.plain).help("Mark complete").disabled(isChangingCompletion)
                .accessibilityLabel("Complete \(reminder.title)")
                VStack(alignment: .leading, spacing: 1) {
                    Text(reminder.title).font(DockDesign.Grouped.titleFont).lineLimit(2)
                    if let dueText = RemindersFacePresentation.dueText(reminder, now: now) {
                        Text((overdue ? "Overdue · " : "") + dueText)
                            .font(DockDesign.Grouped.subtitleFont)
                            .foregroundStyle(overdue ? WidgetPalette.critical : Color.secondary)
                    }
                }
                Spacer(minLength: 6)
                Text(reminder.calendarTitle).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func updateList(_ listID: String) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.selectedReminderCalendarID = listID }
        reload()
    }

    private func updateLayout(_ layout: RemindersWidgetLayout) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.remindersLayout = layout }
    }

    private func reload() { Task { await requestAndLoad() } }

    private func requestAndLoad() async {
        let selectedListID = configuration.selectedReminderCalendarID
        let requestID = UUID()
        refreshRequestID = requestID
        #if DEBUG
        if let fixture = RemindersQAFixture.override {
            lists = fixture.lists
            reminders = fixture.reminders()
            errorMessage = fixture == .denied ? CalendarRemindersServiceError.accessDenied.localizedDescription : nil
            failure = .accessDenied
            isLoading = false
            loadedAt = fixture == .denied ? nil : .now
            return
        }
        #endif
        isLoading = true
        defer { if refreshRequestID == requestID { isLoading = false } }
        // The lists are read first and kept when only the selection is gone, so another can be chosen here.
        var fetchedLists: [ReminderListSnapshot]?
        do {
            try await CalendarRemindersService.shared.requestRemindersAccess()
            fetchedLists = try await CalendarRemindersService.shared.reminderLists()
            let fetchedReminders = try await CalendarRemindersService.shared.reminders(calendarID: selectedListID)
            let stillAuthorized = await CalendarRemindersService.shared.hasRemindersAccess()
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            guard stillAuthorized else { throw CalendarRemindersServiceError.accessDenied }
            lists = fetchedLists ?? []
            reminders = fetchedReminders
            errorMessage = nil
            loadedAt = .now
        } catch {
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            let readFailure = EventKitReadFailure(error)
            errorMessage = error.localizedDescription
            failure = readFailure
            lists = readFailure == .selectionUnavailable ? (fetchedLists ?? lists) : []
            reminders = []
            loadedAt = nil
        }
    }

    private func requestIsCurrent(_ requestID: UUID, selectedListID: String) -> Bool {
        guard refreshRequestID == requestID, !Task.isCancelled,
              let current = currentConfiguration() else { return false }
        return current.selectedReminderCalendarID == selectedListID
    }

    private func currentConfiguration() -> WidgetConfiguration? {
        guard let currentItem = store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id }) else { return nil }
        return currentItem.widgetConfiguration ?? WidgetConfiguration()
    }

    private func addReminder() {
        guard !isAddingReminder else { return }
        let title = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let targetListID = configuration.selectedReminderCalendarID
        isAddingReminder = true
        actionErrorMessage = nil
        Task {
            do {
                try await CalendarRemindersService.shared.addReminder(title: title, calendarID: targetListID)
                if newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines) == title {
                    newReminderTitle = ""
                }
                isAddingReminder = false
                await requestAndLoad()
            } catch {
                isAddingReminder = false
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func complete(_ reminder: ReminderSnapshot) {
        guard !isChangingCompletion else { return }
        isChangingCompletion = true
        actionErrorMessage = nil
        Task {
            do {
                try await CalendarRemindersService.shared.setReminderCompleted(identifier: reminder.id, completed: true)
                lastCompletedIdentifier = reminder.id
                isChangingCompletion = false
                // The completed row leaves at once; the reload then confirms the list without hiding it.
                reminders.removeAll { $0.id == reminder.id }
                await requestAndLoad()
            } catch {
                isChangingCompletion = false
                actionErrorMessage = error.localizedDescription
            }
        }
    }

    private func undoCompletion(_ identifier: String) {
        guard !isChangingCompletion else { return }
        isChangingCompletion = true
        actionErrorMessage = nil
        Task {
            do {
                try await CalendarRemindersService.shared.setReminderCompleted(identifier: identifier, completed: false)
                lastCompletedIdentifier = nil
                isChangingCompletion = false
                await requestAndLoad()
            } catch {
                isChangingCompletion = false
                actionErrorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Coalesced EventKit refresh

/// The `.task(id:)` key of an EventKit view: its own settings plus the shared change generation.
private struct EventKitRefreshKey<Value: Equatable>: Equatable {
    var value: Value
    var generation: Int
}

/// One shared signal for every Calendar and Reminders view. EventKit store changes arrive in bursts during iCloud
/// sync, and app activation and wake follow each other, so the views refetch once per burst instead of once per
/// notification. While nothing visible wants refreshes (the Dock is hidden and no popout is open), the signal waits
/// for the scheduler's next active tick instead of fetching for a Dock nobody sees.
@MainActor
final class EventKitChangeMonitor: ObservableObject {
    static let shared = EventKitChangeMonitor()

    /// Increments once per coalesced burst; views use it in `.task(id:)`.
    @Published private(set) var generation = 0
    private let delay: Duration
    private let scheduler: RefreshScheduler
    private var observations: [AnyCancellable] = []
    private var pending: Task<Void, Never>?

    init(delay: Duration = .seconds(1), center: NotificationCenter = .default,
         workspaceCenter: NotificationCenter? = nil, scheduler: RefreshScheduler? = nil) {
        self.delay = delay
        self.scheduler = scheduler ?? .shared
        let publishers = [
            center.publisher(for: .EKEventStoreChanged),
            center.publisher(for: NSApplication.didBecomeActiveNotification),
            (workspaceCenter ?? NSWorkspace.shared.notificationCenter).publisher(for: NSWorkspace.didWakeNotification)
        ]
        // EKEventStoreChanged may be posted off the main thread, so each signal hops to the main actor.
        observations = publishers.map { publisher in
            publisher.sink { @Sendable [weak self] _ in
                Task { @MainActor in self?.signal() }
            }
        }
    }

    /// Restarts the coalescing window; the generation advances once the window passes without another signal.
    func signal() {
        pending?.cancel()
        pending = Task { [weak self, delay, scheduler] in
            do { try await Task.sleep(for: delay) } catch { return }
            if !scheduler.isActive {
                // The scheduler only ticks while active, so the first tick marks the Dock or a popout becoming visible.
                for await _ in scheduler.ticks(every: 1) { break }
            }
            guard !Task.isCancelled, let self else { return }
            self.generation &+= 1
            self.pending = nil
        }
    }
}
