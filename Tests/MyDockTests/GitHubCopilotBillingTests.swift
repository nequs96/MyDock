import Foundation
import Testing
@testable import MyDock

struct GitHubCopilotBillingTests {
    private let now = ISO8601DateFormatter().date(from: "2025-01-15T12:00:00Z")!

    @Test func parserCountsCopilotCreditsAndComputesUTCMonthlyReset() throws {
        let response = #"{"user":"octocat","usageItems":[{"product":"Copilot","sku":"Copilot Pro","unitType":"ai-credits","grossQuantity":100,"netQuantity":0},{"product":"GitHub Copilot","sku":"Copilot premium requests","unitType":"credits","grossQuantity":50},{"product":"GitHub Actions","sku":"Actions minutes","unitType":"minutes","grossQuantity":999},{"product":"Other","sku":"Other credits","unitType":"credits","grossQuantity":800}]}"#
        let reading = try GitHubCopilotBillingParser.reading(from: Data(response.utf8),
                                                             username: "octocat",
                                                             monthlyAllowance: 1_500,
                                                             now: now)

        #expect(reading.provider == .copilot)
        #expect(reading.availability == .available)
        #expect(reading.windows.count == 1)
        #expect(reading.windows[0].name == "Monthly AI credits")
        #expect(reading.windows[0].usedPercent == 10)
        #expect(reading.windows[0].durationMinutes == nil)
        let reset = try #require(reading.windows[0].resetsAt)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = utc.dateComponents([.year, .month, .day, .hour], from: reset)
        #expect(parts.year == 2025)
        #expect(parts.month == 2)
        #expect(parts.day == 1)
        #expect(parts.hour == 0)
    }

    @Test func parserReportsZeroUsageForAnEmptyMonth() throws {
        let response = #"{"user":"octocat","usageItems":[]}"#
        let reading = try GitHubCopilotBillingParser.reading(from: Data(response.utf8),
                                                             username: "octocat",
                                                             monthlyAllowance: 1_500,
                                                             now: now)
        #expect(reading.windows.first?.usedPercent == 0)
    }

    @Test func parserRejectsMalformedMismatchedAndUnconfiguredResponses() {
        let valid = Data(#"{"user":"octocat","usageItems":[]}"#.utf8)
        #expect(throws: GitHubCopilotBillingError.self) {
            try GitHubCopilotBillingParser.reading(from: Data("{".utf8), username: "octocat",
                                                   monthlyAllowance: 1_500, now: now)
        }
        #expect(throws: GitHubCopilotBillingError.self) {
            try GitHubCopilotBillingParser.reading(from: valid, username: "someone-else",
                                                   monthlyAllowance: 1_500, now: now)
        }
        #expect(throws: GitHubCopilotBillingError.self) {
            try GitHubCopilotBillingParser.reading(from: valid, username: "octocat",
                                                   monthlyAllowance: 0, now: now)
        }
    }

    @Test func usernamePolicyMatchesGitHubLoginConstraints() {
        #expect(GitHubCopilotUsernamePolicy.isValid("octocat"))
        #expect(GitHubCopilotUsernamePolicy.isValid("octo-cat-42"))
        #expect(GitHubCopilotUsernamePolicy.isValid(String(repeating: "a", count: 39)))
        #expect(!GitHubCopilotUsernamePolicy.isValid("-octocat"))
        #expect(!GitHubCopilotUsernamePolicy.isValid("octocat-"))
        #expect(!GitHubCopilotUsernamePolicy.isValid("octo--cat"))
        #expect(!GitHubCopilotUsernamePolicy.isValid("octo.cat"))
        #expect(!GitHubCopilotUsernamePolicy.isValid(String(repeating: "a", count: 40)))
    }

    @Test func requestUsesTheDocumentedPersonalBillingEndpointAndReadOnlyHeaders() throws {
        let request = try GitHubCopilotBillingClient.makeRequest(username: "octocat",
                                                                 token: "secret-token",
                                                                 now: now)
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(request.httpMethod == "GET")
        #expect(url.path == "/users/octocat/settings/billing/ai_credit/usage")
        #expect(query["year"] == "2025")
        #expect(query["month"] == "1")
        #expect(query["product"] == "Copilot AI Credits")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(!url.absoluteString.contains("secret-token"))
    }

    @Test func monthlyAllowanceIsOptionalAndBackwardsCompatible() throws {
        let legacy = try JSONDecoder().decode(WidgetConfiguration.self, from: Data("{}".utf8))
        #expect(legacy.aiCopilotMonthlyCreditAllowance == nil)

        var configured = WidgetConfiguration()
        configured.aiCopilotMonthlyCreditAllowance = 7_000
        let roundTrip = try JSONDecoder().decode(WidgetConfiguration.self,
                                                 from: JSONEncoder().encode(configured))
        #expect(roundTrip.aiCopilotMonthlyCreditAllowance == 7_000)

        let invalid = try JSONDecoder().decode(WidgetConfiguration.self,
                                               from: Data(#"{"aiCopilotMonthlyCreditAllowance":0}"#.utf8))
        #expect(invalid.aiCopilotMonthlyCreditAllowance == nil)
    }
}
