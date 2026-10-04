import AppKit
import SwiftUI

struct DiskSpaceSnapshot: Equatable, Sendable {
    var name: String
    var totalBytes: Int64
    var availableBytes: Int64
    var usedFraction: Double { totalBytes > 0 ? Double(totalBytes - min(totalBytes, max(0, availableBytes))) / Double(totalBytes) : 0 }
    var availableText: String { ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file) }
    var totalText: String { ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file) }
    static func read() -> Self? {
        let url = FileManager.default.homeDirectoryForCurrentUser
        guard let values = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
              let total = values.volumeTotalCapacity, total > 0, let available = values.volumeAvailableCapacity else { return nil }
        return Self(name: values.volumeLocalizedName ?? "Startup disk", totalBytes: Int64(total), availableBytes: Int64(max(0, available)))
    }
}

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
        VStack(alignment: .leading, spacing: 14) {
            if compact {
                DiskDockFace(snapshot: snapshot).frame(width: width, height: 54)
            } else {
                WidgetSection(title: snapshot?.name ?? "Startup disk") {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(snapshot?.availableText ?? "—").font(.system(size: 36, weight: .semibold)).monospacedDigit()
                        Text("available").foregroundStyle(.secondary)
                    }
                    if let snapshot {
                        ProgressView(value: snapshot.usedFraction).tint(snapshot.usedFraction > 0.9 ? .orange : .teal)
                        HStack {
                            Text("\(Int((snapshot.usedFraction * 100).rounded()))% used")
                            Spacer()
                            Text("\(snapshot.totalText) capacity")
                        }.font(.caption).foregroundStyle(.secondary)
                    } else { Text("Disk reading unavailable. Try refreshing.").font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        if let sampledAt {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(WidgetTimingPresentation.readingStatus(fetchedAt: sampledAt, now: context.date, maximumAge: 120))
                            }
                        }
                        Text(refreshFailed ? "Refresh failed. The last successful reading is retained." : "Samples the volume containing your home folder every minute while open.")
                    }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Refresh") { Task { await refresh() } }
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

struct CalculatorWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WidgetIconTile(item: item, style: .tinted))
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
        VStack(alignment: .leading, spacing: 14) {
            WidgetSection(title: "Quick calculation") {
                TextField("e.g. (120 + 35) × 2", text: Binding(get: { expression }, set: { expression = String($0.prefix(256)); message = nil }))
                    .onSubmit(calculate).focused($expressionFocused).accessibilityLabel("Calculation expression")
                HStack(alignment: .firstTextBaseline) {
                    Text(resultText).font(.system(size: 34, weight: .medium)).monospacedDigit().lineLimit(2).minimumScaleFactor(0.65)
                    Spacer()
                    Button { message = copyUtilityText(resultText) ? "Result copied. Paste with ⌘V." : utilityCopyFailureMessage } label: { Image(systemName: "doc.on.doc") }
                        .disabled(result == nil).accessibilityLabel("Copy result")
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(keys, id: \.self) { key in
                    Button { enter(key) } label: { Text(key).font(.system(size: 19, weight: .medium)).frame(maxWidth: .infinity, minHeight: 40) }
                        .buttonStyle(DockButtonStyle(primary: key == "="))
                        .accessibilityLabel(key == "C" ? "Clear expression" : key == "=" ? "Calculate" : key)
                }
            }
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This session").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(history.enumerated()), id: \.offset) { _, value in Text(value).font(.caption).textSelection(.enabled) }
                }
            }
            Text("Type an expression and press Return to calculate. Percent divides a number by 100: 200 × 15% = 30. Expression and history clear when this popout closes.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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

struct QuickChecklistWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(QuickChecklistCompactView(item: item))
    }
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(QuickChecklistView(store: store, item: item, profileID: profileID))
    }
}

private struct QuickChecklistCompactView: View {
    var item: DockItem
    @Environment(\.dockWidgetContentWidth) private var width
    private var entries: [QuickChecklistEntry] { item.widgetConfiguration?.checklistEntries ?? [] }
    var body: some View {
        HStack(spacing: 8) {
            if width >= 100 { WidgetEmblem(kind: "Quick Checklist", size: 30) }
            VStack(alignment: width >= 100 ? .leading : .center, spacing: 3) {
                Text("\(entries.filter { !$0.isComplete }.count)").font(.system(size: 22, weight: .semibold)).monospacedDigit()
                Text("To do").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        }.frame(width: width, height: 54)
    }
}

struct QuickChecklistView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var newEntry = ""
    @State private var undoPending: RemovedEntries<QuickChecklistEntry>?
    private var entries: [QuickChecklistEntry] { item.widgetConfiguration?.checklistEntries ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(entries.filter { !$0.isComplete }.count) remaining").font(.system(size: 22, weight: .semibold))
                Spacer()
                if entries.contains(where: \.isComplete) {
                    Button("Clear Completed") { remove(entries.filter(\.isComplete).map(\.id), message: "Cleared completed tasks.") }
                }
            }
            HStack(spacing: 8) {
                TextField("Add a task…", text: Binding(get: { newEntry }, set: { newEntry = String($0.prefix(400)) })).onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }.buttonStyle(DockButtonStyle(primary: true))
                    .disabled(newEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entries.count >= 100)
                    .accessibilityLabel("Add checklist task")
            }
            if entries.isEmpty {
                VStack(spacing: 10) {
                    WidgetEmblem(kind: "Quick Checklist", size: 48)
                    Text("A little space for what’s next.").font(.system(size: 14, weight: .medium))
                    Text("Add a task above. Your checklist stays in this Dock.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        HStack(spacing: 10) {
                            Button { edit { list in if let index = list.firstIndex(where: { $0.id == entry.id }) { list[index].isComplete.toggle() } } } label: {
                                Image(systemName: entry.isComplete ? "checkmark.circle.fill" : "circle").font(.system(size: 19)).foregroundStyle(entry.isComplete ? Color.accentColor : .secondary)
                            }.buttonStyle(.plain).accessibilityLabel("\(entry.isComplete ? "Reopen" : "Complete") \(entry.title)")
                            TextField("Task", text: Binding(get: { entry.title }, set: { value in
                                edit { list in if let index = list.firstIndex(where: { $0.id == entry.id }) { list[index].title = String(value.prefix(400)) } }
                            })).textFieldStyle(.plain).strikethrough(entry.isComplete).foregroundStyle(entry.isComplete ? .secondary : .primary)
                            Button { remove([entry.id], message: "Removed \(entry.title).") } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }
                                .buttonStyle(.plain).accessibilityLabel("Remove \(entry.title)")
                        }.padding(.vertical, 11)
                        if entry.id != entries.last?.id { Divider() }
                    }
                }.padding(.horizontal, 14).background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 14))
            }
            UndoNotice(pending: $undoPending) { removed in
                store.updateWidgetConfiguration(itemID: item.id, in: profileID) { removed.restore(into: &$0.checklistEntries, capacity: 100) }
            }
            Text(entries.count >= 100 ? "Checklist full · remove a task to add another." : "Saved locally with your profile. No account required.")
                .font(.caption).foregroundStyle(.secondary)
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
