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
    /// False only when an unreadable file could not be set aside; that file is then never overwritten.
    private var readable = true
    /// Recovery history is written on every profile edit, so its file I/O runs on a serial background queue.
    /// Presets stay synchronous because an import reports whether it was saved.
    private let writesInBackground: Bool
    private var writeRevision: UInt64 = 0
    private static let maximumBytes = 8 * 1_024 * 1_024
    nonisolated private static let writeQueue = DispatchQueue(label: "app.mydock.profile-library", qos: .utility)

    init(fileURL: URL, maximumEntries: Int = 25, retentionDays: Int? = nil, writesInBackground: Bool = false) {
        self.fileURL = fileURL; self.maximumEntries = maximumEntries; self.retentionDays = retentionDays
        self.writesInBackground = writesInBackground
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let size = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= Self.maximumBytes else { throw ProfileValidationError.invalid("profile library is too large") }
            let decoded = try JSONDecoder().decode([ProfileLibraryEntry].self, from: Data(contentsOf: fileURL))
            // An entry a newer validator rejects is dropped on its own; the rest of the library stays usable.
            entries = decoded.filter { (try? ProfileSemanticValidator.validate([$0.profile])) != nil }
            trim()
            if entries.count != decoded.count { persist() }
        } catch {
            // Preserve the unreadable file for recovery, then start an empty library so new snapshots are still kept.
            entries = []
            let aside = fileURL.appendingPathExtension("recovery-\(UUID().uuidString)")
            do {
                try FileManager.default.moveItem(at: fileURL, to: aside)
                errorMessage = "This library could not be read, so a new one was started. The original was kept as \(aside.lastPathComponent)."
            } catch {
                readable = false
                errorMessage = "Could not read this library. The original file was kept. \(error.localizedDescription)"
            }
        }
    }

    /// Returns false when the library could not keep the entry: it needs recovery, or a synchronous write failed.
    /// A background write reports a failure later, through `errorMessage`.
    @discardableResult
    func record(_ profile: DockProfile, reason: String) -> Bool {
        // A failed write does not stop later snapshots: the next record retries it.
        guard readable else { return false }
        let sanitized = ProfileSanitizer.sanitize(profile, includeNotes: includeNotes)
        if entries.first?.profile == sanitized { return writesInBackground || errorMessage == nil }
        entries.insert(ProfileLibraryEntry(reason: reason, profile: sanitized), at: 0)
        trim(); persist()
        return writesInBackground || errorMessage == nil
    }

    /// Like `record`, these never touch a library file that could not be read or set aside.
    func remove(_ id: UUID) { guard readable else { return }; entries.removeAll { $0.id == id }; persist() }
    func clear() { guard readable else { return }; entries = []; persist() }

    /// Accepts a Dock export (the format presets are exported in) or a legacy bare-profile preset.
    func importPreset(_ data: Data) throws {
        guard readable else { throw EditSessionSaveError.failed(errorMessage ?? "The preset library needs recovery.") }
        guard data.count <= Self.maximumBytes else { throw ProfileValidationError.invalid("preset is too large") }
        let profile: DockProfile
        if let package = try? PortableDockPackage.preview(data, existingNames: [], targetExists: { _ in true }) {
            profile = package.profile
        } else {
            do { profile = try JSONDecoder().decode(DockProfile.self, from: data) }
            catch is DecodingError { throw EditSessionSaveError.failed(Self.unreadablePreset) }
            _ = try BackupManager.makeArchive(from: [profile])
        }
        guard profile.kind == .custom else { throw EditSessionSaveError.failed("Personal presets must be Custom Docks.") }
        record(ProfileSanitizer.newIdentity(ProfileSanitizer.sanitize(profile)), reason: "Imported preset")
        if let errorMessage { throw EditSessionSaveError.failed(errorMessage) }
    }

    /// A sanitized Dock export, so a preset file also opens with Import Dock….
    func exportPreset(_ id: UUID) throws -> Data {
        guard let entry = entries.first(where: { $0.id == id }) else { throw ProfileDraftMergeError.profileRemoved }
        return try PortableDockPackage.makePackage(from: entry.profile, includePersonalData: false)
    }

    static let unreadablePreset = "This file is not a MyDock preset or Dock export."

    private func trim() {
        if let retentionDays { entries.removeAll { $0.recordedAt < Date.now.addingTimeInterval(-Double(retentionDays) * 86_400) } }
        entries = Array(entries.prefix(maximumEntries))
    }

    /// Waits for background library writes queued so far. Lifecycle boundaries call this before quitting.
    nonisolated static func waitForPendingWrites() { writeQueue.sync {} }

    private func persist() {
        guard readable else { return }
        let data: Data
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var encoded = try encoder.encode(entries)
            while encoded.count > Self.maximumBytes, !entries.isEmpty {
                entries.removeLast(); encoded = try encoder.encode(entries)
            }
            data = encoded
        } catch { errorMessage = "Library could not be saved: \(error.localizedDescription)"; return }
        guard writesInBackground else {
            finishWrite(Self.writeResult(data, to: fileURL))
            return
        }
        writeRevision &+= 1
        let revision = writeRevision
        let fileURL = fileURL
        Self.writeQueue.async { [weak self] in
            let result = Self.writeResult(data, to: fileURL)
            Task { @MainActor [weak self] in
                // Writes run in order, so only the latest one decides what the library reports.
                guard let self, revision == self.writeRevision else { return }
                self.finishWrite(result)
            }
        }
    }

    private func finishWrite(_ result: Result<Void, Error>) {
        switch result {
        case .success: errorMessage = nil
        case .failure(let error): errorMessage = "Library could not be saved: \(error.localizedDescription)"
        }
    }

    nonisolated private static func write(_ data: Data, to fileURL: URL) throws {
        try PrivateAtomicFile.write(data, to: fileURL)
    }

    /// The write as a value. A plain do/catch, not `Result { … }`: that closure form in `persist()` crashed the Swift
    /// compiler's closure-lifetime pass (ClosureLifetimeFixup) on CI.
    nonisolated private static func writeResult(_ data: Data, to fileURL: URL) -> Result<Void, Error> {
        do {
            try write(data, to: fileURL)
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
