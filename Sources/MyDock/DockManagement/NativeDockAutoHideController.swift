import Combine
import Foundation

/// Only the preferences owned by replacement mode. Nil preserves an absent key.
struct NativeDockVisibilitySettings: Codable, Equatable {
    var autoHide: Bool?
    var revealDelay: Double?
    var noBouncing: Bool?

    // A finite delay avoids undocumented infinity/negative-value behavior in Dock.
    // It prevents ordinary edge hover while the system Dock process keeps running.
    static let replacement = Self(autoHide: true, revealDelay: 86_400, noBouncing: true)
}

@MainActor
protocol DockAutoHidePreferencesBackend {
    func readVisibilitySettings() throws -> NativeDockVisibilitySettings
    func writeVisibilitySettings(_ settings: NativeDockVisibilitySettings) throws
}

@MainActor
final class UserDefaultsDockAutoHideBackend: DockAutoHidePreferencesBackend {
    private let domain = "com.apple.dock"

    func readVisibilitySettings() throws -> NativeDockVisibilitySettings {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard let defaults = UserDefaults(suiteName: domain) else { throw NativeDockError.preferencesUnavailable }
        let values = defaults.persistentDomain(forName: domain) ?? [:]
        let delay = (values["autohide-delay"] as? NSNumber)?.doubleValue
        guard delay?.isFinite != false else { throw NativeDockError.preferencesUnavailable }
        return NativeDockVisibilitySettings(autoHide: (values["autohide"] as? NSNumber)?.boolValue,
                                            revealDelay: delay,
                                            noBouncing: (values["no-bouncing"] as? NSNumber)?.boolValue)
    }

    func writeVisibilitySettings(_ settings: NativeDockVisibilitySettings) throws {
        try AppRuntimeEnvironment.requireNativeEffects()
        guard let defaults = UserDefaults(suiteName: domain), settings.revealDelay?.isFinite != false else {
            throw NativeDockError.preferencesUnavailable
        }
        // Update individual keys so unrelated Dock layout preferences remain owned by macOS.
        if let value = settings.autoHide { defaults.set(value, forKey: "autohide") }
        else { defaults.removeObject(forKey: "autohide") }
        if let value = settings.revealDelay { defaults.set(value, forKey: "autohide-delay") }
        else { defaults.removeObject(forKey: "autohide-delay") }
        if let value = settings.noBouncing { defaults.set(value, forKey: "no-bouncing") }
        else { defaults.removeObject(forKey: "no-bouncing") }
        guard defaults.synchronize() else { throw NativeDockError.preferencesUnavailable }
    }
}

@MainActor
final class NativeDockAutoHideController: ObservableObject {
    private struct RecoveryRecord: Codable {
        var version: Int
        var originalValue: Bool? // Recovery compatibility with the previous auto-hide-only mode.
        var originalSettings: NativeDockVisibilitySettings?

        init(original: NativeDockVisibilitySettings) {
            version = 2
            originalValue = original.autoHide
            originalSettings = original
        }

        func original(current: NativeDockVisibilitySettings) throws -> NativeDockVisibilitySettings {
            switch version {
            case 1:
                // The previous release never changed these other preferences.
                var settings = current
                settings.autoHide = originalValue
                return settings
            case 2:
                guard let originalSettings, originalSettings.revealDelay?.isFinite != false else {
                    throw NativeDockError.interruptedTransaction
                }
                return originalSettings
            default: throw NativeDockError.interruptedTransaction
            }
        }
    }

    static let shared = NativeDockAutoHideController()
    @Published private(set) var errorMessage: String?
    private static let recoveryKey = "nativeDockAutoHideRecoveryRecord"

    private let backend: DockAutoHidePreferencesBackend
    private let relauncher: DockRelaunching
    private let defaults: UserDefaults
    private let gate = DockSystemOperationGate.shared

    init(backend: DockAutoHidePreferencesBackend = UserDefaultsDockAutoHideBackend(),
         relauncher: DockRelaunching = ProcessDockRelauncher(),
         defaults: UserDefaults = AppRuntimeEnvironment.defaults) {
        self.backend = backend
        self.relauncher = relauncher
        self.defaults = defaults
    }

    var hasPendingRestore: Bool { defaults.data(forKey: Self.recoveryKey) != nil }

    func setCustomDockMain(_ enabled: Bool) async throws {
        await gate.acquire()
        do {
            if enabled { try await enableReplacement() }
            else { try await restoreOriginalSetting() }
            errorMessage = nil
            await gate.release()
        } catch {
            errorMessage = enabled
                ? "The Custom Dock could not replace the macOS Dock. \(error.localizedDescription)"
                : "The macOS Dock's previous settings could not be restored. \(error.localizedDescription)"
            await gate.release()
            throw error
        }
    }

    func restoreBeforeExit() async throws { try await setCustomDockMain(false) }

    private func enableReplacement() async throws {
        let existingRecord = try recoveryRecord()
        let current = try backend.readVisibilitySettings()
        if existingRecord == nil || existingRecord?.version == 1 {
            let original = try existingRecord?.original(current: current) ?? current
            // Persist all original keys before changing the system, including absent keys.
            defaults.set(try JSONEncoder().encode(RecoveryRecord(original: original)), forKey: Self.recoveryKey)
            guard defaults.synchronize() else { throw NativeDockError.preferencesUnavailable }
        }
        guard current != .replacement else { return }
        do {
            try backend.writeVisibilitySettings(.replacement)
            try await relauncher.restartDock()
            try verify(expected: .replacement)
        } catch {
            let originalError = error.localizedDescription
            do {
                try backend.writeVisibilitySettings(current)
                try await relauncher.restartDock()
                try verify(expected: current)
                // Re-enabling must retain a previous session's original settings.
                if existingRecord == nil { defaults.removeObject(forKey: Self.recoveryKey) }
            } catch {
                throw NativeDockError.rollbackFailed(original: originalError, rollback: error.localizedDescription)
            }
            throw error
        }
    }

    private func restoreOriginalSetting() async throws {
        guard let record = try recoveryRecord() else { return }
        let current = try backend.readVisibilitySettings()
        let original = try record.original(current: current)
        if current != original {
            try backend.writeVisibilitySettings(original)
            try await relauncher.restartDock()
            try verify(expected: original)
        }
        defaults.removeObject(forKey: Self.recoveryKey)
    }

    private func recoveryRecord() throws -> RecoveryRecord? {
        guard let data = defaults.data(forKey: Self.recoveryKey) else { return nil }
        do {
            let record = try JSONDecoder().decode(RecoveryRecord.self, from: data)
            guard record.version == 1 || (record.version == 2 && record.originalSettings != nil) else {
                throw NativeDockError.interruptedTransaction
            }
            return record
        } catch { throw NativeDockError.interruptedTransaction }
    }

    private func verify(expected: NativeDockVisibilitySettings) throws {
        guard try backend.readVisibilitySettings() == expected else { throw NativeDockError.verificationFailed }
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
