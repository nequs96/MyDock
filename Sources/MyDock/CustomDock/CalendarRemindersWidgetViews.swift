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

struct RemindersWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersCompactWidgetView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersPopoutWidgetView(store: store, item: item, profileID: profileID))
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
    @State private var refreshRequestID = UUID()

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            (contentWidth > 54 ? AnyLayout(HStackLayout(spacing: 9)) : AnyLayout(VStackLayout(spacing: 1))) {
                if configuration.calendarLayout != .nextEvent || dockLayout == .compact {
                    VStack(spacing: 1) {
                        HStack(spacing: 3) {
                            WidgetIcon(kind: "Calendar", size: 9)
                            Text(context.date.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                        }
                        Text(context.date.formatted(.dateTime.day()))
                            .font(.system(size: contentWidth > 54 || configuration.calendarLayout == .date ? 26 : 18, weight: .medium)).monospacedDigit()
                    }
                }
                if configuration.calendarLayout != .date && dockLayout == .wide {
                    VStack(alignment: contentWidth > 54 ? .leading : .center, spacing: 3) {
                        if let next = CalendarEventOrdering.compactEvent(from: events, now: context.date) {
                            Text(next.title).font(.system(size: 9, weight: .semibold)).lineLimit(1)
                            Text(WidgetTimingPresentation.eventStatus(next, now: context.date)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        } else {
                            Text(errorMessage != nil ? "Unavailable" : accessAvailable ? "No events" : "Calendar")
                                .font(.system(size: 9, weight: .medium)).lineLimit(1)
                            if contentWidth > 54 { Text(accessAvailable ? "Today" : "Choose calendars").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
            .padding(.horizontal, contentWidth > 54 ? 9 : 1)
            .frame(width: contentWidth, height: 54)
        }
        .task(id: configuration) {
            await refreshIfAuthorized()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfAuthorized()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await refreshIfAuthorized() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshIfAuthorized() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            Task { await refreshIfAuthorized() }
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

private struct CalendarPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var calendars: [CalendarListSnapshot] = []
    @State private var events: [CalendarEventSnapshot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var refreshRequestID = UUID()
    @State private var layoutSelection = CalendarWidgetLayout.dateAndNextEvent
    @State private var showAllDaySelection = false

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

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
                Text("Showing: " + selectedCalendarLabel + " · next seven days")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if configuration.calendarLayout == .date {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    HStack(spacing: 12) {
                        Text(context.date.formatted(.dateTime.day())).font(.system(size: 54, weight: .medium, design: .rounded))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.date.formatted(.dateTime.weekday(.wide))).font(.title3.weight(.semibold))
                            Text(context.date.formatted(.dateTime.month(.wide).year())).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        HStack(spacing: 8) {
                            Image(systemName: "calendar").foregroundStyle(.tint)
                            Text(context.date.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let visibleEvents = configuration.calendarLayout == .nextEvent
                        ? CalendarEventOrdering.compactEvent(from: events, now: context.date).map { [$0] } ?? []
                        : events.filter { $0.endDate > context.date }.sorted { CalendarEventOrdering.precedes($0, $1, now: context.date) }
                    DockScrollView {
                        LazyVStack(alignment: .leading, spacing: 7) {
                            ForEach(visibleEvents) { event in eventRow(event) }
                            if visibleEvents.isEmpty { Text("No upcoming events in this reading. Refresh to check again.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .frame(maxHeight: 260)
                }
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
        .task {
            await requestAndLoad()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await requestAndLoad()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in reload() }
    }

    @ViewBuilder private func eventRow(_ event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.callout.weight(.medium)).lineLimit(2)
                Text(event.startDate.formatted(date: .abbreviated, time: event.isAllDay ? .omitted : .shortened) + " · " + event.calendarTitle)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(WidgetTimingPresentation.eventStatus(event, now: context.date))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let url = event.meetingURL {
                Button("Join") { NSWorkspace.shared.open(url) }.buttonStyle(DockButtonStyle())
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
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
            return
        }
        #if DEBUG
        if let fixture = CalendarQAFixture.current {
            calendars = fixture.calendars
            events = fixture.events()
            errorMessage = nil
            isLoading = false
            return
        }
        #endif
        isLoading = true
        defer { if refreshRequestID == requestID { isLoading = false } }
        do {
            try await CalendarRemindersService.shared.requestCalendarAccess()
            let fetchedCalendars = try await CalendarRemindersService.shared.calendarLists()
            let fetchedEvents = try await CalendarRemindersService.shared.events(calendarIDs: selectedIDs,
                                                                                includeAllDay: includeAllDay)
            let stillAuthorized = await CalendarRemindersService.shared.hasCalendarAccess()
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            guard stillAuthorized else { throw CalendarRemindersServiceError.accessDenied }
            calendars = fetchedCalendars
            events = fetchedEvents
            errorMessage = nil
        } catch {
            guard requestIsCurrent(requestID, selectedIDs: selectedIDs,
                                   includeAllDay: includeAllDay, layout: layout) else { return }
            errorMessage = error.localizedDescription
            calendars = []
            events = []
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

private struct RemindersCompactWidgetView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var count = 0
    @State private var hasAccess = false
    @State private var errorMessage: String?
    @State private var refreshRequestID = UUID()

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    var body: some View {
        RemindersDockFace(count: hasAccess && errorMessage == nil ? count : nil,
                          context: errorMessage != nil ? "Unavailable" : hasAccess ? "Selected reminders" : "Choose a list")
        .frame(width: contentWidth, height: 54)
        .task(id: configuration.selectedReminderCalendarID) {
            await refreshIfAuthorized()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await refreshIfAuthorized()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { await refreshIfAuthorized() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshIfAuthorized() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            Task { await refreshIfAuthorized() }
        }
        .help(errorMessage ?? "Reminders")
    }

    private func refreshIfAuthorized() async {
        let selectedListID = configuration.selectedReminderCalendarID
        let requestID = UUID()
        refreshRequestID = requestID
        guard await CalendarRemindersService.shared.hasRemindersAccess() else {
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            count = 0
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
                hasAccess = false
                errorMessage = "Reminders access is unavailable."
                return
            }
            count = result.count
            hasAccess = true
            errorMessage = nil
        } catch {
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            count = 0
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
    @State private var actionErrorMessage: String?
    @State private var refreshRequestID = UUID()
    @State private var layoutSelection = RemindersWidgetLayout.list
    @State private var selectedList = ""
    @State private var isAddingReminder = false
    @State private var isChangingCompletion = false

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Apple Reminders · changes update your Reminders lists. Quick Checklist keeps separate tasks in MyDock.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
                DockScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(shown) { reminder in reminderRow(reminder) }
                    }
                }
                .frame(maxHeight: 220)
            }

            HStack(spacing: 7) {
                TextField("New reminder", text: $newReminderTitle)
                    .textFieldStyle(DockTextFieldStyle())
                    .onSubmit(addReminder)
                Button("Add", action: addReminder)
                    .buttonStyle(DockButtonStyle(primary: true))
                    .disabled(isAddingReminder || newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if isAddingReminder { ProgressView("Adding reminder…").font(.caption) }
            if let lastCompletedIdentifier {
                Button("Undo completion") { undoCompletion(lastCompletedIdentifier) }
                    .font(.caption).buttonStyle(.plain).disabled(isChangingCompletion)
            }
            if let actionErrorMessage {
                Text(actionErrorMessage).font(.caption).foregroundStyle(.red)
            }
        }
        .frame(width: 410).frame(minHeight: 220, alignment: .topLeading)
        .onAppear { layoutSelection = configuration.remindersLayout }
        .onChange(of: layoutSelection) { updateLayout($0) }
        .onChange(of: configuration.remindersLayout) { layoutSelection = $0 }
        .onAppear { selectedList = configuration.selectedReminderCalendarID }
        .onChange(of: selectedList) { updateList($0) }
        .onChange(of: configuration.selectedReminderCalendarID) { selectedList = $0 }
        .task {
            await requestAndLoad()
            for await _ in RefreshScheduler.shared.ticks(every: 5 * 60) {
                guard !Task.isCancelled else { return }
                await requestAndLoad()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in reload() }
    }

    @ViewBuilder private func reminderRow(_ reminder: ReminderSnapshot) -> some View {
        HStack(spacing: 8) {
            Button { complete(reminder) } label: { Image(systemName: "circle") }
                .buttonStyle(.plain).help("Mark complete").disabled(isChangingCompletion)
                .accessibilityLabel("Complete \(reminder.title)")
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
        let selectedListID = configuration.selectedReminderCalendarID
        let requestID = UUID()
        refreshRequestID = requestID
        isLoading = true
        defer { if refreshRequestID == requestID { isLoading = false } }
        do {
            try await CalendarRemindersService.shared.requestRemindersAccess()
            let fetchedLists = try await CalendarRemindersService.shared.reminderLists()
            let fetchedReminders = try await CalendarRemindersService.shared.reminders(calendarID: selectedListID)
            let stillAuthorized = await CalendarRemindersService.shared.hasRemindersAccess()
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            guard stillAuthorized else { throw CalendarRemindersServiceError.accessDenied }
            lists = fetchedLists
            reminders = fetchedReminders
            errorMessage = nil
        } catch {
            guard requestIsCurrent(requestID, selectedListID: selectedListID) else { return }
            errorMessage = error.localizedDescription
            lists = []
            reminders = []
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
