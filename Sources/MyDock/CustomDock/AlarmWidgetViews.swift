import SwiftUI

struct AlarmWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AlarmCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AlarmPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

struct AlarmWeekdayChip: Identifiable, Equatable {
    var weekday: Int
    var letter: String
    var name: String
    var id: Int { weekday }
}

enum AlarmFacePresentation {
    /// The next armed alarm and when it fires. A one-time alarm rings at the time recorded when it was armed.
    static func next(_ alarms: [DockAlarm], now: Date) -> (alarm: DockAlarm, date: Date)? {
        alarms.filter { isArmed($0, now: now) }.compactMap { alarm -> (alarm: DockAlarm, date: Date)? in
            let recorded = alarm.repeatWeekdays.isEmpty ? alarm.scheduledFireDate : nil
            let date = recorded ?? AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute,
                                                              repeatWeekdays: alarm.repeatWeekdays, now: now)
            return date.map { (alarm: alarm, date: $0) }
        }.min { $0.date < $1.date }
    }

    /// On and not yet rung: a one-time alarm whose ring time has passed no longer counts as armed.
    static func isArmed(_ alarm: DockAlarm, now: Date) -> Bool { alarm.isEnabled && !alarm.hasRung(now: now) }

    /// "Today", "Tomorrow" or the weekday of the next firing.
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    static func repeatSummary(_ weekdays: [Int], symbols: [String] = Calendar.current.shortWeekdaySymbols,
                              firstWeekday: Int = Calendar.current.firstWeekday) -> String {
        guard !weekdays.isEmpty else { return "Once" }
        if Set(weekdays) == Set(1...7) { return "Every day" }
        let order = orderedWeekdays(firstWeekday: firstWeekday)
        return weekdays.sorted { (order.firstIndex(of: $0) ?? $0) < (order.firstIndex(of: $1) ?? $1) }
            .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: " ")
    }

    /// The stored weekdays (1 Sunday … 7 Saturday, as `Calendar` numbers them) in the order this Mac's week starts.
    static func orderedWeekdays(firstWeekday: Int = Calendar.current.firstWeekday) -> [Int] {
        let first = (1...7).contains(firstWeekday) ? firstWeekday : 1
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// The repeat chips: the calendar's very short symbol, as Clock shows it ("S M T W T F S"; one character per day
    /// in Chinese or Japanese, where a cut short name would repeat), the full name for VoiceOver, in the locale's
    /// week order. The stored value stays the Gregorian weekday number.
    static func weekdayChips(calendar: Calendar = .current) -> [AlarmWeekdayChip] {
        let letters = calendar.veryShortStandaloneWeekdaySymbols
        let names = calendar.standaloneWeekdaySymbols
        return orderedWeekdays(firstWeekday: calendar.firstWeekday).map { weekday in
            AlarmWeekdayChip(weekday: weekday,
                             letter: letters.indices.contains(weekday - 1) ? letters[weekday - 1] : "\(weekday)",
                             name: names.indices.contains(weekday - 1) ? names[weekday - 1] : "\(weekday)")
        }
    }

    /// The one alarm time format: this Mac's short time ("7:30 AM", "07:30"). The face, the popout
    /// hero and the alarm rows all use it, so one alarm never reads in two formats.
    static func timeText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale)
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// An alarm's wall-clock time in the same format, on a fixed reference day so no DST gap shifts it.
    static func timeText(hour: Int, minute: Int, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = calendar.date(from: DateComponents(year: 2001, month: 1, day: 15, hour: hour, minute: minute)) ?? .now
        return timeText(date, locale: locale, timeZone: timeZone)
    }

    /// The alarms listed under the popout hero: every alarm except the one the hero already shows.
    static func listed(_ alarms: [DockAlarm], excluding heroID: UUID?) -> [DockAlarm] {
        guard let heroID else { return alarms }
        return alarms.filter { $0.id != heroID }
    }
}

/// The Alarm module: the next alarm time as the value, its name (or "Alarm") as the label.
/// An armed alarm shows the filled glyph; with none armed the value reads "Off" in secondary.
struct AlarmDockFace: View {
    /// The next firing time already formatted for this Mac, or nil when no alarm is on.
    var time: String?
    var title: String?
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetShowsLabel) private var showsLabel
    private let kind = "Alarm"
    private var armed: Bool { time != nil }
    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                VStack(spacing: 2) {
                    WidgetIcon(kind: kind, symbol: armed ? "alarm.fill" : "alarm", size: 15, appearance: armed ? nil : .mono, enclosed: false, active: armed)
                    ModuleValue(value: time.map { ClockDockTextFormatter.text($0, narrow: true) } ?? "Off", size: .small,
                                color: armed ? .primary : .secondary, lineLimit: 2)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            } else {
                ModuleStack(kind: kind, label: label, value: time ?? "Off", size: armed ? .large : .medium,
                            valueColor: armed ? .primary : .secondary, symbol: armed ? "alarm.fill" : "alarm")
            }
        }
        .moduleInsets()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alarm")
        .accessibilityValue(time.map { "Next alarm " + $0 + (title.map { ", " + $0 } ?? "") } ?? "No alarm on")
    }
    private var label: String {
        guard armed, layout != .compact, let title, !title.isEmpty else { return "Alarm" }
        return title
    }
}

private struct AlarmCompactWidgetView: View {
    var item: DockItem
    @Environment(\.dockWidgetContentWidth) private var width

    private var alarms: [DockAlarm] { (item.widgetConfiguration ?? WidgetConfiguration()).alarms }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let next = AlarmFacePresentation.next(alarms, now: context.date)
            AlarmDockFace(time: next.map { AlarmFacePresentation.timeText($0.date) }, title: next?.alarm.title)
                .frame(width: width, height: 54)
        }
        .help("Alarm")
    }
}

/// Alarm copy: one short footer sentence; the detail lives in its tooltip.
enum AlarmCopy {
    static let editorFooter = "Alarms follow this Mac’s time zone."
    static let editorFooterHelp = "A one-time alarm rings at the next occurrence. Delivery depends on macOS notification settings."
    /// The most alarms one widget keeps, as ProfileSemanticValidator allows.
    static let capacity = 64
}

#if DEBUG
/// QA seam: the render export opens the first alarm's editor without a pointer click.
enum AlarmQAFixture {
    @MainActor static var editsFirstAlarm = false
}
#endif

private struct AlarmPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var alarmTime = Date.now
    @State private var alarmTitle = ""
    @State private var repeatWeekdays: Set<Int> = []
    @State private var operationMessage: String?
    /// The detail behind the one short result line, shown as its tooltip.
    @State private var operationDetail: String?
    @State private var removedAlarms: RemovedEntries<DockAlarm>?
    @State private var isScheduling = false
    @State private var busyAlarmIDs = Set<UUID>()
    @State private var editingAlarmID: UUID?
    /// The New Alarm form sits behind a final disclosure; it opens for editing and when there is no alarm yet.
    @State private var editorExpanded = false
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @Environment(\.widgetPopoutContext) private var context
    private var inSheet: Bool { WidgetPopoutContext.resolve(explicit: context, showsHero: showsHero) == .sheet }

    private var alarms: [DockAlarm] { store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id }?.widgetConfiguration?.alarms ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            TimelineView(.everyMinute) { context in
                let next = AlarmFacePresentation.next(alarms, now: context.date)
                // The hero shows the next alarm; the list below never repeats it. In the settings sheet the
                // hero is hidden, so every alarm is listed with its time.
                let heroAlarm = showsHero ? next?.alarm : nil
                let listed = AlarmFacePresentation.listed(alarms, excluding: heroAlarm?.id)
                VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
                    if let next {
                        WidgetPopoutHero(value: AlarmFacePresentation.timeText(next.date),
                                         caption: next.alarm.title + " · " + AlarmFacePresentation.day(next.date, now: context.date))
                    } else {
                        WidgetPopoutHero(value: "Off", caption: alarms.isEmpty ? "No alarms yet" : "No alarm is on", valueColor: .secondary)
                    }
                    if let heroAlarm {
                        GroupedSection { alarmRow(heroAlarm, showsTime: false, now: context.date) }
                    }
                    if !listed.isEmpty {
                        GroupedSection(heroAlarm == nil ? "Alarms" : "Other Alarms", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                            ForEach(listed) { alarm in alarmRow(alarm, showsTime: true, now: context.date) }
                        }
                    }
                }
            }
            WidgetPopoutSettingsDisclosure(editingAlarmID == nil ? "New Alarm" : "Edit Alarm", isExpanded: $editorExpanded) {
                editor
            }
            UndoNotice(pending: $removedAlarms, undo: restoreAlarms)
                .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            if let operationMessage { WidgetPopoutCaption(operationMessage).help(operationDetail ?? operationMessage) }
        }
        .onAppear {
            if alarms.isEmpty { editorExpanded = true }
            #if DEBUG
            if AlarmQAFixture.editsFirstAlarm, let first = alarms.first { editAlarm(first) }
            #endif
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            // In the Dock popout the disclosure names the form; in the settings sheet the section does.
            GroupedSection(inSheet ? (editingAlarmID == nil ? "New Alarm" : "Edit Alarm") : nil,
                           footer: AlarmCopy.editorFooter,
                           separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Time") {
                    DatePicker("Time", selection: $alarmTime, displayedComponents: .hourAndMinute)
                        .labelsHidden().disabled(isScheduling)
                }
                GroupedRow("Label") {
                    TextField("Alarm name", text: $alarmTitle).disabled(isScheduling)
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(maxWidth: 220)
                        .accessibilityLabel("Alarm name")
                }
                WidgetPopoutRow {
                    HStack(spacing: 5) {
                        Text("Repeat").font(DockDesign.Grouped.titleFont)
                        Spacer(minLength: 8)
                        ForEach(AlarmFacePresentation.weekdayChips()) { chip in
                            let weekday = chip.weekday
                            let selected = repeatWeekdays.contains(weekday)
                            Button(chip.letter) {
                                if selected { repeatWeekdays.remove(weekday) } else { repeatWeekdays.insert(weekday) }
                            }
                            .buttonStyle(.plain).disabled(isScheduling)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(width: 24, height: 24)
                            .background(selected ? DockDesign.accent : Color.primary.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                            .accessibilityLabel("Repeat on \(chip.name)")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                        Button("Once") { repeatWeekdays.removeAll() }
                            .buttonStyle(.borderless).controlSize(.small)
                            .help("Clear the repeat days: a one-time alarm rings at the next occurrence.")
                            .disabled(repeatWeekdays.isEmpty || isScheduling)
                    }
                }
            }
            .help(AlarmCopy.editorFooterHelp)
            HStack(spacing: 10) {
                if editingAlarmID != nil {
                    Button("Cancel Editing") { clearEditor() }.buttonStyle(WidgetRowTextButtonStyle()).disabled(isScheduling)
                }
                Spacer()
                PillButton(editingAlarmID == nil ? "Add Alarm" : "Save Changes", action: saveAlarm)
                    .disabled(isScheduling)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    /// One alarm: its time (in the shared format) over its name and repeat, then edit, remove and on/off.
    /// The row under the hero omits the time, which the hero already shows.
    @ViewBuilder private func alarmRow(_ alarm: DockAlarm, showsTime: Bool, now: Date) -> some View {
        // A one-time alarm that has rung reads as off; turning it on again arms its next occurrence.
        let armed = AlarmFacePresentation.isArmed(alarm, now: now)
        WidgetPopoutRow {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    if showsTime {
                        Text(AlarmFacePresentation.timeText(hour: alarm.hour, minute: alarm.minute))
                            .font(.system(size: 26, weight: .regular).monospacedDigit())
                            .foregroundStyle(armed ? .primary : .secondary)
                    }
                    let schedule = AlarmFacePresentation.repeatSummary(alarm.repeatWeekdays) + (armed ? "" : " · Off")
                    if showsTime {
                        // Two lines: the time, then name and schedule.
                        Text(alarm.title + " · " + schedule)
                            .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    } else {
                        Text(alarm.title).font(DockDesign.Grouped.titleFont).lineLimit(1)
                        Text(schedule).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 6)
                WidgetRowIconButton(symbol: "pencil", label: "Edit \(alarm.title)") { editAlarm(alarm) }
                    .disabled(isScheduling || busyAlarmIDs.contains(alarm.id))
                Button(role: .destructive) { removeAlarm(alarm) } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Remove alarm").accessibilityLabel("Remove \(alarm.title)")
                .disabled(isScheduling || busyAlarmIDs.contains(alarm.id))
                Toggle("Enabled", isOn: Binding(get: { armed }, set: { enabled in changeEnabled(alarm, to: enabled) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                    .accessibilityLabel("Enable \(alarm.title)").disabled(busyAlarmIDs.contains(alarm.id) || isScheduling)
            }
        }
    }

    private func editAlarm(_ alarm: DockAlarm) {
        editingAlarmID = alarm.id; alarmTitle = alarm.title; repeatWeekdays = Set(alarm.repeatWeekdays)
        editorExpanded = true
        alarmTime = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
        report(nil)
    }

    private func clearEditor() {
        editingAlarmID = nil; alarmTitle = ""; repeatWeekdays.removeAll()
    }

    private func saveAlarm() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        guard let hour = components.hour, let minute = components.minute else { return }
        guard let alarm = AlarmEditorCandidate.make(editingID: editingAlarmID, alarms: alarms, title: alarmTitle,
                                                   hour: hour, minute: minute, repeatWeekdays: repeatWeekdays)?.armed() else {
            report("This alarm was removed or its time is invalid. Your input is kept."); return
        }
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { configuration in
                if let index = configuration.alarms.firstIndex(where: { $0.id == alarm.id }) { configuration.alarms[index] = alarm }
                else { configuration.alarms.append(alarm) }
            }
        } catch {
            report("Couldn't save the alarm. Your input is kept.", detail: error.localizedDescription)
            return
        }
        if !alarm.isEnabled {
            AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
            clearEditor(); report("Saved. The alarm is off."); return
        }
        editingAlarmID = alarm.id
        isScheduling = true
        scheduleSavedAlarm(alarm, clearFormOnSuccess: true)
    }

    private func changeEnabled(_ alarm: DockAlarm, to enabled: Bool) {
        guard !busyAlarmIDs.contains(alarm.id), let current = alarms.first(where: { $0.id == alarm.id }) else { return }
        var candidate = current; candidate.isEnabled = enabled
        candidate = candidate.armed()
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { configuration in
                if let index = configuration.alarms.firstIndex(where: { $0.id == candidate.id }) { configuration.alarms[index] = candidate }
            }
        } catch { report("Couldn't save the change.", detail: error.localizedDescription); return }
        if enabled { scheduleSavedAlarm(candidate, clearFormOnSuccess: false) }
        else { AlarmNotificationService.cancel(widgetID: item.id, alarm: candidate); report("Alarm turned off.", detail: "Its alerts were cancelled.") }
    }

    private func scheduleSavedAlarm(_ alarm: DockAlarm, clearFormOnSuccess: Bool) {
        let operationID = UUID()
        AlarmNotificationService.begin(widgetID: item.id, alarmID: alarm.id, operationID: operationID)
        busyAlarmIDs.insert(alarm.id); report(nil)
        Task { @MainActor in
            defer { busyAlarmIDs.remove(alarm.id); if clearFormOnSuccess { isScheduling = false } }
            do {
                try await AlarmNotificationService.schedule(widgetID: item.id, alarm: alarm, operationID: operationID)
                guard AlarmNotificationService.isCurrent(widgetID: item.id, alarmID: alarm.id, operationID: operationID),
                      AlarmEditorCandidate.stillMatches(alarm, alarms: alarms) else {
                    AlarmNotificationService.cancelOperation(widgetID: item.id, alarmID: alarm.id, operationID: operationID); return
                }
                if clearFormOnSuccess { clearEditor() }
                report("Alarm set.", detail: "An alert was scheduled with macOS; delivery depends on notification settings.")
            } catch {
                guard AlarmNotificationService.isCurrent(widgetID: item.id, alarmID: alarm.id, operationID: operationID),
                      AlarmEditorCandidate.stillMatches(alarm, alarms: alarms) else {
                    AlarmNotificationService.cancelOperation(widgetID: item.id, alarmID: alarm.id, operationID: operationID); return
                }
                do {
                    try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { configuration in
                        if let index = configuration.alarms.firstIndex(where: { $0.id == alarm.id }) { configuration.alarms[index].isEnabled = false }
                    }
                    report("Couldn't schedule. Alarm turned off.", detail: error.localizedDescription + " Turn it on to try again.")
                } catch {
                    report("Couldn't schedule or save. Your input is kept.", detail: "Save again to retry. " + error.localizedDescription)
                }
                AlarmNotificationService.cancelOperation(widgetID: item.id, alarmID: alarm.id, operationID: operationID)
            }
        }
    }

    private func removeAlarm(_ alarm: DockAlarm) {
        let pending = RemovedEntries.capture([alarm.id], from: alarms, message: "Removed \(alarm.title).")
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { $0.alarms.removeAll { $0.id == alarm.id } }
            AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
            if editingAlarmID == alarm.id { clearEditor() }
            report(nil)
            removedAlarms = pending
        } catch { report("Couldn't remove the alarm. It is still saved.", detail: error.localizedDescription) }
    }

    /// Undo puts the alarm back where it was and schedules it again if it is still armed.
    /// Puts removed alarms back and re-arms the armed ones. False when nothing came back (a rejected write or a full
    /// list), so the undo notice says so.
    private func restoreAlarms(_ removed: RemovedEntries<DockAlarm>) -> Bool {
        var restoredCount = 0
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) {
                restoredCount = removed.restore(into: &$0.alarms, capacity: AlarmCopy.capacity)
            }
        } catch { report("Couldn't restore the alarm.", detail: error.localizedDescription); return false }
        for slot in removed.slots where AlarmFacePresentation.isArmed(slot.entry, now: .now) {
            guard let restored = alarms.first(where: { $0.id == slot.entry.id }) else { continue }
            scheduleSavedAlarm(restored, clearFormOnSuccess: false)
        }
        return restoredCount > 0
    }

    private func report(_ message: String?, detail: String? = nil) {
        operationMessage = message
        operationDetail = detail
    }
}
