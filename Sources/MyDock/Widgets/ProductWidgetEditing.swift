import Foundation

enum AlarmEditorCandidate {
    /// Missing edited alarms must not be recreated by a stale editor.
    static func make(editingID: UUID?, alarms: [DockAlarm], title: String,
                     hour: Int, minute: Int, repeatWeekdays: Set<Int>) -> DockAlarm? {
        guard (0...23).contains(hour), (0...59).contains(minute), repeatWeekdays.allSatisfy({ (1...7).contains($0) }) else { return nil }
        let existing = editingID.flatMap { id in alarms.first { $0.id == id } }
        guard editingID == nil || existing != nil else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return DockAlarm(id: existing?.id ?? UUID(),
                         title: trimmed.isEmpty ? "Alarm" : String(trimmed.prefix(ProfileSemanticValidator.maximumShortTextLength)),
                         hour: hour, minute: minute, repeatWeekdays: repeatWeekdays.sorted(),
                         isEnabled: existing?.isEnabled ?? true)
    }

    static func stillMatches(_ candidate: DockAlarm, alarms: [DockAlarm]) -> Bool {
        alarms.first { $0.id == candidate.id } == candidate
    }
}

enum SavedSnippetSearch {
    /// Searches saved entries only; recoverable editor state has no role in this projection. Matches exactly what the
    /// command palette finds for the same query (word prefixes, ignoring case and accents) and keeps the saved order.
    static func results(_ entries: [TextSnippet], query: String) -> [TextSnippet] {
        let tokens = SavedCollectionSearch.words(query)
        guard !tokens.isEmpty else { return entries }
        return entries.filter { SavedCollectionSearch.snippetRank(tokens: tokens, entry: $0) != nil }
    }
}
