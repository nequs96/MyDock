import AppKit
import Foundation
import Testing
@testable import MyDock

@MainActor
struct WindowPreviewCacheTests {
    @Test func cacheIdentitySurvivesProcessRestartAndRejectsDuplicateTitles() {
        let original = descriptor(processID: 42, windowIndex: 1, title: "Planning")
        let relaunched = descriptor(processID: 900, windowIndex: 0, title: " Planning ")
        let originalKey = WindowPreviewCacheIdentity.uniqueKeys(for: [original])[original.id]
        let relaunchedKey = WindowPreviewCacheIdentity.uniqueKeys(for: [relaunched])[relaunched.id]

        #expect(originalKey != nil)
        #expect(originalKey == relaunchedKey)

        let duplicate = descriptor(processID: 42, windowIndex: 2, title: "Planning")
        #expect(WindowPreviewCacheIdentity.uniqueKeys(for: [original, duplicate]).isEmpty)

        let otherApp = descriptor(processID: 43, windowIndex: 0, title: "Planning", bundleIdentifier: "com.example.other")
        #expect(WindowPreviewCacheIdentity.uniqueKeys(for: [original, otherApp]).count == 2)

        var repeatedIdentifierA = descriptor(processID: 42, windowIndex: 3, title: "First")
        var repeatedIdentifierB = descriptor(processID: 42, windowIndex: 4, title: "Second")
        repeatedIdentifierA.accessibilityIdentifier = "same-window-id"
        repeatedIdentifierB.accessibilityIdentifier = "same-window-id"
        #expect(WindowPreviewCacheIdentity.uniqueKeys(for: [repeatedIdentifierA, repeatedIdentifierB]).isEmpty)
    }

    @Test func previewCacheSurvivesRecreationAndExpiresLocally() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyDock-WindowPreview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let key = String(repeating: "a", count: 64)
        let start = Date.now.addingTimeInterval(5)
        var currentDate = start
        let firstCache = WindowPreviewDiskCache(directoryURL: directory,
                                                now: { currentDate },
                                                maximumAge: 60)
        firstCache.store(testImage(), for: key)

        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(directoryPermissions?.intValue == 0o700)

        let relaunchedCache = WindowPreviewDiskCache(directoryURL: directory,
                                                     now: { currentDate },
                                                     maximumAge: 60)
        #expect(relaunchedCache.preview(for: key)?.image != nil)
        let file = directory.appendingPathComponent(key).appendingPathExtension("jpg")
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        currentDate = start.addingTimeInterval(61)
        #expect(relaunchedCache.preview(for: key) == nil)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func cacheRemovalAndEntryCapsBoundLocalStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MyDock-WindowPreview-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = WindowPreviewDiskCache(directoryURL: directory,
                                           maximumEntryCount: 1,
                                           maximumTotalBytes: 1024 * 1024)
        let first = String(repeating: "1", count: 64)
        let second = String(repeating: "2", count: 64)
        cache.store(testImage(), for: first)
        cache.store(testImage(), for: second)
        cache.pruneExpired()

        let jpgs = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "jpg" }
        #expect(jpgs.count == 1)

        cache.removeAll()
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    private func descriptor(processID: pid_t,
                            windowIndex: Int,
                            title: String,
                            bundleIdentifier: String = "com.example.editor") -> DockWindowDescriptor {
        DockWindowDescriptor(processID: processID,
                             windowIndex: windowIndex,
                             bundleIdentifier: bundleIdentifier,
                             applicationName: "Editor",
                             title: title,
                             isMinimized: false,
                             accessibilityIdentifier: nil)
    }

    private func testImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }
}
