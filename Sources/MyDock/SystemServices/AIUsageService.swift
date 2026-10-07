import CryptoKit
import CoreFoundation
import Foundation

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case codex
    case claude
    case grok
    case cursor
    case geminiCLI
    case copilot
    case antigravity

    var id: String { rawValue }
    /// The providers with a local activity source; AI Activity offers and decodes only these.
    static let localActivityProviders: [AIProvider] = [.codex, .claude, .grok]
    var title: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .grok: "Grok"
        case .cursor: "Cursor"
        case .geminiCLI: "Gemini CLI"
        case .copilot: "GitHub Copilot"
        case .antigravity: "Antigravity CLI"
        }
    }

    var setupInstructions: String {
        switch self {
        case .codex: "Sign in to Codex with your ChatGPT account or install Codex CLI and run codex login. MyDock asks the local app-server for read-only account limits; it never starts a task."
        case .claude: "Find your Claude Code account on this Mac, then choose Enable Limits. Subscription limits sync through Claude Code’s status line while you use it. Local activity is read automatically."
        case .grok: "Grok subscription allowance is visible in Grok settings, but this build has no supported local quota reader. Activity is a local estimate from ~/.grok/sessions."
        case .cursor: "Cursor shows individual included usage and remaining allowance in its Spending dashboard. MyDock has no documented personal-account API reader for those values."
        case .geminiCLI: "Gemini CLI's /stats model shows model usage and quota in the CLI. Google does not permit third-party tools to piggyback on Gemini CLI OAuth or backend services, so MyDock does not read private credentials or service caches."
        case .copilot: "For a personal Copilot plan, save a fine-grained GitHub token with Plan read permission in Settings → Integrations, then set the monthly AI-credit allowance in this widget. MyDock reads only the official GitHub billing endpoint; organization-billed plans are not included."
        case .antigravity: "Antigravity CLI provides /usage in its own interface. MyDock does not yet read a supported local allowance source."
        }
    }
}

enum AILimitLayout: String, Codable, CaseIterable, Identifiable {
    case numbers
    case rings
    case bars
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum AIUsageRepresentation: String, Codable, CaseIterable, Identifiable {
    case remaining
    case used
    var id: String { rawValue }
    var title: String { self == .remaining ? "Remaining" : "Used" }
}

enum AILimitAvailability: String, Codable {
    case available
    case setupRequired
    case unavailable
    case error
}

/// Domains for cached/untrusted AI numbers, per provider.
enum AIUsageDomain {
    static let maximumDurationMinutes = 366 * 24 * 60 * 10
    static let maximumWindows = 16
    static let maximumPoints = 10_000
    static let maximumCount = 1_000_000_000_000
    static let maximumTokens: Int64 = 1_000_000_000_000_000
    static let maximumCostUSD = Decimal(1_000_000_000)
    static let maximumDateInterval: TimeInterval = 315_576_000_000

    /// Copilot credits and Claude's spend-limit window can legitimately pass 100% (overage); the rest are fixed windows.
    static func maximumPercent(for provider: AIProvider) -> Int { provider == .copilot || provider == .claude ? 100_000 : 100 }
    static func isSupported(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite && abs(date.timeIntervalSinceReferenceDate) <= maximumDateInterval
    }
}

struct AILimitWindow: Codable, Hashable, Identifiable {
    var name: String
    var usedPercent: Int?
    var resetsAt: Date?
    var durationMinutes: Int?
    var id: String { name }

    func isValid(for provider: AIProvider) -> Bool {
        usedPercent.map { (0...AIUsageDomain.maximumPercent(for: provider)).contains($0) } ?? true
            && durationMinutes.map { (1...AIUsageDomain.maximumDurationMinutes).contains($0) } ?? true
            && resetsAt.map(AIUsageDomain.isSupported) ?? true
    }

    /// Out-of-domain readings become unavailable (nil) rather than failing the whole profile.
    func sanitized(for provider: AIProvider) -> AILimitWindow {
        var copy = self
        if let percent = usedPercent, !(0...AIUsageDomain.maximumPercent(for: provider)).contains(percent) { copy.usedPercent = nil }
        if let minutes = durationMinutes, !(1...AIUsageDomain.maximumDurationMinutes).contains(minutes) { copy.durationMinutes = nil }
        if let reset = resetsAt, !AIUsageDomain.isSupported(reset) { copy.resetsAt = nil }
        return copy
    }

    var remainingPercent: Int? {
        guard let usedPercent, usedPercent >= 0 else { return nil }
        guard usedPercent < 100 else { return 0 }
        return 100 - usedPercent
    }
}

/// Paths identify local data scope, never an authenticated account. Hashes keep private paths out of cached labels.
enum AIUsageSourceScope {
    static func directory(provider: AIProvider, homeDirectory: URL? = nil, environment: [String: String]? = nil) -> URL? {
        let home = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let environment = environment ?? (homeDirectory == nil ? ProcessInfo.processInfo.environment : [:])
        switch provider {
        case .codex:
            let configured = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            return (configured ?? home.appendingPathComponent(".codex", isDirectory: true)).appendingPathComponent("sessions", isDirectory: true)
        case .claude:
            return AIAccountService.claudeDirectory(home: home, environment: environment).appendingPathComponent("projects", isDirectory: true)
        case .grok: return home.appendingPathComponent(".grok/sessions", isDirectory: true)
        default: return nil
        }
    }

    private static func root(provider: AIProvider, homeDirectory: URL?, environment: [String: String]?) -> String {
        guard let url = directory(provider: provider, homeDirectory: homeDirectory, environment: environment) else {
            return provider.rawValue + "|provider-api"
        }
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func activity(provider: AIProvider, range: AIActivityRange, homeDirectory: URL? = nil,
                         environment: [String: String]? = nil, timeZone: TimeZone = .current, now: Date = .now,
                         semanticVersion: Int = AIActivitySnapshot.currentSemanticVersion) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Sliding ranges change their start each day; MTD retains same-month offline readings.
        let intervalStart = range.interval(endingAt: now, calendar: calendar).start.timeIntervalSince1970
        return "activity-v\(semanticVersion)|\(provider.rawValue)|\(range.rawValue)|\(timeZone.identifier)|\(Int64(intervalStart))|" +
            hash(root(provider: provider, homeDirectory: homeDirectory, environment: environment))
    }

    static func limits(providers: [AIProvider], homeDirectory: URL? = nil, environment: [String: String]? = nil, now: Date = .now) -> String {
        let roots = Set(providers).sorted { $0.rawValue < $1.rawValue }.map {
            $0.rawValue + "|" + root(provider: $0, homeDirectory: homeDirectory, environment: environment)
        }.joined(separator: ";")
        var period = ""
        if providers.contains(.copilot) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let start = calendar.dateInterval(of: .month, for: now)!.start.timeIntervalSince1970
            period = "|\(Int64(start))"
        }
        return "limits-v1|UTC\(period)|" + hash(roots)
    }
}

enum AILimitFailureKind: String, Codable { case transient, authentication, unavailable }

/// Only the Copilot adapter can attach a requested identity that its supported response subsequently verifies.
struct AILimitReadFailure: Error {
    var kind: AILimitFailureKind
    var requestedAccountIdentity: String?
    var message: String
}

struct AIProviderLimitReading: Codable, Hashable, Identifiable {
    var provider: AIProvider
    var availability: AILimitAvailability
    var plan: String?
    var windows: [AILimitWindow]
    var updatedAt: Date?
    var message: String?
    var verifiedAccountIdentity: String?
    var requestedAccountIdentity: String?
    var failureKind: AILimitFailureKind?
    var lastRefreshError: String?
    var id: AIProvider { provider }

    private enum CodingKeys: String, CodingKey { case provider, availability, plan, windows, updatedAt, message, verifiedAccountIdentity, requestedAccountIdentity, failureKind, lastRefreshError }

    init(provider: AIProvider, availability: AILimitAvailability, plan: String? = nil, windows: [AILimitWindow],
         updatedAt: Date? = nil, message: String? = nil, verifiedAccountIdentity: String? = nil,
         requestedAccountIdentity: String? = nil, failureKind: AILimitFailureKind? = nil, lastRefreshError: String? = nil) {
        self.verifiedAccountIdentity = verifiedAccountIdentity; self.requestedAccountIdentity = requestedAccountIdentity; self.failureKind = failureKind; self.lastRefreshError = lastRefreshError
        self.provider = provider; self.availability = availability; self.plan = plan
        self.windows = windows; self.updatedAt = updatedAt; self.message = message
    }

    /// Cached readings are runtime data: malformed numbers are dropped on decode so authored configuration survives.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProvider = try values.decode(AIProvider.self, forKey: .provider)
        provider = decodedProvider
        availability = try values.decode(AILimitAvailability.self, forKey: .availability)
        plan = try values.decodeIfPresent(String.self, forKey: .plan)
        windows = try values.decode([AILimitWindow].self, forKey: .windows)
            .prefix(AIUsageDomain.maximumWindows).map { $0.sanitized(for: decodedProvider) }
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt).flatMap { AIUsageDomain.isSupported($0) ? $0 : nil }
        message = try values.decodeIfPresent(String.self, forKey: .message)
        verifiedAccountIdentity = try values.decodeIfPresent(String.self, forKey: .verifiedAccountIdentity)
        requestedAccountIdentity = try values.decodeIfPresent(String.self, forKey: .requestedAccountIdentity)
        failureKind = try values.decodeIfPresent(AILimitFailureKind.self, forKey: .failureKind)
        lastRefreshError = try values.decodeIfPresent(String.self, forKey: .lastRefreshError)
    }

    var isValid: Bool {
        windows.count <= AIUsageDomain.maximumWindows && windows.allSatisfy { $0.isValid(for: provider) }
            && (updatedAt.map(AIUsageDomain.isSupported) ?? true)
    }
}

struct AILimitsSnapshot: Codable, Hashable {
    var fetchedAt: Date
    var readings: [AIProviderLimitReading]
    var sourceScope: String?

    private enum CodingKeys: String, CodingKey { case fetchedAt, readings, sourceScope }

    init(fetchedAt: Date, readings: [AIProviderLimitReading], sourceScope: String? = nil) {
        self.fetchedAt = fetchedAt; self.readings = readings; self.sourceScope = sourceScope
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let fetched = try values.decode(Date.self, forKey: .fetchedAt)
        fetchedAt = AIUsageDomain.isSupported(fetched) ? fetched : .distantPast
        readings = Array(try values.decode([AIProviderLimitReading].self, forKey: .readings).prefix(AIProvider.allCases.count * 4))
        sourceScope = try values.decodeIfPresent(String.self, forKey: .sourceScope)
    }

    var isValid: Bool {
        AIUsageDomain.isSupported(fetchedAt) && readings.count <= AIProvider.allCases.count * 4 && readings.allSatisfy(\.isValid)
    }

    func reading(for provider: AIProvider) -> AIProviderLimitReading? {
        readings.first { $0.provider == provider }
    }
}

enum AIActivityRange: String, Codable, CaseIterable, Identifiable {
    case today
    case sevenDays
    case thirtyDays
    case monthToDate

    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .sevenDays: "L7"
        case .thirtyDays: "L30"
        case .monthToDate: "MTD"
        }
    }

    func interval(endingAt now: Date, calendar: Calendar) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        let start: Date
        switch self {
        case .today: start = today
        case .sevenDays: start = calendar.date(byAdding: .day, value: -6, to: today) ?? today.addingTimeInterval(-6 * 86_400)
        case .thirtyDays: start = calendar.date(byAdding: .day, value: -29, to: today) ?? today.addingTimeInterval(-29 * 86_400)
        case .monthToDate: start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? today
        }
        return DateInterval(start: start, end: now)
    }

    func chartInterval(endingAt now: Date, calendar: Calendar) -> DateInterval {
        if self == .today {
            let today = calendar.startOfDay(for: now)
            return DateInterval(start: calendar.date(byAdding: .day, value: -6, to: today) ?? today.addingTimeInterval(-6 * 86_400), end: now)
        }
        return interval(endingAt: now, calendar: calendar)
    }
}

enum AIActivityChartStyle: String, Codable, CaseIterable, Identifiable {
    case sparkline
    case bars
    case totals
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AIActivityDailyPoint: Codable, Hashable, Identifiable {
    var date: Date
    var sessions: Int
    var toolCalls: Int
    var totalTokens: Int64
    var cachedInputTokens: Int64
    var inputTokens: Int64
    var outputTokens: Int64
    var requests: Int
    var reportedCostUSD: Decimal?
    var id: Date { date }

    var isValid: Bool {
        AIUsageDomain.isSupported(date)
            && [sessions, toolCalls, requests].allSatisfy({ (0...AIUsageDomain.maximumCount).contains($0) })
            && [totalTokens, cachedInputTokens, inputTokens, outputTokens].allSatisfy({ (0...AIUsageDomain.maximumTokens).contains($0) })
            && (reportedCostUSD.map { $0 >= 0 && $0 <= AIUsageDomain.maximumCostUSD } ?? true)
    }

    /// Totals keep their meaning but cannot carry negative or absurd components.
    func clamped() -> AIActivityDailyPoint {
        func count(_ value: Int) -> Int { min(max(value, 0), AIUsageDomain.maximumCount) }
        func tokens(_ value: Int64) -> Int64 { min(max(value, 0), AIUsageDomain.maximumTokens) }
        let cost = reportedCostUSD.flatMap { $0 >= 0 && $0 <= AIUsageDomain.maximumCostUSD ? $0 : nil }
        return AIActivityDailyPoint(date: AIUsageDomain.isSupported(date) ? date : .distantPast,
                                    sessions: count(sessions), toolCalls: count(toolCalls),
                                    totalTokens: tokens(totalTokens), cachedInputTokens: tokens(cachedInputTokens),
                                    inputTokens: tokens(inputTokens), outputTokens: tokens(outputTokens),
                                    requests: count(requests), reportedCostUSD: cost)
    }
}

struct AIActivitySnapshot: Codable, Hashable {
    var provider: AIProvider
    var range: AIActivityRange
    var fetchedAt: Date
    var sourceDescription: String
    var available: Bool
    var estimated: Bool
    var partial: Bool
    var message: String?
    var points: [AIActivityDailyPoint]
    var totals: AIActivityDailyPoint
    /// 1 counted session-days and duplicate log records; 2 counts distinct sessions in the range and de-duplicates records.
    var semanticVersion: Int
    var sourceScope: String?

    static let currentSemanticVersion = 2
    var hasCurrentSemantics: Bool { semanticVersion >= Self.currentSemanticVersion }

    private enum CodingKeys: String, CodingKey {
        case provider, range, fetchedAt, sourceDescription, available, estimated, partial, message, points, totals, semanticVersion, sourceScope
    }

    init(provider: AIProvider, range: AIActivityRange, fetchedAt: Date, sourceDescription: String, available: Bool,
         estimated: Bool, partial: Bool, message: String? = nil, points: [AIActivityDailyPoint], totals: AIActivityDailyPoint,
         semanticVersion: Int = AIActivitySnapshot.currentSemanticVersion, sourceScope: String? = nil) {
        self.sourceScope = sourceScope
        self.semanticVersion = semanticVersion
        self.provider = provider; self.range = range; self.fetchedAt = fetchedAt
        self.sourceDescription = sourceDescription; self.available = available; self.estimated = estimated
        self.partial = partial; self.message = message; self.points = points; self.totals = totals
    }

    /// Cached activity is runtime data: invalid points are dropped and totals clamped so authored configuration survives.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decode(AIProvider.self, forKey: .provider)
        range = try values.decode(AIActivityRange.self, forKey: .range)
        let fetched = try values.decode(Date.self, forKey: .fetchedAt)
        fetchedAt = AIUsageDomain.isSupported(fetched) ? fetched : .distantPast
        sourceDescription = try values.decode(String.self, forKey: .sourceDescription)
        available = try values.decode(Bool.self, forKey: .available)
        estimated = try values.decode(Bool.self, forKey: .estimated)
        partial = try values.decode(Bool.self, forKey: .partial)
        message = try values.decodeIfPresent(String.self, forKey: .message)
        points = try values.decode([AIActivityDailyPoint].self, forKey: .points)
            .prefix(AIUsageDomain.maximumPoints).filter(\.isValid)
        totals = try values.decode(AIActivityDailyPoint.self, forKey: .totals).clamped()
        semanticVersion = try values.decodeIfPresent(Int.self, forKey: .semanticVersion) ?? 1
        sourceScope = try values.decodeIfPresent(String.self, forKey: .sourceScope)
    }

    var isValid: Bool {
        AIUsageDomain.isSupported(fetchedAt) && points.count <= AIUsageDomain.maximumPoints
            && points.allSatisfy(\.isValid) && totals.isValid
    }

    var tokensText: String {
        if estimated { return "Est. \(totals.totalTokens.formatted()) tokens" }
        if partial { return "≥\(totals.totalTokens.formatted()) tokens" }
        return "\(totals.totalTokens.formatted()) tokens"
    }
}

enum AIUsageError: LocalizedError, Equatable {
    case codexCLIUnavailable
    case codexAppServerTimedOut
    case codexAuthenticationUnavailable
    case codexResponseInvalid
    case claudeLimitResponseInvalid

    var errorDescription: String? {
        switch self {
        case .codexCLIUnavailable: "Codex app-server was not found. Install Codex CLI or the Codex app, then refresh."
        case .codexAppServerTimedOut: "Codex app-server did not answer its read-only limits request in time."
        case .codexAuthenticationUnavailable: "Codex could not read account limits. Sign in with your ChatGPT account in Codex and try again."
        case .codexResponseInvalid: "Codex returned a rate-limit response MyDock could not parse."
        case .claudeLimitResponseInvalid: "Claude Code's saved status-line limits could not be read."
        }
    }
}

enum CodexRateLimitParser {
    static func reading(from data: Data, now: Date = .now) throws -> AIProviderLimitReading {
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIUsageError.codexResponseInvalid }
        if response["error"] != nil { throw AIUsageError.codexAuthenticationUnavailable }
        let source = (response["result"] as? [String: Any]) ?? response
        let fallback = source["rateLimits"] as? [String: Any]
        var buckets = source["rateLimitsByLimitId"] as? [String: [String: Any]] ?? [:]
        if buckets.isEmpty, let fallback {
            buckets["codex"] = fallback
        }
        let windows = buckets.sorted { $0.key < $1.key }.flatMap { id, bucket in
            let name = (bucket["limitName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (id == "codex" ? "Included usage" : id)
            var values: [AILimitWindow] = []
            if let primary = bucket["primary"] as? [String: Any] {
                values.append(window(name: "\(name) · \(windowTitle(primary["windowDurationMins"] as? Int))", raw: primary))
            }
            if let secondary = bucket["secondary"] as? [String: Any] {
                values.append(window(name: "\(name) · \(windowTitle(secondary["windowDurationMins"] as? Int))", raw: secondary))
            }
            return values
        }
        let plan = fallback?["planType"] as? String
        let hasPercentages = windows.contains { $0.usedPercent != nil }
        return AIProviderLimitReading(provider: .codex,
                                      availability: hasPercentages ? .available : .unavailable,
                                      plan: plan,
                                      windows: windows,
                                      updatedAt: now,
                                      message: hasPercentages ? nil : "This Codex account did not report percentage-based limits.")
    }

    private static func window(name: String, raw: [String: Any]) -> AILimitWindow {
        let used = (raw["usedPercent"] as? NSNumber).flatMap { value -> Int? in
            guard CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite else { return nil }
            return Int(min(100, max(0, value.doubleValue)).rounded())
        }
        let reset = (raw["resetsAt"] as? NSNumber).flatMap { number -> Date? in
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                  abs(number.doubleValue) < 4_102_444_800 else { return nil }
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        let duration = (raw["windowDurationMins"] as? Int).flatMap { (1...AIUsageDomain.maximumDurationMinutes).contains($0) ? $0 : nil }
        return AILimitWindow(name: name, usedPercent: used, resetsAt: reset, durationMinutes: duration)
    }

    private static func windowTitle(_ minutes: Int?) -> String {
        switch minutes {
        case 300: "5 hours"
        case 10_080: "Weekly"
        case let value? where value >= 1_440: "\(value / 1_440) days"
        case let value? where value > 0: "\(value) min"
        default: "Limit"
        }
    }
}

enum CodexAppServerLimitReader {
    static func read(now: Date = .now, environment: [String: String]? = nil) throws -> AIProviderLimitReading {
        try AppRuntimeEnvironment.requireCredentials()
        guard let executable = executableURL() else { throw AIUsageError.codexCLIUnavailable }
        let response = try CodexAccountRPC.request(executable: executable, method: "account/rateLimits/read", environment: environment)
        return try CodexRateLimitParser.reading(from: response, now: now)
    }

    private static func executableURL() -> URL? { AIAccountService.executable(for: .codex) }
}

protocol AILimitProviderAdapter {
    var provider: AIProvider { get }
    func read(now: Date) async throws -> AIProviderLimitReading
}

struct CodexLimitAdapter: AILimitProviderAdapter {
    let provider: AIProvider = .codex
    var environment: [String: String]? = nil

    func read(now: Date) async throws -> AIProviderLimitReading {
        try AppRuntimeEnvironment.requireCredentials()
        return try CodexAppServerLimitReader.read(now: now, environment: environment)
    }
}

struct UnavailableLimitAdapter: AILimitProviderAdapter {
    let provider: AIProvider

    func read(now: Date) async throws -> AIProviderLimitReading {
        let message: String
        switch provider {
        case .grok, .cursor, .geminiCLI, .antigravity:
            message = "No supported personal allowance reader is available in this build."
        case .claude:
            message = "No Claude Code status-line snapshot has been received yet."
        case .copilot:
            message = "Add personal GitHub credentials and a monthly AI-credit allowance to use Copilot limits."
        case .codex:
            message = "Codex limits require the local app-server."
        }
        return AIProviderLimitReading(provider: provider, availability: .unavailable,
                                      plan: nil, windows: [], updatedAt: nil, message: message)
    }
}

enum ClaudeStatusLineLimitParser {
    static func reading(from data: Data, now: Date = .now, maximumAge: TimeInterval = 30 * 60) throws -> AIProviderLimitReading {
        guard data.count <= 64_000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedNumber = root["updated_at"] as? NSNumber,
              CFGetTypeID(updatedNumber) != CFBooleanGetTypeID(),
              updatedNumber.doubleValue.isFinite, updatedNumber.doubleValue > 0,
              updatedNumber.doubleValue <= now.timeIntervalSince1970 + 60,
              let limits = root["rate_limits"] as? [String: Any] else {
            throw AIUsageError.claudeLimitResponseInvalid
        }
        let timestamp = updatedNumber.doubleValue
        let updatedAt = Date(timeIntervalSince1970: timestamp)
        guard now.timeIntervalSince(updatedAt) <= maximumAge else {
            return AIProviderLimitReading(provider: .claude, availability: .unavailable, plan: nil,
                                          windows: [], updatedAt: updatedAt,
                                          message: "Claude Code status-line data is stale. Use Claude Code to refresh it.")
        }
        let definitions: [(String, String, Int?)] = [
            ("five_hour", "5 hours", 300),
            ("seven_day", "7 days", 10_080),
            ("spend_limit", "Spend limit", nil)
        ]
        let windows = definitions.compactMap { key, title, duration -> AILimitWindow? in
            guard let value = limits[key] as? [String: Any] else { return nil }
            let percent = (value["used_percentage"] as? NSNumber).flatMap { number -> Int? in
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                      number.doubleValue >= 0 else { return nil }
                return Int(min(Double(AIUsageDomain.maximumPercent(for: .claude)), number.doubleValue).rounded())
            }
            let reset = (value["resets_at"] as? NSNumber).flatMap { number -> Date? in
                guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite,
                      number.doubleValue > 0, number.doubleValue < 4_102_444_800 else { return nil }
                return Date(timeIntervalSince1970: number.doubleValue)
            }
            return AILimitWindow(name: title, usedPercent: percent, resetsAt: reset, durationMinutes: duration)
        }
        let available = windows.contains { $0.usedPercent != nil }
        return AIProviderLimitReading(provider: .claude,
                                      availability: available ? .available : .unavailable,
                                      plan: nil, windows: windows, updatedAt: updatedAt,
                                      message: available ? nil : "Claude Code did not report percentage-based limits in its latest status line.")
    }
}

struct ClaudeStatusLineLimitAdapter: AILimitProviderAdapter {
    let provider: AIProvider = .claude
    var homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    /// Fixtures inject an environment; nil means the process environment for the real account home only.
    var environment: [String: String]?

    func read(now: Date) async throws -> AIProviderLimitReading {
        let usesAccountHome = homeDirectory == FileManager.default.homeDirectoryForCurrentUser
        // Isolated runs must not read the real account's status-line file; fixtures pass an explicit home.
        if usesAccountHome { try AppRuntimeEnvironment.requireCredentials() }
        let directory = AIAccountService.claudeDirectory(home: homeDirectory,
                                                         environment: environment ?? (usesAccountHome ? ProcessInfo.processInfo.environment : [:]))
        let url = directory.appendingPathComponent("mydock-rate-limits.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            return AIProviderLimitReading(provider: .claude, availability: .setupRequired, plan: nil,
                                          windows: [], updatedAt: nil,
                                          message: "No Claude Code status-line snapshot has been received yet.")
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 64_000 else {
            throw AIUsageError.claudeLimitResponseInvalid
        }
        return try ClaudeStatusLineLimitParser.reading(from: Data(contentsOf: url), now: now)
    }
}

enum AILimitsCollector {
    static func collect(providers: [AIProvider], now: Date = .now,
                        copilotMonthlyCreditAllowance: Int? = nil,
                        adapters: [any AILimitProviderAdapter]? = nil,
                        homeDirectory: URL? = nil, environment: [String: String]? = nil) async -> AILimitsSnapshot {
        var environment = environment ?? (homeDirectory == nil ? ProcessInfo.processInfo.environment : [:])
        if let homeDirectory {
            if environment["CODEX_HOME"] == nil { environment["CODEX_HOME"] = homeDirectory.appendingPathComponent(".codex").path }
            if environment["CLAUDE_CONFIG_DIR"] == nil { environment["CLAUDE_CONFIG_DIR"] = homeDirectory.appendingPathComponent(".claude").path }
        }
        let sourceScope = AIUsageSourceScope.limits(providers: providers, homeDirectory: homeDirectory, environment: environment, now: now)
        let adapters = adapters ?? defaultAdapters(copilotMonthlyCreditAllowance: copilotMonthlyCreditAllowance, homeDirectory: homeDirectory, environment: environment)
        let readers = Dictionary(adapters.map { ($0.provider, $0) }, uniquingKeysWith: { first, _ in first })
        var readings: [AIProviderLimitReading] = []
        for provider in providers {
            guard !Task.isCancelled else { break }
            let reader = readers[provider] ?? UnavailableLimitAdapter(provider: provider)
            do {
                readings.append(try await reader.read(now: now))
            } catch let failure as AILimitReadFailure {
                readings.append(.init(provider: provider,
                    availability: failure.kind == .authentication ? .setupRequired : (failure.kind == .unavailable ? .unavailable : .error),
                    windows: [], message: DataSourceProvenance.sanitized(failure.message), requestedAccountIdentity: failure.requestedAccountIdentity,
                    failureKind: failure.kind))
            } catch {
                let needsSetup: Bool
                if let usageError = error as? AIUsageError {
                    needsSetup = usageError == .codexCLIUnavailable || usageError == .codexAuthenticationUnavailable
                } else {
                    needsSetup = false
                }
                readings.append(AIProviderLimitReading(provider: provider,
                                                       availability: needsSetup ? .setupRequired : .error,
                                                       plan: nil, windows: [], updatedAt: nil,
                                                       message: error.localizedDescription))
            }
        }
        return AILimitsSnapshot(fetchedAt: now, readings: readings, sourceScope: sourceScope)
    }

    private static func defaultAdapters(copilotMonthlyCreditAllowance: Int?, homeDirectory: URL?, environment: [String: String]) -> [any AILimitProviderAdapter] {
        AIProvider.allCases.map { provider in
            switch provider {
            case .codex: CodexLimitAdapter(environment: environment) as any AILimitProviderAdapter
            case .claude: ClaudeStatusLineLimitAdapter(homeDirectory: homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser, environment: environment) as any AILimitProviderAdapter
            case .copilot: GitHubCopilotLimitAdapter(monthlyAllowance: copilotMonthlyCreditAllowance) as any AILimitProviderAdapter
            default: UnavailableLimitAdapter(provider: provider) as any AILimitProviderAdapter
            }
        }
    }
}

enum AIActivityReader {
    private struct SessionActivity: Hashable {
        var id: String
        var day: Date
    }

    /// Identity bookkeeping shared by every file in one read, so copied or resumed logs are not counted twice.
    private struct DedupeState {
        struct ClaudeUsage { var day: Date; var input: Int64; var cached: Int64; var output: Int64 }
        var claudeMessages: [String: ClaudeUsage] = [:]
        var claudeToolUses = Set<String>()
        var unidentifiedClaudeRows = Set<String>()
        var codexPoints = Set<String>()
        /// Set when identity was missing and a duplicate could not be ruled out.
        var uncertain = false
    }

    private struct MutablePoint {
        var sessions = 0
        var toolCalls = 0
        var totalTokens: Int64 = 0
        var cachedInputTokens: Int64 = 0
        var inputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var requests = 0
        var reportedCostUSD: Decimal?
    }

    private final class JSONLDataReader {
        private let handle: FileHandle
        private var buffer = Data()
        private var reachedEOF = false
        private let maximumLineSize = 2_000_000
        private let deadline = Date.now.addingTimeInterval(10)
        private var bytesRead = 0

        init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
        deinit { try? handle.close() }

        func nextLine() throws -> Data? {
            while true {
                try Task.checkCancellation()
                guard Date.now < deadline, bytesRead <= 32_000_000 else { throw CocoaError(.fileReadTooLarge) }
                if let newline = buffer.firstIndex(of: 0x0A) {
                    let line = buffer.subdata(in: 0..<newline)
                    buffer.removeSubrange(0...newline)
                    return line
                }
                if buffer.count > maximumLineSize { throw CocoaError(.fileReadTooLarge) }
                if reachedEOF {
                    guard !buffer.isEmpty else { return nil }
                    defer { buffer.removeAll(keepingCapacity: false) }
                    return buffer
                }
                let next = try handle.read(upToCount: 64 * 1024) ?? Data()
                if next.isEmpty { reachedEOF = true }
                else { buffer.append(next); bytesRead += next.count }
            }
        }
    }

    static func read(provider: AIProvider, range: AIActivityRange, now: Date = .now, timeZone: TimeZone = .current,
                     homeDirectory: URL? = nil, environment: [String: String]? = nil) -> AIActivitySnapshot {
        let environment = environment ?? (homeDirectory == nil ? ProcessInfo.processInfo.environment : [:])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let interval = range.interval(endingAt: now, calendar: calendar)
        let chartInterval = range.chartInterval(endingAt: now, calendar: calendar)
        guard provider == .codex || provider == .claude || provider == .grok else {
            return unavailable(provider: provider, range: range, now: now, message: "This provider does not expose a supported local activity source.")
        }
        // Isolated runs never scan the real account's session logs; fixtures pass an explicit home.
        guard homeDirectory != nil || AppRuntimeEnvironment.allowsCredentials else {
            return unavailable(provider: provider, range: range, now: now, message: "Local activity is disabled in isolated validation.")
        }
        guard let source = AIUsageSourceScope.directory(provider: provider, homeDirectory: homeDirectory, environment: environment) else {
            return unavailable(provider: provider, range: range, now: now, message: "This provider does not expose a supported local activity source.")
        }
        let sourceScope = AIUsageSourceScope.activity(provider: provider, range: range, homeDirectory: homeDirectory,
                                                      environment: environment, timeZone: timeZone, now: now)
        var daily: [Date: MutablePoint] = [:]
        var sessionsByIDAndDay: Set<SessionActivity> = []
        var dedupe = DedupeState()
        let deadline = Date.now.addingTimeInterval(10)
        var budgetExceeded = false
        var processedFiles = 0
        var skippedFiles = 0
        let lowerBound = chartInterval.start
        let fileScan = dataFiles(in: source, modifiedAfter: lowerBound.addingTimeInterval(-30 * 86_400), maximumFiles: 10_000)
        let files = fileScan.files
        for file in files {
            guard !Task.isCancelled, Date.now < deadline else { budgetExceeded = true; break }
            do {
                switch provider {
                case .codex: try parseCodex(file: file, calendar: calendar, interval: chartInterval, daily: &daily, sessions: &sessionsByIDAndDay, dedupe: &dedupe)
                case .claude: try parseClaude(file: file, calendar: calendar, interval: chartInterval, daily: &daily, sessions: &sessionsByIDAndDay, dedupe: &dedupe)
                case .grok: try parseGrok(file: file, calendar: calendar, interval: chartInterval, daily: &daily, sessions: &sessionsByIDAndDay)
                default: break
                }
                processedFiles += 1
            } catch {
                skippedFiles += 1
            }
        }
        for session in sessionsByIDAndDay { daily[session.day, default: MutablePoint()].sessions += 1 }
        let days = dayStarts(from: chartInterval.start, through: now, calendar: calendar)
        let points = days.map { day in
            let value = daily[day] ?? MutablePoint()
            return AIActivityDailyPoint(date: day, sessions: value.sessions, toolCalls: value.toolCalls,
                                        totalTokens: value.totalTokens, cachedInputTokens: value.cachedInputTokens,
                                        inputTokens: value.inputTokens, outputTokens: value.outputTokens,
                                        requests: value.requests, reportedCostUSD: value.reportedCostUSD)
        }
        let included = points.filter { interval.contains($0.date) || calendar.isDate($0.date, inSameDayAs: interval.start) }
        var totals = included.reduce(into: MutablePoint()) { total, point in
            total.sessions += point.sessions
            total.toolCalls += point.toolCalls
            total.totalTokens += point.totalTokens
            total.cachedInputTokens += point.cachedInputTokens
            total.inputTokens += point.inputTokens
            total.outputTokens += point.outputTokens
            total.requests += point.requests
            if let cost = point.reportedCostUSD { total.reportedCostUSD = (total.reportedCostUSD ?? .zero) + cost }
        }
        // Range total: distinct session IDs across the included days; per-day points keep their own daily counts.
        let includedDays = Set(included.map(\.date))
        totals.sessions = Set(sessionsByIDAndDay.filter { includedDays.contains($0.day) }.map(\.id)).count
        let available = processedFiles > 0 && (totals.sessions > 0 || totals.totalTokens > 0 || totals.requests > 0)
        let estimated = provider == .grok
        let partial = estimated || skippedFiles > 0 || fileScan.hitLimit || budgetExceeded || dedupe.uncertain
        let sourceDescription: String
        switch provider {
        case .codex: sourceDescription = "Local Codex session event logs · total token deltas include cached input. This excludes ChatGPT conversations outside Codex."
        case .claude: sourceDescription = "Local Claude Code session usage records · API-key and enterprise billing may be reported separately by Claude."
        case .grok: sourceDescription = "Estimated from local Grok session summaries, grouped by file update day. An updated older session moves its estimate to that day."
        default: sourceDescription = ""
        }
        return AIActivitySnapshot(provider: provider,
                                  range: range,
                                  fetchedAt: now,
                                  sourceDescription: sourceDescription,
                                  available: available,
                                  estimated: estimated,
                                  partial: partial,
                                  message: available ? (skippedFiles > 0 || fileScan.hitLimit || budgetExceeded ? "Some local records could not be read; totals are partial." : (dedupe.uncertain ? "Some records had no identity to rule out duplicates; totals may be overstated." : (estimated ? "Local estimate; not an exact provider billing total." : nil))) : (processedFiles == 0 ? "No supported local activity records were found." : "No provider usage counters were present in these records."),
                                  points: points,
                                  totals: AIActivityDailyPoint(date: calendar.startOfDay(for: now), sessions: totals.sessions,
                                                               toolCalls: totals.toolCalls, totalTokens: totals.totalTokens,
                                                               cachedInputTokens: totals.cachedInputTokens, inputTokens: totals.inputTokens,
                                                               outputTokens: totals.outputTokens, requests: totals.requests,
                                                               reportedCostUSD: totals.reportedCostUSD),
                                  sourceScope: sourceScope)
    }

    private static func unavailable(provider: AIProvider, range: AIActivityRange, now: Date, message: String) -> AIActivitySnapshot {
        AIActivitySnapshot(provider: provider, range: range, fetchedAt: now, sourceDescription: provider.setupInstructions,
                           available: false, estimated: false, partial: false, message: message, points: [],
                           totals: AIActivityDailyPoint(date: now, sessions: 0, toolCalls: 0, totalTokens: 0,
                                                       cachedInputTokens: 0, inputTokens: 0, outputTokens: 0,
                                                       requests: 0, reportedCostUSD: nil))
    }

    private static func dataFiles(in directory: URL, modifiedAfter: Date, maximumFiles: Int) -> (files: [URL], hitLimit: Bool) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey],
                                              options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return ([], false) }
        var result: [URL] = []
        let deadline = Date.now.addingTimeInterval(5)
        while let url = enumerator.nextObject() as? URL {
            guard !Task.isCancelled, Date.now < deadline else { return (result, true) }
            guard ["jsonl", "json"].contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true,
                  (values.contentModificationDate ?? .distantPast) >= modifiedAfter else {
                if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]), values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if result.count == maximumFiles { return (result, true) }
            result.append(url)
        }
        return (result, false)
    }

    private static func parseCodex(file: URL, calendar: Calendar, interval: DateInterval,
                                   daily: inout [Date: MutablePoint], sessions: inout Set<SessionActivity>,
                                   dedupe: inout DedupeState) throws {
        let reader = try JSONLDataReader(url: file)
        let fileID = file.deletingPathExtension().lastPathComponent
        var sessionID = fileID
        var hasSessionIdentity = false
        var previousTotal: Int64 = 0
        var previousInput: Int64 = 0
        var previousCached: Int64 = 0
        var previousOutput: Int64 = 0
        while let lineData = try reader.nextLine() {
            guard let row = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = row["type"] as? String,
                  let payload = row["payload"] as? [String: Any] else { continue }
            if type == "session_meta", let id = (payload["session_id"] as? String) ?? (payload["id"] as? String), !id.isEmpty {
                sessionID = id
                hasSessionIdentity = true
            }
            guard let timestamp = date(row["timestamp"] as? String) else { continue }
            let day = calendar.startOfDay(for: timestamp)
            guard interval.contains(timestamp) || calendar.isDate(timestamp, inSameDayAs: interval.start) else {
                if type == "event_msg", payload["type"] as? String == "token_count",
                   let info = payload["info"] as? [String: Any],
                   let usage = info["total_token_usage"] as? [String: Any],
                   let total = integer(usage["total_tokens"]) {
                    previousTotal = total
                    previousInput = integer(usage["input_tokens"]) ?? previousInput
                    previousCached = integer(usage["cached_input_tokens"]) ?? previousCached
                    previousOutput = integer(usage["output_tokens"]) ?? previousOutput
                }
                continue
            }
            if type == "event_msg", payload["type"] as? String == "token_count",
               let info = payload["info"] as? [String: Any],
               let usage = info["total_token_usage"] as? [String: Any],
               let total = integer(usage["total_tokens"]) {
                let delta = max(0, total - previousTotal)
                let input = integer(usage["input_tokens"]) ?? previousInput
                let cached = integer(usage["cached_input_tokens"]) ?? previousCached
                let output = integer(usage["output_tokens"]) ?? previousOutput
                let inputDelta = max(0, input - previousInput)
                let cachedDelta = max(0, cached - previousCached)
                let outputDelta = max(0, output - previousOutput)
                previousTotal = total
                previousInput = input
                previousCached = cached
                previousOutput = output
                // Cumulative usage identifies a point in a session; a copied or resumed log repeats it.
                if !hasSessionIdentity { dedupe.uncertain = true }
                guard dedupe.codexPoints.insert("\(sessionID)|\(total)|\(input)|\(cached)|\(output)").inserted else { continue }
                daily[day, default: MutablePoint()].totalTokens += delta
                daily[day, default: MutablePoint()].cachedInputTokens += cachedDelta
                daily[day, default: MutablePoint()].inputTokens += inputDelta
                daily[day, default: MutablePoint()].outputTokens += outputDelta
                sessions.insert(SessionActivity(id: sessionID, day: day))
            } else if type == "item_completed", let item = payload["item"] as? [String: Any],
                      let itemType = item["type"] as? String, isToolType(itemType) {
                daily[day, default: MutablePoint()].toolCalls += 1
                sessions.insert(SessionActivity(id: sessionID, day: day))
            }
        }
    }

    private static func parseClaude(file: URL, calendar: Calendar, interval: DateInterval,
                                    daily: inout [Date: MutablePoint], sessions: inout Set<SessionActivity>,
                                    dedupe: inout DedupeState) throws {
        let reader = try JSONLDataReader(url: file)
        let fallbackID = file.deletingPathExtension().lastPathComponent
        while let lineData = try reader.nextLine() {
            guard let row = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  row["type"] as? String == "assistant",
                  let timestamp = date(row["timestamp"] as? String),
                  interval.contains(timestamp) || calendar.isDate(timestamp, inSameDayAs: interval.start),
                  let message = row["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let input: Int64 = integer(usage["input_tokens"]) ?? 0
            let cached: Int64 = (integer(usage["cache_read_input_tokens"]) ?? 0) + (integer(usage["cache_creation_input_tokens"]) ?? 0)
            let output: Int64 = integer(usage["output_tokens"]) ?? 0
            let day = calendar.startOfDay(for: timestamp)
            let sessionID = row["sessionId"] as? String ?? fallbackID
            var isNewMessage = true
            if let messageID = message["id"] as? String, !messageID.isEmpty {
                // The same API message is logged once per content block and again in copied or resumed files.
                let key = messageID + "|" + (row["requestId"] as? String ?? "")
                if let seen = dedupe.claudeMessages[key] {
                    isNewMessage = false
                    // Streaming rows can carry growing counters; add only the increase, on the original day.
                    let more = DedupeState.ClaudeUsage(day: seen.day, input: max(seen.input, input), cached: max(seen.cached, cached),
                                                       output: max(seen.output, output))
                    daily[seen.day, default: MutablePoint()].inputTokens += more.input - seen.input
                    daily[seen.day, default: MutablePoint()].cachedInputTokens += more.cached - seen.cached
                    daily[seen.day, default: MutablePoint()].outputTokens += more.output - seen.output
                    daily[seen.day, default: MutablePoint()].totalTokens += (more.input - seen.input) + (more.cached - seen.cached) + (more.output - seen.output)
                    dedupe.claudeMessages[key] = more
                } else {
                    dedupe.claudeMessages[key] = .init(day: day, input: input, cached: cached, output: output)
                }
            } else {
                // No message identity: count it (never undercount) but flag identical rows as possible duplicates.
                let fingerprint = "\(sessionID)|\(timestamp.timeIntervalSince1970)|\(input)|\(cached)|\(output)"
                if !dedupe.unidentifiedClaudeRows.insert(fingerprint).inserted { dedupe.uncertain = true }
            }
            if isNewMessage {
                daily[day, default: MutablePoint()].totalTokens += input + cached + output
                daily[day, default: MutablePoint()].inputTokens += input
                daily[day, default: MutablePoint()].cachedInputTokens += cached
                daily[day, default: MutablePoint()].outputTokens += output
                daily[day, default: MutablePoint()].requests += 1
            }
            if let blocks = message["content"] as? [[String: Any]] {
                for block in blocks where (block["type"] as? String) == "tool_use" {
                    if let id = block["id"] as? String, !id.isEmpty {
                        if dedupe.claudeToolUses.insert(id).inserted { daily[day, default: MutablePoint()].toolCalls += 1 }
                    } else if isNewMessage {
                        daily[day, default: MutablePoint()].toolCalls += 1
                    }
                }
            }
            sessions.insert(SessionActivity(id: sessionID, day: day))
        }
    }

    private static func parseGrok(file: URL, calendar: Calendar, interval: DateInterval,
                                  daily: inout [Date: MutablePoint], sessions: inout Set<SessionActivity>) throws {
        guard let fileSize = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= 32_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let contents = try Data(contentsOf: file, options: [.mappedIfSafe])
        let objects: [[String: Any]]
        if file.pathExtension.lowercased() == "jsonl" {
            objects = contents.split(separator: 0x0A).compactMap { try? JSONSerialization.jsonObject(with: Data($0)) as? [String: Any] }
        } else if let object = try? JSONSerialization.jsonObject(with: contents) as? [String: Any] {
            objects = [object]
        } else { throw AIUsageError.codexResponseInvalid }
        var savedContext: Int64 = 0
        var preCompaction: Int64 = 0
        var total: Int64 = 0
        for object in objects { grokCounters(object, inUsageScope: false, savedContext: &savedContext, preCompaction: &preCompaction, total: &total) }
        let estimate = savedContext + preCompaction > 0 ? savedContext + preCompaction : total
        guard estimate > 0 else { return }
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? nil
        guard let modified, interval.contains(modified) || calendar.isDate(modified, inSameDayAs: interval.start) else { return }
        let day = calendar.startOfDay(for: modified)
        daily[day, default: MutablePoint()].totalTokens += estimate
        sessions.insert(SessionActivity(id: file.deletingPathExtension().lastPathComponent, day: day))
    }

    private static func grokCounters(_ value: Any, inUsageScope: Bool, savedContext: inout Int64, preCompaction: inout Int64, total: inout Int64, depth: Int = 0) {
        guard depth < 64, !Task.isCancelled, let object = value as? [String: Any] else { return }
        for (key, child) in object {
            let normalized = key.replacingOccurrences(of: "_", with: "").lowercased()
            let entersScope = inUsageScope || ["usage", "stats", "summary", "tokenusage", "usageinfo"].contains(normalized)
            if entersScope, let number = integer(child) {
                switch normalized {
                case "savedcontexttokens", "contexttokens", "contexttokencount": savedContext = max(savedContext, number)
                case "precompactiontokens", "precompactiontotal", "precompactiontokencount": preCompaction = max(preCompaction, number)
                case "totaltokens", "tokencount": total = max(total, number)
                default: break
                }
            }
            if entersScope, child is [String: Any] { grokCounters(child, inUsageScope: true, savedContext: &savedContext, preCompaction: &preCompaction, total: &total, depth: depth + 1) }
            if entersScope, let rows = child as? [[String: Any]] {
                for row in rows { grokCounters(row, inUsageScope: true, savedContext: &savedContext, preCompaction: &preCompaction, total: &total, depth: depth + 1) }
            }
        }
    }

    private static func isToolType(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("tool") || normalized.contains("command_execution") || normalized.contains("commandexecution") || normalized.contains("function_call")
    }

    private static func dayStarts(from start: Date, through end: Date, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        var date = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while date <= last, result.count < 32 {
            result.append(date)
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return result
    }

    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }

    private static func integer(_ value: Any?) -> Int64? {
        let parsed: Int64?
        if let value = value as? String { parsed = Int64(value) }
        else if let value = value as? NSNumber { parsed = value.int64Value }
        else { parsed = nil }
        guard let parsed, (0...1_000_000_000_000).contains(parsed) else { return nil }
        return parsed
    }
}
