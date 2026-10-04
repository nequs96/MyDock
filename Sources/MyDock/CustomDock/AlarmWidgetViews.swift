import SwiftUI

struct AlarmWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AlarmCompactWidgetView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AlarmPopoutWidgetView(store: store, item: item, profileID: profileID))
    }
}

private struct AlarmCompactWidgetView: View {
    var item: DockItem
    @Environment(\.dockWidgetContentWidth) private var width

    private var alarms: [DockAlarm] { (item.widgetConfiguration ?? WidgetConfiguration()).alarms.filter(\.isEnabled) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 3) {
                WidgetHeader(kind: "Alarm", title: "Alarm")
                if let next = nextAlarm(from: alarms, now: context.date) {
                    MetricText(value: next.date.formatted(date: .omitted, time: .shortened), size: 18)
                    if width >= 100 { Text(next.alarm.title).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                } else { Text("No alarm").font(.system(size: 12)) }
            }.padding(.horizontal, 9).frame(width: width, height: 54)
        }
        .help("Alarm")
    }

    private func nextAlarm(from alarms: [DockAlarm], now: Date) -> (alarm: DockAlarm, date: Date)? {
        alarms.compactMap { alarm in
            AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute, repeatWeekdays: alarm.repeatWeekdays, now: now)
                .map { (alarm, $0) }
        }.min { $0.date < $1.date }
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
        VStack(alignment: .leading, spacing: 12) {
            Text(editingAlarmID == nil ? "Local alarms" : "Edit alarm").font(.headline)
            Text("Times follow this Mac’s current time zone. Once means the next occurrence of this time. Next time is calculated; notification delivery depends on macOS settings.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                DatePicker("Time", selection: $alarmTime, displayedComponents: .hourAndMinute)
                    .labelsHidden().disabled(isScheduling)
                TextField("Alarm name", text: $alarmTitle).disabled(isScheduling).textFieldStyle(DockTextFieldStyle())
            }
            HStack(spacing: 5) {
                Text("Repeat").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    let weekday = index + 1
                    Button(symbol.prefix(1)) {
                        if repeatWeekdays.contains(weekday) { repeatWeekdays.remove(weekday) }
                        else { repeatWeekdays.insert(weekday) }
                    }
                    .buttonStyle(.plain).disabled(isScheduling)
                    .font(.caption.weight(.semibold))
                    .frame(width: 23, height: 23)
                    .background(repeatWeekdays.contains(weekday) ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08), in: Circle())
                    .accessibilityLabel("Repeat on \(symbol)")
                    .accessibilityAddTraits(repeatWeekdays.contains(weekday) ? .isSelected : [])
                }
                if !repeatWeekdays.isEmpty {
                    Button("Once") { repeatWeekdays.removeAll() }.font(.caption).buttonStyle(.plain)
                }
                Spacer()
                Button(editingAlarmID == nil ? "Add Alarm" : "Save Changes", action: saveAlarm).buttonStyle(DockButtonStyle(primary: true)).disabled(isScheduling)
            }

            if editingAlarmID != nil {
                Button("Cancel Editing") { clearEditor() }.disabled(isScheduling)
            }
            if let operationMessage {
                Text(operationMessage).font(.caption).foregroundStyle(.secondary)
            }

            if alarms.isEmpty {
                Label("No alarms yet", systemImage: "alarm").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 70)
            } else {
                DockScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(alarms) { alarm in alarmRow(alarm) }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(width: 390).frame(minHeight: 180, alignment: .topLeading)
    }

    @ViewBuilder private func alarmRow(_ alarm: DockAlarm) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                    .font(.system(size: 21, weight: .medium, design: .rounded).monospacedDigit())
                Text(alarm.title + (alarm.repeatWeekdays.isEmpty ? " · Once" : " · " + weekdaySummary(alarm.repeatWeekdays)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if alarm.isEnabled, let date = AlarmSchedule.nextFireDate(hour: alarm.hour, minute: alarm.minute, repeatWeekdays: alarm.repeatWeekdays, now: context.date) {
                        Text("Next calculated time: " + date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    } else { Text("Off · no alert requested").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { alarm.isEnabled }, set: { enabled in changeEnabled(alarm, to: enabled) }))
                .labelsHidden().accessibilityLabel("Enable \(alarm.title)").disabled(busyAlarmIDs.contains(alarm.id) || isScheduling)
            Button { editAlarm(alarm) } label: { Image(systemName: "pencil") }
                .buttonStyle(.plain).accessibilityLabel("Edit \(alarm.title)")
                .disabled(isScheduling || busyAlarmIDs.contains(alarm.id))
            Button(role: .destructive) { removeAlarm(alarm) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).help("Remove alarm").disabled(isScheduling || busyAlarmIDs.contains(alarm.id))
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
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

    private func weekdaySummary(_ weekdays: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: " ")
    }
}
