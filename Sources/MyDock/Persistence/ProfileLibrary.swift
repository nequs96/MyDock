import Combine
import Foundation

struct ProfileLibraryEntry: Codable, Identifiable {
    var id = UUID()
    var recordedAt: Date = .now
    var reason: String
    var profile: DockProfile
}

@MainActor
final class ProfileLibrary: ObservableObject {
    @Published private(set) var entries: [ProfileLibraryEntry] = []
    @Published private(set) var errorMessage: String?
    @Published var includeNotes = false
    private let fileURL: URL
    private let maximumEntries: Int
    private let retentionDays: Int?
    private static let maximumBytes = 8 * 1_024 * 1_024

    init(fileURL: URL, maximumEntries: Int = 25, retentionDays: Int? = nil) {
        self.fileURL = fileURL; self.maximumEntries = maximumEntries; self.retentionDays = retentionDays
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Self.maximumBytes else { throw ProfileValidationError.invalid("profile library is too large") }
                let decoded = try JSONDecoder().decode([ProfileLibraryEntry].self, from: Data(contentsOf: fileURL))
                guard decoded.count <= maximumEntries else { throw ProfileValidationError.invalid("too many library entries") }
                for entry in decoded { try ProfileSemanticValidator.validate([entry.profile]) }
                entries = decoded
                trim()
                if entries.count != decoded.count { persist() }
            }
        } catch { errorMessage = "Could not read this library. The original file was kept. \(error.localizedDescription)" }
    }

    func record(_ profile: DockProfile, reason: String) {
        guard errorMessage == nil else { return }
        let sanitized = ProfileSanitizer.sanitize(profile, includeNotes: includeNotes)
        if entries.first?.profile == sanitized { return }
        entries.insert(ProfileLibraryEntry(reason: reason, profile: sanitized), at: 0)
        trim(); persist()
    }

    func remove(_ id: UUID) { entries.removeAll { $0.id == id }; persist() }
    func clear() { entries = []; persist() }

    func importPreset(_ data: Data) throws {
        guard errorMessage == nil else { throw EditSessionSaveError.failed(errorMessage ?? "The preset library needs recovery.") }
        guard data.count <= Self.maximumBytes else { throw ProfileValidationError.invalid("preset is too large") }
        let profile = try JSONDecoder().decode(DockProfile.self, from: data)
        _ = try BackupManager.makeArchive(from: [profile])
        guard profile.kind == .custom else { throw EditSessionSaveError.failed("Personal presets must be Custom Dock profiles.") }
        record(ProfileSanitizer.newIdentity(ProfileSanitizer.sanitize(profile)), reason: "Imported preset")
        if let errorMessage { throw EditSessionSaveError.failed(errorMessage) }
    }

    func exportPreset(_ id: UUID) throws -> Data {
        guard let entry = entries.first(where: { $0.id == id }) else { throw ProfileDraftMergeError.profileRemoved }
        return try JSONEncoder().encode(ProfileSanitizer.sanitize(entry.profile))
    }

    private func trim() {
        if let retentionDays { entries.removeAll { $0.recordedAt < Date.now.addingTimeInterval(-Double(retentionDays) * 86_400) } }
        entries = Array(entries.prefix(maximumEntries))
    }

    private func persist() {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var data = try encoder.encode(entries)
            while data.count > Self.maximumBytes, !entries.isEmpty {
                entries.removeLast(); data = try encoder.encode(entries)
            }
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            errorMessage = nil
        } catch { errorMessage = "Library could not be saved: \(error.localizedDescription)" }
    }
}
