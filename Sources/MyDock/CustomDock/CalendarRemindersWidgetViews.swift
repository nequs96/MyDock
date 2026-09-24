import AppKit
import SwiftUI

struct CalendarWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CalendarCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CalendarPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

struct RemindersWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

private struct CalendarCompactWidgetView: View {
    var item: DockItem
    @State private var events: [CalendarEventSnapshot] = []
    @State private var accessAvailable = false

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 2) {
                if configuration.calendarLayout != .nextEvent {
                    Text(context.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    Text(context.date.formatted(.dateTime.day()))
                        .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                }
                if configuration.calendarLayout != .date {
                    if let next = CalendarEventOrdering.compactEvent(from: events) {
                        Text(next.title).font(.system(size: 8, weight: .medium)).lineLimit(1).frame(maxWidth: 52)
                        Text(next.timeDescription).font(.system(size: 8, weight: .regular)).foregroundStyle(.secondary)
                    } else {
                        Text(accessAvailable ? "No events" : "Calendar")
                            .font(.system(size: 8, weight: .medium)).lineLimit(1).frame(maxWidth: 52)
                    }
                }
            }
            .frame(width: 54, height: 54)
        }
        .task(id: item.widgetConfiguration) { await refreshIfAuthorized() }
        .help("Calendar")
    }

    private func refreshIfAuthorized() async {
        guard configuration.calendarLayout != .date else { return }
        guard await CalendarRemindersService.shared.hasCalendarAccess() else { return }
        do {
            events = try await CalendarRemindersService.shared.events(
                calendarIDs: configuration.selectedCalendarIDs,
                includeAllDay: configuration.calendarShowsAllDayEvents
            )
            accessAvailable = true
        } catch {
            accessAvailable = true
            events = []
        }
    }
}

private struct CalendarPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var calendars: [CalendarListSnapshot] = []
    @State private var events: [CalendarEventSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var layoutSelection = CalendarWidgetLayout.dateAndNextEvent
    @State private var showAllDaySelection = false

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Layout", selection: $layoutSelection) {
                    ForEach(CalendarWidgetLayout.allCases) { layout in Text(layout.title).tag(layout) }
                }
                .frame(maxWidth: 210)
                Spacer()
                if configuration.calendarLayout != .date {
                    Button("Refresh", action: reload)
                        .disabled(isLoading)
                }
            }

            if configuration.calendarLayout != .date {
                DisclosureGroup("Calendars · \(selectedCalendarLabel)") {
                    Button("All calendars") { updateCalendars([]) }.buttonStyle(.plain)
                    ForEach(calendars) { calendar in
                        Button { toggleCalendar(calendar.id) } label: {
                            Label(calendar.title,
                                  systemImage: configuration.selectedCalendarIDs.contains(calendar.id) ? "checkmark.circle.fill" : "circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    Toggle("Show all-day events", isOn: $showAllDaySelection)
                }
                .font(.caption)
            }

            if configuration.calendarLayout == .date {
                HStack(spacing: 12) {
                    Text(Date.now.formatted(.dateTime.day())).font(.system(size: 54, weight: .medium, design: .rounded))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide))).font(.title3.weight(.semibold))
                        Text(Date.now.formatted(.dateTime.month(.wide).year())).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if isLoading {
                ProgressView("Loading calendar…").frame(maxWidth: .infinity, minHeight: 90)
            } else if let errorMessage {
                CalendarWidgetEmptyState(title: errorMessage, symbol: "calendar.badge.exclamationmark", detail: "You can change Calendar access in System Settings.")
                    .frame(minHeight: 90)
            } else if events.isEmpty {
                CalendarWidgetEmptyState(title: "No upcoming events", symbol: "calendar", detail: "There are no events in the next seven days for these calendars.")
                    .frame(minHeight: 100)
            } else {
                if configuration.calendarLayout == .dateAndNextEvent || configuration.calendarLayout == .agenda {
                    HStack(spacing: 8) {
                        Image(systemName: "calendar").foregroundStyle(.tint)
                        Text(Date.now.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                let visibleEvents = configuration.calendarLayout == .nextEvent
                    ? Array(events.prefix(1)) : events
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(visibleEvents) { event in eventRow(event) }
                    }
                }
                .frame(maxHeight: 260)
            }
            if let errorMessage, !isLoading, configuration.calendarLayout == .date {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(width: 370).frame(minHeight: 190, alignment: .topLeading)
        .onAppear { layoutSelection = configuration.calendarLayout }
        .onChange(of: layoutSelection) { updateLayout($0) }
        .onChange(of: item.widgetConfiguration?.calendarLayout) { layoutSelection = $0 ?? .dateAndNextEvent }
        .onAppear { showAllDaySelection = configuration.calendarShowsAllDayEvents }
        .onChange(of: showAllDaySelection) { value in
            updateConfiguration { $0.calendarShowsAllDayEvents = value }
            reload()
        }
        .onChange(of: item.widgetConfiguration?.calendarShowsAllDayEvents) { showAllDaySelection = $0 ?? false }
        .task { await requestAndLoad() }
    }

    @ViewBuilder private func eventRow(_ event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                Text(event.startDate.formatted(date: .abbreviated, time: .shortened) + " · " + event.calendarTitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(.bordered)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private var selectedCalendarLabel: String {
        let selected = calendars.filter { configuration.selectedCalendarIDs.contains($0.id) }
        guard !configuration.selectedCalendarIDs.isEmpty else { return "All" }
        return selected.map(\.title).joined(separator: ", ")
    }

    private func updateLayout(_ layout: CalendarWidgetLayout) {
        updateConfiguration { $0.calendarLayout = layout }
        if layout != .date { reload() }
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
        guard configuration.calendarLayout != .date else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await CalendarRemindersService.shared.requestCalendarAccess()
            calendars = try await CalendarRemindersService.shared.calendarLists()
            events = try await CalendarRemindersService.shared.events(
                calendarIDs: configuration.selectedCalendarIDs,
                includeAllDay: configuration.calendarShowsAllDayEvents
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            calendars = []
            events = []
        }
    }
}

private struct RemindersCompactWidgetView: View {
    var item: DockItem
    @State private var count = 0
    @State private var hasAccess = false

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "checklist").font(.system(size: 21)).foregroundStyle(.tint)
            Text(hasAccess ? "\(count) left" : "Reminders")
                .font(.system(size: 8, weight: .medium)).lineLimit(1).frame(maxWidth: 52)
        }
        .frame(width: 54, height: 54)
        .task(id: configuration.selectedReminderCalendarID) { await refreshIfAuthorized() }
        .help("Reminders")
    }

    private func refreshIfAuthorized() async {
        guard await CalendarRemindersService.shared.hasRemindersAccess() else { return }
        do {
            count = try await CalendarRemindersService.shared.reminders(calendarID: configuration.selectedReminderCalendarID).count
            hasAccess = true
        } catch {
            hasAccess = true
            count = 0
        }
    }
}

private struct RemindersPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var lists: [ReminderListSnapshot] = []
    @State private var reminders: [ReminderSnapshot] = []
    @State private var newReminderTitle = ""
    @State private var lastCompletedIdentifier: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var layoutSelection = RemindersWidgetLayout.list
    @State private var selectedList = ""

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Picker("List", selection: $selectedList) {
                    Text("All lists").tag("")
                    ForEach(lists) { list in Text(list.title).tag(list.id) }
                }
                .frame(maxWidth: 220)
                Picker("Layout", selection: $layoutSelection) {
                    ForEach(RemindersWidgetLayout.allCases) { layout in Text(layout.title).tag(layout) }
                }
                .frame(maxWidth: 150)
                Button("Refresh", action: reload).disabled(isLoading)
            }

            if isLoading {
                ProgressView("Loading reminders…").frame(maxWidth: .infinity, minHeight: 90)
            } else if let errorMessage {
                CalendarWidgetEmptyState(title: errorMessage, symbol: "checklist", detail: "You can change access in System Settings.")
                    .frame(minHeight: 90)
            } else if configuration.remindersLayout == .count {
                VStack(spacing: 4) {
                    Text("\(reminders.count)").font(.system(size: 48, weight: .medium, design: .rounded))
                    Text("incomplete reminders").font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 105)
            } else if reminders.isEmpty {
                CalendarWidgetEmptyState(title: "No incomplete reminders", symbol: "checkmark.circle", detail: "Add a reminder here or in the Reminders app.")
                    .frame(minHeight: 100)
            } else {
                let shown = configuration.remindersLayout == .nextReminder ? Array(reminders.prefix(1)) : reminders
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(shown) { reminder in reminderRow(reminder) }
                    }
                }
                .frame(maxHeight: 220)
            }

            HStack(spacing: 7) {
                TextField("New reminder", text: $newReminderTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReminder)
                Button("Add", action: addReminder)
                    .buttonStyle(.borderedProminent).disabled(newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let lastCompletedIdentifier {
                Button("Undo completion") { undoCompletion(lastCompletedIdentifier) }
                    .font(.caption).buttonStyle(.plain)
            }
        }
        .frame(width: 410).frame(minHeight: 220, alignment: .topLeading)
        .onAppear { layoutSelection = configuration.remindersLayout }
        .onChange(of: layoutSelection) { updateLayout($0) }
        .onChange(of: item.widgetConfiguration?.remindersLayout) { layoutSelection = $0 ?? .list }
        .onAppear { selectedList = configuration.selectedReminderCalendarID }
        .onChange(of: selectedList) { updateList($0) }
        .onChange(of: item.widgetConfiguration?.selectedReminderCalendarID) { selectedList = $0 ?? "" }
        .task { await requestAndLoad() }
    }

    @ViewBuilder private func reminderRow(_ reminder: ReminderSnapshot) -> some View {
        HStack(spacing: 8) {
            Button { complete(reminder) } label: { Image(systemName: "circle") }
                .buttonStyle(.plain).help("Mark complete")
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title).lineLimit(2)
                if let dueDate = reminder.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(reminder.calendarTitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(7)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
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
        isLoading = true
        defer { isLoading = false }
        do {
            try await CalendarRemindersService.shared.requestRemindersAccess()
            lists = try await CalendarRemindersService.shared.reminderLists()
            reminders = try await CalendarRemindersService.shared.reminders(calendarID: configuration.selectedReminderCalendarID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            lists = []
            reminders = []
        }
    }

    private func addReminder() {
        let title = newReminderTitle
        Task {
            do {
                try await CalendarRemindersService.shared.addReminder(title: title, calendarID: configuration.selectedReminderCalendarID)
                newReminderTitle = ""
                await requestAndLoad()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func complete(_ reminder: ReminderSnapshot) {
        Task {
            do {
                try await CalendarRemindersService.shared.setReminderCompleted(identifier: reminder.id, completed: true)
                lastCompletedIdentifier = reminder.id
                await requestAndLoad()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func undoCompletion(_ identifier: String) {
        Task {
            do {
                try await CalendarRemindersService.shared.setReminderCompleted(identifier: identifier, completed: false)
                lastCompletedIdentifier = nil
                await requestAndLoad()
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct CalendarWidgetEmptyState: View {
    var title: String
    var symbol: String
    var detail: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium)).multilineTextAlignment(.center)
            Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding(.vertical, 8)
    }
}
