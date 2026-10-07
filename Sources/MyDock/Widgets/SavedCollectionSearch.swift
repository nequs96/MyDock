import Foundation

/// One saved snippet, link or shelf file found for the command palette. Value type, derived on demand and never persisted.
struct SavedCollectionResult: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case snippet, link, file
        var symbol: String {
            switch self {
            case .snippet: "doc.on.clipboard"
            case .link: "link"
            case .file: "doc"
            }
        }
        var label: String {
            switch self {
            case .snippet: "Snippet"
            case .link: "Link"
            case .file: "File"
            }
        }
    }

    let id: String
    let kind: Kind
    let title: String
    /// One line only. Snippets are truncated to `SavedCollectionSearch.previewLimit` characters.
    let detail: String
    let dockName: String
    let profileID: UUID
    let itemID: UUID
    let entryID: UUID
    /// Full text, used only to copy. Never displayed beyond `detail`.
    let snippetText: String?
    let linkURL: URL?
    let fileURL: URL?
    /// Files only: the original could not be found.
    let isMissing: Bool
}

enum SavedCollectionSearch {
    static let maxResults = 8
    static let previewLimit = 60
    static let snippetsKind = "Text Snippets"
    static let linksKind = "Quick Links"
    static let shelfKind = "File Shelf"

    /// Prefix and word matching over explicitly saved content in every Dock. An empty query returns nothing.
    /// Ordering is deterministic: match quality, then Dock name, then title, then entry id.
    static func results(in profiles: [DockProfile], query: String, limit: Int = maxResults,
                        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> [SavedCollectionResult] {
        let tokens = words(query)
        guard !tokens.isEmpty, limit > 0 else { return [] }
        // Shelf files rank on their stored name; only the shown results resolve their bookmarks.
        var candidates: [(rank: Int, result: SavedCollectionResult, shelfFile: ShelfFile?)] = []
        for profile in profiles {
            for item in profile.items where item.type == .widget {
                guard let configuration = item.widgetConfiguration else { continue }
                switch item.widgetKind ?? "" {
                case snippetsKind:
                    for entry in configuration.textSnippets {
                        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        let preview = oneLinePreview(entry.text)
                        let shownTitle = title.isEmpty ? preview : title
                        guard let rank = rank(tokens: tokens, primary: shownTitle, secondary: String(entry.text.prefix(2_000))) else { continue }
                        candidates.append((rank, SavedCollectionResult(
                            id: "\(profile.id)-\(item.id)-\(entry.id)", kind: .snippet, title: shownTitle, detail: preview,
                            dockName: profile.name, profileID: profile.id, itemID: item.id, entryID: entry.id,
                            snippetText: entry.text, linkURL: nil, fileURL: nil, isMissing: false), nil))
                    }
                case linksKind:
                    for entry in configuration.quickLinks {
                        let host = entry.url.host ?? entry.url.absoluteString
                        guard let rank = rank(tokens: tokens, primary: entry.title, secondary: entry.url.absoluteString) else { continue }
                        candidates.append((rank, SavedCollectionResult(
                            id: "\(profile.id)-\(item.id)-\(entry.id)", kind: .link, title: entry.title, detail: host,
                            dockName: profile.name, profileID: profile.id, itemID: item.id, entryID: entry.id,
                            snippetText: nil, linkURL: entry.url, fileURL: nil, isMissing: false), nil))
                    }
                case shelfKind:
                    for entry in configuration.shelfFiles {
                        let name = entry.url.lastPathComponent
                        guard let rank = rank(tokens: tokens, primary: name, secondary: "") else { continue }
                        candidates.append((rank, SavedCollectionResult(
                            id: "\(profile.id)-\(item.id)-\(entry.id)", kind: .file, title: name, detail: "",
                            dockName: profile.name, profileID: profile.id, itemID: item.id, entryID: entry.id,
                            snippetText: nil, linkURL: nil, fileURL: entry.url, isMissing: false), entry))
                    }
                default:
                    continue
                }
            }
        }
        let ordered = candidates.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            let dock = lhs.result.dockName.localizedStandardCompare(rhs.result.dockName)
            if dock != .orderedSame { return dock == .orderedAscending }
            let title = lhs.result.title.localizedStandardCompare(rhs.result.title)
            if title != .orderedSame { return title == .orderedAscending }
            return lhs.result.id < rhs.result.id
        }
        // Bookmarks are resolved and file existence is checked only for the few results that will be shown.
        return ordered.prefix(limit).map { candidate in
            var result = candidate.result
            guard result.kind == .file, let shelfFile = candidate.shelfFile else { return result }
            let url = shelfFile.resolvedURL
            let missing = !fileExists(url)
            result = SavedCollectionResult(id: result.id, kind: result.kind, title: url.lastPathComponent,
                                           detail: missing ? "Missing" : (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
                                           dockName: result.dockName, profileID: result.profileID, itemID: result.itemID, entryID: result.entryID,
                                           snippetText: nil, linkURL: nil, fileURL: url, isMissing: missing)
            return result
        }
    }

    /// 0 = the whole title starts with the query, 1 = every token starts a title word, 2 = tokens start words elsewhere in the content.
    static func rank(tokens: [String], primary: String, secondary: String) -> Int? {
        let titleWords = words(primary)
        if tokens.allSatisfy({ token in titleWords.contains { $0.hasPrefix(token) } }) {
            return folded(primary).hasPrefix(tokens.joined(separator: " ")) ? 0 : 1
        }
        let allWords = titleWords + words(secondary)
        return tokens.allSatisfy({ token in allWords.contains { $0.hasPrefix(token) } }) ? 2 : nil
    }

    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func words(_ text: String) -> [String] {
        folded(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }

    /// A single line of at most `previewLimit` characters; longer text ends in an ellipsis.
    static func oneLinePreview(_ text: String, limit: Int = previewLimit) -> String {
        let collapsed = text.prefix(limit * 4).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
