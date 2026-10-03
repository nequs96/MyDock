import SwiftUI

/// Bounded, in-session undo for removed collection entries. Never persisted.
struct RemovedEntries<Element: Identifiable> {
    struct Slot { var entry: Element; var index: Int }
    var message: String
    var slots: [Slot]
    var createdAt = Date()
    /// Undo is offered only briefly so it cannot resurrect stale entries later.
    static var lifetime: TimeInterval { 15 }

    /// Captures `ids` from `list` with their original positions.
    static func capture(_ ids: Set<Element.ID>, from list: [Element], message: String) -> Self? {
        let slots = list.enumerated().filter { ids.contains($0.element.id) }.map { Slot(entry: $0.element, index: $0.offset) }
        return slots.isEmpty ? nil : Self(message: message, slots: slots)
    }

    func isExpired(at date: Date = Date()) -> Bool { date.timeIntervalSince(createdAt) > Self.lifetime }

    /// Re-inserts entries whose ID is absent, at a clamped index, without exceeding `capacity`.
    /// Entries edited or re-added meanwhile are left untouched. Returns the number restored.
    @discardableResult
    func restore(into list: inout [Element], capacity: Int) -> Int {
        var restored = 0
        for slot in slots.sorted(by: { $0.index < $1.index }) {
            guard list.count < capacity, !list.contains(where: { $0.id == slot.entry.id }) else { continue }
            list.insert(slot.entry, at: min(max(slot.index, 0), list.count))
            restored += 1
        }
        return restored
    }
}

struct UndoNotice<Element: Identifiable>: View {
    @Binding var pending: RemovedEntries<Element>?
    var undo: (RemovedEntries<Element>) -> Void
    var body: some View {
        if let current = pending {
            HStack(spacing: 8) {
                Text(current.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Undo") { undo(current); pending = nil }.accessibilityHint("Restores what was just removed")
            }
            .task(id: current.createdAt) {
                try? await Task.sleep(for: .seconds(RemovedEntries<Element>.lifetime))
                if !Task.isCancelled { pending = nil }
            }
        }
    }
}
