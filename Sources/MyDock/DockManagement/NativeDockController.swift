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
    /// Also records the layout being applied, so launch recovery can tell whether the Dock still shows it.
    func begin(snapshot: [[String: Any]], target: [[String: Any]], profileID: UUID) throws
    func pendingSnapshot() throws -> [[String: Any]]?
    /// Signatures of the layout the interrupted change was applying; nil when the journal does not know it.
    func pendingTargetSignatures() throws -> [String]?
    func clear() throws
}

extension DockTransactionJournal {
    func begin(snapshot: [[String: Any]], target: [[String: Any]], profileID: UUID) throws {
        try begin(snapshot: snapshot, profileID: profileID)
    }
    func pendingTargetSignatures() throws -> [String]? { nil }
}

enum NativeDockError: LocalizedError {
    case preferencesUnavailable
    case missingApplication(String)
    case unsupportedItem(String)
    case dockDidNotSettle
    case visibilityNotApplied
    case dockRestartFailed
    /// The change failed and the previous layout is back; carries the failure's description.
    case restoredAfterFailure(String)
    case rollbackFailed(original: String, rollback: String)
    case interruptedTransaction
    case changedSinceInterruption

    var errorDescription: String? {
        switch self {
        case .preferencesUnavailable: "The current macOS Dock layout could not be read or saved."
        case .missingApplication(let title): "The application “\(title)” is missing or no longer accessible."
        case .unsupportedItem(let title): "“\(title)” cannot be stored in a macOS Dock profile."
        case .dockDidNotSettle: "The macOS Dock did not show the expected layout."
        case .visibilityNotApplied: "The macOS Dock did not keep the requested visibility settings."
        case .dockRestartFailed: "The macOS Dock could not be restarted."
        case .restoredAfterFailure(let reason): "\(reason) The previous layout was restored."
        case .rollbackFailed(let original, let rollback): "The Dock change failed (\(original)); restoring the previous Dock also failed (\(rollback))."
        case .interruptedTransaction: "An interrupted Dock change could not be recovered. The saved recovery data remains available for the next launch."
        case .changedSinceInterruption: "An earlier Dock change was interrupted, and the Dock has changed since, so it was not restored automatically. Restore Previous Dock returns to the layout from before that change."
        }
    }
}

@MainActor
final class UserDefaultsDockPreferencesBackend: DockPreferencesBackend {
    private let domain = "com.apple.dock"
    private let key = "persistent-apps"

    func readCurrentTiles() throws -> [[String: Any]] {
        try AppRuntimeEnvironment.requireNativeEffects()
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
        try AppRuntimeEnvironment.requireNativeEffects()
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
        /// Absent in journals written before targets were recorded.
        var targetSignatures: [String]?
    }

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        // Production: ~/Library/Application Support/MyDock/Transactions. Isolated runs stay inside their own root.
        self.fileURL = fileURL ?? AppRuntimeEnvironment.applicationSupportDirectory
            .appendingPathComponent("Transactions/native-dock.json")
    }

    func begin(snapshot: [[String: Any]], profileID: UUID) throws {
        try write(snapshot: snapshot, targetSignatures: nil, profileID: profileID)
    }

    func begin(snapshot: [[String: Any]], target: [[String: Any]], profileID: UUID) throws {
        try write(snapshot: snapshot, targetSignatures: NativeDockSerializer.signatures(from: target), profileID: profileID)
    }

    private func write(snapshot: [[String: Any]], targetSignatures: [String]?, profileID: UUID) throws {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { throw NativeDockError.interruptedTransaction }
        let propertyList = try PropertyListSerialization.data(fromPropertyList: snapshot, format: .binary, options: 0)
        let record = Record(profileID: profileID, snapshot: propertyList, targetSignatures: targetSignatures)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func pendingSnapshot() throws -> [[String: Any]]? {
        guard let record = try pendingRecord() else { return nil }
        do {
            guard let tiles = try PropertyListSerialization.propertyList(from: record.snapshot, options: [], format: nil) as? [[String: Any]] else {
                throw NativeDockError.interruptedTransaction
            }
            return tiles
        } catch {
            throw NativeDockError.interruptedTransaction
        }
    }

    func pendingTargetSignatures() throws -> [String]? {
        try pendingRecord()?.targetSignatures
    }

    private func pendingRecord() throws -> Record? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let record = try decoder.decode(Record.self, from: BackupManager.boundedArchiveData(from: fileURL))
            guard record.version == 1 else { throw NativeDockError.interruptedTransaction }
            return record
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
    private static let dockBundleIdentifier = "com.apple.dock"

    /// Returns once a new Dock process has finished launching and had a moment to load its preferences
    /// (bounded), so verification reads what the relaunched Dock kept and a switch freeze lasts until it draws.
    func restartDock() async throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        let previousProcessID = Self.runningDock()?.processIdentifier
        let output = try await BoundedSubprocessCapture.runCancellable(executableURL: URL(fileURLWithPath: "/usr/bin/killall"),
            arguments: ["Dock"], maximumOutputBytes: 4_096, maximumErrorBytes: 4_096, timeout: 5)
        let status = output.terminationStatus
        guard status == 0 else { throw NativeDockError.dockRestartFailed }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if let dock = Self.runningDock(), dock.processIdentifier != previousProcessID, dock.isFinishedLaunching {
                try await Task.sleep(for: .milliseconds(300))
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // launchd normally relaunches the Dock well within the deadline; verification decides either way.
    }

    private static func runningDock() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first { !$0.isTerminated }
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
    private let verifyAttempts: Int
    private let verifyInterval: Duration
    /// The newest `applyLatest` request; older requests still waiting for the gate give way to it.
    private var latestRequest: UUID?
    private let logger = Logger(subsystem: Product.bundleIdentifier, category: "native-dock")
    @Published private(set) var health: NativeDockHealth = .ready
    @Published private(set) var recoveryError: String?
    private(set) var appliedGeneration: UInt64 = 0
    private(set) var lastAppliedSignatures: [String]?

    init(backend: DockPreferencesBackend = UserDefaultsDockPreferencesBackend(),
         relauncher: DockRelaunching = ProcessDockRelauncher(),
         journal: DockTransactionJournal = FileDockTransactionJournal(),
         freezeProvider: DockSwitchFreezeProviding = NoDockSwitchFreezeProvider(),
         gate: DockSystemOperationGate = .shared,
         verifyAttempts: Int = 20,
         verifyInterval: Duration = .milliseconds(250)) {
        self.backend = backend
        self.relauncher = relauncher
        self.journal = journal
        self.freezeProvider = freezeProvider
        self.gate = gate
        self.verifyAttempts = max(1, verifyAttempts)
        self.verifyInterval = verifyInterval
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
        _ = try await apply(profile, onlyIfLatest: nil)
    }

    /// For quick successive picks (menus): a request that is no longer the newest when its turn comes
    /// returns false without touching the Dock, so only the last pick restarts it.
    @discardableResult
    func applyLatest(_ profile: DockProfile) async throws -> Bool {
        let request = UUID()
        latestRequest = request
        return try await apply(profile, onlyIfLatest: request)
    }

    private func apply(_ profile: DockProfile, onlyIfLatest request: UUID?) async throws -> Bool {
        guard profile.kind == .native else { throw NativeDockError.unsupportedItem(profile.name) }
        await gate.acquire()
        if let request, request != latestRequest {
            await gate.release()
            return false
        }
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
            return true
        } catch {
            DiagnosticsService.shared.record(.nativeApplyFailed)
            recordRecoveryFailureIfNeeded(error)
            await gate.release()
            throw error
        }
    }

    /// Puts back the layout from before an interrupted change. At launch (`automatic`) it does so only while the Dock
    /// still shows that change; when the Dock already shows the earlier layout the journal is simply cleared, and when
    /// the Dock has changed since, restoring would overwrite those changes, so Restore Previous Dock decides.
    func recoverInterruptedTransaction(automatic: Bool = false) async throws {
        await gate.acquire()
        health = .recovering
        do {
            if let snapshot = try journal.pendingSnapshot() {
                let needsRestore: Bool
                if automatic {
                    let current = NativeDockSerializer.signatures(from: try backend.readCurrentTiles())
                    if current == NativeDockSerializer.signatures(from: snapshot) {
                        needsRestore = false
                    } else if try journal.pendingTargetSignatures() == current {
                        needsRestore = true
                    } else {
                        health = .recoveryRequired
                        recoveryError = NativeDockError.changedSinceInterruption.localizedDescription
                        logger.notice("Left an interrupted native Dock transaction for the user: the Dock changed since")
                        await gate.release()
                        return
                    }
                } else {
                    needsRestore = true
                }
                if needsRestore {
                    try backend.writeTiles(snapshot)
                    try await relauncher.restartDock()
                    try await verify(snapshot: snapshot)
                }
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
            logger.error("Could not recover an interrupted native Dock transaction: \(error.localizedDescription, privacy: .private)")
            DiagnosticsService.shared.record(.nativeInterruptedRecoveryFailed)
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
        try journal.begin(snapshot: snapshot, target: nextTiles, profileID: profileID)
        let freezeSession = await freezeProvider.beginIfEnabled()
        if Task.isCancelled {
            // Nothing has been written yet, so a cancelled apply leaves the Dock untouched.
            if let freezeSession { freezeProvider.end(freezeSession) }
            try journal.clear()
            throw CancellationError()
        }
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
                try await restoreJournaledSnapshot()
            } catch {
                if let freezeSession { freezeProvider.end(freezeSession) }
                logger.fault("Native Dock apply and rollback both failed")
                DiagnosticsService.shared.record(.nativeRollbackFailed)
                throw NativeDockError.rollbackFailed(original: originalError, rollback: error.localizedDescription)
            }
            if let freezeSession { freezeProvider.end(freezeSession) }
            if error is CancellationError { throw error }
            throw NativeDockError.restoredAfterFailure(originalError)
        }
    }

    /// Puts back the layout `journal.begin` recorded and clears the journal once the Dock shows it again. The work runs
    /// in its own task: a cancelled apply (an App Intent, a superseded switch) must still finish the restore, and in
    /// the cancelled task `killall` and the verification sleeps would stop at once.
    private func restoreJournaledSnapshot() async throws {
        try await Task { @MainActor in
            guard let snapshot = try self.journal.pendingSnapshot() else { return }
            try self.backend.writeTiles(snapshot)
            try await self.relauncher.restartDock()
            try await self.verify(snapshot: snapshot)
            try self.journal.clear()
        }.value
    }

    private func verify(expectedSignatures: [String]) async throws {
        for attempt in 0..<verifyAttempts {
            if NativeDockSerializer.signatures(from: try backend.readCurrentTiles()) == expectedSignatures { return }
            if attempt < verifyAttempts - 1 { try await Task.sleep(for: verifyInterval) }
        }
        throw NativeDockError.dockDidNotSettle
    }

    private func verify(snapshot: [[String: Any]]) async throws {
        for attempt in 0..<verifyAttempts {
            if NativeDockSerializer.plistArraysEqual(try backend.readCurrentTiles(), snapshot) { return }
            if attempt < verifyAttempts - 1 { try await Task.sleep(for: verifyInterval) }
        }
        throw NativeDockError.dockDidNotSettle
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

    /// An app already in the Dock keeps its own tile (GUID and metadata). A new app gets a fresh tile with
    /// only the documented keys, never another app's metadata.
    static func tiles(for items: [DockItem], using snapshot: [[String: Any]]) throws -> [[String: Any]] {
        var existingTiles: [String: [String: Any]] = [:]
        for tile in snapshot where tile["tile-type"] as? String == "file-tile" {
            guard let path = applicationPath(of: tile), existingTiles[path] == nil else { continue }
            existingTiles[path] = tile
        }
        return try items.map { item in
            switch item.type {
            case .spacer:
                guard let spacerKind = item.spacerKind else { throw NativeDockError.unsupportedItem(item.title) }
                return ["tile-type": spacerKind == .small ? "small-spacer-tile" : "spacer-tile"]
            case .application:
                guard let url = item.url, url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
                    throw NativeDockError.missingApplication(item.title)
                }
                // Each existing tile is reused once, so a duplicated app never shares a GUID.
                let existing = existingTiles.removeValue(forKey: url.standardizedFileURL.path)
                return try applicationTile(item, url: url, existing: existing)
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

    private static func applicationPath(of tile: [String: Any]) -> String? {
        guard let tileData = tile["tile-data"] as? [String: Any],
              let fileData = tileData["file-data"] as? [String: Any],
              let rawURL = fileData["_CFURLString"] as? String,
              let url = URL(string: rawURL), url.isFileURL else { return nil }
        return url.standardizedFileURL.path
    }

    /// Dock-authored GUIDs fit in 32 bits.
    static func newTileGUID() -> Int { Int(UInt32.random(in: 1...UInt32.max)) }

    private static func applicationTile(_ item: DockItem, url: URL, existing: [String: Any]?) throws -> [String: Any] {
        let bookmark: Data
        do { bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) }
        catch { throw NativeDockError.missingApplication(item.title) }

        var tile = existing ?? ["tile-type": "file-tile", "GUID": newTileGUID()]
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
        if tile["GUID"] == nil { tile["GUID"] = newTileGUID() }
        tile["tile-data"] = tileData
        tile["tile-type"] = "file-tile"
        return tile
    }
}

/// Applies a native Dock picked from a menu. Quick successive picks write only the newest one, and a
/// failure alert comes forward even though MyDock runs as an accessory app.
@MainActor
enum NativeDockSwitcher {
    static func apply(_ profile: DockProfile, store: ProfileStore) {
        Task { @MainActor in
            do {
                guard try await NativeDockController.shared.applyLatest(profile) else { return }
                store.recordAppliedNativeProfile(profile.id)
            } catch {
                guard AppRuntimeEnvironment.allowsNativeEffects else { return }
                let alert = NSAlert()
                alert.messageText = "Could not switch the macOS Dock"
                alert.informativeText = error.localizedDescription
                AppActivation.activateSelf()
                alert.runModal()
            }
        }
    }
}
