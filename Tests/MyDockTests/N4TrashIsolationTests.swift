import Foundation
import Testing
@testable import MyDock

@MainActor
struct N4TrashIsolationTests {
    @Test func isolatedStatusDoesNotWatchAndReportsUnavailable() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("N4-no-trash-\(UUID().uuidString)", isDirectory: true)
        let status = TrashStatus(trashURL: missing, allowsNativeEffects: false)
        status.refresh()
        #expect(status.watchAttemptCount == 0)
        #expect(status.itemCount == 0)
        #expect(status.errorMessage == TrashStatus.isolatedMessage)
    }

    @Test func nativeStatusStillWatches() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("N4-trash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let status = TrashStatus(trashURL: dir, allowsNativeEffects: true)
        #expect(status.watchAttemptCount == 1)
        #expect(status.errorMessage == nil)
    }
}
