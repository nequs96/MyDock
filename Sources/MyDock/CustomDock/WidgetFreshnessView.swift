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

/// The one refresh rule every popout follows, for coordinator families and for families that load
/// their own reading (Calendar, Reminders, Weather, Disk Space).
enum WidgetFreshnessPresentation {
    /// "Retry" only after a failed or stale reading; otherwise it is a plain "Refresh".
    static func refreshLabel(_ state: WidgetFreshnessState) -> String { state == .stale ? "Retry" : "Refresh" }

    /// How far a reading may sit in the future (clock skew) before its age is unknown.
    static let futureTolerance: TimeInterval = 60

    /// A failed refresh is stale whether or not an older reading is kept. A reading dated in the future
    /// (a clock change, an imported Dock) has no honest age, so it is stale too.
    static func state(isRefreshing: Bool, updatedAt: Date?, failed: Bool, now: Date, maximumAge: TimeInterval) -> WidgetFreshnessState {
        if isRefreshing { return .updating }
        if failed { return .stale }
        guard let updatedAt else { return .empty }
        let age = now.timeIntervalSince(updatedAt)
        return age < -futureTolerance || age > maximumAge ? .stale : .fresh
    }

    /// When a reading was saved, relative to `now`: "just now" under a minute (never "in 0 seconds"),
    /// "5 minutes ago", and the date itself for a timestamp in the future.
    static func relativeText(_ updatedAt: Date, now: Date) -> String {
        let age = now.timeIntervalSince(updatedAt)
        if abs(age) < futureTolerance { return "just now" }
        if age < 0 { return updatedAt.formatted(date: .abbreviated, time: .shortened) }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(for: updatedAt, relativeTo: now)
    }

    /// A watchlist is as old as its oldest ticker; one that never loaded leaves it without a complete reading.
    static func watchlistFetchedAt(_ stocks: [WatchlistStock]) -> Date? {
        let dates = stocks.map { $0.snapshot?.fetchedAt }
        return dates.contains(where: { $0 == nil }) ? nil : dates.compactMap { $0 }.min()
    }

    /// The short status line beside the refresh control.
    static func status(_ state: WidgetFreshnessState, updatedAt: Date?, now: Date = .now) -> String {
        let relative = updatedAt.map { relativeText($0, now: now) }
        switch state {
        case .updating: return "Updating…"
        case .empty: return "No saved data yet"
        case .fresh: return "Updated " + (relative ?? "just now")
        case .stale: return relative.map { "Saved data · " + $0 } ?? "Couldn’t update"
        }
    }
}

/// A family's own reading state, published to the popout shell (`widgetPopoutRefresh`) so the shell's
/// header shows its freshness and the one refresh control, and the settings sheet its Data row. Families
/// draw no Refresh link of their own.
struct WidgetPopoutRefresh: Equatable {
    var updatedAt: Date?
    var isRefreshing: Bool
    var failed: Bool
    /// Older readings are shown as stale.
    var maximumAge: TimeInterval = 15 * 60
    var action: () -> Void

    func state(at now: Date) -> WidgetFreshnessState {
        WidgetFreshnessPresentation.state(isRefreshing: isRefreshing, updatedAt: updatedAt, failed: failed, now: now, maximumAge: maximumAge)
    }

    /// The action is not compared: a family's refresh closure is stable for its lifetime.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.updatedAt == rhs.updatedAt && lhs.isRefreshing == rhs.isRefreshing
            && lhs.failed == rhs.failed && lhs.maximumAge == rhs.maximumAge
    }
}

struct WidgetPopoutRefreshKey: PreferenceKey {
    static var defaultValue: WidgetPopoutRefresh? { nil }
    static func reduce(value: inout WidgetPopoutRefresh?, nextValue: () -> WidgetPopoutRefresh?) {
        value = value ?? nextValue()
    }
}

extension View {
    /// Publishes a family's reading state to the popout shell's single refresh control.
    func widgetPopoutRefresh(_ refresh: WidgetPopoutRefresh?) -> some View {
        preference(key: WidgetPopoutRefreshKey.self, value: refresh)
    }
}

/// The compact refresh control: an icon-only circle like the header's Customize and Close buttons.
struct WidgetRefreshButton: View {
    var state: WidgetFreshnessState
    var action: () -> Void
    var body: some View {
        let label = WidgetFreshnessPresentation.refreshLabel(state)
        Button(action: action) { Image(systemName: "arrow.clockwise") }
            .buttonStyle(WidgetCircleButtonStyle())
            .disabled(state == .updating)
            .help(label)
            .accessibilityLabel(label)
    }
}

/// A dot (or spinner) and the status sentence; optionally the refresh circle and an error line.
struct WidgetFreshnessLine: View {
    var state: WidgetFreshnessState
    var status: String
    var error: String? = nil
    var showsRefreshControl = true
    var refresh: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if state == .updating {
                    ProgressView().controlSize(.mini).accessibilityHidden(true)
                } else if let color = state.dotColor {
                    Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
                }
                Text(status).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                if showsRefreshControl {
                    Spacer(minLength: 8)
                    WidgetRefreshButton(state: state, action: refresh)
                }
            }
            if let error {
                Text(error).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The freshness of a coordinator family (Stripe, Paddle, Shopify, Stock, Watchlist, AI).
struct WidgetCoordinatorFreshness {
    var coordinator: WidgetDataCoordinator
    var item: DockItem

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    var query: WidgetDataQuery? { WidgetDataQuery.make(kind: item.widgetKind, configuration: configuration) }
    var fetchedAt: Date? {
        let c = configuration
        switch item.widgetKind {
        case "Stripe": return c.stripeSnapshot?.fetchedAt
        case "Paddle": return c.paddleSnapshot?.fetchedAt
        case "Shopify": return c.shopifySnapshot?.fetchedAt
        case "Stock": return c.stockSnapshot?.fetchedAt
        case "Watchlist": return WidgetFreshnessPresentation.watchlistFetchedAt(c.watchlistStocks)
        case "AI Limits": return c.aiLimitsSnapshot?.fetchedAt
        case "AI Activity": return c.aiActivitySnapshot?.fetchedAt
        default: return nil
        }
    }
    @MainActor var error: String? { query.flatMap { coordinator.errors[$0] } }
    @MainActor func state(at now: Date) -> WidgetFreshnessState {
        guard let query else { return .empty }
        let limit = item.widgetKind == "Stock" || item.widgetKind == "Watchlist" ? Double(configuration.stockRefreshIntervalMinutes) * 120 : 600
        // No saved reading and no error is "empty"; a failure with or without saved data is stale.
        if !coordinator.refreshing.contains(query), fetchedAt == nil, coordinator.errors[query] == nil { return .empty }
        return WidgetFreshnessPresentation.state(isRefreshing: coordinator.refreshing.contains(query), updatedAt: fetchedAt,
                                                 failed: coordinator.errors[query] != nil, now: now, maximumAge: limit)
    }
}

struct WidgetFreshnessView: View {
    @ObservedObject var coordinator: WidgetDataCoordinator
    var item: DockItem
    /// False in the popout header, which draws the refresh circle beside Customize and Close.
    var showsRefreshControl: Bool
    var refresh: () -> Void

    init(coordinator: WidgetDataCoordinator, item: DockItem, showsRefreshControl: Bool = true, refresh: @escaping () -> Void) {
        self.coordinator = coordinator; self.item = item
        self.showsRefreshControl = showsRefreshControl; self.refresh = refresh
    }

    var body: some View {
        let freshness = WidgetCoordinatorFreshness(coordinator: coordinator, item: item)
        if freshness.query != nil {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let state = freshness.state(at: context.date)
                WidgetFreshnessLine(state: state, status: WidgetFreshnessPresentation.status(state, updatedAt: freshness.fetchedAt, now: context.date),
                                    error: freshness.error, showsRefreshControl: showsRefreshControl, refresh: refresh)
            }
        }
    }
}

/// The refresh circle for a coordinator family, kept in step with its status line.
struct WidgetCoordinatorRefreshButton: View {
    @ObservedObject var coordinator: WidgetDataCoordinator
    var item: DockItem
    var refresh: () -> Void
    var body: some View {
        let freshness = WidgetCoordinatorFreshness(coordinator: coordinator, item: item)
        if freshness.query != nil {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                WidgetRefreshButton(state: freshness.state(at: context.date), action: refresh)
            }
        }
    }
}

/// A family-published reading (`WidgetPopoutRefresh`) as a status line, with or without its control.
struct WidgetFamilyFreshnessView: View {
    var refresh: WidgetPopoutRefresh
    var showsRefreshControl = true
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let state = refresh.state(at: context.date)
            WidgetFreshnessLine(state: state, status: WidgetFreshnessPresentation.status(state, updatedAt: refresh.updatedAt, now: context.date),
                                showsRefreshControl: showsRefreshControl) { refresh.action() }
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
                .overlay {
                    if accessibility.contrast == .increased {
                        Circle().strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .frame(width: 6, height: 6)
                .padding(.top, inset).padding(.trailing, inset)
                .help("Saved data · open this widget to review the refresh error")
                .accessibilityLabel("Refresh failed; saved data shown")
        }
    }
}
