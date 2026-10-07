import SwiftUI

struct RemindersWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersCompactWidgetView(store: store, item: item, profileID: profileID))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(RemindersPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

// MARK: - Pure presentation

enum RemindersFacePresentation {
    static let allListsTitle = "All lists"

    /// The wide module's context: the chosen list's name, or "All lists" when none is chosen.
    static func listTitle(selectedID: String, lists: [ReminderListSnapshot]) -> String {
        guard !selectedID.isEmpty else { return allListsTitle }
        return lists.first { $0.id == selectedID }?.title ?? "Reminders"
    }

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
    @State private var count = 0
    @State private var overdue = 0
    @State private var hasAccess = false
    @State private var errorMessage: String?
    @State private var refreshRequestID = UUID()
    /// The chosen list's name, or "All lists", for the wide module's one line of context.
    @State private var listTitle = RemindersFacePresentation.allListsTitle

    private var configuration: WidgetConfiguration {
        currentConfiguration() ?? item.widgetConfiguration ?? WidgetConfiguration()
    }

    var body: some View {
        RemindersModuleFace(count: hasAccess && errorMessage == nil ? count : nil, overdue: overdue,
                            context: errorMessage != nil ? "Unavailable" : hasAccess ? listTitle : "Choose a list")
        .frame(width: contentWidth, height: 54)
        // One structured refresh per list change and per coalesced EventKit, activation or wake signal.
        .eventKitRefresh(scope: configuration.selectedReminderCalendarID) { await refreshIfAuthorized() }
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
            listTitle = RemindersFacePresentation.listTitle(selectedID: selectedListID, lists: fixture.lists)
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
            // The list names are read only for a chosen list; "All lists" needs none.
            var lists: [ReminderListSnapshot] = []
            if !selectedListID.isEmpty { lists = try await CalendarRemindersService.shared.reminderLists() }
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
            listTitle = RemindersFacePresentation.listTitle(selectedID: selectedListID, lists: lists)
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
        WidgetConfigurationLookup.current(store: store, itemID: item.id, profileID: profileID)
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
    @State private var lists: [ReminderListSnapshot] = []
    @State private var reminders: [ReminderSnapshot] = []
    @State private var newReminderTitle = ""
    @State private var lastCompletedIdentifier: String?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var failure = EventKitReadFailure.accessDenied
    @State private var actionErrorMessage: String?
    @State private var refreshRequestID = UUID()
    /// When the last completion happened, so its Undo expires like every other collection undo.
    @State private var lastCompletedAt = Date.distantPast
    @State private var settingsError: String?
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
                                   symbol: "checklist", color: WidgetPalette.warning)
                        GroupedRow("Show All Lists", role: .button) { updateList("") }
                    case .accessDenied:
                        GroupedRow(errorMessage, subtitle: "You can change access in System Settings.", symbol: "checklist", color: WidgetPalette.warning)
                        GroupedRow("Open Privacy & Security", role: .button) { WidgetPrivacySettings.open(WidgetPrivacySettings.reminders) }
                    case .other:
                        GroupedRow(errorMessage, symbol: "checklist", color: WidgetPalette.warning)
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
                // Adding needs access: without it the field would only fail after submit.
                if errorMessage == nil {
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
                }
                if let lastCompletedIdentifier {
                    HStack {
                        Text("Reminder completed.").font(DockDesign.Grouped.footerFont).foregroundStyle(.secondary)
                        Spacer()
                        Button("Undo") { undoCompletion(lastCompletedIdentifier) }
                            .buttonStyle(WidgetRowTextButtonStyle()).disabled(isChangingCompletion)
                            .accessibilityLabel("Undo completion")
                    }
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                    // Offered only briefly, like every other collection undo, so it cannot reopen a reminder much later.
                    .task(id: lastCompletedAt) {
                        let remaining = RemovedEntries<ReminderSnapshot>.lifetime - Date.now.timeIntervalSince(lastCompletedAt)
                        if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
                        guard !Task.isCancelled else { return }
                        self.lastCompletedIdentifier = nil
                    }
                }
                if let actionErrorMessage {
                    WidgetPopoutCaption(actionErrorMessage, color: WidgetPalette.critical)
                }
            }

            WidgetPopoutSettingsDisclosure(summary: lists.first { $0.id == configuration.selectedReminderCalendarID }?.title ?? RemindersFacePresentation.allListsTitle,
                                           isExpanded: $settingsExpanded) {
                GroupedSection("Reminders", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    GroupedRow("List") {
                        Picker("List", selection: Binding(get: { configuration.selectedReminderCalendarID }, set: { updateList($0) })) {
                            Text(RemindersFacePresentation.allListsTitle).tag("")
                            ForEach(lists) { list in Text(list.title).tag(list.id) }
                        }
                        .labelsHidden().fixedSize().accessibilityLabel("List")
                    }
                    GroupedRow("Show") {
                        Picker("Layout", selection: Binding(get: { configuration.remindersLayout }, set: { updateLayout($0) })) {
                            ForEach(RemindersWidgetLayout.allCases) { layout in Text(layout.title).tag(layout) }
                        }
                        .labelsHidden().fixedSize().accessibilityLabel("Layout")
                    }
                }
                if let settingsError { WidgetPopoutCaption(settingsError, color: WidgetPalette.warning) }
            }
        }
        .widgetPopoutRefresh(WidgetPopoutRefresh(updatedAt: loadedAt, isRefreshing: isLoading, failed: errorMessage != nil, action: reload))
        // Structured: restarts once per list change (from here or the settings sheet) and once per coalesced
        // EventKit, activation or wake signal, and ends with the popout.
        .eventKitRefresh(scope: configuration.selectedReminderCalendarID) { await requestAndLoad() }
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

    /// The task's list key reloads after a list change; a rejected change keeps the list and says why.
    private func updateList(_ listID: String) {
        settingsError = WidgetConfigurationLookup.rejection(
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.selectedReminderCalendarID = listID })
    }

    private func updateLayout(_ layout: RemindersWidgetLayout) {
        settingsError = WidgetConfigurationLookup.rejection(
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.remindersLayout = layout })
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
        WidgetConfigurationLookup.current(store: store, itemID: item.id, profileID: profileID)
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
                lastCompletedAt = .now
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
