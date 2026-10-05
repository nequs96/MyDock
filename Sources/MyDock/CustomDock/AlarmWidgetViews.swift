import SwiftUI

struct AlarmWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AlarmCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AlarmPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

enum AlarmFacePresentation {
    /// The next enabled alarm and when it fires.
    static func next(_ alarms: [DockAlarm], now: Date) -> (alarm: DockAlarm, date: Date)? {
        alarms.filter(\.isEnabled).compactMap { alarm in
            AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute, repeatWeekdays: alarm.repeatWeekdays, now: now)
                .map { (alarm, $0) }
        }.min { $0.date < $1.date }
    }

    /// "Today", "Tomorrow" or the weekday of the next firing.
    static func day(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    static func repeatSummary(_ weekdays: [Int], symbols: [String] = Calendar.current.shortWeekdaySymbols) -> String {
        guard !weekdays.isEmpty else { return "Once" }
        if Set(weekdays) == Set(1...7) { return "Every day" }
        return weekdays.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: " ")
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
                    WidgetIcon(kind: kind, symbol: armed ? "alarm.fill" : "alarm", size: 15, appearance: armed ? nil : .mono, enclosed: false)
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let next = AlarmFacePresentation.next(alarms, now: context.date)
            AlarmDockFace(time: next?.date.formatted(date: .omitted, time: .shortened), title: next?.alarm.title)
                .frame(width: width, height: 54)
        }
        .help("Alarm")
    }
}

private struct AlarmPopoutWidgetView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var alarmTime = Date.now
    @State private var alarmTitle = ""
    @State private var repeatWeekdays: Set<Int> = []
    @State private var operationMessage: String?
    @State private var isScheduling = false
    @State private var busyAlarmIDs = Set<UUID>()
    @State private var editingAlarmID: UUID?

    private var alarms: [DockAlarm] { store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id }?.widgetConfiguration?.alarms ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let next = AlarmFacePresentation.next(alarms, now: context.date) {
                    WidgetPopoutHero(value: next.date.formatted(date: .omitted, time: .shortened),
                                     caption: next.alarm.title + " · " + AlarmFacePresentation.day(next.date, now: context.date))
                } else {
                    WidgetPopoutHero(value: "Off", caption: alarms.isEmpty ? "No alarms yet" : "No alarm is on", valueColor: .secondary)
                }
            }
            if !alarms.isEmpty {
                GroupedSection("Alarms", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    ForEach(alarms) { alarm in alarmRow(alarm) }
                }
            }
            editor
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedSection(editingAlarmID == nil ? "New Alarm" : "Edit Alarm",
                           footer: "Once rings at the next occurrence. Times follow this Mac’s time zone; delivery depends on macOS notification settings.",
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
                        ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                            let weekday = index + 1
                            let selected = repeatWeekdays.contains(weekday)
                            Button(String(symbol.prefix(1))) {
                                if selected { repeatWeekdays.remove(weekday) } else { repeatWeekdays.insert(weekday) }
                            }
                            .buttonStyle(.plain).disabled(isScheduling)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .frame(width: 24, height: 24)
                            .background(selected ? DockDesign.accent : Color.primary.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                            .accessibilityLabel("Repeat on \(symbol)")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                        Button("Once") { repeatWeekdays.removeAll() }
                            .buttonStyle(.borderless).controlSize(.small)
                            .disabled(repeatWeekdays.isEmpty || isScheduling)
                    }
                }
            }
            HStack(spacing: 10) {
                if editingAlarmID != nil {
                    Button("Cancel Editing") { clearEditor() }.buttonStyle(GalleryGlassButtonStyle()).disabled(isScheduling)
                }
                Spacer()
                PillButton(editingAlarmID == nil ? "Add Alarm" : "Save Changes", action: saveAlarm)
                    .disabled(isScheduling)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if let operationMessage { WidgetPopoutCaption(operationMessage) }
        }
    }

    @ViewBuilder private func alarmRow(_ alarm: DockAlarm) -> some View {
        WidgetPopoutRow {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                        .font(.system(size: 26, weight: .regular).monospacedDigit())
                        .foregroundStyle(alarm.isEnabled ? .primary : .secondary)
                    Text(alarm.title + " · " + AlarmFacePresentation.repeatSummary(alarm.repeatWeekdays))
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if alarm.isEnabled, let date = AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute, repeatWeekdays: alarm.repeatWeekdays, now: context.date) {
                            Text("Next: " + date.formatted(date: .abbreviated, time: .shortened))
                                .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                        } else { Text("Off · no alert requested").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 6)
                WidgetRowIconButton(symbol: "pencil", label: "Edit \(alarm.title)") { editAlarm(alarm) }
                    .disabled(isScheduling || busyAlarmIDs.contains(alarm.id))
                Button(role: .destructive) { removeAlarm(alarm) } label: {
                    Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Remove alarm").accessibilityLabel("Remove \(alarm.title)")
                .disabled(isScheduling || busyAlarmIDs.contains(alarm.id))
                Toggle("Enabled", isOn: Binding(get: { alarm.isEnabled }, set: { enabled in changeEnabled(alarm, to: enabled) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small).fixedSize()
                    .accessibilityLabel("Enable \(alarm.title)").disabled(busyAlarmIDs.contains(alarm.id) || isScheduling)
            }
        }
    }

    private func editAlarm(_ alarm: DockAlarm) {
        editingAlarmID = alarm.id; alarmTitle = alarm.title; repeatWeekdays = Set(alarm.repeatWeekdays)
        alarmTime = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
        operationMessage = nil
    }

    private func clearEditor() {
        editingAlarmID = nil; alarmTitle = ""; repeatWeekdays.removeAll()
    }

    private func saveAlarm() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        guard let hour = components.hour, let minute = components.minute else { return }
        guard let alarm = AlarmEditorCandidate.make(editingID: editingAlarmID, alarms: alarms, title: alarmTitle,
                                                   hour: hour, minute: minute, repeatWeekdays: repeatWeekdays) else {
            operationMessage = "This alarm was removed or its time is invalid. Your input is still here."; return
        }
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { configuration in
                if let index = configuration.alarms.firstIndex(where: { $0.id == alarm.id }) { configuration.alarms[index] = alarm }
                else { configuration.alarms.append(alarm) }
            }
        } catch {
            operationMessage = "Could not save the alarm. Your input is still here. " + error.localizedDescription
            return
        }
        if !alarm.isEnabled {
            AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
            clearEditor(); operationMessage = "Changes saved. The alarm remains off."; return
        }
        editingAlarmID = alarm.id
        isScheduling = true
        scheduleSavedAlarm(alarm, clearFormOnSuccess: true)
    }

    private func changeEnabled(_ alarm: DockAlarm, to enabled: Bool) {
        guard !busyAlarmIDs.contains(alarm.id), let current = alarms.first(where: { $0.id == alarm.id }) else { return }
        var candidate = current; candidate.isEnabled = enabled
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { configuration in
                if let index = configuration.alarms.firstIndex(where: { $0.id == candidate.id }) { configuration.alarms[index] = candidate }
            }
        } catch { operationMessage = "Could not save the alarm change. " + error.localizedDescription; return }
        if enabled { scheduleSavedAlarm(candidate, clearFormOnSuccess: false) }
        else { AlarmNotificationService.cancel(widgetID: item.id, alarm: candidate); operationMessage = "Alarm turned off. Its alerts were cancelled." }
    }

    private func scheduleSavedAlarm(_ alarm: DockAlarm, clearFormOnSuccess: Bool) {
        let operationID = UUID()
        AlarmNotificationService.begin(widgetID: item.id, alarmID: alarm.id, operationID: operationID)
        busyAlarmIDs.insert(alarm.id); operationMessage = nil
        Task { @MainActor in
            defer { busyAlarmIDs.remove(alarm.id); if clearFormOnSuccess { isScheduling = false } }
            do {
                try await AlarmNotificationService.schedule(widgetID: item.id, alarm: alarm, operationID: operationID)
                guard AlarmNotificationService.isCurrent(widgetID: item.id, alarmID: alarm.id, operationID: operationID),
                      AlarmEditorCandidate.stillMatches(alarm, alarms: alarms) else {
                    AlarmNotificationService.cancelOperation(widgetID: item.id, alarmID: alarm.id, operationID: operationID); return
                }
                if clearFormOnSuccess { clearEditor() }
                operationMessage = "Alarm saved. An alert was scheduled with macOS; delivery depends on notification settings."
            } catch {
                guard AlarmNotificationService.isCurrent(widgetID: item.id, alarmID: alarm.id, operationID: operationID),
                      AlarmEditorCandidate.stillMatches(alarm, alarms: alarms) else {
                    AlarmNotificationService.cancelOperation(widgetID: item.id, alarmID: alarm.id, operationID: operationID); return
                }
                do {
                    try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { configuration in
                        if let index = configuration.alarms.firstIndex(where: { $0.id == alarm.id }) { configuration.alarms[index].isEnabled = false }
                    }
                    operationMessage = error.localizedDescription + " The alarm was saved turned off. Enable it to try scheduling again."
                } catch {
                    operationMessage = "No alert was scheduled, and the off state could not be saved. Your input is retained. Retry Save. " + error.localizedDescription
                }
                AlarmNotificationService.cancelOperation(widgetID: item.id, alarmID: alarm.id, operationID: operationID)
            }
        }
    }

    private func removeAlarm(_ alarm: DockAlarm) {
        do {
            try store.updateWidgetConfigurationAndPersist(itemID: item.id, in: profileID) { $0.alarms.removeAll { $0.id == alarm.id } }
            AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
            if editingAlarmID == alarm.id { clearEditor() }
            operationMessage = "Alarm removed. Its alerts were cancelled."
        } catch { operationMessage = "Could not remove the alarm. It is still saved. " + error.localizedDescription }
    }
}
