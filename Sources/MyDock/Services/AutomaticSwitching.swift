import Foundation

// Automatic Custom Dock switching: persisted rule model, pure rule evaluation and a pure
// dwell / manual-override state machine. Nothing here observes the system; see
// `AutomaticSwitchingController` for the thin observer.

/// One simple rule. Exactly two kinds exist; there is deliberately no rule builder.
struct AutomaticSwitchRule: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case appFrontmost, timeWindow }

    static let weekdayRange = 1...7
    static let minutesPerDay = 1440

    var id: UUID
    var kind: Kind
    /// The Custom Dock to show. `nil` until chosen; a missing Dock never matches.
    var profileID: UUID?
    var bundleIdentifier: String?
    /// Display name captured when the app was chosen, so the row still reads well if the app is gone.
    var appName: String?
    /// `Calendar` weekday numbers (1 = Sunday ... 7 = Saturday) on which a window starts.
    var weekdays: [Int]
    var startMinute: Int
    var endMinute: Int

    private enum CodingKeys: String, CodingKey {
        case id, kind, profileID, bundleIdentifier, appName, weekdays, startMinute, endMinute
    }

    init(id: UUID = UUID(), kind: Kind, profileID: UUID? = nil, bundleIdentifier: String? = nil,
         appName: String? = nil, weekdays: [Int] = [2, 3, 4, 5, 6], startMinute: Int = 9 * 60, endMinute: Int = 17 * 60) {
        self.id = id
        self.kind = kind
        self.profileID = profileID
        self.bundleIdentifier = bundleIdentifier
        self.appName = appName
        self.weekdays = Self.normalized(weekdays)
        self.startMinute = Self.clampedMinute(startMinute)
        self.endMinute = Self.clampedMinute(endMinute)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // An unknown or missing kind throws, so `AutomaticSwitchingSettings` drops only this rule.
        kind = try values.decode(Kind.self, forKey: .kind)
        id = (try? values.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        profileID = (try? values.decodeIfPresent(UUID.self, forKey: .profileID)) ?? nil
        bundleIdentifier = (try? values.decodeIfPresent(String.self, forKey: .bundleIdentifier)) ?? nil
        appName = (try? values.decodeIfPresent(String.self, forKey: .appName)) ?? nil
        weekdays = Self.normalized((try? values.decodeIfPresent([Int].self, forKey: .weekdays)) ?? [2, 3, 4, 5, 6])
        startMinute = Self.clampedMinute((try? values.decodeIfPresent(Int.self, forKey: .startMinute)) ?? 9 * 60)
        endMinute = Self.clampedMinute((try? values.decodeIfPresent(Int.self, forKey: .endMinute)) ?? 17 * 60)
    }

    static func normalized(_ weekdays: [Int]) -> [Int] {
        Array(Set(weekdays.filter { weekdayRange.contains($0) })).sorted()
    }

    static func clampedMinute(_ minute: Int) -> Int {
        min(max(minute, 0), minutesPerDay - 1)
    }
}

/// The persisted switch. Off by default; old state files decode to this value.
struct AutomaticSwitchingSettings: Codable, Equatable, Sendable {
    static let maximumRules = 20

    var isEnabled = false
    /// Ordered: the order is the priority, and the first matching rule wins.
    var rules: [AutomaticSwitchRule] = []

    private enum CodingKeys: String, CodingKey { case isEnabled, rules }

    /// Decodes one rule at a time so a single unreadable rule does not discard the others.
    private struct LossyRule: Decodable {
        var rule: AutomaticSwitchRule?
        init(from decoder: Decoder) throws { rule = try? AutomaticSwitchRule(from: decoder) }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = (try? values.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? false
        let decoded = (try? values.decodeIfPresent([LossyRule].self, forKey: .rules)) ?? []
        var seen = Set<UUID>()
        rules = decoded.compactMap(\.rule)
            .filter { seen.insert($0.id).inserted }
            .prefix(Self.maximumRules)
            .map { $0 }
    }

    var canAddRule: Bool { rules.count < Self.maximumRules }

    /// Appends a rule and returns its id, or `nil` at the cap.
    @discardableResult
    mutating func addRule(_ kind: AutomaticSwitchRule.Kind, defaultProfileID: UUID?) -> UUID? {
        guard canAddRule else { return nil }
        let rule = AutomaticSwitchRule(kind: kind, profileID: defaultProfileID)
        rules.append(rule)
        return rule.id
    }

    mutating func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
    }

    /// Puts a deleted rule back at its old priority. Ignored at the cap or when the rule is still present.
    @discardableResult
    mutating func restoreRule(_ rule: AutomaticSwitchRule, at index: Int) -> Bool {
        guard canAddRule, !rules.contains(where: { $0.id == rule.id }) else { return false }
        rules.insert(rule, at: min(max(index, 0), rules.count))
        return true
    }

    /// Moves a rule up (`-1`) or down (`+1`) in priority; out-of-range moves are ignored.
    mutating func moveRule(_ id: UUID, by offset: Int) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard rules.indices.contains(target), target != index else { return }
        rules.swapAt(index, target)
    }

    mutating func updateRule(_ id: UUID, _ change: (inout AutomaticSwitchRule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        change(&rules[index])
        rules[index].weekdays = AutomaticSwitchRule.normalized(rules[index].weekdays)
        rules[index].startMinute = AutomaticSwitchRule.clampedMinute(rules[index].startMinute)
        rules[index].endMinute = AutomaticSwitchRule.clampedMinute(rules[index].endMinute)
    }
}

struct AutomaticSwitchContext: Sendable {
    var frontmostBundleIdentifier: String?
    var now: Date
    var calendar: Calendar
}

/// Pure rule matching, selection and boundary calculation.
enum AutomaticSwitchEvaluator {
    static func matches(_ rule: AutomaticSwitchRule, in context: AutomaticSwitchContext) -> Bool {
        switch rule.kind {
        case .appFrontmost:
            guard let wanted = rule.bundleIdentifier, !wanted.isEmpty,
                  let frontmost = context.frontmostBundleIdentifier else { return false }
            return wanted.caseInsensitiveCompare(frontmost) == .orderedSame
        case .timeWindow:
            return windowContains(rule, now: context.now, calendar: context.calendar)
        }
    }

    /// Wall-clock comparison in the calendar's time zone, so DST shifts never need special cases.
    /// Weekdays name the day a window starts on: a 22:00–06:00 window selected for Friday also
    /// covers Saturday 00:00–06:00. Equal start and end, or no weekdays, never match.
    static func windowContains(_ rule: AutomaticSwitchRule, now: Date, calendar: Calendar) -> Bool {
        let start = rule.startMinute, end = rule.endMinute
        guard start != end else { return false }
        let days = Set(rule.weekdays.filter { AutomaticSwitchRule.weekdayRange.contains($0) })
        guard !days.isEmpty else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: now)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return false }
        let minuteOfDay = hour * 60 + minute
        if start < end {
            return days.contains(weekday) && minuteOfDay >= start && minuteOfDay < end
        }
        if minuteOfDay >= start { return days.contains(weekday) }
        if minuteOfDay < end { return days.contains(weekday == 1 ? 7 : weekday - 1) }
        return false
    }

    static func isDockMissing(_ rule: AutomaticSwitchRule, customProfileIDs: Set<UUID>) -> Bool {
        guard let id = rule.profileID else { return true }
        return !customProfileIDs.contains(id)
    }

    struct Selection: Equatable {
        /// The first matching rule whose Custom Dock still exists.
        var rule: AutomaticSwitchRule?
        /// Matching rules that were skipped, ahead of the winner, because their Dock is missing.
        var skippedMissing: [UUID]
    }

    static func selection(rules: [AutomaticSwitchRule], context: AutomaticSwitchContext,
                          customProfileIDs: Set<UUID>) -> Selection {
        var skipped: [UUID] = []
        for rule in rules where matches(rule, in: context) {
            if isDockMissing(rule, customProfileIDs: customProfileIDs) {
                skipped.append(rule.id)
            } else {
                return Selection(rule: rule, skippedMissing: skipped)
            }
        }
        return Selection(rule: nil, skippedMissing: skipped)
    }

    /// The next instant at which any time window starts or ends. One timer is armed for this
    /// date; boundaries on days a rule is not selected are harmless extra evaluations.
    static func nextBoundary(for rules: [AutomaticSwitchRule], after now: Date, calendar: Calendar) -> Date? {
        var minutes = Set<Int>()
        for rule in rules where rule.kind == .timeWindow && rule.startMinute != rule.endMinute && !rule.weekdays.isEmpty {
            minutes.insert(rule.startMinute)
            minutes.insert(rule.endMinute)
        }
        var best: Date?
        for minute in minutes {
            let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
            guard let date = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime),
                  date > now else { continue }
            if let current = best { best = min(current, date) } else { best = date }
        }
        return best
    }
}

/// What the user reads. Pure so it can be tested and shared by Settings and the menu.
enum AutomaticSwitchRuleText {
    static func appName(_ rule: AutomaticSwitchRule) -> String {
        if let name = rule.appName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let identifier = rule.bundleIdentifier, !identifier.isEmpty { return identifier }
        return "an app"
    }

    static func timeString(_ minute: Int) -> String {
        let clamped = AutomaticSwitchRule.clampedMinute(minute)
        return String(format: "%d:%02d", clamped / 60, clamped % 60)
    }

    static func weekdaySummary(_ weekdays: [Int], calendar: Calendar = .current) -> String {
        let days = Set(weekdays.filter { AutomaticSwitchRule.weekdayRange.contains($0) })
        if days.isEmpty { return "No days" }
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = calendar.shortWeekdaySymbols
        let first = max(1, min(calendar.firstWeekday, 7))
        let ordered = (0..<7).map { ((first - 1 + $0) % 7) + 1 }.filter { days.contains($0) }
        return ordered.map { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : "\($0)" }.joined(separator: ", ")
    }

    /// "When Xcode is frontmost" or "Weekdays 9:00–17:00".
    static func title(_ rule: AutomaticSwitchRule, calendar: Calendar = .current) -> String {
        switch rule.kind {
        case .appFrontmost:
            return "When \(appName(rule)) is frontmost"
        case .timeWindow:
            return "\(weekdaySummary(rule.weekdays, calendar: calendar)) \(timeString(rule.startMinute))–\(timeString(rule.endMinute))"
        }
    }

    /// Why a rule can never match, or `nil`. A missing Dock is reported separately.
    static func problem(_ rule: AutomaticSwitchRule) -> String? {
        switch rule.kind {
        case .appFrontmost:
            guard let identifier = rule.bundleIdentifier, !identifier.isEmpty else { return "No app chosen, so this rule never matches." }
            return nil
        case .timeWindow:
            if rule.weekdays.isEmpty { return "No days chosen, so this rule never matches." }
            if rule.startMinute == rule.endMinute { return "Start and end are the same, so this rule never matches." }
            return nil
        }
    }

    /// "When Xcode is frontmost → Build & code".
    static func summary(_ rule: AutomaticSwitchRule, dockName: String?, calendar: Calendar = .current) -> String {
        "\(title(rule, calendar: calendar)) → \(dockName ?? "Dock missing")"
    }

    /// The clause after "because" in Settings.
    static func reason(_ rule: AutomaticSwitchRule, calendar: Calendar = .current) -> String {
        switch rule.kind {
        case .appFrontmost: "\(appName(rule)) became frontmost"
        case .timeWindow: "the \(title(rule, calendar: calendar)) window started"
        }
    }
}

/// Runtime-only record of the last automatic switch. Never persisted.
struct AutomaticSwitchRecord: Equatable, Sendable {
    var ruleID: UUID
    var ruleTitle: String
    var reason: String
    var profileID: UUID
    var profileName: String
    var date: Date
}

/// Pure dwell, priority and manual-override state machine. It owns no clock, timer or observer:
/// the caller supplies the context and the current time, and acts on the returned action.
struct AutomaticSwitchingEngine {
    /// A rule must keep winning for this long before the Dock changes.
    static let dwell: TimeInterval = 2

    struct Input {
        var rules: [AutomaticSwitchRule]
        var context: AutomaticSwitchContext
        var customProfileIDs: Set<UUID>
        var activeProfileID: UUID?
        /// False when switching would change the user's mode (macOS Dock only).
        var canSwitch: Bool
        /// True while any profile draft has unsaved changes.
        var draftIsOpen: Bool
    }

    enum Action: Equatable {
        case none
        /// A winner exists but has not yet held for the dwell time.
        case wait(until: Date)
        /// The dwell is satisfied, but an unsaved draft is open. Re-evaluate when it closes.
        case deferForDraft
        case apply(AutomaticSwitchRule)
    }

    struct Output: Equatable {
        var action: Action
        var winnerRuleID: UUID?
        var skippedMissingRuleIDs: [UUID]
        var isPaused: Bool
    }

    private struct Pending: Equatable {
        var ruleID: UUID
        var since: Date
    }

    private var pending: Pending?
    private(set) var isPaused = false
    private(set) var pausedRuleID: UUID?
    /// The winning rule at the last evaluation: the "matching context".
    private(set) var winnerRuleID: UUID?

    init() {}

    /// The user switched Docks. Automatic switching pauses until the winning rule changes.
    mutating func noteManualSwitch() {
        isPaused = true
        pausedRuleID = winnerRuleID
        pending = nil
    }

    mutating func reset() {
        pending = nil
        isPaused = false
        pausedRuleID = nil
        winnerRuleID = nil
    }

    mutating func evaluate(_ input: Input) -> Output {
        let selection = AutomaticSwitchEvaluator.selection(
            rules: input.rules, context: input.context, customProfileIDs: input.customProfileIDs)
        let winner = selection.rule
        winnerRuleID = winner?.id

        if isPaused {
            if winner?.id == pausedRuleID {
                pending = nil
                return makeOutput(.none, selection: selection)
            }
            isPaused = false
            pausedRuleID = nil
        }
        guard let winner, input.canSwitch, winner.profileID != input.activeProfileID else {
            pending = nil
            return makeOutput(.none, selection: selection)
        }

        let now = input.context.now
        if pending?.ruleID != winner.id || (pending.map { $0.since > now } ?? false) {
            pending = Pending(ruleID: winner.id, since: now)
        }
        let since = pending?.since ?? now
        let ready = since.addingTimeInterval(Self.dwell)
        if now < ready { return makeOutput(.wait(until: ready), selection: selection) }
        if input.draftIsOpen { return makeOutput(.deferForDraft, selection: selection) }
        pending = nil
        return makeOutput(.apply(winner), selection: selection)
    }

    private func makeOutput(_ action: Action, selection: AutomaticSwitchEvaluator.Selection) -> Output {
        Output(action: action, winnerRuleID: selection.rule?.id,
               skippedMissingRuleIDs: selection.skippedMissing, isPaused: isPaused)
    }
}
