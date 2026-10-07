import AppKit
import SwiftUI

/// An app a rule can name: installed or currently running.
struct AutomaticSwitchAppOption: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
}

enum AutomaticSwitchAppOptions {
    /// Union by bundle identifier (case-insensitive), sorted by name. Running apps win name ties.
    static func merge(running: [AutomaticSwitchAppOption], installed: [AutomaticSwitchAppOption]) -> [AutomaticSwitchAppOption] {
        var seen = Set<String>()
        var merged: [AutomaticSwitchAppOption] = []
        for option in running + installed where !option.id.isEmpty && seen.insert(option.id.lowercased()).inserted {
            merged.append(option)
        }
        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func load() async -> [AutomaticSwitchAppOption] {
        var running: [AutomaticSwitchAppOption] = []
        if AppRuntimeEnvironment.allowsNativeEffects {
            running = NSWorkspace.shared.runningApplications.compactMap { application in
                guard application.activationPolicy == .regular, !application.isTerminated,
                      let identifier = application.bundleIdentifier, identifier != Bundle.main.bundleIdentifier,
                      let name = application.localizedName, !name.isEmpty else { return nil }
                return AutomaticSwitchAppOption(id: identifier, name: name)
            }
        }
        let scan = await InstalledAppCatalog.scan()
        let installed = scan.applications
            .filter { $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .map { AutomaticSwitchAppOption(id: $0.bundleIdentifier, name: $0.name) }
        return merge(running: running, installed: installed)
    }
}

/// Settings → Dock Setup → Automatic switching. Off by default; two rule kinds only.
struct AutomaticSwitchingSettingsSection: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject var status = AutomaticSwitchingStatus.shared
    @State private var expandedRuleID: UUID?
    /// The last deleted rule and its priority, until it is restored or another rule is deleted.
    @State private var removedRule: RemovedRule?

    private struct RemovedRule {
        var rule: AutomaticSwitchRule
        var index: Int
    }

    private var automatic: AutomaticSwitchingSettings { store.state.settings.automaticSwitching }

    private var footer: String? {
        guard automatic.isEnabled else { return nil }
        return status.settingsLine ?? "Rules are checked from the top. The first match wins."
    }

    var body: some View {
        GroupedSection("Automatic switching", footer: footer) {
            GroupedRow("Switch Custom Docks automatically",
                       subtitle: "By frontmost app or time of day. The macOS Dock is never changed.",
                       symbol: "arrow.left.arrow.right", isOn: Binding(
                get: { automatic.isEnabled },
                set: { enabled in store.updateSettings { $0.automaticSwitching.isEnabled = enabled } }
            ))
            if automatic.isEnabled {
                ForEach(automatic.rules) { rule in
                    AutomaticSwitchRuleRow(
                        store: store,
                        rule: rule,
                        index: automatic.rules.firstIndex(where: { $0.id == rule.id }) ?? 0,
                        count: automatic.rules.count,
                        expandedRuleID: $expandedRuleID,
                        onDelete: { deleteRule(rule.id) })
                }
                if removedRule != nil, automatic.canAddRule {
                    GroupedRow("Undo Delete", role: .button) { undoDelete() }
                }
                GroupedRow("Rules", subtitle: store.customProfiles.isEmpty ? "Create a Custom Dock to add a rule." : nil, accessory: {
                    Menu {
                        Button("When an app is frontmost") { addRule(.appFrontmost) }
                        Button("During a time window") { addRule(.timeWindow) }
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(store.customProfiles.isEmpty || !automatic.canAddRule)
                    .accessibilityLabel("Add rule")
                })
            }
        }
    }

    private func deleteRule(_ id: UUID) {
        guard let index = automatic.rules.firstIndex(where: { $0.id == id }) else { return }
        removedRule = RemovedRule(rule: automatic.rules[index], index: index)
        store.updateSettings { $0.automaticSwitching.removeRule(id) }
    }

    private func undoDelete() {
        guard let removed = removedRule else { return }
        removedRule = nil
        store.updateSettings { $0.automaticSwitching.restoreRule(removed.rule, at: removed.index) }
    }

    private func addRule(_ kind: AutomaticSwitchRule.Kind) {
        var newID: UUID?
        let defaultProfile = store.state.settings.activeCustomProfileID ?? store.customProfiles.first?.id
        store.updateSettings { newID = $0.automaticSwitching.addRule(kind, defaultProfileID: defaultProfile) }
        expandedRuleID = newID
    }
}

private struct AutomaticSwitchRuleRow: View {
    @ObservedObject var store: ProfileStore
    var rule: AutomaticSwitchRule
    var index: Int
    var count: Int
    @Binding var expandedRuleID: UUID?
    var onDelete: () -> Void
    @State private var apps: [AutomaticSwitchAppOption] = []
    @DockAccessibilityStyle() private var accessibility

    private var isExpanded: Bool { expandedRuleID == rule.id }
    private var customProfileIDs: Set<UUID> { Set(store.customProfiles.map(\.id)) }
    private var dockName: String? { store.customProfiles.first { $0.id == rule.profileID }?.name }
    private var isMissing: Bool { AutomaticSwitchEvaluator.isDockMissing(rule, customProfileIDs: customProfileIDs) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(AutomaticSwitchRuleText.summary(rule, dockName: dockName))
                        .font(DockDesign.Grouped.titleFont)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if isMissing {
                        Label("Dock missing. This rule is skipped.", systemImage: "exclamationmark.triangle.fill")
                            .font(DockDesign.Grouped.subtitleFont)
                            .foregroundStyle(.orange)
                    }
                    if let problem = AutomaticSwitchRuleText.problem(rule) {
                        Text(problem).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                iconButton("chevron.up", label: "Move rule up", disabled: index == 0) { move(-1) }
                iconButton("chevron.down", label: "Move rule down", disabled: index >= count - 1) { move(1) }
                iconButton(isExpanded ? "checkmark" : "pencil", label: isExpanded ? "Done editing rule" : "Edit rule", disabled: false) {
                    withAnimation(accessibility.animation(DockDesign.Motion.disclosure)) {
                        expandedRuleID = isExpanded ? nil : rule.id
                    }
                }
                iconButton("trash", label: "Delete rule", disabled: false) { delete() }
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
            .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
            if isExpanded { editor }
        }
        .accessibilityElement(children: .contain)
        .task(id: isExpanded) {
            guard isExpanded, rule.kind == .appFrontmost, apps.isEmpty else { return }
            apps = await AutomaticSwitchAppOptions.load()
        }
    }

    private func iconButton(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch rule.kind {
            case .appFrontmost:
                SettingsControlRow(title: "App") {
                    Picker("App", selection: Binding(
                        get: { rule.bundleIdentifier ?? "" },
                        set: { identifier in
                            let name = apps.first { $0.id == identifier }?.name
                            update { $0.bundleIdentifier = identifier.isEmpty ? nil : identifier; $0.appName = name }
                        }
                    )) {
                        Text("Choose an app").tag("")
                        ForEach(appChoices) { Text($0.name).tag($0.id) }
                    }
                }
            case .timeWindow:
                GroupedRow("Days", accessory: {
                    HStack(spacing: 4) {
                        ForEach(orderedWeekdays, id: \.self) { weekday in
                            Toggle(shortName(weekday), isOn: Binding(
                                get: { rule.weekdays.contains(weekday) },
                                set: { enabled in
                                    update { rule in
                                        if enabled { rule.weekdays.append(weekday) } else { rule.weekdays.removeAll { $0 == weekday } }
                                    }
                                }
                            ))
                            .toggleStyle(.button)
                            .controlSize(.small)
                            .accessibilityLabel(fullName(weekday))
                        }
                    }
                })
                SettingsControlRow(title: "From") {
                    DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                }
                SettingsControlRow(title: "Until") {
                    DatePicker("Until", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                }
            }
            SettingsControlRow(title: "Dock") {
                Picker("Dock", selection: Binding(
                    get: { rule.profileID },
                    set: { id in update { $0.profileID = id } }
                )) {
                    Text("Choose a Dock").tag(Optional<UUID>.none)
                    ForEach(store.customProfiles) { Text($0.name).tag(Optional($0.id)) }
                    if let id = rule.profileID, !customProfileIDs.contains(id) {
                        Text("Dock missing").tag(Optional(id))
                    }
                }
            }
        }
        .padding(.bottom, DockDesign.Grouped.rowVerticalPadding)
    }

    private var appChoices: [AutomaticSwitchAppOption] {
        guard let identifier = rule.bundleIdentifier, !apps.contains(where: { $0.id == identifier }) else { return apps }
        return apps + [AutomaticSwitchAppOption(id: identifier, name: AutomaticSwitchRuleText.appName(rule))]
    }

    private var calendar: Calendar { .current }

    private var orderedWeekdays: [Int] {
        let first = max(1, min(calendar.firstWeekday, 7))
        return (0..<7).map { ((first - 1 + $0) % 7) + 1 }
    }

    private func shortName(_ weekday: Int) -> String {
        let symbols = calendar.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
    }

    private func fullName(_ weekday: Int) -> String {
        let symbols = calendar.weekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "\(weekday)"
    }

    /// Minutes since midnight as a `Date` on a fixed reference day, so a DST gap today never shifts the picker.
    private func minuteBinding(_ keyPath: WritableKeyPath<AutomaticSwitchRule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = rule[keyPath: keyPath]
                return calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: minute / 60, minute: minute % 60)) ?? Date()
            },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                update { $0[keyPath: keyPath] = minute }
            }
        )
    }

    private func update(_ change: @escaping (inout AutomaticSwitchRule) -> Void) {
        let id = rule.id
        store.updateSettings { $0.automaticSwitching.updateRule(id, change) }
    }

    private func move(_ offset: Int) {
        let id = rule.id
        store.updateSettings { $0.automaticSwitching.moveRule(id, by: offset) }
    }

    /// The section removes the rule so it can offer Undo Delete.
    private func delete() {
        if expandedRuleID == rule.id { expandedRuleID = nil }
        onDelete()
    }
}
