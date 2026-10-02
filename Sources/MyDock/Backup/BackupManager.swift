import Foundation

struct DockBackup: Codable {
    static let currentVersion = 1
    var formatVersion = Self.currentVersion
    var exportedAt = Date.now
    var profiles: [DockProfile]
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

    static func makeArchive(from profiles: [DockProfile]) throws -> Data {
        try validate(profiles)
        let archive = DockBackup(profiles: normalizedProfiles(profiles))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)
        guard data.count <= maximumArchiveBytes else { throw BackupError.tooLarge }
        return data
    }

    static func readArchive(_ data: Data) throws -> BackupImportReport {
        guard data.count <= maximumArchiveBytes else { throw BackupError.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(DockBackup.self, from: data)
        guard archive.formatVersion == DockBackup.currentVersion else {
            throw BackupError.unsupportedVersion(archive.formatVersion)
        }
        try validate(archive.profiles)
        let copies = archive.profiles.map { profile in
            var copy = profile
            copy.id = UUID()
            copy.items = profile.items.map { item in
                var itemCopy = item
                itemCopy.id = UUID()
                if itemCopy.widgetKind == "Hydration" {
                    itemCopy.widgetConfiguration?.hydrationRemindersEnabled = false
                }
                if itemCopy.widgetKind == "Alarm", var configuration = itemCopy.widgetConfiguration {
                    configuration.alarms = configuration.alarms.map { alarm in
                        var alarm = alarm
                        alarm.isEnabled = false
                        return alarm
                    }
                    itemCopy.widgetConfiguration = configuration
                }
                if let iconData = itemCopy.linkFaviconData {
                    itemCopy.linkFaviconData = SiteFaviconFetcher.normalizedPNG(from: iconData)
                }
                return itemCopy
            }
            return copy
        }
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
                    guard let url = item.url,
                          DockLinkPolicy.validatedURL(url.absoluteString) != nil else {
                        throw BackupError.invalidLink(item.title)
                    }
                    if let iconData = item.linkFaviconData,
                       SiteFaviconFetcher.normalizedPNG(from: iconData) == nil {
                        throw BackupError.invalidLinkIcon(item.title)
                    }
                case .spacer:
                    guard item.spacerKind != nil else { throw BackupError.invalidFileReference(item.title) }
                case .widget:
                    guard item.widgetKind != nil else { throw BackupError.invalidFileReference(item.title) }
                }
            }
        }
    }

    private static func normalizedProfiles(_ profiles: [DockProfile]) -> [DockProfile] {
        profiles.map { profile in
            var copy = profile
            copy.items = profile.items.map { item in
                var itemCopy = item
                if let iconData = itemCopy.linkFaviconData {
                    itemCopy.linkFaviconData = SiteFaviconFetcher.normalizedPNG(from: iconData)
                }
                return itemCopy
            }
            return copy
        }
    }
}
