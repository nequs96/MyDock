import Foundation

@MainActor
protocol DockAutoHidePreferencesBackend {
    func readAutoHideSetting() throws -> Bool?
    func writeAutoHideSetting(_ value: Bool?) throws
}

@MainActor
final class UserDefaultsDockAutoHideBackend: DockAutoHidePreferencesBackend {
    private let domain = "com.apple.dock"
    private let key = "autohide"

    func readAutoHideSetting() throws -> Bool? {
        guard let defaults = UserDefaults(suiteName: domain) else { throw NativeDockError.preferencesUnavailable }
        let value = defaults.persistentDomain(forName: domain)?[key] as? NSNumber
        return value?.boolValue
    }

    func writeAutoHideSetting(_ value: Bool?) throws {
        guard let defaults = UserDefaults(suiteName: domain) else { throw NativeDockError.preferencesUnavailable }
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
        guard defaults.synchronize() else { throw NativeDockError.preferencesUnavailable }
    }
}

@MainActor
final class NativeDockAutoHideController {
    private struct RecoveryRecord: Codable {
        var version = 1
        var originalValue: Bool?
    }

    static let shared = NativeDockAutoHideController()
    private static let recoveryKey = "nativeDockAutoHideRecoveryRecord"

    private let backend: DockAutoHidePreferencesBackend
    private let relauncher: DockRelaunching
    private let defaults: UserDefaults
    private let gate = DockSystemOperationGate.shared

    init(backend: DockAutoHidePreferencesBackend = UserDefaultsDockAutoHideBackend(),
         relauncher: DockRelaunching = ProcessDockRelauncher(),
         defaults: UserDefaults = .standard) {
        self.backend = backend
        self.relauncher = relauncher
        self.defaults = defaults
    }

    var hasPendingRestore: Bool { defaults.data(forKey: Self.recoveryKey) != nil }

    func setCustomDockMain(_ enabled: Bool) async throws {
        await gate.acquire()
        do {
            if enabled { try await enableAutoHide() }
            else { try await restoreOriginalSetting() }
            await gate.release()
        } catch {
            await gate.release()
            throw error
        }
    }

    func restoreBeforeExit() async throws {
        try await setCustomDockMain(false)
    }

    private func enableAutoHide() async throws {
        let existingRecord = try recoveryRecord()
        let original = try backend.readAutoHideSetting()
        if existingRecord == nil {
            let record = RecoveryRecord(originalValue: original)
            defaults.set(try JSONEncoder().encode(record), forKey: Self.recoveryKey)
        }
        guard original != true else { return }
        do {
            try backend.writeAutoHideSetting(true)
            try await relauncher.restartDock()
            try verify(expected: true)
        } catch {
            let originalError = error.localizedDescription
            do {
                try backend.writeAutoHideSetting(original)
                try await relauncher.restartDock()
                try verify(expected: original)
                defaults.removeObject(forKey: Self.recoveryKey)
            } catch {
                throw NativeDockError.rollbackFailed(original: originalError, rollback: error.localizedDescription)
            }
            throw error
        }
    }

    private func restoreOriginalSetting() async throws {
        guard let record = try recoveryRecord() else { return }
        let current = try backend.readAutoHideSetting()
        if current != record.originalValue {
            try backend.writeAutoHideSetting(record.originalValue)
            try await relauncher.restartDock()
            try verify(expected: record.originalValue)
        }
        defaults.removeObject(forKey: Self.recoveryKey)
    }

    private func recoveryRecord() throws -> RecoveryRecord? {
        guard let data = defaults.data(forKey: Self.recoveryKey) else { return nil }
        do {
            let record = try JSONDecoder().decode(RecoveryRecord.self, from: data)
            guard record.version == 1 else { throw NativeDockError.interruptedTransaction }
            return record
        } catch {
            throw NativeDockError.interruptedTransaction
        }
    }

    private func verify(expected: Bool?) throws {
        guard try backend.readAutoHideSetting() == expected else { throw NativeDockError.verificationFailed }
    }
}

actor DockSystemOperationGate {
    static let shared = DockSystemOperationGate()

    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { continuation in waiters.append(continuation) }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
