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
        case .claude: "Install Claude Code and sign in. Limits require a current Claude Code status-line update or the Claude Desktop account reader; activity is read from local Claude Code session usage records."
        case .grok: "Install Grok CLI and run grok login. Limits are reported by the installed CLI; activity is a local session estimate from ~/.grok/sessions."
        case .cursor: "Sign in to Cursor. Account-wide request and cost history requires Cursor's authenticated usage data; no API key or private endpoint is used by this build."
        case .geminiCLI: "Sign in to Gemini CLI with a supported Google account. API-key and Vertex AI configurations do not expose subscription limits."
        case .copilot: "Install GitHub CLI and run gh auth login with the account that has Copilot. Only provider-reported quotas are shown; unlimited or absent values remain unavailable."
        case .antigravity: "Sign in with agy, enable its status line, reopen the CLI, and run /usage. MyDock does not change CLI settings automatically."
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

struct AILimitWindow: Codable, Hashable, Identifiable {
    var name: String
    var usedPercent: Int?
    var resetsAt: Date?
    var durationMinutes: Int?
    var id: String { name }

    var remainingPercent: Int? {
        guard let usedPercent else { return nil }
        return max(0, min(100, 100 - usedPercent))
    }
}

struct AIProviderLimitReading: Codable, Hashable, Identifiable {
    var provider: AIProvider
    var availability: AILimitAvailability
    var plan: String?
    var windows: [AILimitWindow]
    var updatedAt: Date?
    var message: String?
    var id: AIProvider { provider }
}

struct AILimitsSnapshot: Codable, Hashable {
    var fetchedAt: Date
    var readings: [AIProviderLimitReading]

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

    var errorDescription: String? {
        switch self {
        case .codexCLIUnavailable: "Codex app-server was not found. Install Codex CLI or the Codex app, then refresh."
        case .codexAppServerTimedOut: "Codex app-server did not answer its read-only limits request in time."
        case .codexAuthenticationUnavailable: "Codex could not read account limits. Sign in with your ChatGPT account in Codex and try again."
        case .codexResponseInvalid: "Codex returned a rate-limit response MyDock could not parse."
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
        let used = raw["usedPercent"] as? Int
        let reset = (raw["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let duration = raw["windowDurationMins"] as? Int
        return AILimitWindow(name: name, usedPercent: used.map { max(0, min(100, $0)) }, resetsAt: reset, durationMinutes: duration)
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
    static func read(now: Date = .now) throws -> AIProviderLimitReading {
        guard let executable = executableURL() else { throw AIUsageError.codexCLIUnavailable }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.environment = ProcessInfo.processInfo.environment
        process.environment?["RUST_LOG"] = "off"
        do { try process.run() }
        catch { throw AIUsageError.codexCLIUnavailable }

        let requests: [[String: Any]] = [
            ["jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["clientInfo": ["name": "mydock", "title": "MyDock", "version": "0.1"]]],
            ["jsonrpc": "2.0", "method": "initialized", "params": [:]],
            ["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read", "params": [:]]
        ]
        do {
            for request in requests {
                var line = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
                line.append(0x0A)
                try input.fileHandleForWriting.write(contentsOf: line)
            }
            try input.fileHandleForWriting.close()
        } catch {
            process.terminate()
            throw AIUsageError.codexResponseInvalid
        }

        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 12, execute: timeout)
        let responseData = output.fileHandleForReading.readDataToEndOfFile()
        timeout.cancel()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
        guard responseData.count <= 2_000_000 else { throw AIUsageError.codexResponseInvalid }
        for line in responseData.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  (object["id"] as? Int) == 2 else { continue }
            if object["error"] != nil { throw AIUsageError.codexAuthenticationUnavailable }
            return try CodexRateLimitParser.reading(from: Data(line), now: now)
        }
        if process.terminationReason == .uncaughtSignal { throw AIUsageError.codexAppServerTimedOut }
        throw AIUsageError.codexAuthenticationUnavailable
    }

    private static func executableURL() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex") }
        }
        let home = fileManager.homeDirectoryForCurrentUser
        candidates += ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"].map { URL(fileURLWithPath: $0) }
        candidates += [".local/bin/codex", ".npm-global/bin/codex", "bin/codex"].map { home.appendingPathComponent($0) }
        for appPath in ["/Applications/Codex.app", home.appendingPathComponent("Applications/Codex.app").path] {
            for relative in ["Contents/Resources/codex", "Contents/MacOS/codex"] {
                candidates.append(URL(fileURLWithPath: appPath).appendingPathComponent(relative))
            }
        }
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

protocol AILimitProviderAdapter {
    var provider: AIProvider { get }
    func read(now: Date) throws -> AIProviderLimitReading
}

struct CodexLimitAdapter: AILimitProviderAdapter {
    let provider: AIProvider = .codex

    func read(now: Date) throws -> AIProviderLimitReading {
        try CodexAppServerLimitReader.read(now: now)
    }
}

struct UnavailableLimitAdapter: AILimitProviderAdapter {
    let provider: AIProvider

    func read(now: Date) throws -> AIProviderLimitReading {
        let message: String
        switch provider {
        case .claude, .grok, .antigravity:
            message = "No supported provider-reported allowance update is available in this build."
        case .cursor, .geminiCLI, .copilot:
            message = "No supported personal quota reader is available in this build."
        case .codex:
            message = "Codex limits require the local app-server."
        }
        return AIProviderLimitReading(provider: provider, availability: .unavailable,
                                      plan: nil, windows: [], updatedAt: nil, message: message)
    }
}

enum AILimitsCollector {
    static func collect(providers: [AIProvider], now: Date = .now,
                        adapters: [any AILimitProviderAdapter] = defaultAdapters()) -> AILimitsSnapshot {
        let readers = Dictionary(adapters.map { ($0.provider, $0) }, uniquingKeysWith: { first, _ in first })
        let readings = providers.map { provider -> AIProviderLimitReading in
            let reader = readers[provider] ?? UnavailableLimitAdapter(provider: provider)
            do {
                return try reader.read(now: now)
            } catch {
                let needsSetup: Bool
                if let usageError = error as? AIUsageError {
                    needsSetup = usageError == .codexCLIUnavailable || usageError == .codexAuthenticationUnavailable
                } else {
                    needsSetup = false
                }
                return AIProviderLimitReading(provider: provider,
                                              availability: needsSetup ? .setupRequired : .error,
                                              plan: nil, windows: [], updatedAt: nil,
                                              message: error.localizedDescription)
            }
        }
        return AILimitsSnapshot(fetchedAt: now, readings: readings)
    }

    private static func defaultAdapters() -> [any AILimitProviderAdapter] {
        [CodexLimitAdapter()] + AIProvider.allCases.filter { $0 != .codex }.map(UnavailableLimitAdapter.init(provider:))
    }
}

enum AIActivityReader {
    private struct SessionActivity: Hashable {
        var id: String
        var day: Date
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

        init(url: URL) throws { handle = try FileHandle(forReadingFrom: url) }
        deinit { try? handle.close() }

        func nextLine() throws -> Data? {
            while true {
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
                else { buffer.append(next) }
            }
        }
    }

    static func read(provider: AIProvider, range: AIActivityRange, now: Date = .now, timeZone: TimeZone = .current,
                     homeDirectory: URL? = nil) -> AIActivitySnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let interval = range.interval(endingAt: now, calendar: calendar)
        let chartInterval = range.chartInterval(endingAt: now, calendar: calendar)
        guard provider == .codex || provider == .claude || provider == .grok else {
            return unavailable(provider: provider, range: range, now: now, message: "This provider does not expose a supported local activity source.")
        }
        let root = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        let source: URL
        switch provider {
        case .codex:
            let configured = homeDirectory == nil ? ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) } : nil
            source = (configured ?? root.appendingPathComponent(".codex", isDirectory: true)).appendingPathComponent("sessions", isDirectory: true)
        case .claude:
            source = root.appendingPathComponent(".claude/projects", isDirectory: true)
        case .grok:
            source = root.appendingPathComponent(".grok/sessions", isDirectory: true)
        case .cursor, .geminiCLI, .copilot, .antigravity:
            return unavailable(provider: provider, range: range, now: now, message: "This provider does not expose a supported local activity source.")
        }
        var daily: [Date: MutablePoint] = [:]
        var sessionsByIDAndDay: Set<SessionActivity> = []
        var processedFiles = 0
        var skippedFiles = 0
        let lowerBound = chartInterval.start
        let fileScan = dataFiles(in: source, modifiedAfter: lowerBound.addingTimeInterval(-30 * 86_400), maximumFiles: 10_000)
        let files = fileScan.files
        for file in files {
            do {
                switch provider {
                case .codex: try parseCodex(file: file, calendar: calendar, interval: chartInterval, daily: &daily, sessions: &sessionsByIDAndDay)
                case .claude: try parseClaude(file: file, calendar: calendar, interval: chartInterval, daily: &daily, sessions: &sessionsByIDAndDay)
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
        let totals = included.reduce(into: MutablePoint()) { total, point in
            total.sessions += point.sessions
            total.toolCalls += point.toolCalls
            total.totalTokens += point.totalTokens
            total.cachedInputTokens += point.cachedInputTokens
            total.inputTokens += point.inputTokens
            total.outputTokens += point.outputTokens
            total.requests += point.requests
            if let cost = point.reportedCostUSD { total.reportedCostUSD = (total.reportedCostUSD ?? .zero) + cost }
        }
        let available = processedFiles > 0 && (totals.sessions > 0 || totals.totalTokens > 0 || totals.requests > 0)
        let estimated = provider == .grok
        let partial = estimated || skippedFiles > 0 || fileScan.hitLimit
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
                                  message: available ? (skippedFiles > 0 || fileScan.hitLimit ? "Some local records could not be read; totals are partial." : (estimated ? "Local estimate; not an exact provider billing total." : nil)) : (processedFiles == 0 ? "No supported local activity records were found." : "No provider usage counters were present in these records."),
                                  points: points,
                                  totals: AIActivityDailyPoint(date: calendar.startOfDay(for: now), sessions: totals.sessions,
                                                               toolCalls: totals.toolCalls, totalTokens: totals.totalTokens,
                                                               cachedInputTokens: totals.cachedInputTokens, inputTokens: totals.inputTokens,
                                                               outputTokens: totals.outputTokens, requests: totals.requests,
                                                               reportedCostUSD: totals.reportedCostUSD))
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
        while let url = enumerator.nextObject() as? URL {
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
                                   daily: inout [Date: MutablePoint], sessions: inout Set<SessionActivity>) throws {
        let reader = try JSONLDataReader(url: file)
        let fileID = file.deletingPathExtension().lastPathComponent
        var sessionID = fileID
        var previousTotal: Int64 = 0
        var previousInput: Int64 = 0
        var previousCached: Int64 = 0
        var previousOutput: Int64 = 0
        while let lineData = try reader.nextLine() {
            guard let row = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = row["type"] as? String,
                  let payload = row["payload"] as? [String: Any] else { continue }
            if type == "session_meta", let id = payload["session_id"] as? String { sessionID = id }
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
                                    daily: inout [Date: MutablePoint], sessions: inout Set<SessionActivity>) throws {
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
            daily[day, default: MutablePoint()].totalTokens += input + cached + output
            daily[day, default: MutablePoint()].inputTokens += input
            daily[day, default: MutablePoint()].cachedInputTokens += cached
            daily[day, default: MutablePoint()].outputTokens += output
            daily[day, default: MutablePoint()].requests += 1
            if let blocks = message["content"] as? [[String: Any]] {
                daily[day, default: MutablePoint()].toolCalls += blocks.reduce(0) { $0 + (($1["type"] as? String) == "tool_use" ? 1 : 0) }
            }
            sessions.insert(SessionActivity(id: row["sessionId"] as? String ?? fallbackID, day: day))
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

    private static func grokCounters(_ value: Any, inUsageScope: Bool, savedContext: inout Int64, preCompaction: inout Int64, total: inout Int64) {
        guard let object = value as? [String: Any] else { return }
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
            if entersScope, child is [String: Any] { grokCounters(child, inUsageScope: true, savedContext: &savedContext, preCompaction: &preCompaction, total: &total) }
            if entersScope, let rows = child as? [[String: Any]] {
                for row in rows { grokCounters(row, inUsageScope: true, savedContext: &savedContext, preCompaction: &preCompaction, total: &total) }
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
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) }
        return nil
    }
}
