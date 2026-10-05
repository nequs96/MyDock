import AppKit
import SwiftUI

struct DiskSpaceSnapshot: Equatable, Sendable {
    var name: String
    var totalBytes: Int64
    var availableBytes: Int64
    var usedFraction: Double { totalBytes > 0 ? Double(totalBytes - min(totalBytes, max(0, availableBytes))) / Double(totalBytes) : 0 }
    var availableText: String { ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file) }
    var totalText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
    /// The low-space state: more than 90% used. Faces and popouts colour only this state.
    var isLow: Bool { usedFraction > 0.9 }
    static func read() -> Self? {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0, let available = values.volumeAvailableCapacity else { return nil }
        return Self(name: values.volumeLocalizedName ?? "Startup disk", totalBytes: Int64(total), availableBytes: Int64(max(0, available)))
    }
}

// MARK: - Popout vocabulary shared by the RD-09 families

/// A grouped-section header with an optional trailing control (Refresh, Clear…), aligned with
/// `GroupedSection` headers. Use it above a header-less `GroupedSection` in a 6 pt stack.
struct WidgetPopoutSectionHeader<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing
    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(DockDesign.Grouped.headerFont).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing.buttonStyle(.borderless).controlSize(.small).font(.system(size: 12))
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
    }
}
extension WidgetPopoutSectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title) { EmptyView() } }
}

/// A free-form row inside a `GroupedSection`, with the grouped row metrics.
struct WidgetPopoutRow<Content: View>: View {
    var verticalPadding: CGFloat = DockDesign.Grouped.rowVerticalPadding
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
    }
}

/// A short note under grouped content: secondary, footer-sized, wrapping.
struct WidgetPopoutCaption: View {
    var text: String
    var color: Color = .secondary
    init(_ text: String, color: Color = .secondary) { self.text = text; self.color = color }
    var body: some View {
        Text(text).font(DockDesign.Grouped.footerFont).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
    }
}

/// A small borderless icon action inside a grouped row (copy, edit, remove).
struct WidgetRowIconButton: View {
    var symbol: String
    var label: String
    var tint: Color = .secondary
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// A calm drop or empty area: one rounded surface in the grouped fill, a dashed accent edge while targeted.
struct WidgetPopoutDropArea<Content: View>: View {
    var targeted = false
    var minHeight: CGFloat = 96
    @ViewBuilder var content: Content
    @DockAccessibilityStyle() private var accessibility
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DockDesign.Grouped.radius, style: .continuous) }
    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(targeted ? AnyShapeStyle(DockDesign.accent.opacity(0.12)) : AnyShapeStyle(DockDesign.Grouped.fill), in: shape)
            .overlay {
                if targeted {
                    shape.strokeBorder(DockDesign.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                } else if accessibility.contrast == .increased {
                    shape.strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                }
            }
    }
}

/// Opens a System Settings privacy pane; disabled in isolated validation.
enum WidgetPrivacySettings {
    static let calendars = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
    static let reminders = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
    static let automation = "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
    static func open(_ address: String) {
        guard AppRuntimeEnvironment.allowsNativeEffects, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Disk Space

struct DiskSpaceWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(DiskSpaceView(compact: true)) }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(DiskSpaceView()) }
}

private struct DiskSpaceView: View {
    var compact = false
    @State private var snapshot: DiskSpaceSnapshot?
    @State private var sampledAt: Date?
    @State private var refreshFailed = false
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        Group {
            if compact {
                DiskDockFace(snapshot: snapshot).frame(width: width, height: 54)
            } else {
                DiskSpacePopoutContent(snapshot: snapshot, sampledAt: sampledAt, refreshFailed: refreshFailed) {
                    Task { await refresh() }
                }
            }
        }
        .task {
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: 60) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }
    private func refresh() async {
        let reading = await Task.detached(priority: .utility) { DiskSpaceSnapshot.read() }.value
        guard !Task.isCancelled else { return }
        if let reading { snapshot = reading; sampledAt = .now; refreshFailed = false }
        else { refreshFailed = true }
    }
}

/// Disk popout content: the free space as the one large value, a single-weight usage line, then details.
struct DiskSpacePopoutContent: View {
    var snapshot: DiskSpaceSnapshot?
    var sampledAt: Date?
    var refreshFailed: Bool
    var refresh: () -> Void
    private var stateColor: Color { snapshot?.isLow == true ? WidgetPalette.warning : .primary }
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            VStack(spacing: 10) {
                WidgetPopoutHero(value: snapshot?.availableText ?? "—",
                                 caption: snapshot.map { "available on \($0.name)" } ?? "Disk reading unavailable",
                                 valueColor: stateColor)
                if let snapshot {
                    DiskUsageLine(fraction: snapshot.usedFraction, color: snapshot.isLow ? WidgetPalette.warning : WidgetPalette.accent("Disk Space"))
                        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                WidgetPopoutSectionHeader("Startup Disk") { Button("Refresh", action: refresh) }
                GroupedSection(footer: footer, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    if let snapshot {
                        GroupedRow("Used", value: "\(Int((snapshot.usedFraction * 100).rounded()))%")
                        GroupedRow("Capacity", value: snapshot.totalText)
                    } else {
                        GroupedRow("No reading yet", subtitle: "Try refreshing.")
                    }
                }
            }
        }
    }
    private var footer: String {
        let cadence = refreshFailed ? "Refresh failed. The last successful reading is kept." : "Samples the volume with your home folder every minute while open."
        guard let sampledAt else { return cadence }
        return WidgetTimingPresentation.readingStatus(fetchedAt: sampledAt, now: .now, maximumAge: 120) + ". " + cadence
    }
}

/// A single-weight usage line, thicker than the Dock meter so it reads at popout scale.
private struct DiskUsageLine: View {
    var fraction: Double
    var color: Color
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(Color.primary.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geometry.size.width * (fraction.isFinite ? min(1, max(0, fraction)) : 0))
                }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Calculator

struct CalculatorWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(QuickCalculatorView()) }
}

struct QuickCalculatorView: View {
    @State private var expression = ""
    @State private var message: String?
    @State private var history: [String] = []
    @FocusState private var expressionFocused: Bool
    private var result: Double? { try? QuickCalculator.calculate(expression) }
    private var resultText: String { result.map { $0.formatted(.number.precision(.significantDigits(1...12))) } ?? "—" }
    private let keys = ["C", "(", ")", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", ".", "%", "="]
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            VStack(alignment: .trailing, spacing: 8) {
                TextField("e.g. (120 + 35) × 2", text: Binding(get: { expression }, set: { expression = String($0.prefix(256)); message = nil }))
                    .onSubmit(calculate).focused($expressionFocused).accessibilityLabel("Calculation expression")
                HStack(alignment: .center, spacing: 10) {
                    Button { message = copyUtilityText(resultText) ? "Result copied. Paste with ⌘V." : utilityCopyFailureMessage } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(WidgetCircleButtonStyle())
                        .disabled(result == nil).accessibilityLabel("Copy result").help("Copy result")
                    Spacer(minLength: 8)
                    Text(expression.isEmpty ? "0" : resultText)
                        .font(.system(size: 40, weight: .semibold).monospacedDigit())
                        .foregroundStyle(result == nil ? .secondary : .primary)
                        .lineLimit(1).minimumScaleFactor(0.45)
                        .accessibilityLabel("Result")
                        .accessibilityValue(resultText)
                }
                if let message { WidgetPopoutCaption(message) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { enter(key) } label: { Text(key) }
                        .buttonStyle(CalculatorKeyStyle(role: CalculatorKeyStyle.Role(key)))
                        .accessibilityLabel(key == "C" ? "Clear expression" : key == "=" ? "Calculate" : key)
                }
            }
            if !history.isEmpty {
                GroupedSection("This Session", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                        WidgetPopoutRow {
                            Text(value).font(DockDesign.Grouped.titleFont).monospacedDigit().textSelection(.enabled).lineLimit(2)
                        }
                    }
                }
            }
            WidgetPopoutCaption("Press Return to calculate. Percent divides by 100: 200 × 15% = 30. Clears when this popout closes.")
        }
        .onAppear { expressionFocused = true }
    }
    private func calculate() {
        do {
            _ = try QuickCalculator.calculate(expression)
            history.insert("\(expression) = \(resultText)", at: 0)
            history = Array(history.prefix(3)); message = nil
        } catch { message = error.localizedDescription }
    }
    private func enter(_ key: String) {
        if key == "C" { expression = ""; message = nil }
        else if key == "=" { calculate() }
        else { expression = String((expression + key).prefix(256)); message = nil }
    }
}

/// Calculator keys: quiet digits, slightly stronger functions, accent operators and a filled equals key.
struct CalculatorKeyStyle: ButtonStyle {
    enum Role {
        case digit, function, operation, equals
        init(_ key: String) {
            switch key {
            case "=": self = .equals
            case "÷", "×", "−", "+": self = .operation
            case "C", "(", ")", "%": self = .function
            default: self = .digit
            }
        }
    }
    var role: Role
    func makeBody(configuration: Configuration) -> some View { KeyBody(configuration: configuration, role: role) }
    private struct KeyBody: View {
        let configuration: ButtonStyle.Configuration
        var role: Role
        @Environment(\.isEnabled) private var isEnabled
        @DockAccessibilityStyle() private var accessibility
        @State private var hovered = false
        private var fill: Color {
            switch role {
            case .digit: Color.primary.opacity(0.07)
            case .function: Color.primary.opacity(0.13)
            case .operation: DockDesign.accent.opacity(0.18)
            case .equals: DockDesign.accent
            }
        }
        private var foreground: Color {
            switch role {
            case .digit, .function: .primary
            case .operation: DockDesign.accent
            case .equals: .white
            }
        }
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            configuration.label
                .font(.system(size: 19, weight: role == .digit ? .regular : .medium).monospacedDigit())
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(fill, in: shape)
                .overlay(shape.fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovered ? 0.05 : 0)))
                .overlay {
                    if accessibility.contrast == .increased {
                        shape.strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }
    }
}

// MARK: - Quick Checklist

struct QuickChecklistWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        // The Dock routes Quick Checklist through the shared module face; keep one face for every caller.
        AnyView(LocalWidgetDockFace(item: item))
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(QuickChecklistView(store: store, item: item, profileID: profileID))
    }
}

struct QuickChecklistView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var newEntry = ""
    @State private var undoPending: RemovedEntries<QuickChecklistEntry>?
    private var entries: [QuickChecklistEntry] { item.widgetConfiguration?.checklistEntries ?? [] }
    private var remaining: Int { entries.filter { !$0.isComplete }.count }
    /// Separators start at the task text, past the check button.
    private static let rowSeparatorInset = DockDesign.Grouped.rowHorizontalPadding + 20 + 10
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            WidgetPopoutHero(value: "\(remaining)", caption: entries.isEmpty ? "Nothing to do yet" : remaining == 0 ? "All done" : "to do")
            GroupedSection {
                WidgetPopoutRow {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill").font(.system(size: 19)).foregroundStyle(DockDesign.accent).accessibilityHidden(true)
                        TextField("Add a task…", text: Binding(get: { newEntry }, set: { newEntry = String($0.prefix(400)) }))
                            .textFieldStyle(.plain).onSubmit(add)
                            .accessibilityLabel("New checklist task")
                        Button("Add", action: add)
                            .buttonStyle(.borderless)
                            .disabled(newEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entries.count >= 100)
                            .accessibilityLabel("Add checklist task")
                    }
                }
            }
            if entries.isEmpty {
                GroupedSection {
                    GroupedRow("A little space for what’s next", subtitle: "Add a task above. Your checklist stays in this Dock.", symbol: "checklist", color: .gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetPopoutSectionHeader("Tasks") {
                        if entries.contains(where: \.isComplete) {
                            Button("Clear Completed") { remove(entries.filter(\.isComplete).map(\.id), message: "Cleared completed tasks.") }
                        }
                    }
                    GroupedSection(separatorInset: Self.rowSeparatorInset) {
                        ForEach(entries) { entry in row(entry) }
                    }
                }
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.checklistEntries, capacity: 100) }
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            WidgetPopoutCaption(entries.count >= 100 ? "Checklist full · remove a task to add another." : "Saved locally with your profile. No account required.")
        }
    }
    private func row(_ entry: QuickChecklistEntry) -> some View {
        WidgetPopoutRow(verticalPadding: 5) {
            HStack(spacing: 10) {
                Button { edit { list in if let index = list.firstIndex(where: { $0.id == entry.id }) { list[index].isComplete.toggle() } } } label: {
                    Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle").font(.system(size: 19))
                        .foregroundStyle(entry.isComplete ? DockDesign.accent : Color.secondary)
                        .frame(width: 20)
                }.buttonStyle(.plain).accessibilityLabel("\(entry.isComplete ? "Reopen" : "Complete") \(entry.title)")
                TextField("Task", text: Binding(get: { entry.title }, set: { value in
                    edit { list in if let index = list.firstIndex(where: { $0.id == entry.id }) { list[index].title = String(value.prefix(400)) } }
                })).textFieldStyle(.plain).font(DockDesign.Grouped.titleFont)
                    .strikethrough(entry.isComplete).foregroundStyle(entry.isComplete ? .secondary : .primary)
                WidgetRowIconButton(symbol: "minus.circle", label: "Remove \(entry.title)") { remove([entry.id], message: "Removed \(entry.title).") }
            }
        }
    }
    private func edit(_ change: (inout [QuickChecklistEntry]) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { change(&$0.checklistEntries) }
    }
    private func remove(_ ids: [UUID], message: String) {
        let pending = RemovedEntries.capture(Set(ids), from: entries, message: message)
        let set = Set(ids)
        if case .accepted = store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: { $0.checklistEntries.removeAll { set.contains($0.id) } }) { undoPending = pending }
    }
    private func add() {
        let title = newEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, entries.count < 100 else { return }
        edit { $0.append(QuickChecklistEntry(title: title)) }; newEntry = ""
    }
}
