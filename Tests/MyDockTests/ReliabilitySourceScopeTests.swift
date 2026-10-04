import Foundation
import Testing
@testable import MyDock

struct ReliabilitySourceScopeTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 1_791_115_200) // A fixed fixture instant, not the host clock.

    @Test func configuredRootsAndCanonicalAliasesGiveHonestActivityAndLimitsScopes() {
        let home = URL(fileURLWithPath: "/MyDockFixtureHome")
        for provider in [AIProvider.codex, .claude] {
            let variable = provider == .codex ? "CODEX_HOME" : "CLAUDE_CONFIG_DIR"
            let a = [variable: "/MyDockFixtures/RootA"]
            let b = [variable: "/MyDockFixtures/RootB"]
            let alias = [variable: "/MyDockFixtures/Unused/../RootA"]
            let first = AIUsageSourceScope.activity(provider: provider, range: .sevenDays, homeDirectory: home, environment: a, timeZone: utc, now: now)
            #expect(first == AIUsageSourceScope.activity(provider: provider, range: .sevenDays, homeDirectory: home, environment: alias, timeZone: utc, now: now))
            #expect(first != AIUsageSourceScope.activity(provider: provider, range: .sevenDays, homeDirectory: home, environment: b, timeZone: utc, now: now))
            #expect(!first.contains("MyDockFixtures"))
            #expect(AIUsageSourceScope.limits(providers: [provider], homeDirectory: home, environment: a, now: now) !=
                    AIUsageSourceScope.limits(providers: [provider], homeDirectory: home, environment: b, now: now))
        }
    }

    @Test func projectionCannotAttributeOneRootsReadingsToAnother() {
        let home = URL(fileURLWithPath: "/MyDockFixtureHome")
        var configuration = WidgetConfiguration()
        configuration.aiActivityProvider = .claude; configuration.aiActivityRange = .sevenDays
        configuration.aiLimitsVisibleProviders = [.claude]
        let rootA = ["CLAUDE_CONFIG_DIR": "/MyDockFixtures/RootA"]
        let rootB = ["CLAUDE_CONFIG_DIR": "/MyDockFixtures/RootB"]
        let activityA = AIUsageSourceScope.activity(provider: .claude, range: .sevenDays, homeDirectory: home, environment: rootA, timeZone: utc, now: now)
        let activityB = AIUsageSourceScope.activity(provider: .claude, range: .sevenDays, homeDirectory: home, environment: rootB, timeZone: utc, now: now)
        let limitsA = AIUsageSourceScope.limits(providers: [.claude], homeDirectory: home, environment: rootA, now: now)
        let limitsB = AIUsageSourceScope.limits(providers: [.claude], homeDirectory: home, environment: rootB, now: now)
        configuration.aiActivitySnapshot = .init(provider: .claude, range: .sevenDays, fetchedAt: now, sourceDescription: "Fixture",
            available: true, estimated: false, partial: false, points: [],
            totals: .init(date: now, sessions: 1, toolCalls: 0, totalTokens: 1, cachedInputTokens: 0, inputTokens: 0,
                          outputTokens: 0, requests: 0, reportedCostUSD: nil), sourceScope: activityA)
        configuration.aiLimitsSnapshot = .init(fetchedAt: now, readings: [], sourceScope: limitsA)
        let readings = configuration.runtimeReadings
        configuration.resolveRuntimeReadings(readings, activityScope: activityA, limitsScope: limitsA)
        #expect(configuration.aiActivitySnapshot?.fetchedAt == now && configuration.aiLimitsSnapshot?.fetchedAt == now)
        configuration.resolveRuntimeReadings(readings, activityScope: activityB, limitsScope: limitsB)
        #expect(configuration.aiActivitySnapshot == nil && configuration.aiLimitsSnapshot == nil)
    }

    @Test func periodTimezoneAndSemanticBoundariesRejectWrongIntervalWithoutUnnecessaryMTDInvalidation() throws {
        let parser = ISO8601DateFormatter()
        let before = try #require(parser.date(from: "2026-10-04T23:59:59Z"))
        let after = before.addingTimeInterval(2)
        for range in [AIActivityRange.today, .sevenDays, .thirtyDays] {
            #expect(AIUsageSourceScope.activity(provider: .codex, range: range, timeZone: utc, now: before) !=
                    AIUsageSourceScope.activity(provider: .codex, range: range, timeZone: utc, now: after))
        }
        #expect(AIUsageSourceScope.activity(provider: .codex, range: .monthToDate, timeZone: utc, now: before) ==
                AIUsageSourceScope.activity(provider: .codex, range: .monthToDate, timeZone: utc, now: after))
        let monthEnd = try #require(parser.date(from: "2026-10-31T23:59:59Z"))
        let nextMonth = monthEnd.addingTimeInterval(2)
        #expect(AIUsageSourceScope.activity(provider: .codex, range: .monthToDate, timeZone: utc, now: monthEnd) !=
                AIUsageSourceScope.activity(provider: .codex, range: .monthToDate, timeZone: utc, now: nextMonth))
        #expect(AIUsageSourceScope.limits(providers: [.copilot], now: monthEnd) != AIUsageSourceScope.limits(providers: [.copilot], now: nextMonth))
        #expect(AIUsageSourceScope.limits(providers: [.claude], now: monthEnd) == AIUsageSourceScope.limits(providers: [.claude], now: nextMonth))
        #expect(AIUsageSourceScope.activity(provider: .codex, range: .today, timeZone: utc, now: before) !=
                AIUsageSourceScope.activity(provider: .codex, range: .today, timeZone: TimeZone(secondsFromGMT: 3_600)!, now: before))
        #expect(AIUsageSourceScope.activity(provider: .codex, range: .today, timeZone: utc, now: before, semanticVersion: 1) !=
                AIUsageSourceScope.activity(provider: .codex, range: .today, timeZone: utc, now: before))
    }

    @Test func unattributedLegacyLimitsDecodeButDoNotBecomeCurrentRootReadings() throws {
        var configuration = WidgetConfiguration()
        configuration.noteText = "Preserved authored content"
        configuration.aiLimitsSnapshot = .init(fetchedAt: now, readings: [])
        let legacy = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(legacy.aiLimitsSnapshot?.sourceScope == nil)
        var current = legacy
        current.resolveRuntimeReadings(legacy.runtimeReadings)
        #expect(current.aiLimitsSnapshot == nil && current.noteText == legacy.noteText)
    }

    @Test func selectedAppCopyIdentityPreservesBothCopiesAndCodableFields() throws {
        var first = AppFolderApplication(url: URL(fileURLWithPath: "/MyDockFixtures/First/Editor.app"))
        var second = AppFolderApplication(url: URL(fileURLWithPath: "/MyDockFixtures/Second/Editor.app"))
        first.bundleIdentifier = "com.example.editor"; second.bundleIdentifier = first.bundleIdentifier
        #expect(first.id != second.id)
        var alias = first
        alias.url = URL(fileURLWithPath: "/MyDockFixtures/First/Unused/../Editor.app")
        #expect(alias.id == first.id)
        var configuration = WidgetConfiguration()
        configuration.appFolderApplications = [first, second]
        try ProfileSemanticValidator.validate(configuration)
        let decoded = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(configuration))
        #expect(decoded.appFolderApplications == [first, second])
        configuration.appFolderApplications.removeAll { $0.id == first.id }
        #expect(configuration.appFolderApplications == [second])
    }
    @Test func unattributedRefreshCannotBeStampedWithTheCurrentRoot() {
        var configuration = WidgetConfiguration()
        configuration.aiLimitsVisibleProviders = [.copilot]
        let legacy = AILimitsSnapshot(fetchedAt: now, readings: [.init(provider: .copilot, availability: .available,
            windows: [.init(name: "Credits", usedPercent: 10)], updatedAt: now, verifiedAccountIdentity: "github:fixture")])
        WidgetDataValue.limits(legacy).apply(to: &configuration, now: now)
        #expect(configuration.aiLimitsSnapshot == nil)
        let sample = AIActivityReader.read(provider: .codex, range: .today, now: now,
            timeZone: utc, homeDirectory: URL(fileURLWithPath: "/MyDockMissingFixtureHome"), environment: [:])
        #expect(sample.sourceScope == AIUsageSourceScope.activity(provider: .codex, range: .today,
            homeDirectory: URL(fileURLWithPath: "/MyDockMissingFixtureHome"), environment: [:], timeZone: utc, now: now))
        var unattributed = sample; unattributed.sourceScope = nil
        configuration.aiActivityProvider = .codex; configuration.aiActivityRange = .today
        WidgetDataValue.activity(unattributed).apply(to: &configuration, now: now)
        #expect(configuration.aiActivitySnapshot == nil)
    }

    @Test func symbolicAppAliasesDeduplicateWhileInstalledCopiesRemainDistinct() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MyDock-AppIdentity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("First.app"), alias = root.appendingPathComponent("Alias.app")
        let second = root.appendingPathComponent("Second.app")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let selected = AppFolderApplication(url: first), aliased = AppFolderApplication(url: alias)
        #expect(selected.id == aliased.id && selected.id != AppFolderApplication(url: second).id)
        #expect(try JSONDecoder().decode(AppFolderApplication.self, from: JSONEncoder().encode(aliased)).url == alias)
    }

    @Test func injectedLimitsReadersKeepTheirExplicitFixtureRootAttribution() async {
        struct FixtureAdapter: AILimitProviderAdapter {
            let provider: AIProvider = .claude
            func read(now: Date) async throws -> AIProviderLimitReading {
                .init(provider: .claude, availability: .available, windows: [.init(name: "Fixture", usedPercent: 5)], updatedAt: now)
            }
        }
        let home = URL(fileURLWithPath: "/MyDockFixtureHome")
        let environment = ["CLAUDE_CONFIG_DIR": "/MyDockFixtureRoot"]
        let snapshot = await AILimitsCollector.collect(providers: [.claude], now: now,
            adapters: [FixtureAdapter()], homeDirectory: home, environment: environment)
        #expect(snapshot.readings.first?.availability == .available)
        #expect(snapshot.sourceScope == AIUsageSourceScope.limits(providers: [.claude], homeDirectory: home, environment: environment, now: now))
    }

}
