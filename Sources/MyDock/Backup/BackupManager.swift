import Foundation

struct DockBackup: Codable {
    static let currentVersion = 1
    var formatVersion = Self.currentVersion
    var exportedAt = Date.now
    var profiles: [DockProfile]
    /// Present only in a single-Dock portable package (see PortableDockPackage). Older readers ignore it.
    var dockPackage: DockPackageManifest?
}

struct BackupImportReport {
    var importedProfiles: [DockProfile]
    var missingItems: [String]
}

enum BackupError: LocalizedError {
    case unsupportedVersion(Int)
    case tooLarge
    case notRegularFile
    case invalidLink(String)
    case invalidLinkIcon(String)
    case invalidFileReference(String)
    case tooManyProfiles
    case tooManyItems

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This backup uses unsupported schema version \(version)."
        case .tooLarge: "This backup is larger than the supported 25 MB limit."
        case .notRegularFile: "Choose a regular JSON backup file."
        case .invalidLink(let title): "The link for “\(title)” must use HTTP or HTTPS and include a host."
        case .invalidLinkIcon(let title): "The site icon for “\(title)” is not a supported image."
        case .invalidFileReference(let title): "The file reference for “\(title)” is not a local file URL."
        case .tooManyProfiles: "This backup contains too many Dock profiles."
        case .tooManyItems: "This backup contains too many items."
        }
    }
}

enum BackupManager {
    static let maximumArchiveBytes = 25 * 1_024 * 1_024

    /// Decode only the bounded compatibility envelope before any version-specific model.
    private struct StateSchemaEnvelope: Decodable {
        var schemaVersion: Int?
    }
    private struct BackupSchemaEnvelope: Decodable {
        var formatVersion: Int?
    }

    static func stateSchemaVersion(in data: Data) throws -> Int? {
        guard data.count <= maximumArchiveBytes else { throw BackupError.tooLarge }
        return try JSONDecoder().decode(StateSchemaEnvelope.self, from: data).schemaVersion
    }

    static func readArchive(from url: URL) throws -> BackupImportReport {
        try readArchive(boundedArchiveData(from: url))
    }

    static func boundedArchiveData(from url: URL, maximumBytes: Int = maximumArchiveBytes) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw BackupError.notRegularFile }
        if let fileSize = values.fileSize, fileSize > maximumBytes { throw BackupError.tooLarge }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, 64 * 1_024))
        while data.count <= maximumBytes {
            let remaining = maximumBytes + 1 - data.count
            let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)) ?? Data()
            if chunk.isEmpty { return data }
            data.append(chunk)
        }
        throw BackupError.tooLarge
    }

    static func makeArchive(from profiles: [DockProfile], dockPackage: DockPackageManifest? = nil) throws -> Data {
        try validate(profiles)
        // Provider readings are runtime cache data and never travel in a backup.
        let normalized = try withNormalizedSiteIcons(profiles.map(\.strippedOfRuntimeReadings))
        let archive = DockBackup(profiles: normalized, dockPackage: dockPackage)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        guard data.count <= maximumArchiveBytes else { throw BackupError.tooLarge }
        return data
    }

    /// `computeMissing` stats every file target for the report's missing list; the Dock package preview, which finds
    /// unresolved targets itself, passes false.
    static func readArchive(_ data: Data, computeMissing: Bool = true) throws -> BackupImportReport {
        guard data.count <= maximumArchiveBytes else { throw BackupError.tooLarge }
        let envelope = try JSONDecoder().decode(BackupSchemaEnvelope.self, from: data)
        if let version = envelope.formatVersion, version != DockBackup.currentVersion {
            throw BackupError.unsupportedVersion(version)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(DockBackup.self, from: data)
        guard archive.formatVersion == DockBackup.currentVersion else {
            throw BackupError.unsupportedVersion(archive.formatVersion)
        }
        try validate(archive.profiles)
        // Each site icon is decoded and re-encoded once, here, and the result is what is restored.
        let copies = try withNormalizedSiteIcons(archive.profiles).map { profile in
            var copy = profile
            copy.id = UUID()
            copy.items = profile.items.map { $0.preparedForNewIdentity() }
            copy.workspace = profile.workspace?.remapped(from: profile.items, to: copy.items)
            return copy
        }
        guard computeMissing else { return BackupImportReport(importedProfiles: copies, missingItems: []) }
        let missing = copies.flatMap { profile in
            profile.items.flatMap { item -> [String] in
                var missingItems: [String] = []
                if [.application, .folder, .file].contains(item.type), let url = item.url,
                   !FileManager.default.fileExists(atPath: url.path) {
                    missingItems.append("\(profile.name): \(item.title) (\(url.path))")
                }
                if item.widgetKind == "App Folder", let configuration = item.widgetConfiguration {
                    missingItems += configuration.appFolderApplications.compactMap { application in
                        application.hasExistingBundlePath ? nil
                            : "\(profile.name): \(configuration.appFolderName) → \(application.name) (\(application.url.path))"
                    }
                }
                return missingItems
            }
        }
        return BackupImportReport(importedProfiles: copies, missingItems: missing)
    }

    private static func validate(_ profiles: [DockProfile]) throws {
        try ProfileSemanticValidator.validate(profiles)
        guard profiles.count <= 500 else { throw BackupError.tooManyProfiles }
        let itemCount = profiles.reduce(0) { total, profile in
            total + profile.items.reduce(0) { count, item in
                count + 1 + (item.widgetConfiguration?.appFolderApplications.count ?? 0)
            }
        }
        guard itemCount <= 20_000 else { throw BackupError.tooManyItems }
        for profile in profiles {
            for item in profile.items {
                if let applications = item.widgetConfiguration?.appFolderApplications {
                    guard applications.count <= 2_000 else { throw BackupError.tooManyItems }
                    for application in applications where !application.url.isFileURL {
                        throw BackupError.invalidFileReference(application.name)
                    }
                }
                switch item.type {
                case .application, .folder, .file:
                    if let url = item.url, !url.isFileURL { throw BackupError.invalidFileReference(item.title) }
                case .link:
                    // Site icons are checked by `withNormalizedSiteIcons`, which decodes each one once.
                    guard let url = item.url,
                          DockLinkPolicy.validatedURL(url.absoluteString) != nil else {
                        throw BackupError.invalidLink(item.title)
                    }
                case .spacer:
                    guard item.spacerKind != nil else { throw BackupError.invalidFileReference(item.title) }
                case .widget:
                    guard item.widgetKind != nil else { throw BackupError.invalidFileReference(item.title) }
                }
            }
        }
    }

    /// Re-encodes every site icon as a small PNG, decoding each one once. A link whose icon is not a supported image
    /// is rejected; any other item simply loses an unreadable icon.
    private static func withNormalizedSiteIcons(_ profiles: [DockProfile]) throws -> [DockProfile] {
        try profiles.map { profile in
            var copy = profile
            for index in copy.items.indices {
                guard let iconData = copy.items[index].linkFaviconData else { continue }
                let normalized = SiteFaviconFetcher.normalizedPNG(from: iconData)
                if normalized == nil, copy.items[index].type == .link {
                    throw BackupError.invalidLinkIcon(copy.items[index].title)
                }
                copy.items[index].linkFaviconData = normalized
            }
            return copy
        }
    }
}
