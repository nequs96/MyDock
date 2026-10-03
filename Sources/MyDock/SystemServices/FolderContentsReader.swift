import Foundation

struct FolderContentsEntry: Identifiable, Hashable, Sendable {
    var url: URL
    var isDirectory: Bool
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// A bounded view of a folder: the first `entries` in display order plus how much was left out.
struct FolderContentsListing: Equatable, Sendable {
    var entries: [FolderContentsEntry]
    /// Entries that were enumerated but not displayed.
    var omittedCount: Int
    /// True when enumeration stopped at the safety cap, so the real total is larger than reported.
    var enumerationCapped: Bool

    var isEmpty: Bool { entries.isEmpty && omittedCount == 0 }

    /// "and 12 more" or "and more than 12 more" when enumeration itself was capped.
    var omittedSummary: String? {
        guard omittedCount > 0 else { return nil }
        return enumerationCapped ? "and more than \(omittedCount) more" : "and \(omittedCount) more"
    }
}

enum FolderContentsReader {
    static let defaultDisplayLimit = 300
    static let defaultEnumerationCap = 20_000

    /// Synchronous enumeration. Checks task cancellation between entries, so it stops promptly
    /// when run inside a cancelled task (an in-flight OS call cannot be interrupted).
    static func listing(at folderURL: URL,
                        displayLimit: Int = defaultDisplayLimit,
                        enumerationCap: Int = defaultEnumerationCap) throws -> FolderContentsListing {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
            errorHandler: nil
        ) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: folderURL.path])
        }
        var collected: [FolderContentsEntry] = []
        var capped = false
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if collected.count >= max(1, enumerationCap) {
                capped = true
                break
            }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            collected.append(FolderContentsEntry(url: url, isDirectory: isDirectory))
        }
        // An unreadable folder yields an empty enumerator; surface it instead of showing "Empty folder".
        if collected.isEmpty, !FileManager.default.isReadableFile(atPath: folderURL.path) {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: folderURL.path])
        }
        try Task.checkCancellation()
        return bounded(collected, displayLimit: displayLimit, enumerationCapped: capped)
    }

    /// Full, unbounded listing for callers that need every entry.
    static func entries(at folderURL: URL) throws -> [FolderContentsEntry] {
        try listing(at: folderURL, displayLimit: Int.max, enumerationCap: Int.max).entries
    }

    /// Sorts folders first then by localized name, and keeps only the first `displayLimit` entries.
    static func bounded(_ entries: [FolderContentsEntry],
                        displayLimit: Int,
                        enumerationCapped: Bool = false) -> FolderContentsListing {
        let sorted = entries.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let limit = max(1, displayLimit)
        return FolderContentsListing(entries: Array(sorted.prefix(limit)),
                                     omittedCount: max(0, sorted.count - limit),
                                     enumerationCapped: enumerationCapped)
    }

    /// Async wrapper whose cancellation reaches the detached enumeration.
    static func load(at folderURL: URL,
                     displayLimit: Int = defaultDisplayLimit,
                     enumerationCap: Int = defaultEnumerationCap) async throws -> FolderContentsListing {
        let task = Task.detached(priority: .userInitiated) {
            try listing(at: folderURL, displayLimit: displayLimit, enumerationCap: enumerationCap)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// Issues request tokens so only the most recent request may publish its result.
struct FolderLoadRequestTracker {
    private(set) var current: UUID?

    mutating func begin() -> UUID {
        let token = UUID()
        current = token
        return token
    }

    func isCurrent(_ token: UUID) -> Bool { current == token }

    mutating func invalidate() { current = nil }
}
