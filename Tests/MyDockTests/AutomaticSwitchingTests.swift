import Combine
import Foundation
import Testing
@testable import MyDock

// PX-6 / OP-02: explainable automatic Dock switching. The engine is pure; the controller is
// driven entirely by an injected activation feed, clock and timer, so no test observes the
// real workspace. Monday 5 October 2026 is the reference day.

private let xcode = "com.apple.dt.Xcode"
private let safari = "com.apple.Safari"

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
}

private func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utcCalendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private func iso(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

private func appRule(bundle: String = xcode, name: String? = "Xcode", dock: UUID?) -> AutomaticSwitchRule {
    AutomaticSwitchRule(kind: .appFrontmost, profileID: dock, bundleIdentifier: bundle, appName: name)
}

private func windowRule(days: [Int], from: Int, to: Int, dock: UUID?) -> AutomaticSwitchRule {
    AutomaticSwitchRule(kind: .timeWindow, profileID: dock, weekdays: days, startMinute: from, endMinute: to)
}

private func context(_ frontmost: String?, _ now: Date, calendar: Calendar = utcCalendar()) -> AutomaticSwitchContext {
    AutomaticSwitchContext(frontmostBundleIdentifier: frontmost, now: now, calendar: calendar)
}

private func engineInput(_ rules: [AutomaticSwitchRule], front: String?, now: Date, active: UUID?, valid: Set<UUID>,
                         canSwitch: Bool = true, draft: Bool = false) -> AutomaticSwitchingEngine.Input {
    AutomaticSwitchingEngine.Input(rules: rules, context: context(front, now), customProfileIDs: valid,
                                   activeProfileID: active, canSwitch: canSwitch, draftIsOpen: draft)
}

// MARK: - Controller fixture

private final class FakeTimer {
    let date: Date
    let fire: @MainActor () -> Void
    var cancelled = false
    init(date: Date, fire: @escaping @MainActor () -> Void) { self.date = date; self.fire = fire }
}

private final class FakeFeed {
    var cancelled = false
}

@MainActor
private final class SwitchWorld {
    var now: Date
    var calendar: Calendar
    var frontmost: String?
    var activationHandler: (@MainActor (String?) -> Void)?
    var clockHandler: (@MainActor () -> Void)?
    var clockFeed: FakeFeed?
    var timers: [FakeTimer] = []

    init(now: Date, calendar: Calendar) { self.now = now; self.calendar = calendar }

    var activeTimers: [FakeTimer] { timers.filter { !$0.cancelled } }

    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }

    func fireNextTimer() {
        guard let timer = activeTimers.first else { return }
        timer.cancelled = true
        timer.fire()
    }

    /// Wake, a clock change or a time zone change, delivered only while the controller listens.
    func fireClockChange() {
        guard let clockFeed, !clockFeed.cancelled else { return }
        clockHandler?()
    }

    func dependencies() -> AutomaticSwitchingController.Dependencies {
        AutomaticSwitchingController.Dependencies(
            now: { [unowned self] in self.now },
            calendar: { [unowned self] in self.calendar },
            frontmostBundleIdentifier: { [unowned self] in self.frontmost },
            ownBundleIdentifier: "com.mydock.tests",
            observeActivations: { [unowned self] handler in
                self.activationHandler = handler
                return AnyCancellable {}
            },
            observeClockChanges: { [unowned self] handler in
                let feed = FakeFeed()
                self.clockHandler = handler
                self.clockFeed = feed
                return AnyCancellable { feed.cancelled = true }
            },
            schedule: { [unowned self] date, fire in
                let timer = FakeTimer(date: date, fire: fire)
                self.timers.append(timer)
                return AnyCancellable { timer.cancelled = true }
            })
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let store: ProfileStore
    let world: SwitchWorld
    let status: AutomaticSwitchingStatus
    let controller: AutomaticSwitchingController
    let home: UUID
    let build: UUID
    let work: UUID

    init(now: Date = utcDate(2026, 10, 5, 10, 0)) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ProfileStore(fileURL: root.appendingPathComponent("state.json"), allowsSystemChanges: false)
        let home = try store.createProfileAndPersist(kind: .custom, name: "Home")
        let build = try store.createProfileAndPersist(kind: .custom, name: "Build & code")
        let work = try store.createProfileAndPersist(kind: .custom, name: "Work")
        store.setActiveCustomProfile(home)
        let world = SwitchWorld(now: now, calendar: utcCalendar())
        let status = AutomaticSwitchingStatus()
        self.root = root
        self.store = store
        self.home = home
        self.build = build
        self.work = work
        self.world = world
        self.status = status
        self.controller = AutomaticSwitchingController(store: store, status: status, dependencies: world.dependencies())
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func configure(enabled: Bool = true, rules: [AutomaticSwitchRule]) {
        var settings = AutomaticSwitchingSettings()
        settings.isEnabled = enabled
        settings.rules = rules
        store.updateSettings { $0.automaticSwitching = settings }
    }

    var active: UUID? { store.state.settings.activeCustomProfileID }

    /// Activates an app and lets the dwell elapse, firing the single timer as the real one would.
    func activateAndWait(_ bundle: String) {
        world.frontmost = bundle
        world.activationHandler?(bundle)
        world.advance(AutomaticSwitchingEngine.dwell)
        world.fireNextTimer()
    }
}

@MainActor
struct AutomaticSwitchingTests {
    // MARK: Persistence

    @Test func oldStateDecodesWithAutomaticSwitchingOff() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"setupMode":"both"}"#.utf8))
        #expect(!settings.automaticSwitching.isEnabled)
        #expect(settings.automaticSwitching.rules.isEmpty)
        #expect(AppSettings().automaticSwitching == AutomaticSwitchingSettings())
        #expect(!AppSettings().automaticSwitching.isEnabled)
    }

    @Test func rulesRoundTripAndDecodeLeniently() throws {
        let dock = UUID()
        var original = AppSettings()
        original.automaticSwitching.isEnabled = true
        original.automaticSwitching.rules = [appRule(dock: dock), windowRule(days: [2, 4], from: 540, to: 1020, dock: dock)]
        let restored = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(original))
        #expect(restored == original)

        let json = """
        {"automaticSwitching":{"isEnabled":true,"rules":[
          {"kind":"bogus"},
          {"kind":"appFrontmost","bundleIdentifier":"\(xcode)","profileID":"\(dock.uuidString)","startMinute":99999},
          "junk",
          {"kind":"timeWindow","weekdays":[0,2,2,9],"startMinute":-5,"endMinute":600}
        ]}}
        """
        let lenient = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).automaticSwitching
        #expect(lenient.isEnabled)
        #expect(lenient.rules.count == 2)
        #expect(lenient.rules[0].kind == .appFrontmost && lenient.rules[0].profileID == dock)
        #expect(lenient.rules[1].weekdays == [2] && lenient.rules[1].startMinute == 0 && lenient.rules[1].endMinute == 600)

        let junk = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"automaticSwitching":"junk"}"#.utf8))
        #expect(junk.automaticSwitching == AutomaticSwitchingSettings())
        let badFlag = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"automaticSwitching":{"isEnabled":"yes"}}"#.utf8))
        #expect(!badFlag.automaticSwitching.isEnabled)
    }

    @Test func ruleListEditingAddsMovesUpdatesAndRemoves() {
        let dock = UUID()
        var settings = AutomaticSwitchingSettings()
        let first = settings.addRule(.appFrontmost, defaultProfileID: dock)!
        let second = settings.addRule(.timeWindow, defaultProfileID: dock)!
        settings.moveRule(second, by: -1)
        #expect(settings.rules.map(\.id) == [second, first])
        settings.moveRule(second, by: -1)
        #expect(settings.rules.map(\.id) == [second, first])
        settings.moveRule(first, by: 1)
        #expect(settings.rules.map(\.id) == [second, first])
        settings.updateRule(second) { $0.weekdays = [9, 0, 3, 3]; $0.startMinute = 5000 }
        #expect(settings.rules[0].weekdays == [3] && settings.rules[0].startMinute == 1439)
        settings.removeRule(first)
        #expect(settings.rules.map(\.id) == [second])
        while settings.canAddRule { settings.addRule(.appFrontmost, defaultProfileID: dock) }
        #expect(settings.rules.count == AutomaticSwitchingSettings.maximumRules)
        #expect(settings.addRule(.appFrontmost, defaultProfileID: dock) == nil)
    }

    // MARK: Matching and priority

    @Test func appRuleMatchesOnlyTheFrontmostApp() {
        let rule = appRule(dock: UUID())
        let now = utcDate(2026, 10, 5, 10)
        #expect(AutomaticSwitchEvaluator.matches(rule, in: context(xcode, now)))
        #expect(AutomaticSwitchEvaluator.matches(rule, in: context(xcode.uppercased(), now)))
        #expect(!AutomaticSwitchEvaluator.matches(rule, in: context(safari, now)))
        #expect(!AutomaticSwitchEvaluator.matches(rule, in: context(nil, now)))
        let blank = AutomaticSwitchRule(kind: .appFrontmost, profileID: UUID())
        #expect(!AutomaticSwitchEvaluator.matches(blank, in: context("", now)))
        #expect(!AutomaticSwitchEvaluator.matches(blank, in: context(xcode, now)))
    }

    @Test func theFirstMatchingRuleWinsAndOrderIsPriority() {
        let a = UUID(), b = UUID()
        let first = appRule(dock: a), second = appRule(dock: b)
        let now = utcDate(2026, 10, 5, 10)
        let both = AutomaticSwitchEvaluator.selection(rules: [first, second], context: context(xcode, now), customProfileIDs: [a, b])
        #expect(both.rule?.id == first.id)

        var settings = AutomaticSwitchingSettings()
        settings.rules = [first, second]
        settings.moveRule(second.id, by: -1)
        let swapped = AutomaticSwitchEvaluator.selection(rules: settings.rules, context: context(xcode, now), customProfileIDs: [a, b])
        #expect(swapped.rule?.id == second.id)

        // A time window listed first beats an app rule that also matches.
        let window = windowRule(days: [2], from: 540, to: 1020, dock: a)
        let mixed = AutomaticSwitchEvaluator.selection(rules: [window, second], context: context(xcode, now), customProfileIDs: [a, b])
        #expect(mixed.rule?.id == window.id)
        let nothing = AutomaticSwitchEvaluator.selection(rules: [first], context: context(safari, now), customProfileIDs: [a])
        #expect(nothing.rule == nil)
    }

    // MARK: Time windows

    @Test func sameDayWindowIncludesStartAndExcludesEnd() {
        let rule = windowRule(days: [2, 3, 4, 5, 6], from: 9 * 60, to: 17 * 60, dock: UUID())
        let calendar = utcCalendar()
        #expect(AutomaticSwitchEvaluator.windowContains(rule, now: utcDate(2026, 10, 5, 10), calendar: calendar))
        #expect(AutomaticSwitchEvaluator.windowContains(rule, now: utcDate(2026, 10, 5, 9, 0), calendar: calendar))
        #expect(!AutomaticSwitchEvaluator.windowContains(rule, now: utcDate(2026, 10, 5, 8, 59), calendar: calendar))
        #expect(!AutomaticSwitchEvaluator.windowContains(rule, now: utcDate(2026, 10, 5, 17, 0), calendar: calendar))
        #expect(!AutomaticSwitchEvaluator.windowContains(rule, now: utcDate(2026, 10, 10, 10), calendar: calendar))
    }

    @Test func windowAcrossMidnightBelongsToTheDayItStarted() {
        let friday = windowRule(days: [6], from: 22 * 60, to: 6 * 60, dock: UUID())
        let calendar = utcCalendar()
        func inside(_ date: Date) -> Bool { AutomaticSwitchEvaluator.windowContains(friday, now: date, calendar: calendar) }
        #expect(inside(utcDate(2026, 10, 9, 23, 0)))
        #expect(inside(utcDate(2026, 10, 10, 5, 59)))
        #expect(!inside(utcDate(2026, 10, 10, 6, 0)))
        #expect(!inside(utcDate(2026, 10, 10, 23, 0)))
        #expect(!inside(utcDate(2026, 10, 8, 23, 0)))
        #expect(!inside(utcDate(2026, 10, 9, 5, 0)))
    }

    @Test func degenerateWindowsNeverMatch() {
        let calendar = utcCalendar()
        let now = utcDate(2026, 10, 5, 10)
        #expect(!AutomaticSwitchEvaluator.windowContains(windowRule(days: [2], from: 600, to: 600, dock: nil), now: now, calendar: calendar))
        #expect(!AutomaticSwitchEvaluator.windowContains(windowRule(days: [], from: 0, to: 1439, dock: nil), now: now, calendar: calendar))
    }

    @Test func nextBoundaryIsTheNextStartOrEnd() {
        let overnight = windowRule(days: [1, 2, 3, 4, 5, 6, 7], from: 22 * 60, to: 6 * 60, dock: UUID())
        let calendar = utcCalendar()
        #expect(AutomaticSwitchEvaluator.nextBoundary(for: [overnight], after: utcDate(2026, 10, 5, 10), calendar: calendar) == utcDate(2026, 10, 5, 22))
        #expect(AutomaticSwitchEvaluator.nextBoundary(for: [overnight], after: utcDate(2026, 10, 5, 23), calendar: calendar) == utcDate(2026, 10, 6, 6))
        #expect(AutomaticSwitchEvaluator.nextBoundary(for: [overnight], after: utcDate(2026, 10, 5, 22), calendar: calendar) == utcDate(2026, 10, 6, 6))
        #expect(AutomaticSwitchEvaluator.nextBoundary(for: [appRule(dock: UUID())], after: utcDate(2026, 10, 5, 10), calendar: calendar) == nil)
        #expect(AutomaticSwitchEvaluator.nextBoundary(for: [], after: utcDate(2026, 10, 5, 10), calendar: calendar) == nil)
    }

    @Test func windowsFollowTheWallClockAcrossDaylightSavingChanges() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let allDays = [1, 2, 3, 4, 5, 6, 7]

        // Fall back on 1 November 2026: 01:30 happens twice, and a 01:00-02:00 window covers both.
        let fall = windowRule(days: allDays, from: 60, to: 120, dock: UUID())
        #expect(AutomaticSwitchEvaluator.windowContains(fall, now: iso("2026-11-01T05:30:00Z"), calendar: newYork))
        #expect(AutomaticSwitchEvaluator.windowContains(fall, now: iso("2026-11-01T06:30:00Z"), calendar: newYork))
        #expect(!AutomaticSwitchEvaluator.windowContains(fall, now: iso("2026-11-01T07:00:00Z"), calendar: newYork))
        let afterFirstPass = iso("2026-11-01T05:15:00Z")
        let fallBoundary = AutomaticSwitchEvaluator.nextBoundary(for: [fall], after: afterFirstPass, calendar: newYork)
        #expect(fallBoundary != nil && fallBoundary! > afterFirstPass && fallBoundary! <= iso("2026-11-01T07:00:00Z"))

        // Spring forward on 8 March 2026: 02:00 jumps to 03:00. A 02:30-03:30 window starts at 03:00.
        let spring = windowRule(days: allDays, from: 150, to: 210, dock: UUID())
        #expect(!AutomaticSwitchEvaluator.windowContains(spring, now: iso("2026-03-08T06:59:00Z"), calendar: newYork))
        #expect(AutomaticSwitchEvaluator.windowContains(spring, now: iso("2026-03-08T07:00:00Z"), calendar: newYork))
        #expect(!AutomaticSwitchEvaluator.windowContains(spring, now: iso("2026-03-08T07:30:00Z"), calendar: newYork))
        let beforeGap = iso("2026-03-08T06:00:00Z")
        let springBoundary = AutomaticSwitchEvaluator.nextBoundary(for: [spring], after: beforeGap, calendar: newYork)
        #expect(springBoundary != nil && springBoundary! > beforeGap && springBoundary! <= iso("2026-03-08T07:30:00Z"))
    }

    // MARK: Dwell, override, missing Dock (engine)

    @Test func theDwellAbsorbsQuickAppSwitches() {
        var engine = AutomaticSwitchingEngine()
        let dock = UUID(), other = UUID()
        let rule = appRule(dock: dock)
        let valid: Set<UUID> = [dock, other]
        let t0 = utcDate(2026, 10, 5, 10)
        func step(_ front: String?, _ seconds: TimeInterval) -> AutomaticSwitchingEngine.Action {
            engine.evaluate(engineInput([rule], front: front, now: t0.addingTimeInterval(seconds), active: other, valid: valid)).action
        }
        #expect(step(xcode, 0) == .wait(until: t0.addingTimeInterval(2)))
        #expect(step(safari, 1) == .none)
        #expect(step(xcode, 1.5) == .wait(until: t0.addingTimeInterval(3.5)))
        #expect(step(xcode, 3) == .wait(until: t0.addingTimeInterval(3.5)))
        #expect(step(xcode, 3.5) == .apply(rule))
        #expect(AutomaticSwitchingEngine.dwell == 2)
    }

    @Test func aRuleWhoseDockIsAlreadyShownDoesNothing() {
        var engine = AutomaticSwitchingEngine()
        let dock = UUID()
        let output = engine.evaluate(engineInput([appRule(dock: dock)], front: xcode, now: utcDate(2026, 10, 5, 10), active: dock, valid: [dock]))
        #expect(output.action == .none)
        #expect(output.winnerRuleID != nil)
    }

    @Test func aManualSwitchPausesUntilTheMatchingContextChanges() {
        var engine = AutomaticSwitchingEngine()
        let dock = UUID(), manual = UUID()
        let rule = appRule(dock: dock)
        let valid: Set<UUID> = [dock, manual]
        let t0 = utcDate(2026, 10, 5, 10)
        func step(_ front: String?, _ seconds: TimeInterval, active: UUID?) -> AutomaticSwitchingEngine.Output {
            engine.evaluate(engineInput([rule], front: front, now: t0.addingTimeInterval(seconds), active: active, valid: valid))
        }
        _ = step(xcode, 0, active: manual)
        #expect(step(xcode, 2, active: manual).action == .apply(rule))
        #expect(step(xcode, 3, active: dock).action == .none)

        engine.noteManualSwitch()
        let paused = step(xcode, 4, active: manual)
        #expect(paused.action == .none && paused.isPaused)
        #expect(step(xcode, 600, active: manual).action == .none)
        #expect(engine.isPaused)

        // The context changes (another app), which resumes automation without switching back.
        let left = step(safari, 601, active: manual)
        #expect(left.action == .none && !left.isPaused)
        #expect(step(xcode, 602, active: manual).action == .wait(until: t0.addingTimeInterval(604)))
        #expect(step(xcode, 604, active: manual).action == .apply(rule))
    }

    @Test func aManualSwitchWhileNothingMatchesPausesUntilARuleMatches() {
        var engine = AutomaticSwitchingEngine()
        let dock = UUID(), manual = UUID()
        let rule = appRule(dock: dock)
        let t0 = utcDate(2026, 10, 5, 10)
        _ = engine.evaluate(engineInput([rule], front: safari, now: t0, active: manual, valid: [dock, manual]))
        engine.noteManualSwitch()
        #expect(engine.evaluate(engineInput([rule], front: safari, now: t0.addingTimeInterval(5), active: manual, valid: [dock, manual])).isPaused)
        let matching = engine.evaluate(engineInput([rule], front: xcode, now: t0.addingTimeInterval(6), active: manual, valid: [dock, manual]))
        #expect(!matching.isPaused)
        #expect(matching.action == .wait(until: t0.addingTimeInterval(8)))
    }

    @Test func aMissingDockSkipsTheRuleToTheNextMatch() {
        let missing = UUID(), dock = UUID()
        let skipped = appRule(dock: missing), fallback = appRule(dock: dock)
        let unassigned = appRule(dock: nil)
        let now = utcDate(2026, 10, 5, 10)
        let selection = AutomaticSwitchEvaluator.selection(rules: [skipped, unassigned, fallback], context: context(xcode, now), customProfileIDs: [dock])
        #expect(selection.rule?.id == fallback.id)
        #expect(selection.skippedMissing == [skipped.id, unassigned.id])
        let onlyMissing = AutomaticSwitchEvaluator.selection(rules: [skipped], context: context(xcode, now), customProfileIDs: [dock])
        #expect(onlyMissing.rule == nil && onlyMissing.skippedMissing == [skipped.id])
        #expect(AutomaticSwitchEvaluator.isDockMissing(skipped, customProfileIDs: [dock]))
        #expect(AutomaticSwitchEvaluator.isDockMissing(unassigned, customProfileIDs: [dock]))
        #expect(!AutomaticSwitchEvaluator.isDockMissing(fallback, customProfileIDs: [dock]))
    }

    @Test func draftsAndNativeOnlyModeDeferOrBlockTheSwitch() {
        var engine = AutomaticSwitchingEngine()
        let dock = UUID(), other = UUID()
        let rule = appRule(dock: dock)
        let t0 = utcDate(2026, 10, 5, 10)
        _ = engine.evaluate(engineInput([rule], front: xcode, now: t0, active: other, valid: [dock, other], draft: true))
        let held = engine.evaluate(engineInput([rule], front: xcode, now: t0.addingTimeInterval(3), active: other, valid: [dock, other], draft: true))
        #expect(held.action == .deferForDraft)
        let released = engine.evaluate(engineInput([rule], front: xcode, now: t0.addingTimeInterval(4), active: other, valid: [dock, other], draft: false))
        #expect(released.action == .apply(rule))
        var blocked = AutomaticSwitchingEngine()
        #expect(blocked.evaluate(engineInput([rule], front: xcode, now: t0, active: other, valid: [dock, other], canSwitch: false)).action == .none)
    }

    // MARK: Controller

    @Test func automaticSwitchingIsOffByDefaultAndSubscribesToNothing() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        #expect(!fixture.store.state.settings.automaticSwitching.isEnabled)
        fixture.controller.start()
        #expect(fixture.world.activationHandler == nil)
        #expect(fixture.world.timers.isEmpty)
        #expect(fixture.active == fixture.home)

        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.controller.reevaluate()
        #expect(fixture.world.activationHandler != nil)
        fixture.configure(enabled: false, rules: [appRule(dock: fixture.build)])
        fixture.controller.reevaluate()
        #expect(fixture.world.activeTimers.isEmpty)
    }

    @Test func aRuleSwitchesAfterTheDwellAndExplainsItself() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.controller.start()
        fixture.world.frontmost = xcode
        fixture.world.activationHandler?(xcode)
        #expect(fixture.active == fixture.home)
        #expect(fixture.world.activeTimers.count == 1)
        #expect(fixture.world.activeTimers.first?.date == fixture.world.now.addingTimeInterval(2))

        fixture.world.advance(2)
        fixture.world.fireNextTimer()
        #expect(fixture.active == fixture.build)
        #expect(fixture.status.menuLine == "Switched by rule: When Xcode is frontmost")
        #expect(fixture.status.settingsLine == "Last switch: Build & code because Xcode became frontmost.")
        #expect(fixture.world.activeTimers.isEmpty)
    }

    @Test func quickAppSwitchesNeverFlipTheDock() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.controller.start()
        fixture.world.activationHandler?(xcode)
        fixture.world.advance(1)
        fixture.world.activationHandler?(safari)
        fixture.world.advance(5)
        fixture.controller.reevaluate()
        #expect(fixture.active == fixture.home)
        #expect(fixture.status.lastSwitch == nil)
    }

    @Test func ownActivationsAreIgnored() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(bundle: "com.mydock.tests", name: "MyDock", dock: fixture.build)])
        fixture.controller.start()
        fixture.world.activationHandler?("com.mydock.tests")
        fixture.world.advance(10)
        fixture.controller.reevaluate()
        #expect(fixture.active == fixture.home)
    }

    @Test func aManualSwitchPausesTheControllerAndAContextChangeResumesIt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.controller.start()
        fixture.activateAndWait(xcode)
        #expect(fixture.active == fixture.build)

        fixture.store.setActiveCustomProfile(fixture.work)
        fixture.controller.reevaluate()
        #expect(fixture.status.isPaused)
        #expect(fixture.status.menuLine == "Automatic switching paused")
        fixture.world.advance(120)
        fixture.controller.reevaluate()
        #expect(fixture.active == fixture.work)

        fixture.world.activationHandler?(safari)
        #expect(!fixture.status.isPaused)
        #expect(fixture.status.menuLine == nil)
        fixture.activateAndWait(xcode)
        #expect(fixture.active == fixture.build)
        #expect(fixture.status.menuLine == "Switched by rule: When Xcode is frontmost")
    }

    @Test func aDeletedDockSkipsTheRuleInFavourOfTheNextOne() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: UUID()), appRule(dock: fixture.work)])
        fixture.controller.start()
        fixture.activateAndWait(xcode)
        #expect(fixture.active == fixture.work)

        let alone = try Fixture()
        defer { alone.cleanup() }
        alone.configure(rules: [appRule(dock: UUID())])
        alone.controller.start()
        alone.activateAndWait(xcode)
        #expect(alone.active == alone.home)
        #expect(alone.status.lastSwitch == nil)
    }

    @Test func anOpenDraftDefersTheSwitchUntilItCloses() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.controller.start()
        fixture.world.activationHandler?(xcode)

        var draft = DockProfileDraft(profile: try #require(fixture.store.customProfiles.first { $0.id == fixture.home }))
        draft.update { $0.name = "Home edited" }
        fixture.store.editSessions.set(draft, for: fixture.home)
        #expect(fixture.store.editSessions.hasUnsavedChanges)

        fixture.world.advance(2)
        fixture.world.fireNextTimer()
        #expect(fixture.active == fixture.home)
        #expect(fixture.status.lastSwitch == nil)
        #expect(fixture.store.editSessions.drafts[fixture.home]?.profile.name == "Home edited")

        fixture.store.editSessions.set(nil, for: fixture.home)
        fixture.controller.reevaluate()
        #expect(fixture.active == fixture.build)
    }

    @Test func switchingNeverChangesTheModeOfAMacOSDockOnlyUser() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.store.setSetupMode(.nativeOnly)
        fixture.controller.start()
        fixture.activateAndWait(xcode)
        #expect(fixture.active == fixture.home)
        #expect(fixture.store.state.settings.setupMode == .nativeOnly)
    }

    @Test func oneTimerTracksTheNextTimeWindowBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let overnight = windowRule(days: [1, 2, 3, 4, 5, 6, 7], from: 22 * 60, to: 6 * 60, dock: fixture.work)
        fixture.world.calendar.locale = Locale(identifier: "en_GB")
        fixture.configure(rules: [overnight])
        fixture.controller.start()
        #expect(fixture.active == fixture.home)
        #expect(fixture.world.activeTimers.count == 1)
        #expect(fixture.world.activeTimers.first?.date == utcDate(2026, 10, 5, 22))

        // Repeated evaluations never stack timers.
        fixture.controller.reevaluate()
        fixture.controller.reevaluate()
        #expect(fixture.world.timers.count == 1)

        fixture.world.now = utcDate(2026, 10, 5, 22)
        fixture.world.fireNextTimer()
        #expect(fixture.active == fixture.home)
        #expect(fixture.world.activeTimers.count == 1)
        #expect(fixture.world.activeTimers.first?.date == utcDate(2026, 10, 5, 22).addingTimeInterval(2))

        fixture.world.advance(2)
        fixture.world.fireNextTimer()
        #expect(fixture.active == fixture.work)
        #expect(fixture.world.activeTimers.count == 1)
        #expect(fixture.world.activeTimers.first?.date == utcDate(2026, 10, 6, 6))
        #expect(fixture.status.menuLine == "Switched by rule: Every day 22:00–06:00")
    }

    // MARK: Clock changes, stop and store observation (S18-021)

    @Test func aClockChangeReArmsTheTimerAtTheNewBoundary() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [windowRule(days: [1, 2, 3, 4, 5, 6, 7], from: 22 * 60, to: 6 * 60, dock: fixture.work)])
        fixture.controller.start()
        let armed = try #require(fixture.world.activeTimers.first)
        #expect(armed.date == utcDate(2026, 10, 5, 22))

        // The Mac moves two hours east: 22:00 on the wall clock now comes two hours sooner.
        fixture.world.calendar.timeZone = try #require(TimeZone(secondsFromGMT: 2 * 3600))
        fixture.world.fireClockChange()
        #expect(armed.cancelled)
        #expect(fixture.world.activeTimers.count == 1)
        #expect(fixture.world.activeTimers.first?.date == utcDate(2026, 10, 5, 20))
    }

    @Test func stoppingClearsTheTimerTheStatusAndEveryFeed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build),
                                  windowRule(days: [1, 2, 3, 4, 5, 6, 7], from: 22 * 60, to: 6 * 60, dock: fixture.work)])
        fixture.controller.start()
        fixture.activateAndWait(xcode)
        #expect(fixture.active == fixture.build)
        #expect(fixture.status.menuLine != nil)
        #expect(!fixture.world.activeTimers.isEmpty)

        fixture.controller.stop()
        #expect(fixture.world.activeTimers.isEmpty)
        #expect(fixture.status.menuLine == nil)
        #expect(fixture.world.clockFeed?.cancelled == true)

        // A late activation callback after stop changes nothing.
        fixture.store.setActiveCustomProfile(fixture.home)
        fixture.world.activationHandler?(xcode)
        fixture.world.advance(AutomaticSwitchingEngine.dwell)
        fixture.world.fireNextTimer()
        #expect(fixture.active == fixture.home)
        #expect(fixture.world.activeTimers.isEmpty)
        #expect(fixture.status.menuLine == nil)
    }

    @Test func aManualSwitchIsSeenThroughTheStoreWithoutAnExplicitReevaluate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        fixture.configure(rules: [appRule(dock: fixture.build)])
        fixture.controller.start()
        fixture.activateAndWait(xcode)
        #expect(fixture.active == fixture.build)

        fixture.store.setActiveCustomProfile(fixture.work)
        // The controller hears the store on the main run loop.
        let deadline = Date().addingTimeInterval(10)
        while !fixture.status.isPaused, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        #expect(fixture.status.isPaused)
        #expect(fixture.active == fixture.work)
    }

    // MARK: Text and options

    @Test func rulesReadAsPlainSentences() {
        // Times follow the locale's clock; a 24-hour locale pins the expected text.
        var calendar = utcCalendar()
        calendar.locale = Locale(identifier: "en_GB")
        let dock = UUID()
        #expect(AutomaticSwitchRuleText.summary(appRule(dock: dock), dockName: "Build & code", calendar: calendar) == "When Xcode is frontmost → Build & code")
        #expect(AutomaticSwitchRuleText.summary(appRule(dock: dock), dockName: nil, calendar: calendar) == "When Xcode is frontmost → Dock missing")
        #expect(AutomaticSwitchRuleText.summary(windowRule(days: [2, 3, 4, 5, 6], from: 540, to: 1020, dock: dock), dockName: "Work", calendar: calendar) == "Weekdays 09:00–17:00 → Work")
        #expect(AutomaticSwitchRuleText.title(windowRule(days: [1, 7], from: 0, to: 90, dock: dock), calendar: calendar) == "Weekends 00:00–01:30")
        #expect(AutomaticSwitchRuleText.title(windowRule(days: [2, 4], from: 600, to: 660, dock: dock), calendar: calendar) == "Mon, Wed 10:00–11:00")
        // A 12-hour locale reads the same rule on a 12-hour clock.
        var american = utcCalendar()
        american.locale = Locale(identifier: "en_US")
        #expect(AutomaticSwitchRuleText.timeString(1020, calendar: american).contains("5:00"))
        #expect(AutomaticSwitchRuleText.timeString(1020, calendar: american).contains("PM"))
        #expect(AutomaticSwitchRuleText.weekdaySummary([1, 2, 3, 4, 5, 6, 7], calendar: calendar) == "Every day")
        #expect(AutomaticSwitchRuleText.weekdaySummary([], calendar: calendar) == "No days")
        #expect(AutomaticSwitchRuleText.title(appRule(bundle: "com.example.App", name: nil, dock: dock), calendar: calendar) == "When com.example.App is frontmost")
    }

    @Test func appOptionsMergeRunningAndInstalledWithoutDuplicates() {
        let running = [AutomaticSwitchAppOption(id: xcode, name: "Xcode")]
        let installed = [
            AutomaticSwitchAppOption(id: xcode.uppercased(), name: "Xcode (installed)"),
            AutomaticSwitchAppOption(id: safari, name: "Safari"),
            AutomaticSwitchAppOption(id: "com.apple.iCal", name: "Calendar"),
            AutomaticSwitchAppOption(id: "", name: "Nameless")
        ]
        let merged = AutomaticSwitchAppOptions.merge(running: running, installed: installed)
        #expect(merged.map(\.name) == ["Calendar", "Safari", "Xcode"])
    }
}
