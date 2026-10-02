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

    private var alarms: [DockAlarm] { item.widgetConfiguration?.alarms ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local alarms").font(.headline)
            HStack {
                DatePicker("Time", selection: $alarmTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                TextField("Alarm name", text: $alarmTitle).textFieldStyle(DockTextFieldStyle())
            }
            HStack(spacing: 5) {
                Text("Repeat").font(.caption).foregroundStyle(.secondary)
                ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    let weekday = index + 1
                    Button(symbol.prefix(1)) {
                        if repeatWeekdays.contains(weekday) { repeatWeekdays.remove(weekday) }
                        else { repeatWeekdays.insert(weekday) }
                    }
                    .buttonStyle(.plain)
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
                Button("Add Alarm", action: addAlarm).buttonStyle(DockButtonStyle(primary: true)).disabled(isScheduling)
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
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { alarm.isEnabled }, set: { enabled in changeEnabled(alarm, to: enabled) }))
                .labelsHidden().disabled(busyAlarmIDs.contains(alarm.id))
            Button(role: .destructive) { removeAlarm(alarm) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).help("Remove alarm")
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private func addAlarm() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        guard let hour = components.hour, let minute = components.minute else { return }
        let trimmedTitle = alarmTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let alarm = DockAlarm(title: trimmedTitle.isEmpty ? "Alarm" : trimmedTitle,
                              hour: hour,
                              minute: minute,
                              repeatWeekdays: repeatWeekdays.sorted(),
                              isEnabled: true)
        let operationID = UUID()
        AlarmNotificationService.begin(widgetID: item.id, alarmID: alarm.id, operationID: operationID)
        isScheduling = true
        operationMessage = nil
        Task { @MainActor in
            defer { isScheduling = false }
            do {
                try await AlarmNotificationService.schedule(widgetID: item.id, alarm: alarm, operationID: operationID)
                guard AlarmNotificationService.isCurrent(widgetID: item.id,
                                                         alarmID: alarm.id,
                                                         operationID: operationID) else { return }
                update { $0.alarms.append(alarm) }
                alarmTitle = ""
                repeatWeekdays.removeAll()
                operationMessage = "Alarm scheduled. macOS will deliver it even when MyDock is closed."
            } catch {
                guard AlarmNotificationService.isCurrent(widgetID: item.id,
                                                         alarmID: alarm.id,
                                                         operationID: operationID) else { return }
                var disabled = alarm
                disabled.isEnabled = false
                update { $0.alarms.append(disabled) }
                operationMessage = error.localizedDescription + " The alarm was saved turned off."
            }
        }
    }

    private func changeEnabled(_ alarm: DockAlarm, to enabled: Bool) {
        guard !busyAlarmIDs.contains(alarm.id) else { return }
        busyAlarmIDs.insert(alarm.id)
        operationMessage = nil
        let operationID = UUID()
        if enabled {
            AlarmNotificationService.begin(widgetID: item.id, alarmID: alarm.id, operationID: operationID)
        } else {
            AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
        }
        Task { @MainActor in
            defer { busyAlarmIDs.remove(alarm.id) }
            if enabled {
                var active = alarm
                active.isEnabled = true
                do {
                    try await AlarmNotificationService.schedule(widgetID: item.id,
                                                                alarm: active,
                                                                operationID: operationID)
                    guard AlarmNotificationService.isCurrent(widgetID: item.id,
                                                             alarmID: alarm.id,
                                                             operationID: operationID) else { return }
                    setAlarmState(alarm.id, enabled: true)
                } catch {
                    guard AlarmNotificationService.isCurrent(widgetID: item.id,
                                                             alarmID: alarm.id,
                                                             operationID: operationID) else { return }
                    operationMessage = error.localizedDescription
                    setAlarmState(alarm.id, enabled: false)
                }
            } else {
                setAlarmState(alarm.id, enabled: false)
            }
        }
    }

    private func setAlarmState(_ id: UUID, enabled: Bool) {
        update { configuration in
            guard let index = configuration.alarms.firstIndex(where: { $0.id == id }) else { return }
            configuration.alarms[index].isEnabled = enabled
        }
    }

    private func removeAlarm(_ alarm: DockAlarm) {
        AlarmNotificationService.cancel(widgetID: item.id, alarm: alarm)
        update { $0.alarms.removeAll { $0.id == alarm.id } }
    }

    private func update(_ change: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: change)
    }

    private func weekdaySummary(_ weekdays: [Int]) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: " ")
    }
}
