import Foundation

struct FolderContentsEntry: Identifiable, Hashable, Sendable {
    var url: URL
    /// A folder the popout can browse. Apps and document packages (.app, .rtfd, .pages) are directories on disk
    /// but open like files, as in Finder.
    var isDirectory: Bool
    /// Finder's display name (no .app, localized folder names); the file name when unknown.
    var displayName: String? = nil
    var id: String { url.path }
    var name: String { displayName ?? url.lastPathComponent }
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
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
        // The enumerator does not descend into a symbolic link at its root, so a browsed link lists its target.
        let isLinkedRoot = (try? folderURL.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
        guard let enumerator = FileManager.default.enumerator(
            at: isLinkedRoot ? folderURL.resolvingSymlinksInPath() : folderURL,
            includingPropertiesForKeys: Array(keys),
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
            var values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                // A link to a folder sorts and browses like that folder, as in Finder; the entry keeps the link's URL.
                values = try? url.resolvingSymlinksInPath().resourceValues(forKeys: keys)
            }
            let browsable = values?.isDirectory == true && values?.isPackage != true
            collected.append(FolderContentsEntry(url: url, isDirectory: browsable,
                                                 displayName: FileManager.default.displayName(atPath: url.path)))
        }
        // An unreadable folder yields an empty enumerator; surface it instead of showing "Empty folder".
        if collected.isEmpty, !FileManager.default.isReadableFile(atPath: folderURL.path) {
            throw CocoaError(.fileReadNoPermission, userInfo: [NSFilePathErrorKey: folderURL.path])
        }
        try Task.checkCancellation()
        return bounded(collected, displayLimit: displayLimit, enumerationCapped: capped)
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
