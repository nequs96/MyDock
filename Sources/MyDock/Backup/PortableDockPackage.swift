import Foundation

/// Item counts by kind. Recomputed from the profile on import; a package's own summary is never trusted.
struct DockContentSummary: Codable, Equatable, Sendable {
    var applications = 0
    var folders = 0
    var files = 0
    var links = 0
    var widgets = 0
    var spacers = 0

    init() {}

    init(profile: DockProfile) {
        for item in profile.items {
            switch item.type {
            case .application: applications += 1
            case .folder: folders += 1
            case .file: files += 1
            case .link: links += 1
            case .widget: widgets += 1
            case .spacer: spacers += 1
            }
        }
    }

    private enum CodingKeys: String, CodingKey { case applications, folders, files, links, widgets, spacers }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func count(_ key: CodingKeys) -> Int { max(0, (try? values.decodeIfPresent(Int.self, forKey: key)) ?? 0) }
        applications = count(.applications); folders = count(.folders); files = count(.files)
        links = count(.links); widgets = count(.widgets); spacers = count(.spacers)
    }

    struct Row: Identifiable, Equatable {
        var title: String
        var count: Int
        var id: String { title }
    }

    /// Non-empty rows for display, in a fixed order.
    var rows: [Row] {
        let all = [Row(title: "Apps", count: applications), Row(title: "Folders", count: folders),
                   Row(title: "Files", count: files), Row(title: "Links", count: links),
                   Row(title: "Widgets", count: widgets), Row(title: "Spacers", count: spacers)]
        return all.filter { $0.count > 0 }
    }
}

/// Marks a backup archive as a single-Dock portable package and records what it contains.
/// Stored beside `profiles` in the existing backup format, so Add Docks from Backup… still accepts the file.
struct DockPackageManifest: Codable, Equatable, Sendable {
    var includesPersonalData: Bool
    var summary: DockContentSummary

    init(includesPersonalData: Bool, summary: DockContentSummary) {
        self.includesPersonalData = includesPersonalData
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey { case includesPersonalData, summary }

    /// Lenient: the manifest is descriptive only, so a damaged one never blocks an import.
    init(from decoder: Decoder) throws {
        let values = try? decoder.container(keyedBy: CodingKeys.self)
        includesPersonalData = (try? values?.decodeIfPresent(Bool.self, forKey: .includesPersonalData)) ?? false
        summary = (try? values?.decodeIfPresent(DockContentSummary.self, forKey: .summary)) ?? DockContentSummary()
    }
}

enum PortableDockError: LocalizedError, Equatable {
    case newerVersion(Int)
    case malformed
    case noDock
    case multipleDocks(Int)

    var errorDescription: String? {
        switch self {
        case .newerVersion: "This Dock was exported by a newer version of MyDock. Update MyDock to import it. Nothing was changed."
        case .malformed: "This file is not a readable MyDock Dock. Nothing was changed."
        case .noDock: "This file contains no Dock. Nothing was changed."
        case .multipleDocks(let count): "This file is a backup of \(count) Docks. Use Add Docks from Backup… in Settings → General to add them."
        }
    }
}

/// A target in an imported Dock that this Mac cannot resolve, with what happens to it.
struct PortableDockUnresolvedTarget: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var reason: String
    var fallback: String
}

/// A widget whose account or provider connection is never part of a package.
struct PortableDockReconnection: Identifiable, Equatable {
    var id: UUID
    var title: String
    var fallback: String
}

/// Everything the import preview shows. `profile` already has a fresh identity and is added as new.
struct PortableDockImportPreview: Identifiable {
    var id: UUID { profile.id }
    var profile: DockProfile
    var summary: DockContentSummary
    var includesPersonalData: Bool?
    var unresolved: [PortableDockUnresolvedTarget]
    var reconnections: [PortableDockReconnection]
}

/// Single-Dock export and import-as-new, built on the existing backup reader and writer.
@MainActor
enum PortableDockPackage {
    private struct VersionEnvelope: Decodable { var formatVersion: Int? }

    /// Personal widget data is included only when the user explicitly chooses it.
    /// Credentials, provider readings and permissions are never part of a profile export.
    static func exportedProfile(_ profile: DockProfile, includePersonalData: Bool) -> DockProfile {
        includePersonalData ? withoutAccountAssignments(profile) : ProfileSanitizer.sanitize(profile)
    }

    /// Account and store IDs are Keychain lookup keys for one Mac. They never travel in a Dock package,
    /// in either direction, so an imported Dock always reconnects explicitly on this Mac.
    static func withoutAccountAssignments(_ profile: DockProfile) -> DockProfile {
        var copy = profile
        for index in copy.items.indices {
            guard var c = copy.items[index].widgetConfiguration else { continue }
            c.stripeAccountID = ""; c.paddleAccountID = ""; c.shopifyStoreID = ""
            copy.items[index].widgetConfiguration = c
        }
        return copy
    }

    /// What an imported Dock may carry onto this Mac: a fresh identity, no account assignments and no provider readings.
    private static func importable(_ profile: DockProfile) -> DockProfile {
        withoutAccountAssignments(ProfileSanitizer.newIdentity(profile)).strippedOfRuntimeReadings
    }

    static func makePackage(from profile: DockProfile, includePersonalData: Bool) throws -> Data {
        let exported = exportedProfile(profile, includePersonalData: includePersonalData)
        let manifest = DockPackageManifest(includesPersonalData: includePersonalData, summary: DockContentSummary(profile: exported))
        return try BackupManager.makeArchive(from: [exported], dockPackage: manifest)
    }

    static func readPackage(from url: URL, existingNames: [String]) throws -> PortableDockImportPreview {
        try preview(BackupManager.boundedArchiveData(from: url), existingNames: existingNames,
                    targetExists: { !AppLauncher.isMissingTarget($0) })
    }

    /// Validates and prepares an import without changing any stored profile.
    static func preview(_ data: Data, existingNames: [String],
                        targetExists: (DockItem) -> Bool) throws -> PortableDockImportPreview {
        guard data.count <= BackupManager.maximumArchiveBytes else { throw BackupError.tooLarge }
        let envelope: VersionEnvelope
        do { envelope = try JSONDecoder().decode(VersionEnvelope.self, from: data) }
        catch { throw PortableDockError.malformed }
        if let version = envelope.formatVersion, version > DockBackup.currentVersion {
            throw PortableDockError.newerVersion(version)
        }
        let report: BackupImportReport
        do { report = try BackupManager.readArchive(data) }
        catch is DecodingError { throw PortableDockError.malformed }
        guard let imported = report.importedProfiles.first else { throw PortableDockError.noDock }
        guard report.importedProfiles.count == 1 else { throw PortableDockError.multipleDocks(report.importedProfiles.count) }

        let manifest = try? decodedManifest(data)
        var profile = importable(imported)
        profile.name = uniqueName(profile.name, existing: existingNames)
        return PortableDockImportPreview(profile: profile, summary: DockContentSummary(profile: profile),
                                         includesPersonalData: manifest?.includesPersonalData,
                                         unresolved: unresolvedTargets(in: profile, targetExists: targetExists),
                                         reconnections: reconnections(in: profile))
    }

    /// Appends the previewed Dock as a new profile. Never replaces or activates an existing one.
    @discardableResult
    static func importAsNew(_ preview: PortableDockImportPreview, into store: ProfileStore) throws -> UUID {
        var profile = importable(preview.profile)
        profile.name = uniqueName(profile.name, existing: store.state.profiles.map(\.name))
        try ProfileSemanticValidator.validate(store.state.profiles + [profile])
        try store.importProfiles([profile])
        return profile.id
    }

    static func uniqueName(_ name: String, existing: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "Imported Dock" : trimmed
        var candidate = base
        var suffix = 2
        while existing.contains(where: { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(base) \(suffix)"; suffix += 1
        }
        return candidate
    }

    static func unresolvedTargets(in profile: DockProfile, targetExists: (DockItem) -> Bool) -> [PortableDockUnresolvedTarget] {
        var result: [PortableDockUnresolvedTarget] = []
        for item in profile.items {
            switch item.type {
            case .application, .folder, .file:
                guard !targetExists(item) else { break }
                let reason = item.type == .application ? "App not installed" : item.type == .folder ? "Folder not found" : "File not found"
                result.append(.init(title: item.displayName, reason: reason, fallback: "Kept as missing. Use Locate… to reconnect."))
            case .widget where item.widgetKind == "App Folder":
                for application in item.widgetConfiguration?.appFolderApplications ?? [] where !application.hasExistingBundlePath {
                    result.append(.init(title: application.name, reason: "App not installed",
                                        fallback: "Shown dimmed in \(item.widgetConfiguration?.appFolderName ?? "App Folder")."))
                }
            default:
                break
            }
        }
        return result
    }

    /// Business and AI widgets: their accounts and provider sign-ins stay on the original Mac.
    static func reconnections(in profile: DockProfile) -> [PortableDockReconnection] {
        profile.items.compactMap { item in
            guard item.type == .widget, let kind = item.widgetKind,
                  let definition = WidgetRegistry.definition(named: kind),
                  definition.capabilities.needsConnection || definition.category == .ai else { return nil }
            return PortableDockReconnection(id: item.id, title: kind, fallback: "Shows no figures until connected on this Mac.")
        }
    }

    private struct ManifestEnvelope: Decodable { var dockPackage: DockPackageManifest? }

    private static func decodedManifest(_ data: Data) throws -> DockPackageManifest? {
        try JSONDecoder().decode(ManifestEnvelope.self, from: data).dockPackage
    }
}
