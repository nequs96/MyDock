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

    /// S05-005/S09-002: macOS protects ~/.Trash. Without Full Disk Access the count is unknown, which is a calm
    /// state with its own setup row, not an error.
    @Test func aProtectedTrashAsksForAccessInsteadOfReportingAnError() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("N4-protected-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let status = TrashStatus(trashURL: dir, allowsNativeEffects: true)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !status.needsFullDiskAccess, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(status.needsFullDiskAccess)
        #expect(status.errorMessage == nil && status.itemCount == 0)
    }

    @Test func noAccessIsRecognisedAndStillAllowsEmptyingThroughFinder() {
        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError,
                             userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        #expect(TrashContentsReader.isPermissionDenied(denied))
        #expect(TrashContentsReader.isPermissionDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        #expect(!TrashContentsReader.isPermissionDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError)))
        let face = TrashFacePresentation(count: 0, errorMessage: nil, needsAccess: true)
        #expect(face.label == "No access" && face.symbol == "trash" && !face.isFull && face.isUnavailable)
        #expect(TrashFacePresentation.heroValue(count: 0, errorMessage: nil, needsAccess: true) == "No access")
        #expect(TrashFacePresentation.heroCaption(count: 0, errorMessage: nil, needsAccess: true) == nil)
        #expect(TrashFacePresentation.canEmpty(count: 0, errorMessage: nil, needsAccess: true))
        #expect(!TrashFacePresentation.canEmpty(count: 0, errorMessage: nil, needsAccess: false))
        #expect(!TrashFacePresentation.canEmpty(count: 3, errorMessage: "Read failed", needsAccess: false))
        #expect(TrashFacePresentation.canEmpty(count: 3, errorMessage: nil, needsAccess: false))
    }
}
