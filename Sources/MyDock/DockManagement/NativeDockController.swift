import AppKit
import Combine
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
        guard let defaults = UserDefaults(suiteName: domain) else {
            throw NativeDockError.preferencesUnavailable
        }
        _ = defaults.synchronize()
        guard let tiles = defaults.array(forKey: key) as? [[String: Any]] else {
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
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw NativeDockError.interruptedTransaction }
        let propertyList = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        let record = Record(profileID: profileID, snapshot: propertyList)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func pendingSnapshot() throws -> [[String: Any]]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(Record.self, from: BackupManager.boundedArchiveData(from: fileURL))
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
        let output = try await BoundedSubprocessCapture.runCancellable(executableURL: URL(fileURLWithPath: "/usr/bin/killall"),
            arguments: ["Dock"], maximumOutputBytes: 4_096, maximumErrorBytes: 4_096, timeout: 5)
        let status = output.terminationStatus
        guard status == 0 else { throw NativeDockError.preferencesUnavailable }
    }
}

enum NativeDockHealth: Equatable, Sendable { case ready, applying, recovering, recoveryRequired }

@MainActor
final class NativeDockController: ObservableObject {
    static let shared = NativeDockController(freezeProvider: ScreenCaptureDockSwitchFreezeProvider {
        ProfileStore.shared.state.settings.smoothNativeDockSwitches
    })

    private let backend: DockPreferencesBackend
    private let relauncher: DockRelaunching
    private let journal: DockTransactionJournal
    private let freezeProvider: DockSwitchFreezeProviding
    private let gate: DockSystemOperationGate
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "native-dock")
    @Published private(set) var health: NativeDockHealth = .ready
    @Published private(set) var recoveryError: String?
    private(set) var appliedGeneration: UInt64 = 0
    private(set) var lastAppliedSignatures: [String]?

    init(backend: DockPreferencesBackend = UserDefaultsDockPreferencesBackend(),
         relauncher: DockRelaunching = ProcessDockRelauncher(),
         journal: DockTransactionJournal = FileDockTransactionJournal(),
         freezeProvider: DockSwitchFreezeProviding = NoDockSwitchFreezeProvider(),
         gate: DockSystemOperationGate = .shared) {
        self.backend = backend
        self.relauncher = relauncher
        self.journal = journal
        self.freezeProvider = freezeProvider
        self.gate = gate
        do {
            if try journal.pendingSnapshot() != nil { health = .recoveryRequired; recoveryError = NativeDockError.interruptedTransaction.localizedDescription }
        } catch { health = .recoveryRequired; recoveryError = error.localizedDescription }
    }

    func readCurrentItems() throws -> [DockItem] {
        let tiles = try backend.readCurrentTiles()
        let items = NativeDockSerializer.items(from: tiles)
        guard items.count == tiles.count else {
            throw NativeDockError.unsupportedItem("An item in the current macOS Dock")
        }
        return items
    }

    func apply(_ profile: DockProfile) async throws {
        guard profile.kind == .native else { throw NativeDockError.unsupportedItem(profile.name) }
        await gate.acquire()
        DiagnosticsService.shared.record(.nativeApplyStarted)
        do {
            // Cancelled requests waiting behind another Dock transaction must
            // not change system preferences when their turn arrives.
            try Task.checkCancellation()
            guard try journal.pendingSnapshot() == nil else { throw NativeDockError.interruptedTransaction }
            health = .applying
            recoveryError = nil
            let snapshot = try backend.readCurrentTiles()
            let nextTiles = try NativeDockSerializer.tiles(for: profile.items, using: snapshot)
            try await transact(nextTiles, snapshot: snapshot, profileID: profile.id)
            health = .ready
            await gate.release()
        } catch {
            DiagnosticsService.shared.record(.nativeApplyFailed)
            recordRecoveryFailureIfNeeded(error)
            await gate.release()
            throw error
        }
    }

    func recoverInterruptedTransaction() async throws {
        await gate.acquire()
        health = .recovering
        do {
            if let snapshot = try journal.pendingSnapshot() {
                try backend.writeTiles(snapshot)
                try await relauncher.restartDock()
                try await verify(snapshot: snapshot)
                try journal.clear()
                lastAppliedSignatures = NativeDockSerializer.signatures(from: snapshot)
                appliedGeneration &+= 1
                logger.notice("Recovered an interrupted native Dock transaction")
                DiagnosticsService.shared.record(.nativeInterruptedRecoverySucceeded)
            }
            health = .ready
            recoveryError = nil
            await gate.release()
        } catch {
            health = .recoveryRequired
            recoveryError = error.localizedDescription
            await gate.release()
            throw error
        }
    }

    private func recordRecoveryFailureIfNeeded(_ error: Error) {
        do { health = try journal.pendingSnapshot() == nil ? .ready : .recoveryRequired }
        catch { health = .recoveryRequired }
        recoveryError = health == .recoveryRequired ? error.localizedDescription : nil
    }

    private func transact(_ nextTiles: [[String: Any]], snapshot: [[String: Any]], profileID: UUID) async throws {
        try journal.begin(snapshot: snapshot, profileID: profileID)
        let freezeSession = await freezeProvider.beginIfEnabled()
        do {
            try backend.writeTiles(nextTiles)
            try await relauncher.restartDock()
            try await verify(expectedSignatures: NativeDockSerializer.signatures(from: nextTiles))
            try journal.clear()
            lastAppliedSignatures = NativeDockSerializer.signatures(from: nextTiles)
            appliedGeneration &+= 1
            if let freezeSession { freezeProvider.end(freezeSession) }
            logger.notice("Applied native Dock profile")
            DiagnosticsService.shared.record(.nativeApplySucceeded)
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
                DiagnosticsService.shared.record(.nativeRollbackFailed)
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
        signatures(from: items(from: tiles))
    }

    static func signatures(from items: [DockItem]) -> [String] {
        items.map(signature(for:))
    }

    static func preservingIDs(in imported: [DockItem], from previous: [DockItem]) -> [DockItem] {
        var availableIDs: [String: ArraySlice<UUID>] = [:]
        for item in previous { availableIDs[signature(for: item), default: []].append(item.id) }
        return imported.map { importedItem in
            var result = importedItem
            let signature = signature(for: importedItem)
            if var ids = availableIDs[signature], let retainedID = ids.popFirst() {
                result.id = retainedID
                availableIDs[signature] = ids
            }
            return result
        }
    }

    private static func signature(for item: DockItem) -> String {
        if item.type == .spacer { return "spacer:\(item.spacerKind?.rawValue ?? "unknown")" }
        return "application:\(item.url?.standardizedFileURL.path ?? item.title)"
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
