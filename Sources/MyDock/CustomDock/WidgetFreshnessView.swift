import SwiftUI

/// Freshness of a widget's saved data, shared by the popout status line and the Dock indicator.
enum WidgetFreshnessState: Equatable {
    case updating, fresh, stale, empty

    /// A single small dot colour; nil draws nothing.
    var dotColor: Color? {
        switch self {
        case .fresh: WidgetPalette.positive
        case .stale: WidgetPalette.warning
        case .updating, .empty: nil
        }
    }
}

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
                let state = state(query, at: context.date)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if state == .updating {
                            ProgressView().controlSize(.mini).accessibilityHidden(true)
                        } else if let color = state.dotColor {
                            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                        }
                        Text(status(query, state: state)).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        // "Retry" only after a failed or stale reading; otherwise it is a plain refresh.
                        Button(state == .stale ? "Retry" : "Refresh", action: refresh).controlSize(.small)
                            .disabled(state == .updating)
                    }
                    if let error = coordinator.errors[query] {
                        Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.accessibilityElement(children: .contain)
            }
        }
    }
    private func state(_ query: WidgetDataQuery, at now: Date) -> WidgetFreshnessState {
        if coordinator.refreshing.contains(query) { return .updating }
        guard let date = fetchedAt else { return .empty }
        let age = max(0, now.timeIntervalSince(date))
        let limit = item.widgetKind == "Stock" || item.widgetKind == "Watchlist" ? Double(configuration.stockRefreshIntervalMinutes) * 120 : 600
        return coordinator.errors[query] != nil || age > limit ? .stale : .fresh
    }
    private func status(_ query: WidgetDataQuery, state: WidgetFreshnessState) -> String {
        switch state {
        case .updating: return "Updating…"
        case .empty: return "No saved data yet"
        case .fresh, .stale:
            let relative = fetchedAt.map { $0.formatted(.relative(presentation: .numeric)) } ?? ""
            return (state == .stale ? "Saved data · " : "Updated ") + relative
        }
    }
}

/// Exactly one minimal indicator per widget: a tiny spinner while AI Activity refreshes, or a small
/// warning dot when a refresh failed. AI Limits draws its own per-provider stale mark, so it is skipped here.
struct WidgetFreshnessIndicator: View {
    @ObservedObject var coordinator: WidgetDataCoordinator
    var item: DockItem
    @Environment(\.dockModuleRadius) private var moduleRadius
    @DockAccessibilityStyle() private var accessibility
    /// Keeps the dot inside the rounded corner for any module radius.
    private var inset: CGFloat { max(6, min(10, moduleRadius * 0.45)) }
    var body: some View {
        let c = item.widgetConfiguration ?? WidgetConfiguration()
        if let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: c), item.widgetKind == "AI Activity", coordinator.refreshing.contains(query) {
            ProgressView().controlSize(.mini).scaleEffect(0.5).frame(width: 10, height: 10).padding(inset - 2)
                .help("Updating local activity").accessibilityHidden(true)
        } else if item.widgetKind != "AI Limits", // its face shows a per-provider stale mark itself
                  let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: c), coordinator.errors[query] != nil {
            Circle().fill(WidgetPalette.warning)
                .overlay { if accessibility.contrast == .increased { Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1) } }
                .frame(width: 6, height: 6)
                .padding(.top, inset).padding(.trailing, inset)
                .help("Saved data · open this widget to review the refresh error")
                .accessibilityLabel("Refresh failed; saved data shown")
        }
    }
}
