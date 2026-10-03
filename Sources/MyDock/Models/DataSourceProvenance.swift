import Foundation

/// Pure description of where a displayed number came from and how trustworthy its freshness is.
/// It reads snapshot fields and error text only; it never contacts a provider or invents a health claim.
struct DataSourceProvenance: Equatable {
    enum Health: Equatable {
        /// A reading is stored locally. This is not a statement that the connection was tested.
        case stored
        /// The most recent refresh failed; the sanitized message is shown with any saved reading.
        case refreshFailed(String)
        /// The reading carries partial or unsupported-data flags (listed in `flags`).
        case partial
        /// The saved reading is older than the freshness window and has not been renewed.
        case stale
        case notRefreshed
    }

    var source: String
    var metric: String
    var lastRefresh: Date?
    var health: Health
    var flags: [String]

    static let defaultStaleAfter: TimeInterval = 60 * 60

    static func derive(source: String, metric: String, lastRefresh: Date?, error: String? = nil, flags: [String] = [],
                       staleAfter: TimeInterval = defaultStaleAfter, now: Date = .now) -> DataSourceProvenance {
        let health: Health
        if let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            health = .refreshFailed(sanitized(error))
        } else if lastRefresh == nil {
            health = .notRefreshed
        } else if !flags.isEmpty {
            health = .partial
        } else if let lastRefresh, now.timeIntervalSince(lastRefresh) > staleAfter {
            health = .stale
        } else {
            health = .stored
        }
        return DataSourceProvenance(source: source, metric: metric, lastRefresh: lastRefresh, health: health, flags: flags)
    }

    // MARK: Text

    static func relative(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60)) min ago"
        case ..<86_400: return "\(Int(seconds / 3600)) h ago"
        default: return "\(Int(seconds / 86_400)) d ago"
        }
    }

    func refreshText(now: Date = .now) -> String {
        guard let lastRefresh else { return "No successful refresh yet" }
        return "Last refreshed \(Self.relative(lastRefresh, now: now))"
    }

    var healthText: String {
        switch health {
        case .stored: "Stored reading"
        case .refreshFailed(let message): "Last refresh failed: \(message)"
        case .partial: "Partial: " + flags.joined(separator: "; ")
        case .stale: "Saved reading is out of date"
        case .notRefreshed: "Not refreshed yet"
        }
    }

    var needsAttention: Bool {
        switch health { case .refreshFailed, .partial, .stale: true; case .stored, .notRefreshed: false }
    }

    /// One accessible sentence combining every part.
    func summary(now: Date = .now) -> String {
        var parts = [source, metric, refreshText(now: now), healthText]
        if case .partial = health {} else if !flags.isEmpty { parts.append("Flags: " + flags.joined(separator: "; ")) }
        return parts.joined(separator: " · ")
    }

    // MARK: Sanitizing

    /// Removes URLs, credential-shaped tokens and long opaque strings, collapses whitespace and bounds length.
    static func sanitized(_ message: String, limit: Int = 140) -> String {
        var text = message
        let patterns = [#"https?://\S+"#,
                        #"\b(?:rk|sk|pk|shpat|shpss|shpca|ghp|gho|ghu|ghs|github_pat|pdl|pdl_live|pdl_sdbx)_[A-Za-z0-9_\-]+"#,
                        #"\b[A-Za-z0-9_\-]{28,}\b"#,
                        #"(?i)bearer\s+\S+"#]
        for pattern in patterns {
            text = text.replacingOccurrences(of: pattern, with: "…", options: .regularExpression)
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.count > limit { text = String(text.prefix(limit - 1)) + "…" }
        return text
    }

    // MARK: Builders

    private static func name(_ local: String, fallback: String) -> String {
        let trimmed = local.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    static func stripe(snapshot: StripeSnapshot?, localName: String, metric: StripeMetric, error: String?, now: Date = .now) -> DataSourceProvenance {
        var source = name(localName, fallback: "Stripe connection")
        if let id = snapshot?.accountID, id.hasPrefix("acct_") { source += " (\(id))" }
        let definition: String
        switch metric {
        case .mrr, .arr: definition = "Normalized gross MRR from active subscriptions"
        case .revenue: definition = "Balance revenue less refunds, before fees"
        case .netAfterFees: definition = "Stripe balance-transaction net after fees"
        case .payingSubscribers, .arpu: definition = "Active subscription counts and gross MRR"
        case .availableBalance, .pendingBalance: definition = "Stripe balance as reported"
        }
        var flags: [String] = []
        if let skipped = snapshot?.unsupportedSubscriptionItems, skipped > 0 {
            flags.append("\(skipped) unsupported subscription item\(skipped == 1 ? "" : "s") skipped")
        }
        return derive(source: source, metric: definition, lastRefresh: snapshot?.fetchedAt, error: error, flags: flags, now: now)
    }

    static func paddle(snapshot: PaddleSnapshot?, localName: String, metric: PaddleMetric, error: String?, now: Date = .now) -> DataSourceProvenance {
        let definition: String
        switch metric {
        case .mrr, .arr: definition = "Provider-reported MRR"
        case .netRevenue: definition = "Provider-reported net revenue after tax and fees"
        case .activeSubscribers: definition = "Provider-reported active subscribers"
        }
        return derive(source: name(localName, fallback: "Paddle connection"), metric: definition,
                      lastRefresh: snapshot.map { $0.updatedAt }, error: error, now: now)
    }

    static func shopify(snapshot: ShopifySnapshot?, localName: String, error: String?, now: Date = .now) -> DataSourceProvenance {
        var source = name(localName, fallback: "Shopify store")
        if let domain = snapshot?.storeDomain, !domain.isEmpty { source += " (\(domain))" }
        var flags: [String] = []
        if let incomplete = snapshot?.productBreakdownIncompleteOrders, incomplete > 0 {
            flags.append("\(incomplete) order\(incomplete == 1 ? "" : "s") without product detail")
        }
        return derive(source: source, metric: "Order activity from recent orders, not cash received",
                      lastRefresh: snapshot?.fetchedAt, error: error, flags: flags, now: now)
    }

    static func aiLimits(snapshot: AILimitsSnapshot?, error: String? = nil, now: Date = .now) -> DataSourceProvenance {
        let unavailable = snapshot?.readings.filter { $0.availability != .available }.count ?? 0
        let flags = unavailable > 0 ? ["\(unavailable) provider\(unavailable == 1 ? "" : "s") unavailable or not set up"] : []
        return derive(source: "Provider apps and sign-ins on this Mac",
                      metric: "Provider-reported usage windows, not inferred", lastRefresh: snapshot?.fetchedAt,
                      error: error, flags: flags, now: now)
    }

    static func aiActivity(snapshot: AIActivitySnapshot?, error: String?, now: Date = .now) -> DataSourceProvenance {
        var flags: [String] = []
        if snapshot?.partial == true { flags.append("some records could not be read") }
        if snapshot?.estimated == true { flags.append("local estimate") }
        let provider = snapshot?.provider.title ?? "AI"
        return derive(source: "Local \(provider) logs on this Mac", metric: "Local logs, not billing",
                      lastRefresh: snapshot?.fetchedAt, error: error, flags: flags, now: now)
    }
}
