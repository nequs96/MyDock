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
        guard let values = try? url.resourceValues(forKeys: VolumeFreeSpace.keys.union([.volumeLocalizedNameKey, .volumeTotalCapacityKey])),
              let total = values.volumeTotalCapacity, total > 0, let available = VolumeFreeSpace.availableBytes(values) else { return nil }
        return Self(name: values.volumeLocalizedName ?? "Home volume", totalBytes: Int64(total), availableBytes: max(0, available))
    }
}

/// Free space as Finder and System Settings report it: space macOS can purge on demand counts as available,
/// so the low-space state does not fire while the system would free room itself.
enum VolumeFreeSpace {
    static var keys: Set<URLResourceKey> { [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey] }
    static func availableBytes(_ values: URLResourceValues) -> Int64? {
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values.volumeAvailableCapacity.map { Int64($0) }
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

/// A family's setup in its popout: one final disclosure, collapsed by default, so the popout leads with
/// the reading and its primary actions (Control Center shows the module, not its preferences).
///
/// Inside the widget settings sheet the same rows are the sheet's Content, so they show directly with no
/// disclosure. The context comes from `widgetPopoutContext` (the shell sets `.dock`, the sheet `.sheet`);
/// hosts that set none fall back to `widgetPopoutShowsHero == false` meaning the sheet.
struct WidgetPopoutSettingsDisclosure<Content: View>: View {
    var title: String
    var summary: String?
    @Binding var isExpanded: Bool
    @ViewBuilder var content: Content
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @Environment(\.widgetPopoutContext) private var context
    @DockAccessibilityStyle() private var accessibility
    private var inDockPopout: Bool { WidgetPopoutContext.resolve(explicit: context, showsHero: showsHero) == .dock }

    init(_ title: String = "Settings", summary: String? = nil, isExpanded: Binding<Bool>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.summary = summary
        _isExpanded = isExpanded
        self.content = content()
    }

    var body: some View {
        if inDockPopout {
            VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
                GroupedSection {
                    Button {
                        DockDesign.Motion.perform(DockDesign.Motion.disclosure, reduceMotion: accessibility.reduceMotion) { isExpanded.toggle() }
                    } label: {
                        WidgetPopoutRow {
                            HStack(spacing: 6) {
                                Text(title).font(DockDesign.Grouped.titleFont)
                                Spacer(minLength: 8)
                                if let summary, !isExpanded {
                                    Text(summary).font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                    .accessibilityHint(isExpanded ? "Hides these settings" : "Shows these settings")
                    .accessibilityAddTraits(.isButton)
                }
                if isExpanded { content }
            }
        } else {
            VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) { content }
        }
    }
}

/// A short text action at the end of a grouped row ("Add"). Disabled, it reads as plain secondary text
/// instead of a faint accent; under Increase Contrast it also draws a visible rounded edge, so the
/// enabled and disabled states stay perceivable.
struct WidgetRowTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { TextBody(configuration: configuration) }
    /// Foreground for a state: accent when enabled, secondary (never faded) when disabled.
    static func foreground(enabled: Bool) -> Color { enabled ? DockDesign.accent : Color.secondary }
    /// Whether the edge shows: always under Increase Contrast.
    static func showsEdge(contrast: ColorSchemeContrast) -> Bool { contrast == .increased }
    private struct TextBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @DockAccessibilityStyle() private var accessibility
        var body: some View {
            configuration.label
                .font(DockDesign.Grouped.titleFont.weight(.medium))
                .foregroundStyle(WidgetRowTextButtonStyle.foreground(enabled: isEnabled))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .overlay {
                    if WidgetRowTextButtonStyle.showsEdge(contrast: accessibility.contrast) {
                        RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(isEnabled ? DockDesign.accent : DockDesign.Outline.color(.increased),
                                               lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
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

/// The widget popouts' name for the System Settings panes (`WidgetPrivacySettings.open(.calendars)`).
/// Each pane URL is written once, in `SystemSettingsPane`.
typealias WidgetPrivacySettings = SystemSettingsPane

// MARK: - Disk Space

struct DiskSpaceWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(DiskSpaceView(compact: true)) }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        // PX-7: one row to the System detail surface, only when this Dock has System Activity.
        AnyView(VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            DiskSpaceView(accent: item.widgetConfiguration?.widgetAccent ?? .auto)
            SystemActivityLinkRow(store: store, profileID: profileID)
        })
    }
}

private struct DiskSpaceView: View {
    var compact = false
    /// The popout's usage-line accent; the Dock face reads the same choice from the environment.
    var accent: WidgetAccent = .auto
    @State private var snapshot: DiskSpaceSnapshot?
    @State private var sampledAt: Date?
    @State private var refreshFailed = false
    @State private var isRefreshing = false
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        Group {
            if compact {
                DiskDockFace(snapshot: snapshot).frame(width: width, height: DockDesign.Module.height)
            } else {
                DiskSpacePopoutContent(snapshot: snapshot, sampledAt: sampledAt, refreshFailed: refreshFailed,
                                       isRefreshing: isRefreshing, accent: accent) {
                    Task { await refresh(showsProgress: true) }
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
    /// "Updating…" shows for a refresh someone asked for and for the first reading; the quiet sample each
    /// minute does not flash the header.
    private func refresh(showsProgress: Bool = false) async {
        let visible = showsProgress || snapshot == nil
        if visible { isRefreshing = true }
        defer { if visible { isRefreshing = false } }
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
    var isRefreshing = false
    var accent: WidgetAccent = .auto
    var refresh: () -> Void
    private var stateColor: Color { snapshot?.isLow == true ? WidgetPalette.warning : .primary }
    /// Before the first sample the popout is reading, not failing.
    private var heroCaption: String {
        if let snapshot { return "available on \(snapshot.name)" }
        return refreshFailed ? "Disk reading unavailable" : "Reading…"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            VStack(spacing: 10) {
                WidgetPopoutHero(value: snapshot?.availableText ?? "—", caption: heroCaption, valueColor: stateColor)
                if let snapshot {
                    UsageBar(fraction: snapshot.usedFraction,
                             color: snapshot.isLow ? WidgetPalette.warning : WidgetPalette.resolved(kind: "Disk Space", accent: accent),
                             height: UsageBar.popoutHeight)
                        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                }
            }
            if let snapshot {
                // Titled with the volume actually sampled: the home folder's, which need not be the startup disk.
                GroupedSection(snapshot.name, footer: footer, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                    GroupedRow("Used", value: DockNumberText.percent(fraction: snapshot.usedFraction))
                    GroupedRow("Capacity", value: snapshot.totalText)
                }
            }
        }
        // Freshness and the one refresh control live in the popout header (or the sheet's Data row).
        .widgetPopoutRefresh(WidgetPopoutRefresh(updatedAt: sampledAt, isRefreshing: isRefreshing, failed: refreshFailed,
                                                 maximumAge: 120, action: refresh))
    }
    private var footer: String {
        refreshFailed ? "Refresh failed. The last reading is kept." : "Samples your home folder’s volume every minute."
    }
}

/// The System Storage bar's name for the popout-scale meter: one `UsageBar`, so the two never drift.
struct DiskUsageLine: View {
    var fraction: Double
    var color: Color
    var body: some View { UsageBar(fraction: fraction, color: color, height: UsageBar.popoutHeight) }
}

// MARK: - Calculator

struct CalculatorWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView { AnyView(QuickCalculatorView()) }
}

/// Calculator copy: one short footer sentence; the detail lives in its tooltip.
enum QuickCalculatorCopy {
    static let footer = "Press Return to calculate."
    static let footerHelp = "Percent works as on a calculator: 200 × 15% = 30 and 50 + 10% = 55. The expression and history clear when this popout closes."
}

struct QuickCalculatorView: View {
    @State private var expression = ""
    @State private var message: String?
    @State private var history: [String] = []
    @FocusState private var expressionFocused: Bool
    private var result: Double? { try? QuickCalculator.calculate(expression) }
    private var resultText: String { result.map { $0.formatted(.number.precision(.significantDigits(1...12))) } ?? "—" }
    private let keys = ["C", "(", ")", "÷", "7", "8", "9", "×", "4", "5", "6", "−", "1", "2", "3", "+", "0", QuickCalculator.localDecimalSeparator, "%", "="]
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
                        .font(DockDesign.Popout.heroReading)
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
            WidgetPopoutCaption(QuickCalculatorCopy.footer)
                .help(QuickCalculatorCopy.footerHelp)
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

/// Quick Checklist copy: a footer only when the list is full; where tasks live is in the tooltip.
enum QuickChecklistCopy {
    static let capacity = 100
    static let help = "Quick Checklist keeps up to 100 tasks, saved locally with this Dock. No account is required."
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
                            .buttonStyle(WidgetRowTextButtonStyle())
                            .disabled(newEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entries.count >= 100)
                            .accessibilityLabel("Add checklist task")
                    }
                }
            }
            .help(QuickChecklistCopy.help)
            // Empty, the hero already says so ("0 · Nothing to do yet"): no second empty state.
            if !entries.isEmpty {
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
                var restored = 0
                let result = store.updateWidgetConfiguration(itemID: item.id, in: profileID) { restored = removed.restore(into: &$0.checklistEntries, capacity: 100) }
                return result == .accepted && restored > 0
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            if entries.count >= QuickChecklistCopy.capacity {
                WidgetPopoutCaption("The checklist is full: remove a task to add another.")
                    .help(QuickChecklistCopy.help)
            }
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
