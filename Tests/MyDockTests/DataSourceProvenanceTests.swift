import Foundation
import Testing
@testable import MyDock

struct DataSourceProvenanceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func stripe(accountID: String = "acct_123", fetched: Date, skipped: Int = 0) -> StripeSnapshot {
        StripeSnapshot(accountID: accountID, accountName: "Provider name", fetchedAt: fetched, period: .thirtyDays,
                       periodStart: fetched, periodEnd: fetched, currencies: [], unsupportedSubscriptionItems: skipped)
    }

    @Test func storedFailedPartialStaleAndUnrefreshedStatesAreDistinct() {
        let fresh = now.addingTimeInterval(-120)
        #expect(DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: fresh, now: now).health == .stored)
        #expect(DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: nil, now: now).health == .notRefreshed)
        #expect(DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: now.addingTimeInterval(-7200), now: now).health == .stale)
        #expect(DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: fresh, flags: ["x"], now: now).health == .partial)
        let failed = DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: fresh, error: "Offline", flags: ["x"], now: now)
        #expect(failed.health == .refreshFailed("Offline"))
        #expect(failed.needsAttention)
        #expect(DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: fresh, now: now).needsAttention == false)
    }

    @Test func errorsAreSanitizedOfUrlsTokensAndLength() {
        let raw = "Request to https://api.stripe.com/v1/x?key=abc failed with rk_live_ABCdef123456 and Bearer topsecret\n  extra " + String(repeating: "z", count: 300)
        let clean = DataSourceProvenance.sanitized(raw)
        #expect(!clean.contains("https://"))
        #expect(!clean.contains("rk_live"))
        #expect(!clean.contains("topsecret"))
        #expect(!clean.contains("\n"))
        #expect(clean.count <= 140)
    }

    @Test func relativeTextIsDeterministic() {
        #expect(DataSourceProvenance.relative(now.addingTimeInterval(-10), now: now) == "just now")
        #expect(DataSourceProvenance.relative(now.addingTimeInterval(-300), now: now) == "5 min ago")
        #expect(DataSourceProvenance.relative(now.addingTimeInterval(-7200), now: now) == "2 h ago")
        #expect(DataSourceProvenance.relative(now.addingTimeInterval(-172_800), now: now) == "2 d ago")
        #expect(DataSourceProvenance.derive(source: "S", metric: "M", lastRefresh: nil, now: now).refreshText(now: now) == "No successful refresh yet")
    }

    @Test func stripeShowsLocalNameAccountIdMetricDefinitionAndSkippedItems() {
        let provenance = DataSourceProvenance.stripe(snapshot: stripe(fetched: now.addingTimeInterval(-60), skipped: 2),
                                                     localName: "Studio", metric: .mrr, error: nil, now: now)
        #expect(provenance.source == "Studio (acct_123)")
        #expect(provenance.metric == "Normalized gross MRR from active subscriptions")
        #expect(provenance.health == .partial)
        #expect(provenance.flags == ["2 unsupported subscription items skipped"])
        // A local connection id is never presented as a Stripe account id.
        let local = DataSourceProvenance.stripe(snapshot: stripe(accountID: "local-uuid", fetched: now), localName: "Studio", metric: .revenue, error: nil, now: now)
        #expect(local.source == "Studio")
    }

    @Test func paddleAndAIActivityStateTheirDefinitions() {
        #expect(DataSourceProvenance.paddle(snapshot: nil, localName: "", metric: .mrr, error: nil, now: now).metric == "Provider-reported MRR")
        #expect(DataSourceProvenance.paddle(snapshot: nil, localName: "", metric: .mrr, error: nil, now: now).source == "Paddle connection")
        let activity = AIActivitySnapshot(provider: .codex, range: .sevenDays, fetchedAt: now, sourceDescription: "x", available: true,
                                          estimated: false, partial: true, points: [],
                                          totals: AIActivityDailyPoint(date: now, sessions: 0, toolCalls: 0, totalTokens: 0, cachedInputTokens: 0,
                                                                       inputTokens: 0, outputTokens: 0, requests: 0, reportedCostUSD: nil))
        let provenance = DataSourceProvenance.aiActivity(snapshot: activity, error: nil, now: now)
        #expect(provenance.metric == "Local logs, not billing")
        #expect(provenance.health == .partial)
        #expect(provenance.summary(now: now).contains("some records could not be read"))
    }

    @Test func privateHelpCopyStatesRequiredPrivacyAndLimits() {
        let all = (PrivacyHelpCopy.privacyPoints + PrivacyHelpCopy.limitationPoints).joined(separator: " ")
        for phrase in ["Keychain", "Backups never include credentials", "not a bill", "all volumes", "Xcode-built"] {
            #expect(all.contains(phrase), "\(phrase) missing")
        }
    }

    @MainActor
    @Test func editorDemandHolderKeepsSchedulerActiveWhileHiddenAndReleasesOnEnd() {
        let scheduler = RefreshScheduler.makeForTesting(dockVisible: false)
        let holder = RefreshDemandHolder(kind: .editor, scheduler: scheduler)
        #expect(!scheduler.isActive)
        holder.begin()
        holder.begin()
        #expect(holder.isHolding)
        #expect(scheduler.isActive)
        holder.end()
        holder.end()
        #expect(!holder.isHolding)
        #expect(!scheduler.isActive)
    }
}
