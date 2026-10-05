import AppKit
import Combine
import Foundation

/// Runtime-only explanation of automatic switching, shared by Settings and the menu-bar menu.
/// Nothing here is persisted.
@MainActor
final class AutomaticSwitchingStatus: ObservableObject {
    static let shared = AutomaticSwitchingStatus()

    @Published private(set) var lastSwitch: AutomaticSwitchRecord?
    /// True once the user has switched Docks by hand since `lastSwitch`.
    @Published private(set) var lastSwitchOverridden = false
    @Published private(set) var isPaused = false

    init() {}

    func recordSwitch(_ record: AutomaticSwitchRecord) {
        lastSwitch = record
        lastSwitchOverridden = false
    }

    func markOverridden() {
        guard lastSwitch != nil, !lastSwitchOverridden else { return }
        lastSwitchOverridden = true
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        isPaused = paused
    }

    func clear() {
        if lastSwitch != nil { lastSwitch = nil }
        if lastSwitchOverridden { lastSwitchOverridden = false }
        setPaused(false)
    }

    /// The single line for the menu-bar menu, or `nil` when there is nothing to explain.
    var menuLine: String? {
        if isPaused { return "Automatic switching paused" }
        guard let lastSwitch, !lastSwitchOverridden else { return nil }
        return "Switched by rule: \(lastSwitch.ruleTitle)"
    }

    /// The footer text for Settings.
    var settingsLine: String? {
        guard let lastSwitch else { return nil }
        let base = "Last switch: \(lastSwitch.profileName) because \(lastSwitch.reason)."
        return isPaused ? base + " Paused until the context changes." : base
    }
}

/// The thin observer around `AutomaticSwitchingEngine`. It evaluates on app activation, on
/// settings, Dock and draft changes, and at the next time-window boundary or dwell deadline
/// using a single timer. It never polls. Every system input is injected.
@MainActor
final class AutomaticSwitchingController {
    struct Dependencies {
        var now: @MainActor () -> Date
        var calendar: @MainActor () -> Calendar
        var frontmostBundleIdentifier: @MainActor () -> String?
        /// Activations of this bundle (MyDock itself) are ignored, so opening Settings changes nothing.
        var ownBundleIdentifier: String?
        var observeActivations: @MainActor (_ handler: @escaping @MainActor (String?) -> Void) -> AnyCancellable
        /// Wake, clock and time-zone changes: the single timer is re-armed.
        var observeClockChanges: @MainActor (_ handler: @escaping @MainActor () -> Void) -> AnyCancellable
        var schedule: @MainActor (_ date: Date, _ fire: @escaping @MainActor () -> Void) -> AnyCancellable

        @MainActor static func live() -> Dependencies {
            Dependencies(
                now: { Date() },
                calendar: { Calendar.current },
                frontmostBundleIdentifier: {
                    AppRuntimeEnvironment.allowsNativeEffects
                        ? NSWorkspace.shared.frontmostApplication?.bundleIdentifier : nil
                },
                ownBundleIdentifier: Bundle.main.bundleIdentifier,
                observeActivations: { handler in
                    guard AppRuntimeEnvironment.allowsNativeEffects else { return AnyCancellable {} }
                    return NSWorkspace.shared.notificationCenter
                        .publisher(for: NSWorkspace.didActivateApplicationNotification)
                        .receive(on: RunLoop.main)
                        .sink { notification in
                            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                            handler(application?.bundleIdentifier)
                        }
                },
                observeClockChanges: { handler in
                    guard AppRuntimeEnvironment.allowsNativeEffects else { return AnyCancellable {} }
                    return Publishers.Merge3(
                        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification),
                        NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
                        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
                    )
                    .receive(on: RunLoop.main)
                    .sink { _ in handler() }
                },
                schedule: { date, fire in
                    let task = Task { @MainActor in
                        let seconds = min(max(date.timeIntervalSinceNow, 0), 7 * 24 * 3600)
                        do { try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) } catch { return }
                        fire()
                    }
                    return AnyCancellable { task.cancel() }
                }
            )
        }
    }

    private let store: ProfileStore
    private let status: AutomaticSwitchingStatus
    private let dependencies: Dependencies
    private var engine = AutomaticSwitchingEngine()
    private var isRunning = false
    private var frontmost: String?
    private var lastSeenActiveProfileID: UUID?
    private var timer: AnyCancellable?
    private var scheduledDate: Date?
    private var activationObservation: AnyCancellable?
    private var clockObservation: AnyCancellable?
    private var storeObservations: [AnyCancellable] = []

    init(store: ProfileStore, status: AutomaticSwitchingStatus? = nil, dependencies: Dependencies? = nil) {
        self.store = store
        self.status = status ?? AutomaticSwitchingStatus.shared
        self.dependencies = dependencies ?? Dependencies.live()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastSeenActiveProfileID = store.state.settings.activeCustomProfileID
        storeObservations = [
            store.$state.receive(on: RunLoop.main).sink { [weak self] _ in self?.reevaluate() },
            store.editSessions.$drafts.receive(on: RunLoop.main).sink { [weak self] _ in self?.reevaluate() }
        ]
        clockObservation = dependencies.observeClockChanges { [weak self] in self?.handleClockChange() }
        reevaluate()
    }

    func stop() {
        isRunning = false
        storeObservations = []
        clockObservation = nil
        activationObservation = nil
        cancelTimer()
        engine.reset()
        status.clear()
    }

    private func filtered(_ bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              bundleIdentifier != dependencies.ownBundleIdentifier else { return nil }
        return bundleIdentifier
    }

    private func handleActivation(_ bundleIdentifier: String?) {
        // Ignore MyDock itself and processes without an identifier: the previous context stays.
        guard let identifier = filtered(bundleIdentifier) else { return }
        frontmost = identifier
        reevaluate()
    }

    private func handleClockChange() {
        cancelTimer()
        reevaluate()
    }

    private func cancelTimer() {
        timer?.cancel()
        timer = nil
        scheduledDate = nil
    }

    private func arm(_ date: Date?) {
        guard let date else { cancelTimer(); return }
        guard date != scheduledDate else { return }
        timer?.cancel()
        scheduledDate = date
        timer = dependencies.schedule(date) { [weak self] in
            guard let self else { return }
            self.timer = nil
            self.scheduledDate = nil
            self.reevaluate()
        }
    }

    /// Re-reads the store and the injected context, then acts on the engine's decision.
    func reevaluate() {
        guard isRunning else { return }
        let settings = store.state.settings
        let automatic = settings.automaticSwitching
        let active = settings.activeCustomProfileID

        guard automatic.isEnabled else {
            engine.reset()
            status.clear()
            cancelTimer()
            activationObservation = nil
            lastSeenActiveProfileID = active
            return
        }
        if activationObservation == nil {
            frontmost = filtered(dependencies.frontmostBundleIdentifier())
            activationObservation = dependencies.observeActivations { [weak self] identifier in
                self?.handleActivation(identifier)
            }
        }
        // Applying a rule updates `lastSeenActiveProfileID` itself, so any other change is manual.
        if active != lastSeenActiveProfileID {
            engine.noteManualSwitch()
            status.markOverridden()
            lastSeenActiveProfileID = active
        }

        let calendar = dependencies.calendar()
        let now = dependencies.now()
        let output = engine.evaluate(AutomaticSwitchingEngine.Input(
            rules: automatic.rules,
            context: AutomaticSwitchContext(frontmostBundleIdentifier: frontmost, now: now, calendar: calendar),
            customProfileIDs: Set(store.customProfiles.map(\.id)),
            activeProfileID: active,
            canSwitch: settings.setupMode != .nativeOnly,
            draftIsOpen: store.editSessions.hasUnsavedChanges))
        status.setPaused(output.isPaused)

        var wake: Date?
        switch output.action {
        case .none, .deferForDraft:
            break
        case .wait(let deadline):
            wake = deadline
        case .apply(let rule):
            apply(rule, calendar: calendar, now: now)
        }
        if let boundary = AutomaticSwitchEvaluator.nextBoundary(for: automatic.rules, after: now, calendar: calendar) {
            wake = wake.map { min($0, boundary) } ?? boundary
        }
        arm(wake)
    }

    private func apply(_ rule: AutomaticSwitchRule, calendar: Calendar, now: Date) {
        guard let profileID = rule.profileID,
              let profile = store.customProfiles.first(where: { $0.id == profileID }) else { return }
        // The record is set first so a menu rebuilt by the state change already explains it.
        status.recordSwitch(AutomaticSwitchRecord(
            ruleID: rule.id,
            ruleTitle: AutomaticSwitchRuleText.title(rule, calendar: calendar),
            reason: AutomaticSwitchRuleText.reason(rule, calendar: calendar),
            profileID: profile.id,
            profileName: profile.name,
            date: now))
        store.activate(profile.id)
        lastSeenActiveProfileID = store.state.settings.activeCustomProfileID
    }
}
