import Combine
import Foundation

enum DockUtilityDraftKind: String, Codable, Hashable { case snippet, link }

struct DockUtilityFormDraft: Codable, Equatable {
    var editingID: UUID?
    var title: String
    var body: String
    var isEmpty: Bool { editingID == nil && title.isEmpty && body.isEmpty }
}

private struct DockUtilityDraftKey: Codable, Hashable {
    var profileID: UUID
    var itemID: UUID
    var kind: DockUtilityDraftKind
}

private struct DockUtilityDraftRecord: Codable {
    var key: DockUtilityDraftKey
    var draft: DockUtilityFormDraft
}

private struct DockUtilityDraftArchive: Codable {
    var version = 1
    var records: [DockUtilityDraftRecord]
}

enum DockUtilityDraftError: LocalizedError {
    case tooLarge, tooMany, unsupportedArchive
    var errorDescription: String? {
        switch self {
        case .tooLarge: "This draft is too large to retain. Shorten it before closing; your text is still in this form."
        case .tooMany: "Too many unfinished drafts. Finish or discard one first."
        case .unsupportedArchive: "Saved utility drafts could not be read. The original file was kept."
        }
    }
}

/// Private unfinished forms, separate from saved collections and sanitized history.
@MainActor
final class DockUtilityDraftStore: ObservableObject {
    @Published private var drafts: [DockUtilityDraftKey: DockUtilityFormDraft] = [:]
    @Published private(set) var errorMessage: String?
    /// Set once at load when an unreadable drafts file was moved aside.
    private(set) var recoveryNotice: String?
    private let fileURL: URL
    private let write: (Data, URL) throws -> Void
    private var saveTask: Task<Void, Never>?
    private var needsSave = false
    private var readable = true
    private static let maximumBytes = 2 * 1_024 * 1_024
    private static let maximumDrafts = 100

    init(fileURL: URL, write: ((Data, URL) throws -> Void)? = nil) {
        self.fileURL = fileURL
        self.write = write ?? Self.persist
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumBytes else { throw DockUtilityDraftError.tooLarge }
            let archive = try JSONDecoder().decode(DockUtilityDraftArchive.self, from: Data(contentsOf: fileURL))
            guard archive.version == 1, archive.records.count <= Self.maximumDrafts else { throw DockUtilityDraftError.unsupportedArchive }
            for record in archive.records {
                try Self.validate(record.draft, kind: record.key.kind)
                guard drafts[record.key] == nil else { throw DockUtilityDraftError.unsupportedArchive }
                drafts[record.key] = record.draft
            }
        } catch {
            // Preserve the unreadable file for recovery, then continue with no drafts so quit is never blocked forever.
            drafts = [:]
            let aside = fileURL.appendingPathExtension("recovery-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                recoveryNotice = "Saved utility drafts could not be read. The original file was kept at \(aside.path) and MyDock continued with no unfinished utility drafts."
            } catch {
                // The file cannot be preserved, so never overwrite it.
                readable = false
                errorMessage = DockUtilityDraftError.unsupportedArchive.localizedDescription
            }
        }
    }

    func draft(itemID: UUID, in profileID: UUID, kind: DockUtilityDraftKind) -> DockUtilityFormDraft? {
        drafts[DockUtilityDraftKey(profileID: profileID, itemID: itemID, kind: kind)]
    }

    func update(_ draft: DockUtilityFormDraft, itemID: UUID, in profileID: UUID, kind: DockUtilityDraftKind) throws {
        guard readable else { throw DockUtilityDraftError.unsupportedArchive }
        try Self.validate(draft, kind: kind)
        let key = DockUtilityDraftKey(profileID: profileID, itemID: itemID, kind: kind)
        guard draft.isEmpty || drafts[key] != nil || drafts.count < Self.maximumDrafts else { throw DockUtilityDraftError.tooMany }
        var candidate = drafts
        candidate[key] = draft.isEmpty ? nil : draft
        guard try Self.encoded(candidate).count <= Self.maximumBytes else { throw DockUtilityDraftError.tooLarge }
        guard candidate != drafts else { return }
        drafts = candidate
        scheduleSave()
    }

    /// Explicit discard, or acknowledgement after the collection save is durable.
    @discardableResult
    func discard(itemID: UUID, in profileID: UUID, kind: DockUtilityDraftKind) -> Bool {
        let key = DockUtilityDraftKey(profileID: profileID, itemID: itemID, kind: kind)
        guard let removed = drafts.removeValue(forKey: key) else { return true }
        needsSave = true
        if flush() { return true }
        drafts[key] = removed
        needsSave = true
        return false
    }

    @discardableResult
    func discardTargets(notIn profiles: [DockProfile]) -> Bool {
        let kept = drafts.filter { key, _ in
            profiles.contains { profile in
                profile.id == key.profileID && profile.items.contains { item in
                    item.id == key.itemID && item.type == .widget
                        && item.widgetKind == (key.kind == .snippet ? "Text Snippets" : "Quick Links")
                }
            }
        }
        guard kept.count != drafts.count else { return true }
        drafts = kept
        needsSave = true
        return flush()
    }

    /// Prunes drafts belonging to widgets or profiles that were just removed. Scoped to the removed identities so
    /// drafts for items still only in an open edit session are never touched.
    @discardableResult
    func discardTargets(removedItemIDs: Set<UUID>, removedProfileIDs: Set<UUID> = []) -> Bool {
        let kept = drafts.filter { key, _ in !removedItemIDs.contains(key.itemID) && !removedProfileIDs.contains(key.profileID) }
        guard kept.count != drafts.count else { return true }
        drafts = kept
        needsSave = true
        return flush()
    }

    /// Call at the clean-quit boundary. Failure retains the in-memory draft.
    @discardableResult
    func flush() -> Bool {
        saveTask?.cancel(); saveTask = nil
        guard readable else { return false }
        guard needsSave else { return true }
        do {
            try write(Self.encoded(drafts), fileURL)
            needsSave = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Could not save unfinished utility drafts. Your text is still here. Retry before quitting."
            return false
        }
    }

    private func scheduleSave() {
        needsSave = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private static func validate(_ draft: DockUtilityFormDraft, kind: DockUtilityDraftKind) throws {
        guard draft.title.count <= 100, draft.title.utf8.count <= 400,
              draft.body.count <= (kind == .snippet ? 10_000 : 2_000),
              draft.body.utf8.count <= (kind == .snippet ? 40_000 : 8_192) else { throw DockUtilityDraftError.tooLarge }
    }

    private static func encoded(_ drafts: [DockUtilityDraftKey: DockUtilityFormDraft]) throws -> Data {
        let records = drafts.map { DockUtilityDraftRecord(key: $0.key, draft: $0.value) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(DockUtilityDraftArchive(records: records))
    }

    private static func persist(_ data: Data, _ url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try PrivateAtomicFile.write(data, to: url)
    }
}
