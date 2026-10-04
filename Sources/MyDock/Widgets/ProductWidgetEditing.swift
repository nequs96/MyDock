import Foundation

enum AlarmEditorCandidate {
    /// Missing edited alarms must not be recreated by a stale editor.
    static func make(editingID: UUID?, alarms: [DockAlarm], title: String,
                     hour: Int, minute: Int, repeatWeekdays: Set<Int>) -> DockAlarm? {
        guard (0...23).contains(hour), (0...59).contains(minute), repeatWeekdays.allSatisfy({ (1...7).contains($0) }) else { return nil }
        let existing = editingID.flatMap { id in alarms.first { $0.id == id } }
        guard editingID == nil || existing != nil else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return DockAlarm(id: existing?.id ?? UUID(), title: trimmed.isEmpty ? "Alarm" : trimmed,
                         hour: hour, minute: minute, repeatWeekdays: repeatWeekdays.sorted(),
                         isEnabled: existing?.isEnabled ?? true)
    }

    static func stillMatches(_ candidate: DockAlarm, alarms: [DockAlarm]) -> Bool {
        alarms.first { $0.id == candidate.id } == candidate
    }
}

enum SavedSnippetSearch {
    /// Searches saved entries only; recoverable editor state has no role in this projection.
    static func results(_ entries: [TextSnippet], query: String) -> [TextSnippet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { query.isEmpty || ($0.title + " " + $0.text).localizedStandardContains(query) }
    }
}
