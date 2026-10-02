import Foundation
import Testing
@testable import MyDock

/// Opt-in only: this test deliberately changes Apple's Dock and must run in a disposable login.
@MainActor
struct DisposableSystemAcceptanceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MYDOCK_DISPOSABLE_SYSTEM_TESTS"] == "1"))
    func nativeApplyRestoreAndJournalRecovery() async throws {
        let backend = UserDefaultsDockPreferencesBackend()
        let original = try backend.readCurrentTiles()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let journal = FileDockTransactionJournal(fileURL: folder.appendingPathComponent("native-journal.json"))
        let controller = NativeDockController(backend: backend, relauncher: ProcessDockRelauncher(), journal: journal)
        let items = try controller.readCurrentItems()
        do {
            try await controller.apply(DockProfile(name: "Acceptance temporary Dock", kind: .native, items: items + [.spacer(.small)]))
            #expect(try NativeDockSerializer.signatures(from: backend.readCurrentTiles()).last == "spacer:small")
            try journal.begin(snapshot: original, profileID: UUID())
            try await controller.recoverInterruptedTransaction()
            #expect(try NativeDockSerializer.plistArraysEqual(backend.readCurrentTiles(), original))
            #expect(try journal.pendingSnapshot() == nil)
            try? FileManager.default.removeItem(at: folder)
        } catch {
            // Preserve the recovery journal when restoration itself fails.
            if try journal.pendingSnapshot() == nil { try journal.begin(snapshot: original, profileID: UUID()) }
            try await controller.recoverInterruptedTransaction()
            throw error
        }
    }
}
