import AppKit
import SwiftUI

/// Bounded, in-session undo for removed collection entries. Never persisted.
struct RemovedEntries<Element: Identifiable> {
    struct Slot { var entry: Element; var index: Int }
    var message: String
    var slots: [Slot]
    var createdAt = Date()
    /// Undo is offered only briefly so it cannot resurrect stale entries later.
    static var lifetime: TimeInterval { 15 }
    /// With VoiceOver on the offer stays twice as long, so the button can be reached before it goes.
    static func offerLifetime(extended: Bool) -> TimeInterval { extended ? lifetime * 2 : lifetime }

    /// Captures `ids` from `list` with their original positions.
    static func capture(_ ids: Set<Element.ID>, from list: [Element], message: String) -> Self? {
        let slots = list.enumerated().filter { ids.contains($0.element.id) }.map { Slot(entry: $0.element, index: $0.offset) }
        return slots.isEmpty ? nil : Self(message: message, slots: slots)
    }

    func isExpired(at date: Date = Date(), extended: Bool = false) -> Bool {
        date.timeIntervalSince(createdAt) > Self.offerLifetime(extended: extended)
    }

    /// What is left of the offer, measured from when it was made, so a recreated notice does not restart it.
    func remainingLifetime(at date: Date = Date(), extended: Bool = false) -> TimeInterval {
        max(0, Self.offerLifetime(extended: extended) - date.timeIntervalSince(createdAt))
    }

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

enum UndoNoticeCopy {
    static let failed = "Couldn’t restore. The list may be full, or saving is off."
    static func announcement(_ message: String) -> String { message + " Undo available." }
}

struct UndoNotice<Element: Identifiable>: View {
    @Binding var pending: RemovedEntries<Element>?
    /// Restores the entries. False when nothing came back (a rejected write, a full list); the notice then says so.
    var undo: (RemovedEntries<Element>) -> Bool
    @State private var failed = false
    var body: some View {
        if let current = pending {
            HStack(spacing: 8) {
                Text(failed ? UndoNoticeCopy.failed : current.message)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !failed {
                    Button("Undo") {
                        guard !current.isExpired(extended: Self.voiceOverEnabled) else { pending = nil; return }
                        if undo(current) { pending = nil } else { failed = true }
                    }
                    .accessibilityHint("Restores what was just removed")
                }
            }
            .task(id: current.createdAt) {
                // Reads the offer from the binding (the task restarts for a new one), so the task captures no entries.
                guard let offer = pending else { return }
                failed = false
                let extended = Self.voiceOverEnabled
                if extended {
                    NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested,
                                         userInfo: [.announcement: UndoNoticeCopy.announcement(offer.message),
                                                    .priority: NSAccessibilityPriorityLevel.high.rawValue])
                }
                try? await Task.sleep(for: .seconds(offer.remainingLifetime(extended: extended)))
                if !Task.isCancelled { pending = nil }
            }
        }
    }
    private static var voiceOverEnabled: Bool { NSWorkspace.shared.isVoiceOverEnabled }
}
