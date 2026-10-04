import Foundation
import Testing
@testable import MyDock

struct ReliabilityLastGoodLimitsTests {
    private let now = Date(timeIntervalSince1970: 1_791_115_200)

    private func good(_ provider: AIProvider = .copilot, identity: String? = "github:fixture") -> AIProviderLimitReading {
        .init(provider: provider, availability: .available, windows: [.init(name: "Monthly credits", usedPercent: 20)],
              updatedAt: now.addingTimeInterval(-3_600), verifiedAccountIdentity: identity)
    }

    private func snapshot(_ readings: [AIProviderLimitReading], providers: [AIProvider] = [.copilot]) -> AILimitsSnapshot {
        .init(fetchedAt: now, readings: readings, sourceScope: AIUsageSourceScope.limits(providers: providers, now: now))
    }

    private func configured() -> WidgetConfiguration {
        var configuration = WidgetConfiguration()
        configuration.aiLimitsVisibleProviders = [.copilot]
        configuration.aiCopilotMonthlyCreditAllowance = 100
        configuration.aiLimitsSnapshot = .init(fetchedAt: now.addingTimeInterval(-3_600), readings: [good()],
            sourceScope: AIUsageSourceScope.limits(providers: [.copilot], now: now))
        return configuration
    }

    private func failure(identity: String? = "github:fixture", kind: AILimitFailureKind = .transient,
                         availability: AILimitAvailability = .error) -> AIProviderLimitReading {
        .init(provider: .copilot, availability: availability, windows: [], message: "Fixture request failed",
              requestedAccountIdentity: identity, failureKind: kind)
    }

    @Test func matchingVerifiedCopilotKeepsOriginalSuccessfulTimeAndExplicitFailureUntilRecovery() {
        var configuration = configured()
        let original = configuration.aiLimitsSnapshot!
        WidgetDataValue.limits(snapshot([failure()])).apply(to: &configuration, now: now)
        let retained = configuration.aiLimitsSnapshot!.readings[0]
        #expect(retained.windows == original.readings[0].windows)
        #expect(retained.updatedAt == original.readings[0].updatedAt && configuration.aiLimitsSnapshot?.fetchedAt == original.fetchedAt)
        #expect(retained.lastRefreshError != nil)
        let provenance = DataSourceProvenance.aiLimits(snapshot: configuration.aiLimitsSnapshot, now: now)
        #expect(provenance.lastRefresh == original.readings[0].updatedAt)
        if case .refreshFailed = provenance.health {} else { Issue.record("Retained values need explicit failure provenance") }
        var recovered = good(); recovered.updatedAt = now
        WidgetDataValue.limits(snapshot([recovered])).apply(to: &configuration, now: now)
        #expect(configuration.aiLimitsSnapshot?.readings[0].lastRefreshError == nil)
        #expect(configuration.aiLimitsSnapshot?.readings[0].updatedAt == now)
    }

    @Test func unknownOrDifferentAccountAndDifferentRootCannotCarryOver() {
        for requested in [String?.none, "github:other"] {
            var configuration = configured()
            WidgetDataValue.limits(snapshot([failure(identity: requested)])).apply(to: &configuration, now: now)
            #expect(configuration.aiLimitsSnapshot?.readings[0].windows.isEmpty == true)
        }
        var unknown = configured()
        unknown.aiLimitsSnapshot?.readings[0].verifiedAccountIdentity = nil
        WidgetDataValue.limits(snapshot([failure()])).apply(to: &unknown, now: now)
        #expect(unknown.aiLimitsSnapshot?.readings[0].windows.isEmpty == true)
        var otherRoot = configured()
        otherRoot.aiLimitsSnapshot?.sourceScope = "Different source root"
        WidgetDataValue.limits(snapshot([failure()])).apply(to: &otherRoot, now: now)
        #expect(otherRoot.aiLimitsSnapshot?.readings[0].windows.isEmpty == true)
    }

    @Test func authenticationSetupUnavailableAndUnverifiedProvidersNeverRetainCurrentWindows() {
        for (kind, availability) in [(AILimitFailureKind.authentication, AILimitAvailability.setupRequired), (.unavailable, .unavailable)] {
            var configuration = configured()
            WidgetDataValue.limits(snapshot([failure(kind: kind, availability: availability)])).apply(to: &configuration, now: now)
            #expect(configuration.aiLimitsSnapshot?.readings[0].windows.isEmpty == true)
        }
        for provider in [AIProvider.codex, .claude] {
            var configuration = WidgetConfiguration()
            configuration.aiLimitsVisibleProviders = [provider]
            configuration.aiLimitsSnapshot = .init(fetchedAt: now, readings: [good(provider, identity: nil)],
                sourceScope: AIUsageSourceScope.limits(providers: [provider], now: now))
            let failed = AIProviderLimitReading(provider: provider, availability: .error, windows: [],
                message: "Fixture failure", failureKind: .transient)
            WidgetDataValue.limits(snapshot([failed], providers: [provider])).apply(to: &configuration, now: now)
            #expect(configuration.aiLimitsSnapshot?.readings[0].windows.isEmpty == true)
        }
    }

    @Test func partialRefreshKeepsPerProviderSuccessfulTimestamps() {
        var configuration = configured()
        configuration.aiLimitsVisibleProviders = [.copilot, .codex]
        configuration.aiLimitsSnapshot?.sourceScope = AIUsageSourceScope.limits(providers: [.copilot, .codex], now: now)
        var fresh = good(.codex, identity: nil); fresh.updatedAt = now
        WidgetDataValue.limits(snapshot([failure(), fresh], providers: [.copilot, .codex])).apply(to: &configuration, now: now)
        #expect(configuration.aiLimitsSnapshot?.reading(for: .copilot)?.updatedAt == now.addingTimeInterval(-3_600))
        #expect(configuration.aiLimitsSnapshot?.reading(for: .copilot)?.lastRefreshError != nil)
        #expect(configuration.aiLimitsSnapshot?.reading(for: .codex)?.updatedAt == now)
    }

    @Test func copilotFailureClassificationDistinguishesAuthenticationUnsupportedAndTransient() {
        #expect(GitHubCopilotBillingError.limitFailure(GitHubCopilotBillingError.httpStatus(401), requestedUsername: "Fixture").kind == .authentication)
        #expect(GitHubCopilotBillingError.limitFailure(GitHubCopilotBillingError.httpStatus(403), requestedUsername: "Fixture").kind == .authentication)
        #expect(GitHubCopilotBillingError.limitFailure(GitHubCopilotBillingError.httpStatus(404), requestedUsername: "Fixture").kind == .unavailable)
        #expect(GitHubCopilotBillingError.limitFailure(GitHubCopilotBillingError.invalidResponse, requestedUsername: "Fixture").kind == .unavailable)
        #expect(GitHubCopilotBillingError.limitFailure(GitHubCopilotBillingError.httpStatus(429), requestedUsername: "Fixture").kind == .transient)
        #expect(GitHubCopilotBillingError.limitFailure(URLError(.notConnectedToInternet), requestedUsername: "Fixture").requestedAccountIdentity == "github:fixture")
    }
}
