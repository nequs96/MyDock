#if DEBUG
import AppKit
import SwiftUI

/// Inert fixtures, read only by exports and tests; no provider credentials or system preferences.
@MainActor
enum FacesBQA {
    static let families = ["Stock", "Watchlist", "Stripe", "Paddle", "Shopify", "AI Limits", "AI Activity", "System Activity", "Network Activity"]
    enum State: String, CaseIterable { case ready, setup, unavailable, stale }
    static let now = Date.now

    static func item(_ kind: String, state: State = .ready) -> DockItem {
        if state == .setup { return .widget(kind) }
        let date = state == .stale ? now.addingTimeInterval(-86_400) : now
        var item = DockItem.widget(kind)
        var c = item.widgetConfiguration ?? WidgetConfiguration()
        switch kind {
        case "Stock", "Watchlist":
            item = StockFaceSample.item(kind: kind)
            c = item.widgetConfiguration!
            c.stockSnapshot?.fetchedAt = date
            if !c.watchlistStocks.isEmpty { c.watchlistStocks[0].snapshot?.fetchedAt = date }
            if state == .unavailable {
                c.stockSnapshot = nil
                c.watchlistStocks[0].snapshot = nil
            }
        case "Stripe":
            c.stripeAccountID = "qa-stripe"
            c.stripeDisplayName = "Example account"
            c.stripeCurrency = "USD"
            c.stripeSnapshot = StripeSnapshot(accountID: "qa-stripe", accountName: "Example account", fetchedAt: date,
                period: c.stripePeriod, periodStart: now.addingTimeInterval(-86_400), periodEnd: now,
                currencies: state == .unavailable ? [] : [StripeCurrencyMetrics(currency: "USD", revenueMinor: 240_000,
                    netAfterFeesMinor: 228_000, mrrMinor: 480_000, payingSubscribers: 32, availableBalanceMinor: 120_000, pendingBalanceMinor: 10_000)],
                unsupportedSubscriptionItems: state == .stale ? 2 : 0)
        case "Paddle":
            c.paddleAccountID = "qa-paddle"
            c.paddleDisplayName = "Example account"
            c.paddleShowsChart = true
            c.paddleSnapshot = state == .unavailable ? nil : PaddleSnapshot(accountID: "qa-paddle", accountName: "Example account", fetchedAt: date,
                period: c.paddlePeriod, currency: "USD", points: [12, 18, 14, 25, 20, 28, 24].enumerated().map { index, value in
                    PaddleMetricPoint(date: now.addingTimeInterval(Double(index - 6) * 86_400), netRevenueMinor: Decimal(value * 1_000),
                                      mrrMinor: 480_000, activeSubscribers: 32)
                }, updatedAt: date)
        case "Shopify":
            c.shopifyStoreID = "qa-shopify"
            c.shopifyDisplayName = "Example store"
            c.shopifyShowsChart = true
            c.shopifySnapshot = state == .unavailable ? nil : ShopifySnapshot(storeID: "qa-shopify", storeName: "Example store",
                storeDomain: "example.myshopify.com", fetchedAt: date, period: c.shopifyPeriod, periodStart: now.addingTimeInterval(-86_400),
                periodEnd: now, timeZoneID: "Europe/Warsaw", currency: "USD", orderValue: 2_400, orderCount: 32,
                dailyPoints: [12, 18, 14, 25, 20, 28, 24].enumerated().map { index, value in
                    ShopifyDailyPoint(date: now.addingTimeInterval(Double(index - 6) * 86_400), orderValue: Decimal(value * 10), orders: value)
                }, productBreakdown: [.init(name: "Notebook", units: 12, orders: 8)], trafficBreakdown: [.init(name: "Direct", units: 0, orders: 20)],
                productBreakdownIncompleteOrders: state == .stale ? 1 : 0, trafficAttributedOrders: 20)
        case "AI Limits":
            c.aiLimitsVisibleProviders = [.copilot, .geminiCLI]
            c.aiLimitsCompactProvider = .copilot
            c.aiLimitsSnapshot = AILimitsSnapshot(fetchedAt: date, readings: [AIProviderLimitReading(provider: .copilot,
                availability: state == .unavailable ? .unavailable : .available, plan: "Pro",
                windows: state == .unavailable ? [] : [AILimitWindow(name: "Monthly credits", usedPercent: state == .stale ? 96 : 28,
                    resetsAt: now.addingTimeInterval(86_400), durationMinutes: 43_200)], updatedAt: date,
                message: state == .unavailable ? "No supported local reading is available." : nil,
                lastRefreshError: state == .stale ? "Example temporary connection failure" : nil),
                AIProviderLimitReading(provider: .geminiCLI, availability: .available,
                    windows: [.init(name: "Daily", usedPercent: 15, durationMinutes: 1440)], updatedAt: date)])
        case "AI Activity":
            c = AIActivityPreviewData.item().widgetConfiguration!
            if var activity = c.aiActivitySnapshot {
                let total: Int64 = 643_900_000
                let original = max(1, activity.totals.totalTokens)
                for index in activity.points.indices {
                    activity.points[index].totalTokens = activity.points[index].totalTokens * total / original
                }
                if !activity.points.isEmpty {
                    activity.points[activity.points.count - 1].totalTokens += total - activity.points.map(\.totalTokens).reduce(0, +)
                }
                activity.totals.totalTokens = total
                c.aiActivitySnapshot = activity
            }
            c.aiActivitySnapshot?.fetchedAt = date
            c.aiActivitySnapshot?.available = state != .unavailable
            c.aiActivitySnapshot?.partial = state == .stale
        default: break
        }
        c.aiLimitsSnapshot?.sourceScope = AIUsageSourceScope.limits(providers: c.aiLimitsVisibleProviders)
        c.aiActivitySnapshot?.sourceScope = AIUsageSourceScope.activity(provider: c.aiActivityProvider, range: c.aiActivityRange)
        item.widgetConfiguration = c
        return item
    }

    static func system(_ state: State) -> SystemActivityReadings {
        guard state == .ready || state == .stale else { return SystemActivityReadings() }
        return SystemActivityReadings(cpuPercentage: state == .stale ? 96 : 37, cpuHistory: [15, 21, 30, 18, 28, 37, 29, 37],
            perCorePercentages: [21, 35, 50, 42], memory: HostMemoryReading(usedBytes: 12_000_000_000, totalBytes: 32_000_000_000,
                swapUsedBytes: 512_000_000, activeBytes: 5_000_000_000, wiredBytes: 3_000_000_000, compressedBytes: 1_000_000_000,
                inactiveBytes: 2_000_000_000, freeBytes: 20_000_000_000, purgeableBytes: 1_000_000_000),
            loadAverage: SystemLoadAverage(oneMinute: 2.4, fiveMinutes: 1.9, fifteenMinutes: 1.4), thermalState: .nominal,
            systemUptime: 92_000, startupVolume: .init(name: "Startup disk", totalBytes: 500_000_000_000, availableBytes: 128_000_000_000),
            memoryPressure: .normal, storageSampledAt: state == .stale ? now.addingTimeInterval(-86_400) : now)
    }
    static func network(_ state: State) -> NetworkActivityReadings {
        guard state == .ready || state == .stale else { return NetworkActivityReadings() }
        return NetworkActivityReadings(interfaces: [.init(name: "en0", receivedBytesPerSecond: 2_400_000,
            sentBytesPerSecond: 148_000, addresses: ["192.0.2.10", "fe80::123%en0"]),
            .init(name: "awdl0", receivedBytesPerSecond: 0, sentBytesPerSecond: 0, addresses: ["fe80::456%awdl0"]),
            .init(name: "utun4", receivedBytesPerSecond: 0, sentBytesPerSecond: 0, addresses: [])], updatedAt: state == .stale ? now.addingTimeInterval(-86_400) : now,
            downloadHistory: [1, 4, 3, 8, 5, 4, 7, 6], uploadHistory: [1, 2, 1, 3, 2, 4, 2, 3],
            hasCompletedRateSample: true, aggregateDownloadRate: 2_400_000, aggregateUploadRate: 148_000)
    }

    static func face(kind: String, state: State, layout: WidgetLayout, width: CGFloat, store: ProfileStore, profileID: UUID) -> some View {
        let item = item(kind, state: state)
        return WidgetProviderRegistry.provider(for: kind).compactView(store: store, item: item, profileID: profileID)
            .environment(\.widgetLayout, layout).environment(\.dockWidgetContentWidth, width)
            .environment(\.systemActivityFixture, system(state)).environment(\.networkActivityFixture, network(state))
            .frame(width: width, height: 54)
    }
}

extension PremiumVisualQA {
    static func exportFacesBUI(to directory: URL, store: ProfileStore) async throws {
        precondition(AppRuntimeEnvironment.isIsolated)
        let profileID = try store.createProfileAndPersist(kind: .custom, name: "Faces B fixtures")
        var matrix = WidgetQAMatrix()
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            for surface in DockWidgetSurface.allCases {
                for kind in FacesBQA.families {
                    let options = WidgetPresentationCatalog.options(for: kind)
                    try await render(FacesBQAPage(title: "\(kind) · \(surface.rawValue) · \(suffix)") {
                        ForEach(FacesBQA.State.allCases, id: \.self) { state in
                            FacesBQAGroup(title: state.rawValue) {
                                ForEach(options) { option in
                                    VStack(spacing: 6) {
                                        Text(option.title).font(DockDesign.Module.label)
                                        WidgetContainer(width: option.width, kind: kind) {
                                            FacesBQA.face(kind: kind, state: state, layout: option.layout, width: option.width, store: store, profileID: profileID)
                                        }
                                    }
                                }
                            }
                        }
                        FacesBQAGroup(title: "Side Dock · 54 pt") {
                            ForEach(options) { option in
                                WidgetContainer(width: 54, kind: kind) {
                                    FacesBQA.face(kind: kind, state: .ready, layout: option.layout, width: 54, store: store, profileID: profileID)
                                }
                            }
                        }
                        FacesBQAGroup(title: "Labels hidden") {
                            ForEach(options) { option in
                                WidgetContainer(width: option.width, kind: kind) {
                                    FacesBQA.face(kind: kind, state: .ready, layout: option.layout, width: option.width, store: store, profileID: profileID)
                                }.environment(\.widgetShowsLabel, false)
                            }
                        }
                        FacesBQAGroup(title: "Gallery samples") {
                            ForEach(options) { option in WidgetCardPreview(kind: kind, width: option.width, layout: option.layout) }
                        }
                    }.environment(\.dockWidgetSurface, surface), name: "facesb-\(slug(kind))-\(surface.rawValue)-\(suffix)",
                        size: NSSize(width: 700, height: 880), scheme: scheme, directory: directory)
                    for option in options { matrix.record(kind, .layout(option.layout)) }
                    matrix.record(kind, .setup)
                }
                for mode in ["reduce-transparency", "increase-contrast"] {
                    try await render(FacesBQAPage(title: "\(mode) · \(surface.rawValue) · \(suffix)") {
                        ForEach(FacesBQA.families, id: \.self) { kind in
                            FacesBQAGroup(title: kind) {
                                ForEach(WidgetPresentationCatalog.options(for: kind)) { option in
                                    WidgetContainer(width: option.width, kind: kind) {
                                        FacesBQA.face(kind: kind, state: .ready, layout: option.layout, width: option.width, store: store, profileID: profileID)
                                    }
                                }
                            }
                        }
                    }.environment(\.dockWidgetSurface, surface), name: "facesb-\(mode)-\(surface.rawValue)-\(suffix)",
                        size: NSSize(width: 700, height: 1120), scheme: scheme, directory: directory,
                        contrast: mode == "increase-contrast" ? .increased : .standard, reduceTransparency: mode == "reduce-transparency")
                }
            }
            for kind in FacesBQA.families {
                for state in FacesBQA.State.allCases {
                    let item = FacesBQA.item(kind, state: state)
                    store.add(item, to: profileID)
                    let naturalSize = facesBPopoutSize(store: store, item: item, profileID: profileID, state: state, scheme: scheme, fullContentForQA: true)
                    let inspectionSize = facesBPopoutSize(store: store, item: item, profileID: profileID, state: state, scheme: scheme, fullContentForQA: true)
                    try await render(FacesBQAPopout(store: store, item: item, profileID: profileID, fullContentForQA: true)
                        .environment(\.systemActivityFixture, FacesBQA.system(state))
                        .environment(\.networkActivityFixture, FacesBQA.network(state)),
                        name: "facesb-popout-\(slug(kind))-\(state.rawValue)-\(suffix)",
                        size: naturalSize, scheme: scheme, directory: directory)
                    try await render(FacesBQAPopout(store: store, item: item, profileID: profileID, fullContentForQA: true)
                        .environment(\.systemActivityFixture, FacesBQA.system(state))
                        .environment(\.networkActivityFixture, FacesBQA.network(state)),
                        name: "facesb-popout-content-\(slug(kind))-\(state.rawValue)-\(suffix)",
                        size: inspectionSize, scheme: scheme, directory: directory)
                    // Default-height shipping sheet, plus a taller export to inspect all embedded content.
                    try await render(WidgetConfigurationSheet(store: store, item: item, profileID: profileID)
                        .environment(\.systemActivityFixture, FacesBQA.system(state))
                        .environment(\.networkActivityFixture, FacesBQA.network(state)),
                        name: "facesb-sheet-\(slug(kind))-\(state.rawValue)-\(suffix)",
                        size: NSSize(width: 504, height: 640), scheme: scheme, directory: directory)
                    try await render(WidgetConfigurationSheet(store: store, item: item, profileID: profileID, maximumHeight: 1800)
                        .environment(\.systemActivityFixture, FacesBQA.system(state))
                        .environment(\.networkActivityFixture, FacesBQA.network(state)),
                        name: "facesb-sheet-content-\(slug(kind))-\(state.rawValue)-\(suffix)",
                        size: NSSize(width: 504, height: 1800), scheme: scheme, directory: directory)
                    if state == .ready {
                        for mode in ["reduce-transparency", "increase-contrast"] {
                            try await render(FacesBQAPopout(store: store, item: item, profileID: profileID, fullContentForQA: true)
                                .environment(\.systemActivityFixture, FacesBQA.system(state))
                                .environment(\.networkActivityFixture, FacesBQA.network(state)),
                                name: "facesb-popout-\(slug(kind))-\(mode)-\(suffix)",
                                size: naturalSize, scheme: scheme, directory: directory,
                                contrast: mode == "increase-contrast" ? .increased : .standard,
                                reduceTransparency: mode == "reduce-transparency")
                            try await render(WidgetConfigurationSheet(store: store, item: item, profileID: profileID)
                                .environment(\.systemActivityFixture, FacesBQA.system(state))
                                .environment(\.networkActivityFixture, FacesBQA.network(state)),
                                name: "facesb-sheet-\(slug(kind))-\(mode)-\(suffix)",
                                size: NSSize(width: 504, height: 640), scheme: scheme, directory: directory,
                                contrast: mode == "increase-contrast" ? .increased : .standard,
                                reduceTransparency: mode == "reduce-transparency")
                        }
                    }
                }
            }
        }
        try matrix.validate(registry: WidgetRegistry.all.filter { FacesBQA.families.contains($0.name) })
    }
    private static func facesBPopoutSize(store: ProfileStore, item: DockItem, profileID: UUID, state: FacesBQA.State,
                                         scheme: ColorScheme, fullContentForQA: Bool = false) -> NSSize {
        let host = NSHostingView(rootView: WidgetPopout(store: store, item: item, profileID: profileID)
            .environment(\.systemActivityFixture, FacesBQA.system(state))
            .environment(\.networkActivityFixture, FacesBQA.network(state))
            .environment(\.dockSnapshotRendering, true).environment(\.colorScheme, scheme))
        let content = host.fittingSize
        // render() uses a titled NSWindow. Its safe area sits inside the exported bitmap;
        // include that measured inset so the final Settings row and shell padding remain visible.
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: content),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.isReleasedWhenClosed = false
        let safeAreaHeight = window.frame.height - window.contentLayoutRect.height
        window.close()
        let maximum = FacesBQAPopout(store: store, item: item, profileID: profileID, fullContentForQA: fullContentForQA).maximumHeight
        return NSSize(width: ceil(content.width), height: min(maximum, max(150, ceil(content.height + safeAreaHeight))))
    }
    private static func slug(_ kind: String) -> String { kind.lowercased().replacingOccurrences(of: " ", with: "-") }
}

private struct FacesBQAPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(DockDesign.Module.labelLarge)
            content
            Spacer(minLength: 0)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(LinearGradient(colors: [Color(nsColor: .windowBackgroundColor), Color.primary.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}
private struct FacesBQAGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DockDesign.Module.label).foregroundStyle(.secondary)
            HStack(spacing: 16) { content }
        }
    }
}
/// The shipping single-widget popover host, including its scroll view and current outer chrome.
/// Matrix captures lift only its display-height cap to inspect the entire natural-height content.
/// Changes to CustomDockView's host must be reflected here by the shell owner.
private struct FacesBQAPopout: View {
    var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    /// Inspection export only; the default uses CustomDockView's screen-dependent scroll cap.
    var fullContentForQA = false
    var maximumHeight: CGFloat {
        if fullContentForQA { return 1500 }
        let selectedDisplayID = store.effectiveSettings(profileID: profileID).customDockDisplayID
        let screen = DockDisplaySelection.screen(selectedID: selectedDisplayID).screen
        let visibleHeight = screen?.visibleFrame.height ?? 720
        return min(600, max(180, visibleHeight - 160))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DockScrollView(.vertical) {
                WidgetPopout(store: store, item: item, profileID: profileID)
                    .frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
            }
        }
        .modifier(DockPopoutAppearEffect(anchor: .bottom, progress: 1))
        .modifier(WidgetPopoverSurface())
        // NSWindow bitmap exports need the native popover's backing colour; the real shell remains inside.
        .background(WidgetDesign.surface)
        .frame(minWidth: 250, minHeight: 150, maxHeight: maximumHeight, alignment: .topLeading)
        .id(item.id)
    }
}
#endif
