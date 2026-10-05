import ServiceManagement
import AppKit
import UserNotifications
import Testing
@testable import MyDock

struct NativeFollowupTests {
    @Test @MainActor func defaultUpdateCheckFailsClosedInIsolatedValidation() async {
        #expect(!AppRuntimeEnvironment.allowsNetwork)
        let service = UpdateCheckService()
        await service.check(repositoryURL: "https://github.com/fixture/mydock")
        #expect(!service.checking && service.releaseURL == nil)
        #expect(service.message == ValidationBoundaryError.networkDisabled.localizedDescription)
    }

    @MainActor private func revealState() -> DockRevealMonitor.Snapshot {
        DockRevealMonitor.Snapshot(canPresent: true, retainsInteraction: false, overviewPresent: false,
            systemDockOverlaps: false, desktopMode: false, autoHide: true, visible: false,
            mouseLocation: NSPoint(x: 50, y: 2), expandedFrame: NSRect(x: 0, y: 10, width: 100, height: 60),
            revealFrame: NSRect(x: 30, y: 1, width: 40, height: 6), popoutFrames: [])
    }

    @Test @MainActor func revealRetentionPrecedesSuppressionAndHiddenPanelsRequireDwell() {
        var state = revealState()
        #expect(state.decision == .dwell)
        state.overviewPresent = true
        #expect(state.decision == .suppress)
        state.retainsInteraction = true
        #expect(state.decision == .show)
        state.canPresent = false
        #expect(state.decision == nil)
    }

    @Test @MainActor func popoutRetainsOnlyAnAlreadyVisibleDock() {
        var state = revealState()
        state.mouseLocation = NSPoint(x: 250, y: 200)
        state.popoutFrames = [NSRect(x: 200, y: 150, width: 100, height: 100)]
        state.visible = true
        #expect(state.decision == .show)
        state.visible = false
        #expect(state.decision == .hide)
        state.systemDockOverlaps = true
        state.desktopMode = true
        #expect(state.decision == .suppress)
    }

    @Test @MainActor func stoppingMonitoringCancelsPendingReveal() async throws {
        let state = revealState()
        var decisions: [DockRevealMonitor.Decision] = []
        let monitor = DockRevealMonitor(snapshot: { _ in state }, present: { decisions.append($0) })
        monitor.sample()
        #expect(decisions == [.hide])
        monitor.stop()
        try await Task.sleep(for: .milliseconds(400))
        #expect(decisions == [.hide])
    }

    @MainActor private func completeRevealDwell(with completionState: DockRevealMonitor.Snapshot) async
        -> (decisions: [DockRevealMonitor.Decision], snapshotRequests: [Bool]) {
        var state = revealState()
        var snapshotRequests: [Bool] = []
        let dwell = AsyncStream<Void>.makeStream()
        let presentations = AsyncStream<DockRevealMonitor.Decision>.makeStream()
        var decisions: [DockRevealMonitor.Decision] = []
        let monitor = DockRevealMonitor(snapshot: { forDwell in
            snapshotRequests.append(forDwell)
            return state
        }, present: {
            decisions.append($0)
            presentations.continuation.yield($0)
        }, waitForDwell: {
            var iterator = dwell.stream.makeAsyncIterator()
            guard await iterator.next() != nil else { throw CancellationError() }
        })
        defer {
            monitor.stop()
            dwell.continuation.finish()
            presentations.continuation.finish()
        }
        var iterator = presentations.stream.makeAsyncIterator()
        monitor.sample()
        #expect(await iterator.next() == .hide)
        // Change native state while the dwell is pending, without a periodic sample.
        state = completionState
        dwell.continuation.yield(())
        _ = await iterator.next()
        return (decisions, snapshotRequests)
    }

    @Test @MainActor func overviewAppearingDuringDwellSuppressesRevealAtCompletion() async {
        var state = revealState()
        state.overviewPresent = true
        let result = await completeRevealDwell(with: state)
        #expect(result.snapshotRequests == [false, true])
        #expect(result.decisions == [.hide, .suppress])
        #expect(!result.decisions.contains(.show))
    }

    @Test @MainActor func ordinaryDwellRevealsAtCompletion() async {
        let result = await completeRevealDwell(with: revealState())
        #expect(result.snapshotRequests == [false, true])
        #expect(result.decisions == [.hide, .show])
    }

    @Test @MainActor func interactionRetentionDuringDwellPrecedesSuppression() async {
        var state = revealState()
        state.retainsInteraction = true
        state.overviewPresent = true
        state.systemDockOverlaps = true
        let result = await completeRevealDwell(with: state)
        #expect(result.decisions == [.hide, .show])
    }

    @Test @MainActor func vanishedPresentationCanStartAnotherDwellWhenItReturns() async throws {
        var state: DockRevealMonitor.Snapshot? = revealState()
        var decisions: [DockRevealMonitor.Decision] = []
        let monitor = DockRevealMonitor(snapshot: { _ in state }, present: { decisions.append($0) })
        monitor.sample()
        state = nil
        // Expiry with no panel must release the completed task.
        try await Task.sleep(for: .milliseconds(400))
        #expect(decisions == [.hide])
        state = revealState()
        monitor.sample()
        state = nil
        // A sampled disappearance must cancel the new pending task as well.
        monitor.sample()
        state = revealState()
        monitor.sample()
        // The dwell is a real 350 ms sleep; poll for its result instead of racing it on loaded CI runners.
        let deadline = Date.now.addingTimeInterval(15)
        while decisions.count < 4, Date.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(decisions == [.hide, .hide, .hide, .show])
        monitor.stop()
    }

    @Test func approvalDoesNotClaimLoginEligibility() {
        let state = LoginItemState(status: .requiresApproval)
        #expect(state == .requiresApproval)
        #expect(state.registrationRequested)
        #expect(state != .enabled)
        #expect(state.message.contains("approval is required"))
    }

    @Test func revokedAndMissingRegistrationRemainDistinct() {
        #expect(LoginItemState(status: .notRegistered) == .notRegistered)
        #expect(!LoginItemState(status: .notRegistered).registrationRequested)
        #expect(LoginItemState(status: .notFound) == .notFound)
        #expect(!LoginItemState(status: .notFound).registrationRequested)
        #expect(LoginItemState(status: .enabled).registrationRequested)
        #expect(!LoginItemState.unavailable.registrationRequested)
    }
}

@MainActor
private final class AlarmFixtureClient: AlarmNotificationClient {
    var authorization: UNAuthorizationStatus = .authorized
    var pending: [String] = []
    var delivered: [String] = []
    var onAdd: ((UNNotificationRequest) throws -> Void)?
    var onPending: (() -> Void)?
    var authorizationRequested = 0
    var authorizationGranted = false
    var addCount = 0
    func authorizationStatus() async -> UNAuthorizationStatus { authorization }
    func requestAuthorization() async throws -> Bool { authorizationRequested += 1; return authorizationGranted }
    func add(_ request: UNNotificationRequest) async throws {
        addCount += 1
        pending.append(request.identifier)
        try onAdd?(request)
    }
    func pendingIdentifiers() async -> [String] { onPending?(); return pending }
    func deliveredIdentifiers() async -> [String] { delivered }
    func removePending(_ identifiers: [String]) { pending.removeAll { identifiers.contains($0) } }
    func removeDelivered(_ identifiers: [String]) { delivered.removeAll { identifiers.contains($0) } }
}

struct NativeAlarmCalendarTests {
    @Test @MainActor func failedReplacementRetiresOldScheduleWithoutTouchingAnotherAlarm() async {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Fixture", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true)
        let client = AlarmFixtureClient()
        let old = AlarmNotificationService.oneTimeID(widgetID: widget, alarmID: alarm.id, operationID: UUID())
        client.pending = [old, "unrelated"]
        client.delivered = [old, "unrelated"]
        client.authorization = .denied
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        do {
            try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
            Issue.record("Denied fixture unexpectedly scheduled")
        } catch {
            #expect(error as? AlarmNotificationError == .permissionDenied)
        }
        #expect(client.pending == ["unrelated"])
        #expect(client.delivered == ["unrelated"])
        #expect(client.addCount == 0)
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
    }

    @Test @MainActor func staleAddCallbackAndCancellationPreserveNewerGeneration() async throws {
        let widget = UUID(), operation = UUID(), newer = UUID()
        let alarm = DockAlarm(title: "Fixture", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true)
        let client = AlarmFixtureClient()
        defer { client.onAdd = nil }
        let newID = AlarmNotificationService.oneTimeID(widgetID: widget, alarmID: alarm.id, operationID: newer)
        client.onAdd = { _ in
            AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: newer)
            client.pending.append(newID)
            client.delivered.append(newID)
        }
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
        #expect(client.pending == [newID])
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
        #expect(AlarmNotificationService.isCurrent(widgetID: widget, alarmID: alarm.id, operationID: newer))
        #expect(client.pending == [newID])
        #expect(client.delivered == [newID])
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: newer, client: client)
    }

    @Test @MainActor func partialRepeatingScheduleFailureRemovesOnlyItsOperation() async {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Fixture", hour: 12, minute: 0, repeatWeekdays: [2, 4], isEnabled: true)
        let client = AlarmFixtureClient()
        defer { client.onAdd = nil }
        client.pending = ["unrelated"]
        client.onAdd = { _ in if client.addCount == 2 { throw AlarmNotificationError.invalidTime } }
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        do {
            try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
            Issue.record("Partial fixture unexpectedly succeeded")
        } catch { #expect(error as? AlarmNotificationError == .invalidTime) }
        #expect(client.pending == ["unrelated"])
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
    }

    @Test @MainActor func exactCancelRemovesKnownGenerationAndLegacyWithoutAnotherAlarm() {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Fixture", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true)
        let otherAlarm = DockAlarm(title: "Other", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true)
        let client = AlarmFixtureClient()
        let own = AlarmNotificationService.oneTimeID(widgetID: widget, alarmID: alarm.id, operationID: operation)
        let legacy = AlarmNotificationService.notificationPrefix(widgetID: widget, alarmID: alarm.id) + ".once"
        let other = AlarmNotificationService.oneTimeID(widgetID: widget, alarmID: otherAlarm.id, operationID: UUID())
        client.pending = [own, legacy, other]; client.delivered = [own, legacy, other]
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        AlarmNotificationService.cancel(widgetID: widget, alarm: alarm, client: client)
        #expect(client.pending == [other] && client.delivered == [other])
        #expect(!AlarmNotificationService.isCurrent(widgetID: widget, alarmID: alarm.id, operationID: operation))
    }

    @Test @MainActor func invalidRepeatingTimeCannotReachNotificationBackend() async {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Invalid", hour: 25, minute: 0, repeatWeekdays: [2], isEnabled: true)
        let client = AlarmFixtureClient()
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        do {
            try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
            Issue.record("Invalid repeating time unexpectedly scheduled")
        } catch { #expect(error as? AlarmNotificationError == .invalidTime) }
        #expect(client.addCount == 0)
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
    }

    @Test @MainActor func deniedAuthorizationRequestRetiresLegacyRequests() async {
        let widget = UUID(), operation = UUID()
        let alarm = DockAlarm(title: "Fixture", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true)
        let client = AlarmFixtureClient()
        client.authorization = .notDetermined
        let legacy = AlarmNotificationService.notificationPrefix(widgetID: widget, alarmID: alarm.id) + ".once"
        client.pending = [legacy]; client.delivered = [legacy]
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        do {
            try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
            Issue.record("Denied request unexpectedly scheduled")
        } catch { #expect(error as? AlarmNotificationError == .permissionDenied) }
        #expect(client.authorizationRequested == 1)
        #expect(client.addCount == 0)
        #expect(client.pending.isEmpty && client.delivered.isEmpty)
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
    }

    @Test @MainActor func replacementDuringPendingEnumerationProtectsSuccessor() async throws {
        let widget = UUID(), operation = UUID(), newer = UUID()
        let alarm = DockAlarm(title: "Fixture", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true)
        let client = AlarmFixtureClient()
        let newerID = AlarmNotificationService.oneTimeID(widgetID: widget, alarmID: alarm.id, operationID: newer)
        client.onPending = {
            AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: newer)
            client.pending = [newerID]; client.delivered = [newerID]
        }
        defer { client.onPending = nil }
        AlarmNotificationService.begin(widgetID: widget, alarmID: alarm.id, operationID: operation)
        try await AlarmNotificationService.schedule(widgetID: widget, alarm: alarm, operationID: operation, client: client)
        #expect(client.addCount == 0)
        #expect(client.pending == [newerID] && client.delivered == [newerID])
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: operation, client: client)
        #expect(AlarmNotificationService.isCurrent(widgetID: widget, alarmID: alarm.id, operationID: newer))
        AlarmNotificationService.cancelOperation(widgetID: widget, alarmID: alarm.id, operationID: newer, client: client)
    }

    @Test func selectedCalendarAndAllDayScopeNeverFallsBackToUnselectedEvents() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, calendar: String, allDay: Bool = false) -> CalendarEventSnapshot {
            CalendarEventSnapshot(id: id, title: id, startDate: now, endDate: now.addingTimeInterval(60),
                isAllDay: allDay, calendarID: calendar, calendarTitle: calendar, meetingURL: nil)
        }
        let timed = event("timed", calendar: "A"), allDay = event("all-day", calendar: "A", allDay: true)
        let other = event("other", calendar: "B")
        #expect(CalendarEventOrdering.select([other, allDay, timed], calendarIDs: ["A"], includeAllDay: false, now: now) == [timed])
        #expect(CalendarEventOrdering.select([other, allDay, timed], calendarIDs: ["A"], includeAllDay: true, now: now) == [timed, allDay])
        #expect(CalendarEventOrdering.select([other], calendarIDs: ["missing"], includeAllDay: true, now: now).isEmpty)
        #expect(CalendarEventOrdering.select([other], calendarIDs: [], includeAllDay: true, now: now) == [other])
    }

    @Test func endedEventsDoNotWinTheCompactSelectionAtTheirExactEnd() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, start: TimeInterval, end: TimeInterval, allDay: Bool = false) -> CalendarEventSnapshot {
            CalendarEventSnapshot(id: id, title: id, startDate: now.addingTimeInterval(start),
                endDate: now.addingTimeInterval(end), isAllDay: allDay, calendarID: "fixture",
                calendarTitle: "Fixture", meetingURL: nil)
        }
        let ended = event("ended", start: -60, end: 0)
        let expiredAllDay = event("expired-all-day", start: -86_400, end: 0, allDay: true)
        let ongoing = event("ongoing", start: -60, end: 60)
        let upcoming = event("upcoming", start: 120, end: 180)
        let allDay = event("all-day", start: -3_600, end: 86_400, allDay: true)
        #expect(CalendarEventOrdering.compactEvent(from: [ended, expiredAllDay], now: now) == nil)
        #expect(CalendarEventOrdering.compactEvent(from: [ended, upcoming, allDay], now: now)?.id == "upcoming")
        #expect(CalendarEventOrdering.compactEvent(from: [ended, upcoming, ongoing, allDay], now: now)?.id == "ongoing")
        // An all-day event is never "next"; it has its own quiet line.
        #expect(CalendarEventOrdering.compactEvent(from: [expiredAllDay, allDay], now: now) == nil)
    }

    @Test func ongoingStartBoundaryOutranksEarlierAllDayAndUpcomingSortsByStart() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func event(_ id: String, start: TimeInterval, end: TimeInterval, allDay: Bool = false) -> CalendarEventSnapshot {
            CalendarEventSnapshot(id: id, title: id, startDate: now.addingTimeInterval(start),
                endDate: now.addingTimeInterval(end), isAllDay: allDay, calendarID: "fixture",
                calendarTitle: "Fixture", meetingURL: nil)
        }
        let startingNow = event("starting-now", start: 0, end: 60)
        let later = event("later", start: 30, end: 90)
        let sooner = event("sooner", start: 10, end: 20)
        let allDay = event("all-day", start: -3_600, end: 86_400, allDay: true)
        let ordered = CalendarEventOrdering.select([allDay, later, sooner, startingNow], calendarIDs: [],
                                                   includeAllDay: true, now: now)
        #expect(ordered.map(\.id) == ["starting-now", "sooner", "later", "all-day"])
        // One second before the end the event is still current; at the end it is not.
        let almostOver = event("almost-over", start: -60, end: 1)
        #expect(CalendarEventOrdering.compactEvent(from: [almostOver], now: now)?.id == "almost-over")
        #expect(CalendarEventOrdering.compactEvent(from: [almostOver], now: now.addingTimeInterval(1)) == nil)
    }
}
