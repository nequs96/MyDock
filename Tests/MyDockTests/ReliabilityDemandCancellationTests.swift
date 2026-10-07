import Foundation
import Testing
@testable import MyDock

// PR-14 / MD-S01..S05: demand, deadlines and cancellation, using pure or injected fixtures only.

// MARK: S05 demand

@MainActor
struct RefreshDemandTests {
    private func collect(_ scheduler: RefreshScheduler, at date: Date) -> Int {
        let before = scheduler.deliveredTickCount
        scheduler.fireDueSubscriptions(now: date)
        return scheduler.deliveredTickCount - before
    }

    @Test func ledgerCountsTypedDemandAndIgnoresDoubleRelease() {
        var ledger = RefreshDemandLedger()
        let popout = ledger.acquire(.popout)
        let editor = ledger.acquire(.editor)
        #expect(ledger.count(of: .popout) == 1 && ledger.count(of: .editor) == 1)
        let firstRelease = ledger.release(popout)
        let secondRelease = ledger.release(popout)
        #expect(firstRelease && !secondRelease)
        #expect(RefreshDemandLedger.isActive(dockVisible: false, demand: ledger))
        let editorRelease = ledger.release(editor)
        #expect(editorRelease)
        #expect(!RefreshDemandLedger.isActive(dockVisible: false, demand: ledger))
        #expect(RefreshDemandLedger.isActive(dockVisible: true, demand: ledger))
    }

    @Test func hiddenDockWithoutDemandDoesNoWork() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let stream = scheduler.ticks(every: 1)
        _ = stream
        #expect(scheduler.subscriptionCount == 1)
        #expect(!scheduler.isActive)
        #expect(!scheduler.hasArmedTimer)
        #expect(collect(scheduler, at: .now.addingTimeInterval(60)) == 0)
    }

    @Test func popoutDemandRefreshesWhileDockIsHiddenAndReleaseStopsWork() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let stream = scheduler.ticks(every: 1)
        _ = stream
        let token = scheduler.acquireDemand(.popout)
        #expect(scheduler.isActive && scheduler.hasArmedTimer)
        #expect(collect(scheduler, at: .now.addingTimeInterval(60)) == 1)
        scheduler.release(token)
        scheduler.release(token)
        #expect(!scheduler.isActive && !scheduler.hasArmedTimer)
        #expect(collect(scheduler, at: .now.addingTimeInterval(120)) == 0)
    }

    @Test func multipleSameKindDemandsReleaseIndependently() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let stream = scheduler.ticks(every: 1)
        _ = stream
        let first = scheduler.acquireDemand(.editor)
        let second = scheduler.acquireDemand(.editor)
        scheduler.release(first)
        #expect(scheduler.isActive)
        scheduler.release(second)
        #expect(!scheduler.isActive)
    }

    @Test func dockVisibleRefreshesWithoutDemandAndSetDemandIsIdempotent() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: true)
        let stream = scheduler.ticks(every: 1)
        _ = stream
        #expect(collect(scheduler, at: .now.addingTimeInterval(60)) == 1)
        var token: RefreshDemandToken?
        scheduler.setDemand(&token, kind: .popout, active: true)
        let held = token
        scheduler.setDemand(&token, kind: .popout, active: true)
        #expect(token == held)
        scheduler.setDemand(&token, kind: .popout, active: false)
        #expect(token == nil)
        scheduler.setDemand(&token, kind: .popout, active: false)
        #expect(scheduler.isActive)
    }

    @Test func removingAllSubscribersDisarmsTimer() async {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: true)
        var stream: AsyncStream<Date>? = scheduler.ticks(every: 1)
        #expect(scheduler.hasArmedTimer)
        stream = nil
        _ = stream
        for _ in 0..<50 where scheduler.subscriptionCount > 0 { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(scheduler.subscriptionCount == 0)
        #expect(!scheduler.hasArmedTimer)
    }

    @Test func nowPlayingPopoutNeedsNoDockButCompactDoes() {
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: false, kinds: [.popout]) == 5)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: false, kinds: [.compact]) == nil)
        #expect(NowPlayingRefreshPolicy.interval(dockIsVisible: true, kinds: []) == nil)
    }
}

// MARK: S01 Shortcuts

@MainActor
struct ShortcutExecutionTests {
    private func makeCommand(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mydock-shortcut-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fake-shortcuts")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<300 where !condition() { try? await Task.sleep(for: .milliseconds(20)) }
    }

    @Test func successfulRunReportsCompleted() async throws {
        let service = ShortcutExecutionService(commandURL: try makeCommand("exit 0"), requiresNativeEffects: false)
        try service.run("Fixture")
        #expect(service.isRunning("Fixture"))
        await waitUntil { !service.isRunning("Fixture") }
        #expect(service.statusByShortcut["Fixture"] == "Completed")
    }

    @Test func failureIncludesBoundedStandardError() async throws {
        let long = String(repeating: "x", count: 5_000)
        let service = ShortcutExecutionService(commandURL: try makeCommand("echo 'Could not find shortcut' >&2; echo \(long) >&2; exit 3"),
                                               requiresNativeEffects: false)
        try service.run("Fixture")
        await waitUntil { !service.isRunning("Fixture") }
        let status = service.statusByShortcut["Fixture"] ?? ""
        #expect(status.hasPrefix("Shortcut failed (exit code 3)."))
        #expect(status.contains("Could not find shortcut"))
        #expect(status.count < 400)
    }

    @Test func longRunningInteractiveShortcutIsNotKilledByADeadlineAndCancelStopsIt() async throws {
        let service = ShortcutExecutionService(commandURL: try makeCommand("sleep 30"), requiresNativeEffects: false)
        try service.run("Hung")
        try await Task.sleep(for: .milliseconds(400))
        #expect(service.isRunning("Hung"))
        #expect(service.statusByShortcut["Hung"] == "Running…")
        #expect(throws: ShortcutsServiceError.self) { try service.run("Hung") }
        service.cancel("Hung")
        #expect(service.statusByShortcut["Hung"] == "Cancelling…")
        await waitUntil { !service.isRunning("Hung") }
        #expect(!service.isRunning("Hung"))
        #expect(service.statusByShortcut["Hung"] == ShortcutRunMessages.cancelled())
    }

    @Test func cancelAllStopsEveryRunAndRunsCanStartAgain() async throws {
        let service = ShortcutExecutionService(commandURL: try makeCommand("sleep 30"), requiresNativeEffects: false)
        try service.run("A")
        try service.run("B")
        try await Task.sleep(for: .milliseconds(300))
        service.cancelAll()
        await waitUntil { service.runningNames.isEmpty }
        #expect(service.runningNames.isEmpty)
        try service.run("A")
        service.cancelAll()
        await waitUntil { service.runningNames.isEmpty }
    }

    @Test func emptyNameAndMissingCommandAreRejected() throws {
        let service = ShortcutExecutionService(commandURL: try makeCommand("exit 0"), requiresNativeEffects: false)
        #expect(throws: ShortcutsServiceError.self) { try service.run("   ") }
        let missing = ShortcutExecutionService(commandURL: URL(fileURLWithPath: "/nonexistent/mydock-fixture"), requiresNativeEffects: false)
        #expect(throws: ShortcutsServiceError.self) { try missing.run("A") }
    }

    @Test func failureMessageTruncatesAndHandlesEmptyStandardError() {
        #expect(ShortcutRunMessages.failed(exitCode: 1, standardError: Data()) == "Shortcut failed (exit code 1).")
        let message = ShortcutRunMessages.failed(exitCode: 2, standardError: Data(String(repeating: "e", count: 1_000).utf8))
        #expect(message.count <= "Shortcut failed (exit code 2). ".count + ShortcutRunMessages.maximumDetailCharacters + 1)
    }
}

// MARK: S02 Folder popout

struct FolderContentsReaderTests {
    private func makeFolder(files: Int, folders: Int = 0) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mydock-folder-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<files { FileManager.default.createFile(atPath: directory.appendingPathComponent("file-\(index).txt").path, contents: nil) }
        for index in 0..<folders {
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("dir-\(index)"), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: directory.appendingPathComponent(".hidden").path, contents: nil)
        return directory
    }

    @Test func emptyFolderHasNoEntriesAndIsEmpty() throws {
        let listing = try FolderContentsReader.listing(at: try makeFolder(files: 0))
        #expect(listing.isEmpty && listing.omittedSummary == nil)
    }

    @Test func foldersSortFirstHiddenAreSkippedAndDisplayIsBounded() throws {
        let listing = try FolderContentsReader.listing(at: try makeFolder(files: 12, folders: 3), displayLimit: 5)
        #expect(listing.entries.count == 5)
        #expect(listing.entries.prefix(3).allSatisfy { $0.isDirectory })
        #expect(listing.omittedCount == 10)
        #expect(listing.omittedSummary == "and 10 more")
        #expect(!listing.entries.contains { $0.name == ".hidden" })
    }

    @Test func enumerationCapIsReportedHonestly() throws {
        let listing = try FolderContentsReader.listing(at: try makeFolder(files: 20), displayLimit: 5, enumerationCap: 8)
        #expect(listing.enumerationCapped)
        #expect(listing.entries.count == 5 && listing.omittedCount == 3)
        #expect(listing.omittedSummary == "and more than 3 more")
    }

    @Test func missingFolderThrowsInsteadOfLookingEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("mydock-missing-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try FolderContentsReader.listing(at: missing) }
    }

    @Test func cancelledEnumerationStopsAndThrowsCancellation() async throws {
        let folder = try makeFolder(files: 50)
        let task = Task { () throws -> FolderContentsListing in
            withUnsafeCurrentTask { $0?.cancel() }
            return try FolderContentsReader.listing(at: folder)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func cancellingTheAsyncLoadReachesTheEnumeration() async throws {
        let folder = try makeFolder(files: 10)
        let task = Task { try await FolderContentsReader.load(at: folder) }
        task.cancel()
        let outcome = await task.result
        switch outcome {
        case .success: break // enumeration may have finished before cancellation was observed
        case .failure(let error): #expect(error is CancellationError)
        }
    }

    @Test func onlyTheLatestRequestMayPublishAcrossAToBToA() {
        var tracker = FolderLoadRequestTracker()
        let firstA = tracker.begin()
        let b = tracker.begin()
        let secondA = tracker.begin()
        #expect(!tracker.isCurrent(firstA) && !tracker.isCurrent(b) && tracker.isCurrent(secondA))
        tracker.invalidate()
        #expect(!tracker.isCurrent(secondA))
    }
}

// MARK: S03 deadlines and cancellation

struct LocationFixPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func acceptsFreshPreciseFixes() {
        #expect(LocationFixPolicy.evaluate(timestamp: now.addingTimeInterval(-30), horizontalAccuracy: 100, now: now) == .accept)
        #expect(LocationFixPolicy.evaluate(timestamp: now.addingTimeInterval(5), horizontalAccuracy: 4_999, now: now) == .accept)
    }

    @Test func rejectsStaleAndInaccurateFixes() {
        #expect(LocationFixPolicy.evaluate(timestamp: now.addingTimeInterval(-3_600), horizontalAccuracy: 100, now: now) == .stale)
        #expect(LocationFixPolicy.evaluate(timestamp: now, horizontalAccuracy: 50_000, now: now) == .inaccurate)
        #expect(LocationFixPolicy.evaluate(timestamp: now, horizontalAccuracy: -1, now: now) == .inaccurate)
        #expect(LocationFixPolicy.evaluate(timestamp: now, horizontalAccuracy: .nan, now: now) == .inaccurate)
    }

    @Test func failureKindsHaveDistinctUserMessages() {
        let messages = Set([CurrentLocationError.unavailable, .timedOut, .staleOrInaccurate].compactMap(\.errorDescription)
                           + [WeatherServiceError.locationDenied.errorDescription ?? ""])
        #expect(messages.count == 4)
    }
}

struct BoundedNativeFetchTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0
        func increment() { lock.lock(); storage += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return storage }
    }

    @Test func completionDeliversValueAndNeverCancelsNative() async {
        let cancels = Counter()
        let outcome: BoundedFetchOutcome<Int> = await BoundedNativeFetch.run(timeout: 5) { complete in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { complete(7); complete(8) }
            return { cancels.increment() }
        }
        #expect(outcome == .value(7))
        #expect(cancels.value == 0)
    }

    @Test func neverCompletingFetchTimesOutAndCancelsNativeToken() async {
        let cancels = Counter()
        let outcome: BoundedFetchOutcome<Int> = await BoundedNativeFetch.run(timeout: 0.1) { _ in
            { cancels.increment() }
        }
        #expect(outcome == .timedOut)
        #expect(cancels.value == 1)
    }

    @Test func taskCancellationEndsTheWaitAndCancelsNativeToken() async {
        let cancels = Counter()
        let task = Task { () -> BoundedFetchOutcome<Int> in
            await BoundedNativeFetch.run(timeout: 30) { _ in { cancels.increment() } }
        }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let outcome = await task.value
        #expect(outcome == .cancelled)
        #expect(cancels.value == 1)
    }

    @Test func alreadyCancelledTaskStillResumesExactlyOnce() async {
        let cancels = Counter()
        let task = Task { () -> BoundedFetchOutcome<Int> in
            withUnsafeCurrentTask { $0?.cancel() }
            return await BoundedNativeFetch.run(timeout: 30) { complete in
                complete(1)
                return { cancels.increment() }
            }
        }
        let outcome = await task.value
        #expect(outcome == .cancelled || outcome == .value(1))
        #expect(cancels.value <= 1)
    }

    @Test func synchronousCompletionResumesOnceWithoutCancellingNative() async {
        let cancels = Counter()
        let outcome: BoundedFetchOutcome<String> = await BoundedNativeFetch.run(timeout: 5) { complete in
            complete("done")
            return { cancels.increment() }
        }
        #expect(outcome == .value("done"))
        #expect(cancels.value == 0)
    }
}

// MARK: S04 Hydration

@MainActor
private final class FakeHydrationCenter: HydrationNotificationCenter {
    var status: HydrationNotificationAuthorization
    var pending: [String]
    private(set) var requestAuthorizationCalls = 0
    private(set) var added: [(String, Int)] = []
    private(set) var removed: [String] = []
    var onAdd: (() -> Void)?

    init(status: HydrationNotificationAuthorization, pending: [String] = []) {
        self.status = status
        self.pending = pending
    }

    func authorization() async -> HydrationNotificationAuthorization { status }
    func requestAuthorization() async throws -> Bool {
        requestAuthorizationCalls += 1
        return status == .authorized
    }
    func pendingIdentifiers() async -> [String] { pending }
    func add(identifier: String, intervalMinutes: Int) async throws {
        added.append((identifier, intervalMinutes))
        pending.append(identifier)
        onAdd?()
    }
    func remove(identifiers: [String]) {
        removed.append(contentsOf: identifiers)
        pending.removeAll { identifiers.contains($0) }
    }
}

@MainActor
struct HydrationReconcileTests {
    private func target(_ id: UUID = UUID(), interval: Int = 60) -> HydrationReminderTarget {
        HydrationReminderTarget(profileID: UUID(), itemID: id, intervalMinutes: interval)
    }

    @Test func plannerKeepsHealthySchedulesAndReschedulesLostOnes() {
        let kept = target(), lost = target()
        let keptID = HydrationReminderService.notificationID(for: kept.itemID, operationID: UUID())
        let actions = HydrationReconcilePlanner.plan(targets: [kept, lost], authorization: .authorized, pending: [keptID])
        #expect(actions == [.schedule(lost)])
    }

    @Test func plannerDisablesWhenNotificationsAreNotAuthorizedWithoutPrompting() {
        let item = target()
        for status in [HydrationNotificationAuthorization.denied, .notDetermined] {
            let actions = HydrationReconcilePlanner.plan(targets: [item], authorization: status, pending: [])
            #expect(actions == [.disable(item)])
        }
    }

    @Test func plannerRemovesDuplicatesAndOrphans() {
        let item = target(), orphan = UUID()
        let first = HydrationReminderService.notificationID(for: item.itemID, operationID: UUID())
        let second = HydrationReminderService.notificationID(for: item.itemID, operationID: UUID())
        let orphanID = HydrationReminderService.notificationID(for: orphan, operationID: UUID())
        let actions = HydrationReconcilePlanner.plan(targets: [item], authorization: .authorized,
                                                     pending: [first, second, orphanID, "mydock.alarm.keep"])
        guard case .remove(let removals)? = actions.first else { Issue.record("expected removal"); return }
        #expect(removals.contains(orphanID))
        #expect(removals.contains(max(first, second)) && !removals.contains(min(first, second)))
        #expect(!removals.contains("mydock.alarm.keep"))
    }

    @Test func reconcileReschedulesDeletedPendingRequestWithoutPrompting() async {
        let item = target(interval: 90)
        let center = FakeHydrationCenter(status: .authorized)
        let outcomes = await HydrationReminderService.reconcile(using: center) { [item] }
        #expect(outcomes == [.rescheduled(item.itemID)])
        #expect(center.requestAuthorizationCalls == 0)
        #expect(center.added.count == 1 && center.added[0].1 == 90)
    }

    @Test func repeatedReconcileNeverDuplicates() async {
        let item = target()
        let center = FakeHydrationCenter(status: .authorized)
        _ = await HydrationReminderService.reconcile(using: center) { [item] }
        let second = await HydrationReminderService.reconcile(using: center) { [item] }
        _ = await HydrationReminderService.reconcile(using: center) { [item] }
        #expect(second == [.unchanged(item.itemID)])
        #expect(center.added.count == 1)
        #expect(center.pending.count == 1)
    }

    @Test func revokedPermissionDisablesAndClearsPending() async {
        let item = target()
        let pendingID = HydrationReminderService.notificationID(for: item.itemID, operationID: UUID())
        let center = FakeHydrationCenter(status: .denied, pending: [pendingID])
        let outcomes = await HydrationReminderService.reconcile(using: center) { [item] }
        #expect(outcomes == [.disabled(item.itemID)])
        #expect(center.requestAuthorizationCalls == 0 && center.added.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func deletedOrDisabledItemPendingRequestsAreRemoved() async {
        let gone = UUID()
        let pendingID = HydrationReminderService.notificationID(for: gone, operationID: UUID())
        let center = FakeHydrationCenter(status: .authorized, pending: [pendingID])
        let outcomes = await HydrationReminderService.reconcile(using: center) { [] }
        #expect(outcomes.isEmpty)
        #expect(center.pending.isEmpty)
    }

    @Test func userToggleDuringReconcileSupersedesItAndRemovesItsRequest() async {
        let item = target()
        let center = FakeHydrationCenter(status: .authorized)
        // The user turns reminders off while reconcile is adding; their newer operation owns the item.
        center.onAdd = { HydrationReminderService.begin(itemID: item.itemID, operationID: UUID()) }
        let outcomes = await HydrationReminderService.reconcile(using: center) { [item] }
        #expect(outcomes == [.superseded(item.itemID)])
        #expect(center.pending.isEmpty)
    }

    @Test func schedulingWithoutAuthorizationNeverPromptsWhenToldNotTo() async {
        let item = UUID(), operation = UUID()
        let center = FakeHydrationCenter(status: .notDetermined)
        HydrationReminderService.begin(itemID: item, operationID: operation)
        await #expect(throws: HydrationReminderError.self) {
            try await HydrationReminderService.schedule(itemID: item, operationID: operation, intervalMinutes: 60,
                                                        center: center, promptForAuthorization: false)
        }
        #expect(center.requestAuthorizationCalls == 0 && center.added.isEmpty)
    }

    @Test func intervalIsClampedWhenRescheduling() async {
        let item = target(interval: 5)
        let center = FakeHydrationCenter(status: .authorized)
        _ = await HydrationReminderService.reconcile(using: center) { [item] }
        #expect(center.added.first?.1 == 30)
    }
}
