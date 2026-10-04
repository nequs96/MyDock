import SwiftUI

struct WidgetFreshnessView: View {
    @ObservedObject var coordinator: WidgetDataCoordinator
    var item: DockItem
    var refresh: () -> Void

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var query: WidgetDataQuery? { WidgetDataQuery.make(kind: item.widgetKind, configuration: configuration) }
    private var fetchedAt: Date? {
        let c = configuration
        switch item.widgetKind {
        case "Stripe": return c.stripeSnapshot?.fetchedAt
        case "Paddle": return c.paddleSnapshot?.fetchedAt
        case "Shopify": return c.shopifySnapshot?.fetchedAt
        case "Stock": return c.stockSnapshot?.fetchedAt
        case "Watchlist": return c.watchlistStocks.compactMap { $0.snapshot?.fetchedAt }.min()
        case "AI Limits": return c.aiLimitsSnapshot?.fetchedAt
        case "AI Activity": return c.aiActivitySnapshot?.fetchedAt
        default: return nil
        }
    }
    var body: some View {
        if let query {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if coordinator.refreshing.contains(query) { ProgressView().controlSize(.mini) }
                        Text(status(at: context.date)).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Button("Retry", action: refresh).controlSize(.small)
                            .disabled(coordinator.refreshing.contains(query))
                    }
                    if let error = coordinator.errors[query] {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.accessibilityElement(children: .contain)
            }
        }
    }
    private func status(at now: Date) -> String {
        if coordinator.refreshing.contains(query!) { return "Updating…" }
        guard let date = fetchedAt else { return "No saved data yet" }
        let age = max(0, now.timeIntervalSince(date))
        let stale = coordinator.errors[query!] != nil || age > (item.widgetKind == "Stock" || item.widgetKind == "Watchlist" ? Double(configuration.stockRefreshIntervalMinutes) * 120 : 600)
        return "\(stale ? "Saved data · " : "Updated ")\(date.formatted(.relative(presentation: .numeric)))"
    }
}

struct WidgetFreshnessIndicator: View {
    @ObservedObject var coordinator: WidgetDataCoordinator
    var item: DockItem
    var body: some View {
        let c = item.widgetConfiguration ?? WidgetConfiguration()
        if let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: c), item.widgetKind == "AI Activity", coordinator.refreshing.contains(query) {
            ProgressView().controlSize(.mini).scaleEffect(0.5).frame(width: 10, height: 10).padding(3)
                .help("Updating local activity").accessibilityHidden(true)
        } else if item.widgetKind != "AI Limits", // its face shows a per-provider stale badge itself
                  let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: c), coordinator.errors[query] != nil {
            // Inset so the badge stays inside the rounded widget corner.
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                .padding(.top, 7).padding(.trailing, 9)
                .help("Saved data · open this widget to review the refresh error")
                .accessibilityLabel("Refresh failed; saved data shown")
        }
    }
}
