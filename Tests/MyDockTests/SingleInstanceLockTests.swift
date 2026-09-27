import Foundation
import Testing
@testable import MyDock

struct SingleInstanceLockTests {
    @Test func onlyOneOwnerCanHoldTheProfileStoreLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("instance.lock")

        var first: SingleInstanceLock? = try SingleInstanceLock(fileURL: file)
        #expect(first != nil)
        #expect(throws: SingleInstanceLockError.alreadyRunning) {
            _ = try SingleInstanceLock(fileURL: file)
        }
        first = nil
        _ = try SingleInstanceLock(fileURL: file)
    }
}
