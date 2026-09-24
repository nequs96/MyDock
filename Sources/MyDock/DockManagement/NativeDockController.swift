import AppKit
import Foundation
import OSLog

@MainActor
protocol DockPreferencesBackend {
    func readCurrentTiles() throws -> [[String: Any]]
    func writeTiles(_ tiles: [[String: Any]]) throws
}

@MainActor
protocol DockRelaunching {
    func restartDock() async throws
}

@MainActor
protocol DockTransactionJournal {
    func begin(snapshot: [[String: Any]], profileID: UUID) throws
    func pendingSnapshot() throws -> [[String: Any]]?
    func clear() throws
}

enum NativeDockError: LocalizedError {
    case preferencesUnavailable
    case missingApplication(String)
    case unsupportedItem(String)
    case verificationFailed
    case rollbackFailed(original: String, rollback: String)
    case interruptedTransaction

    var errorDescription: String? {
        switch self {
        case .preferencesUnavailable: "The current macOS Dock layout could not be read or saved."
        case .missingApplication(let title): "The application “\(title)” is missing or no longer accessible."
        case .unsupportedItem(let title): "“\(title)” cannot be stored in a macOS Dock profile."
        case .verificationFailed: "The macOS Dock did not settle on the requested profile. The previous layout was restored."
        case .rollbackFailed(let original, let rollback): "Dock apply failed (\(original)); restoring the previous Dock also failed (\(rollback))."
        case .interruptedTransaction: "An interrupted Dock change could not be recovered. The saved recovery data remains available for the next launch."
        }
    }
}

@MainActor
final class UserDefaultsDockPreferencesBackend: DockPreferencesBackend {
    private let domain = "com.apple.dock"
    private let key = "persistent-apps"

    func readCurrentTiles() throws -> [[String: Any]] {
        guard let defaults = UserDefaults(suiteName: domain),
              let tiles = defaults.array(forKey: key) as? [[String: Any]] else {
            throw NativeDockError.preferencesUnavailable
        }
        return tiles
    }

    func writeTiles(_ tiles: [[String: Any]]) throws {
        guard let defaults = UserDefaults(suiteName: domain) else { throw NativeDockError.preferencesUnavailable }
        defaults.set(tiles, forKey: key)
        guard defaults.synchronize() else { throw NativeDockError.preferencesUnavailable }
    }
}

@MainActor
final class FileDockTransactionJournal: DockTransactionJournal {
    private struct Record: Codable {
        var version = 1
        var createdAt = Date.now
        var profileID: UUID
        var snapshot: Data
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.fileURL = fileURL ?? root.appendingPathComponent(Product.name, isDirectory: true)
            .appendingPathComponent("Transactions/native-dock.json")
    }

    func begin(snapshot: [[String: Any]], profileID: UUID) throws {
        let propertyList = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        let record = Record(profileID: profileID, snapshot: propertyList)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    func pendingSnapshot() throws -> [[String: Any]]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(Record.self, from: Data(contentsOf: fileURL))
            guard record.version == 1,
                  let tiles = try PropertyListSerialization.propertyList(from: record.snapshot, options: [], format: nil) as? [[String: Any]] else {
                throw NativeDockError.interruptedTransaction
            }
            return tiles
        } catch {
            throw NativeDockError.interruptedTransaction
        }
    }

    func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

@MainActor
final class ProcessDockRelauncher: DockRelaunching {
    func restartDock() async throws {
        let status = try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = ["Dock"]
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }.value
        guard status == 0 else { throw NativeDockError.preferencesUnavailable }
    }
}

@MainActor
final class NativeDockController {
    static let shared = NativeDockController(freezeProvider: ScreenCaptureDockSwitchFreezeProvider {
        ProfileStore.shared.state.settings.smoothNativeDockSwitches
    })

    private let backend: DockPreferencesBackend
    private let relauncher: DockRelaunching
    private let journal: DockTransactionJournal
    private let freezeProvider: DockSwitchFreezeProviding
    private let gate = DockSystemOperationGate.shared
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "native-dock")

    init(backend: DockPreferencesBackend = UserDefaultsDockPreferencesBackend(),
         relauncher: DockRelaunching = ProcessDockRelauncher(),
         journal: DockTransactionJournal = FileDockTransactionJournal(),
         freezeProvider: DockSwitchFreezeProviding = NoDockSwitchFreezeProvider()) {
        self.backend = backend
        self.relauncher = relauncher
        self.journal = journal
        self.freezeProvider = freezeProvider
    }

    func readCurrentItems() -> [DockItem] {
        do { return NativeDockSerializer.items(from: try backend.readCurrentTiles()) }
        catch {
            logger.error("Could not read current Dock preferences")
            return []
        }
    }

    func apply(_ profile: DockProfile) async throws {
        guard profile.kind == .native else { throw NativeDockError.unsupportedItem(profile.name) }
        await gate.acquire()
        do {
            let snapshot = try backend.readCurrentTiles()
            let nextTiles = try NativeDockSerializer.tiles(for: profile.items, using: snapshot)
            try await transact(nextTiles, snapshot: snapshot, profileID: profile.id)
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    func recoverInterruptedTransaction() async throws {
        await gate.acquire()
        do {
            if let snapshot = try journal.pendingSnapshot() {
                try backend.writeTiles(snapshot)
                try await relauncher.restartDock()
                try await verify(snapshot: snapshot)
                try journal.clear()
                logger.notice("Recovered an interrupted native Dock transaction")
            }
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    private func transact(_ nextTiles: [[String: Any]], snapshot: [[String: Any]], profileID: UUID) async throws {
        try journal.begin(snapshot: snapshot, profileID: profileID)
        let freezeSession = await freezeProvider.beginIfEnabled()
        do {
            try backend.writeTiles(nextTiles)
            try await relauncher.restartDock()
            try await verify(expectedSignatures: NativeDockSerializer.signatures(from: nextTiles))
            try journal.clear()
            if let freezeSession { freezeProvider.end(freezeSession) }
            logger.notice("Applied native Dock profile \(profileID.uuidString, privacy: .public)")
        } catch {
            let originalError = error.localizedDescription
            do {
                try backend.writeTiles(snapshot)
                try await relauncher.restartDock()
                try await verify(snapshot: snapshot)
                try journal.clear()
            } catch {
                if let freezeSession { freezeProvider.end(freezeSession) }
                logger.fault("Native Dock apply and rollback both failed")
                throw NativeDockError.rollbackFailed(original: originalError, rollback: error.localizedDescription)
            }
            if let freezeSession { freezeProvider.end(freezeSession) }
            throw error
        }
    }

    private func verify(expectedSignatures: [String]) async throws {
        for attempt in 0..<20 {
            if NativeDockSerializer.signatures(from: try backend.readCurrentTiles()) == expectedSignatures { return }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(250)) }
        }
        throw NativeDockError.verificationFailed
    }

    private func verify(snapshot: [[String: Any]]) async throws {
        for attempt in 0..<20 {
            if NativeDockSerializer.plistArraysEqual(try backend.readCurrentTiles(), snapshot) { return }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(250)) }
        }
        throw NativeDockError.verificationFailed
    }
}

enum NativeDockSerializer {
    static func items(from tiles: [[String: Any]]) -> [DockItem] {
        tiles.compactMap { tile in
            guard let type = tile["tile-type"] as? String else { return nil }
            if type == "small-spacer-tile" { return .spacer(.small) }
            if type == "spacer-tile" { return .spacer(.regular) }
            guard type == "file-tile",
                  let tileData = tile["tile-data"] as? [String: Any],
                  let fileData = tileData["file-data"] as? [String: Any],
                  let rawURL = fileData["_CFURLString"] as? String,
                  let url = URL(string: rawURL), url.isFileURL else { return nil }
            let label = tileData["file-label"] as? String ?? url.deletingPathExtension().lastPathComponent
            return DockItem(type: .application, title: label, url: url, bundleIdentifier: tileData["bundle-identifier"] as? String)
        }
    }

    static func tiles(for items: [DockItem], using snapshot: [[String: Any]]) throws -> [[String: Any]] {
        let template = snapshot.first { $0["tile-type"] as? String == "file-tile" }
        return try items.map { item in
            switch item.type {
            case .spacer:
                guard let spacerKind = item.spacerKind else { throw NativeDockError.unsupportedItem(item.title) }
                return ["tile-type": spacerKind == .small ? "small-spacer-tile" : "spacer-tile"]
            case .application:
                guard let url = item.url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                    throw NativeDockError.missingApplication(item.title)
                }
                return try applicationTile(item, url: url, template: template)
            default:
                throw NativeDockError.unsupportedItem(item.title)
            }
        }
    }

    static func signatures(from tiles: [[String: Any]]) -> [String] {
        items(from: tiles).map { item in
            if item.type == .spacer { return "spacer:\(item.spacerKind?.rawValue ?? "unknown")" }
            return "application:\(item.url?.standardizedFileURL.path ?? item.title)"
        }
    }

    static func plistArraysEqual(_ lhs: [[String: Any]], _ rhs: [[String: Any]]) -> Bool {
        (lhs as NSArray).isEqual(to: rhs)
    }

    private static func applicationTile(_ item: DockItem, url: URL, template: [String: Any]?) throws -> [String: Any] {
        let bookmark: Data
        do { bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw NativeDockError.missingApplication(item.title) }

        var tile = template ?? ["tile-type": "file-tile", "GUID": Int.random(in: 1..<Int.max)]
        var tileData = tile["tile-data"] as? [String: Any] ?? [:]
        var fileData = tileData["file-data"] as? [String: Any] ?? [:]
        fileData["_CFURLString"] = url.standardizedFileURL.absoluteString
        fileData["_CFURLStringType"] = 15
        tileData["file-data"] = fileData
        tileData["file-label"] = item.title
        tileData["book"] = bookmark
        tileData["bundle-identifier"] = item.bundleIdentifier ?? Bundle(url: url)?.bundleIdentifier ?? ""
        if tileData["file-type"] == nil { tileData["file-type"] = 41 }
        if tileData["file-mod-date"] == nil { tileData["file-mod-date"] = 0 }
        if tileData["parent-mod-date"] == nil { tileData["parent-mod-date"] = 0 }
        if tileData["dock-extra"] == nil { tileData["dock-extra"] = false }
        if tileData["is-beta"] == nil { tileData["is-beta"] = false }
        tile["GUID"] = Int.random(in: 1..<Int.max)
        tile["tile-data"] = tileData
        tile["tile-type"] = "file-tile"
        return tile
    }
}
