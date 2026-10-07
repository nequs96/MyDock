import AppKit
import ApplicationServices
import Foundation
import Testing
@testable import MyDock

/// Lane C audit fixes: OS services, the Dock window, the native Dock and the app shell.
/// Fixtures only: nothing here touches the real Dock, its preferences or user files.
@MainActor
@Suite struct AuditLaneCTests {
    // MARK: Refresh scheduler (S05-006)

    @Test func nearlyDueSubscriptionsShareAWakeUp() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: true)
        let start = Date()
        let stream = scheduler.ticks(every: 10)
        _ = stream
        let before = scheduler.deliveredTickCount
        scheduler.fireDueSubscriptions(now: start.addingTimeInterval(5))
        #expect(scheduler.deliveredTickCount == before)
        // Due within its coalescing window (one second for a 10 s interval): fires with this wake-up.
        scheduler.fireDueSubscriptions(now: start.addingTimeInterval(9.5))
        #expect(scheduler.deliveredTickCount == before + 1)
        #expect(RefreshSchedulePolicy.coalescingWindow(forInterval: 60) == 1)
        #expect(RefreshSchedulePolicy.coalescingWindow(forInterval: 4) < 0.5)
        #expect(RefreshSchedulePolicy.timerTolerance(forDelay: 0.2) == 0.1)
        #expect(RefreshSchedulePolicy.timerTolerance(forDelay: 120) == 1)
    }

    @Test func anAwaySessionStopsTicksUntilItReturns() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: true)
        let stream = scheduler.ticks(every: 1)
        _ = stream
        #expect(scheduler.hasArmedTimer)
        scheduler.setSystemAway(true)
        #expect(!scheduler.isActive && !scheduler.hasArmedTimer)
        let before = scheduler.deliveredTickCount
        scheduler.fireDueSubscriptions(now: .now.addingTimeInterval(60))
        #expect(scheduler.deliveredTickCount == before)
        scheduler.setSystemAway(false)
        #expect(scheduler.isActive && scheduler.hasArmedTimer)
    }

    // MARK: Reveal monitor (S07-011)

    @Test func pointerBurstsRunOneRevealSample() async throws {
        let counter = LaneCCounter()
        let monitor = DockRevealMonitor(snapshot: { _ in counter.value += 1; return nil }, present: { _ in })
        for _ in 0..<20 { monitor.requestSample() }
        try await waitUntil { counter.value >= 1 }
        #expect(counter.value == 1)
        monitor.requestSample()
        try await waitUntil { counter.value == 2 }
    }

    @Test func revealSamplingPausesWhileTheSessionIsAway() {
        let monitor = DockRevealMonitor(snapshot: { _ in nil }, present: { _ in })
        monitor.startSampling()
        #expect(monitor.isSampling)
        monitor.setSystemAway(true)
        #expect(!monitor.isSampling)
        monitor.startSampling()
        #expect(!monitor.isSampling)
        monitor.setSystemAway(false)
        #expect(monitor.isSampling)
        monitor.stop()
        monitor.setSystemAway(true)
        monitor.setSystemAway(false)
        #expect(!monitor.isSampling)
    }

    // MARK: Window sampling and identity (S05-007, S05-008, S05-009)

    @Test func partialWindowSamplesKeepTheSlowAppsWindows() {
        let alpha = window(processID: 10, app: "Alpha", title: "A1", minimized: true)
        let beta = window(processID: 20, app: "Beta", title: "B1", minimized: true)
        let complete = WindowSampleMerge.merged(previous: [], sample: WindowAccessibilitySample(windows: [beta, alpha]))
        #expect(complete.map(\.id) == [alpha.id, beta.id])
        // Beta did not answer before the deadline: its tile stays.
        let partial = WindowSampleMerge.merged(previous: complete,
                                               sample: WindowAccessibilitySample(windows: [alpha], incompleteProcessIDs: [20]))
        #expect(partial.map(\.id) == [alpha.id, beta.id])
        // Beta quit: it was neither sampled nor incomplete, so its windows go.
        let quit = WindowSampleMerge.merged(previous: partial, sample: WindowAccessibilitySample(windows: [alpha]))
        #expect(quit.map(\.id) == [alpha.id])
    }

    @Test func theMonitorKeepsMinimizedTilesThroughAPartialSample() async throws {
        let directory = temporaryDirectory("LaneC-WindowSample")
        defer { try? FileManager.default.removeItem(at: directory) }
        let alpha = window(processID: 10, app: "Alpha", title: "A1", minimized: true)
        let beta = window(processID: 20, app: "Beta", title: "B1", minimized: true)
        let gamma = window(processID: 10, app: "Alpha", title: "A2", minimized: true)
        let samples = LaneCSampleQueue([WindowAccessibilitySample(windows: [alpha, beta]),
                                        WindowAccessibilitySample(windows: [alpha, gamma], incompleteProcessIDs: [20])])
        let monitor = WindowAccessibilityMonitor(previewCache: WindowPreviewDiskCache(directoryURL: directory),
                                                 sampleWindows: { samples.next() }, canCapture: { false })
        defer { monitor.setEnabled(false) }
        monitor.setEnabled(true)
        try await waitUntil { monitor.windows.count == 2 }
        monitor.refresh()
        try await waitUntil { monitor.windows.contains { $0.id == gamma.id } }
        #expect(monitor.windows.contains { $0.id == beta.id })
    }

    @Test func windowIDsSurviveReorderingAndRetitling() {
        var first = window(processID: 42, app: "Editor", title: "Draft", minimized: false,
                           observation: WindowAccessibilityObservation(AXUIElementCreateApplication(90_001)))
        var second = window(processID: 42, app: "Editor", title: "Notes", minimized: false, index: 1,
                            observation: WindowAccessibilityObservation(AXUIElementCreateApplication(90_002)))
        let ids = [first.id, second.id]
        #expect(ids[0] != ids[1])
        first.windowIndex = 1
        second.windowIndex = 0
        first.title = "Draft (edited)"
        first.rawTitle = "Draft (edited)"
        #expect([first.id, second.id] == ids)
    }

    @Test func collidingWindowHashesStillGiveUniqueIDs() {
        let shared = WindowAccessibilityObservation(AXUIElementCreateApplication(90_003))
        let first = window(processID: 42, app: "Editor", title: "One", minimized: false, observation: shared)
        let second = window(processID: 42, app: "Editor", title: "Two", minimized: false, index: 1, observation: shared)
        #expect(first.id == second.id)
        let distinct = WindowIdentityPolicy.disambiguated([first, second])
        #expect(Set(distinct.map(\.id)).count == 2)
    }

    // MARK: Preview disk cache (S05-010, S18-008)

    @Test func sameTitledWindowsOverTimeNeverShareADiskPreview() {
        let identity = NativeApplicationIdentity(processID: 42, bundleIdentifier: "com.example.editor",
                                                 bundleURL: URL(fileURLWithPath: "/fixture/Editor.app"),
                                                 launchDate: Date(timeIntervalSince1970: 100))
        var earlier = window(processID: 42, app: "Editor", title: "Untitled", minimized: false,
                             observation: WindowAccessibilityObservation(AXUIElementCreateApplication(90_011)))
        earlier.applicationIdentity = identity
        var later = window(processID: 42, app: "Editor", title: "Untitled", minimized: false,
                           observation: WindowAccessibilityObservation(AXUIElementCreateApplication(90_012)))
        later.applicationIdentity = identity
        let earlierKey = WindowPreviewCacheIdentity.uniqueKeys(for: [earlier])[earlier.id]
        let laterKey = WindowPreviewCacheIdentity.uniqueKeys(for: [later])[later.id]
        #expect(earlierKey != nil && laterKey != nil)
        #expect(earlierKey != laterKey)
        #expect(WindowPreviewCacheIdentity.uniqueKeys(for: [earlier])[earlier.id] == earlierKey)
        var relaunched = earlier
        relaunched.applicationIdentity?.launchDate = Date(timeIntervalSince1970: 200)
        #expect(WindowPreviewCacheIdentity.uniqueKeys(for: [relaunched])[relaunched.id] != earlierKey)
    }

    @Test func turningPreviewRetentionOffPurgesDiskAndMemory() async throws {
        let directory = temporaryDirectory("LaneC-PreviewRetention")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = window(processID: 42, app: "Example", title: "Document", minimized: false, identifier: "lane-c-window")
        let monitor = WindowAccessibilityMonitor(previewCache: WindowPreviewDiskCache(directoryURL: directory),
                                                 sampleWindows: { WindowAccessibilitySample(windows: [document]) },
                                                 captureWindows: { descriptors, _ in LaneCImages.batch(for: descriptors) },
                                                 canCapture: { true })
        defer { monitor.setEnabled(false) }
        monitor.setPreviewCacheRetentionEnabled(true)
        monitor.setEnabled(true, previewsEnabled: true)
        try await waitUntil { monitor.previews[document.id] != nil && !jpegs(in: directory).isEmpty }
        monitor.setPreviewCacheRetentionEnabled(false)
        #expect(monitor.previews.isEmpty)
        #expect(jpegs(in: directory).isEmpty)
    }

    @Test func losingScreenRecordingPurgesTheDiskCache() async throws {
        let directory = temporaryDirectory("LaneC-PreviewPermission")
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = window(processID: 42, app: "Example", title: "Document", minimized: false, identifier: "lane-c-window")
        var allowed = true
        let monitor = WindowAccessibilityMonitor(previewCache: WindowPreviewDiskCache(directoryURL: directory),
                                                 sampleWindows: { WindowAccessibilitySample(windows: [document]) },
                                                 captureWindows: { descriptors, _ in LaneCImages.batch(for: descriptors) },
                                                 canCapture: { allowed })
        defer { monitor.setEnabled(false) }
        monitor.setPreviewCacheRetentionEnabled(true)
        monitor.setEnabled(true, previewsEnabled: true)
        try await waitUntil { !jpegs(in: directory).isEmpty }
        allowed = false
        monitor.refresh()
        try await waitUntil { jpegs(in: directory).isEmpty }
        #expect(monitor.previews.isEmpty)
    }

    // MARK: Trash watcher (S05-011)

    @Test func replacingTheWatchedTrashDetachesTheWatcher() async throws {
        let directory = temporaryDirectory("LaneC-Trash")
        let moved = FileManager.default.temporaryDirectory.appendingPathComponent("LaneC-Trash-moved-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: moved)
        }
        let status = TrashStatus(trashURL: directory, allowsNativeEffects: true)
        #expect(status.isWatching)
        try FileManager.default.moveItem(at: directory, to: moved)
        try await waitUntil { !status.isWatching }
    }

    // MARK: Automation copy and artwork (S05-012, S05-014)

    @Test func timeoutsGetTheirOwnPlainMessage() {
        #expect(TrashCopy.emptyFailureMessage(for: BoundedSubprocessCaptureError.timedOut)
                == "Finder is still working. Check the Trash in a moment.")
        let nowPlaying = NowPlayingCopy.automationMessage(for: BoundedSubprocessCaptureError.timedOut, sourceTitle: "Music")
        #expect(nowPlaying.hasPrefix("Music did not respond in time."))
    }

    @Test func artworkHexDecodesOverBytes() {
        #expect(BoundedAutomationRunner.artworkData(from: "«data JPEGffD8a0»") == Data([0xff, 0xd8, 0xa0]))
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNGf8950»") == Data([0x89, 0x50]))
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNGf895»") == nil)
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNGf89zz»") == nil)
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNG»") == nil)
        #expect(BoundedAutomationRunner.artworkData(from: "«data PNGf»") == nil)
        #expect(NowPlayingArtwork.decodedThumbnail(from: Data([1, 2, 3]))?.image == nil)
    }

    // MARK: Network totals (S05-017)

    @Test func vpnTunnelTrafficIsNotCountedTwice() {
        let before = NetworkCountersReading(uptime: 0, interfaces: [
            NetworkInterfaceCounters(name: "en0", receivedBytes: 0, sentBytes: 0, addresses: []),
            NetworkInterfaceCounters(name: "utun0", receivedBytes: 0, sentBytes: 0, addresses: [], isPhysical: false)
        ])
        let after = NetworkCountersReading(uptime: 1, interfaces: [
            NetworkInterfaceCounters(name: "en0", receivedBytes: 1_000, sentBytes: 200, addresses: []),
            NetworkInterfaceCounters(name: "utun0", receivedBytes: 900, sentBytes: 150, addresses: [], isPhysical: false)
        ])
        let rates = NetworkRateCalculator.rates(previous: before, current: after)
        #expect(rates.count == 2)
        #expect(NetworkRateCalculator.physicalTotal(rates, \.receivedBytesPerSecond) == 1_000)
        #expect(NetworkRateCalculator.completePhysicalTotal(rates, \.sentBytesPerSecond) == 200)
        #expect(NetworkInterfaceKindPolicy.isPhysical(name: "en0", interfaceType: 0x06))
        #expect(!NetworkInterfaceKindPolicy.isPhysical(name: "utun3", interfaceType: 0xff))
        #expect(!NetworkInterfaceKindPolicy.isPhysical(name: "bridge0", interfaceType: 0x06))
        #expect(!NetworkInterfaceKindPolicy.isPhysical(name: "awdl0", interfaceType: 0x06))
        #expect(!NetworkInterfaceKindPolicy.isPhysical(name: "en7", interfaceType: 0x87))
    }

    // MARK: Window preview hover (S07-009)

    @Test func aLatePanelEnterWhileIdleDoesNotHoldTheNextPreviewOpen() {
        var machine = WindowPreviewHoverMachine(showDelay: 0.5, closeGrace: 0.25)
        #expect(machine.handle(.enterPanel, at: 0) == .noChange)
        #expect(!machine.pointerInPanel)
        _ = machine.handle(.enterTile("safari"), at: 1)
        _ = machine.handle(.enterPanel, at: 1.1)
        #expect(machine.handle(.tick, at: 1.5) == .show("safari"))
        #expect(!machine.pointerInPanel)
        _ = machine.handle(.exitTile("safari"), at: 2)
        #expect(machine.nextDeadline == 2.25)
        #expect(machine.handle(.tick, at: 2.25) == .close)
    }

    // MARK: Dock window (S07-014)

    @Test func onlyAnAutoHidingDockJoinsFullScreenSpaces() {
        #expect(!DockWindowSpacePolicy.collectionBehavior(autoHide: false).contains(.fullScreenAuxiliary))
        #expect(DockWindowSpacePolicy.collectionBehavior(autoHide: true).contains(.fullScreenAuxiliary))
        #expect(DockWindowSpacePolicy.collectionBehavior(autoHide: false).contains(.canJoinAllSpaces))
    }

    // MARK: Native Dock (S07-007, S07-016, S07-017, S18-007)

    @Test func failedApplyAndFailedRollbackKeepTheJournalForRecovery() async {
        let original: [[String: Any]] = [["tile-type": "small-spacer-tile"]]
        let backend = LaneCDockBackend(tiles: original, failingWrites: [1, 2])
        let journal = LaneCDockJournal()
        let freeze = LaneCFreezeProvider()
        let controller = NativeDockController(backend: backend, relauncher: LaneCRelauncher(), journal: journal,
                                              freezeProvider: freeze, gate: DockSystemOperationGate(),
                                              verifyAttempts: 1, verifyInterval: .zero)
        var thrown: Error?
        do { try await controller.apply(DockProfile(name: "Next", kind: .native, items: [.spacer(.regular)])) }
        catch { thrown = error }
        #expect(isRollbackFailure(thrown))
        #expect(journal.isPending)
        #expect(controller.health == .recoveryRequired)
        #expect(freeze.beginCount == 1 && freeze.endCount == 1)
    }

    @Test func recoveringAnInterruptedChangeRestoresTheSnapshot() async throws {
        let snapshot: [[String: Any]] = [["tile-type": "spacer-tile"]]
        let backend = LaneCDockBackend(tiles: [["tile-type": "small-spacer-tile"]])
        let journal = LaneCDockJournal()
        try journal.begin(snapshot: snapshot, profileID: UUID())
        let relauncher = LaneCRelauncher()
        let controller = NativeDockController(backend: backend, relauncher: relauncher, journal: journal,
                                              gate: DockSystemOperationGate(), verifyAttempts: 1, verifyInterval: .zero)
        #expect(controller.health == .recoveryRequired)
        try await controller.recoverInterruptedTransaction()
        #expect(NativeDockSerializer.plistArraysEqual(backend.tiles, snapshot))
        #expect(!journal.isPending)
        #expect(controller.health == .ready)
        #expect(controller.appliedGeneration == 1)
        #expect(relauncher.restartCount == 1)
    }

    @Test func aDockThatDropsTheLayoutIsRestoredAndSaysSo() async {
        let original: [[String: Any]] = [["tile-type": "small-spacer-tile"]]
        let backend = LaneCDockBackend(tiles: original, ignoredWrites: [1])
        let journal = LaneCDockJournal()
        let controller = NativeDockController(backend: backend, relauncher: LaneCRelauncher(), journal: journal,
                                              gate: DockSystemOperationGate(), verifyAttempts: 2, verifyInterval: .milliseconds(1))
        var message: String?
        do { try await controller.apply(DockProfile(name: "Next", kind: .native, items: [.spacer(.regular)])) }
        catch { message = error.localizedDescription }
        #expect(message == "The macOS Dock did not show the expected layout. The previous layout was restored.")
        #expect(NativeDockSerializer.plistArraysEqual(backend.tiles, original))
        #expect(!journal.isPending)
        #expect(controller.health == .ready)
        #expect(NativeDockError.dockDidNotSettle.localizedDescription.contains("restored") == false)
        #expect(NativeDockError.visibilityNotApplied.localizedDescription.contains("profile") == false)
    }

    @Test func quickSuccessiveMenuPicksWriteOnlyTheNewestDock() async throws {
        let gate = DockSystemOperationGate()
        await gate.acquire()
        let backend = LaneCDockBackend(tiles: [["tile-type": "spacer-tile"]])
        let relauncher = LaneCRelauncher()
        let controller = NativeDockController(backend: backend, relauncher: relauncher, journal: LaneCDockJournal(),
                                              gate: gate, verifyAttempts: 1, verifyInterval: .zero)
        let first = DockProfile(name: "First", kind: .native, items: [.spacer(.small)])
        let last = DockProfile(name: "Last", kind: .native, items: [.spacer(.regular), .spacer(.small)])
        var firstStarted = false
        var lastStarted = false
        let firstTask = Task { firstStarted = true; return try await controller.applyLatest(first) }
        do { try await waitUntil { firstStarted } } catch { await gate.release(); throw error }
        let lastTask = Task { lastStarted = true; return try await controller.applyLatest(last) }
        do { try await waitUntil { lastStarted } } catch { await gate.release(); throw error }
        await gate.release()
        let firstApplied = try await firstTask.value
        let lastApplied = try await lastTask.value
        #expect(!firstApplied && lastApplied)
        #expect(relauncher.restartCount == 1)
        #expect(NativeDockSerializer.signatures(from: backend.tiles) == ["spacer:regular", "spacer:small"])
    }

    @Test func newAppTilesNeverInheritAnotherAppsMetadata() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        let otherApp: [String: Any] = [
            "GUID": 7,
            "tile-type": "file-tile",
            "tile-data": [
                "dock-extra": true,
                "file-mod-date": 99,
                "custom-key": "kept by TextEdit only",
                "file-label": "TextEdit",
                "file-data": ["_CFURLString": textEdit.absoluteString, "_CFURLStringType": 15]
            ] as [String: Any]
        ]
        let tiles = try NativeDockSerializer.tiles(for: [DockItem(type: .application, title: "Calculator", url: calculator)],
                                                   using: [otherApp])
        let tileData = try #require(tiles.first?["tile-data"] as? [String: Any])
        #expect(tileData["dock-extra"] as? Bool == false)
        #expect(tileData["file-mod-date"] as? Int == 0)
        #expect(!tileData.keys.contains("custom-key"))
        let guid = try #require(tiles.first?["GUID"] as? Int)
        #expect(guid != 7 && guid >= 1 && guid <= Int(UInt32.max))
    }

    @Test func appsAlreadyInTheDockKeepTheirOwnTile() throws {
        let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let existing: [String: Any] = [
            "GUID": 4_242,
            "tile-type": "file-tile",
            "tile-data": [
                "dock-extra": true,
                "file-label": "Calculator",
                "file-data": ["_CFURLString": calculator.absoluteString, "_CFURLStringType": 15]
            ] as [String: Any]
        ]
        let item = DockItem(type: .application, title: "Calculator", url: calculator)
        let tiles = try NativeDockSerializer.tiles(for: [item, item], using: [existing])
        #expect(tiles.count == 2)
        #expect(tiles[0]["GUID"] as? Int == 4_242)
        #expect((tiles[0]["tile-data"] as? [String: Any])?["dock-extra"] as? Bool == true)
        // The same app twice: the second copy gets a tile of its own, never a shared GUID.
        #expect(tiles[1]["GUID"] as? Int != 4_242)
    }

    @Test func aPendingJournalAtLaunchRequiresRecovery() throws {
        let journal = LaneCDockJournal()
        try journal.begin(snapshot: [["tile-type": "spacer-tile"]], profileID: UUID())
        let controller = NativeDockController(backend: LaneCDockBackend(tiles: []), relauncher: LaneCRelauncher(),
                                              journal: journal, gate: DockSystemOperationGate())
        #expect(controller.health == .recoveryRequired)
        #expect(controller.recoveryError != nil)
    }

    // MARK: Helpers

    private func window(processID: pid_t, app: String, title: String, minimized: Bool, index: Int = 0,
                        identifier: String? = nil, observation: WindowAccessibilityObservation? = nil) -> DockWindowDescriptor {
        DockWindowDescriptor(processID: processID, windowIndex: index, bundleIdentifier: "com.example.\(app.lowercased())",
                             applicationName: app, title: title, isMinimized: minimized,
                             accessibilityIdentifier: identifier, accessibilityObservation: observation)
    }

    private func isRollbackFailure(_ error: Error?) -> Bool {
        guard let error = error as? NativeDockError else { return false }
        if case .rollbackFailed = error { return true }
        return false
    }

    private func temporaryDirectory(_ prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func jpegs(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jpg" }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(condition())
    }
}

private final class LaneCCounter {
    var value = 0
}

@MainActor
private final class LaneCSampleQueue {
    private var samples: [WindowAccessibilitySample]
    init(_ samples: [WindowAccessibilitySample]) { self.samples = samples }
    /// Serves the samples in order, then repeats the last one.
    func next() -> WindowAccessibilitySample {
        samples.count > 1 ? samples.removeFirst() : samples[0]
    }
}

@MainActor
private enum LaneCImages {
    static func batch(for descriptors: [DockWindowDescriptor]) -> WindowPreviewBatch {
        var batch = WindowPreviewBatch()
        for descriptor in descriptors {
            batch.attemptedIDs.insert(descriptor.id)
            batch.images[descriptor.id] = image()
        }
        return batch
    }

    private static func image() -> NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
private final class LaneCDockBackend: DockPreferencesBackend {
    var tiles: [[String: Any]]
    private let failingWrites: Set<Int>
    private let ignoredWrites: Set<Int>
    private(set) var writeCount = 0

    init(tiles: [[String: Any]], failingWrites: Set<Int> = [], ignoredWrites: Set<Int> = []) {
        self.tiles = tiles
        self.failingWrites = failingWrites
        self.ignoredWrites = ignoredWrites
    }

    func readCurrentTiles() throws -> [[String: Any]] { tiles }

    func writeTiles(_ tiles: [[String: Any]]) throws {
        writeCount += 1
        if failingWrites.contains(writeCount) { throw NativeDockError.preferencesUnavailable }
        // An ignored write models a Dock that relaunches without keeping the new layout.
        if ignoredWrites.contains(writeCount) { return }
        self.tiles = tiles
    }
}

@MainActor
private final class LaneCRelauncher: DockRelaunching {
    private(set) var restartCount = 0
    func restartDock() async throws { restartCount += 1 }
}

@MainActor
private final class LaneCDockJournal: DockTransactionJournal {
    private var snapshot: [[String: Any]]?
    var isPending: Bool { snapshot != nil }

    func begin(snapshot: [[String: Any]], profileID: UUID) throws { self.snapshot = snapshot }
    func pendingSnapshot() throws -> [[String: Any]]? { snapshot }
    func clear() throws { snapshot = nil }
}

@MainActor
private final class LaneCFreezeProvider: DockSwitchFreezeProviding {
    private(set) var beginCount = 0
    private(set) var endCount = 0

    func beginIfEnabled() async -> UUID? {
        beginCount += 1
        return UUID()
    }

    func end(_ sessionID: UUID) { endCount += 1 }
}
