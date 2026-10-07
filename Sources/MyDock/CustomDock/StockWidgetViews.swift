import AppKit
import SwiftUI

struct StockWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StockCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StockPopoutView(store: store, item: item, profileID: profileID))
    }
}

struct WatchlistWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WatchlistCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WatchlistPopoutView(store: store, item: item, profileID: profileID))
    }
}

struct StockCompactView: View {
    var item: DockItem
    var body: some View { LocalWidgetDockFace(item: item) }
}

struct WatchlistCompactView: View {
    var item: DockItem
    var body: some View { LocalWidgetDockFace(item: item) }
}

enum StockFaceFormatting {
    /// Market data names each trading session by its calendar day, stored as UTC midnight. Formatting it in UTC keeps
    /// the session's own day; the Mac's time zone would show the previous day everywhere west of UTC.
    static func sessionDate(_ date: Date, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: Calendar(identifier: .gregorian))
        style.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return date.formatted(style)
    }

    static func percentText(_ percent: Double, fractionLength: Int = 2, locale: Locale = .current) -> String {
        (percent / 100).formatted(.percent.precision(.fractionLength(fractionLength)).sign(strategy: .always()).locale(locale))
    }
    /// The Dock face's change: one decimal, in the Mac's number format, e.g. "+1.2%" or "+1,2 %".
    static func faceChangeText(_ percent: Double?, locale: Locale = .current) -> String? {
        guard let percent, percent.isFinite else { return nil }
        return percentText(percent, fractionLength: 1, locale: locale)
    }
    static func changeText(_ change: Double, percent: Double, locale: Locale = .current) -> String {
        change.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()).locale(locale))
            + " (" + percentText(percent, locale: locale) + ")"
    }
    static func changeColor(_ change: Double?) -> Color {
        guard let change, change.isFinite, change < 0 else { return .secondary }
        return WidgetPalette.critical
    }
    /// The one line under the price: an end-of-day close, and a change that compares one session, not the range.
    static func closeCaption(_ date: Date, locale: Locale = .current) -> String {
        "Close · " + sessionDate(date, locale: locale) + " · 1-day change"
    }
    /// The shown range's own change, which colours its chart: the last close against the first.
    static func rangeChange(_ points: [StockMarketPoint]) -> Double? {
        guard points.count > 1, let first = points.first?.close, let last = points.last?.close else { return nil }
        return last - first
    }
}

/// What the Stock and Watchlist popouts share: the key read, the Yahoo Finance link, the display options and the copy.
enum MarketPopoutSupport {
    static let footer = "End-of-day quotes from Alpha Vantage."
    static let help = "Ranges count trading sessions, up to 100 daily closes; change compares the latest two sessions. Standard-plan quotes are end of day, and request limits depend on your Alpha Vantage plan."

    static func requiredAPIKey() throws -> String {
        guard let key = try MarketAPIKeyStore.read(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarketDataError.missingAPIKey
        }
        return key
    }

    @MainActor static func openFinance(_ symbol: String) {
        guard AppRuntimeEnvironment.allowsNativeEffects, let url = MarketFinanceURL.url(for: symbol) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Range, update interval and volume, as rows of the caller's grouped section.
    @MainActor @ViewBuilder
    static func displayOptionRows(range: Binding<StockChartRange>, interval: Binding<Int>, showsVolume: Binding<Bool>) -> some View {
        GroupedRow("Range", symbol: "chart.xyaxis.line") {
            Picker("Range", selection: range) {
                ForEach(StockChartRange.allCases) { Text($0.title).tag($0) }
            }.labelsHidden()
        }
        GroupedRow("Update interval", symbol: "arrow.clockwise") {
            Picker("Update interval", selection: interval) {
                Text("1 hour").tag(60); Text("3 hours").tag(180); Text("6 hours").tag(360)
                Text("12 hours").tag(720); Text("24 hours").tag(1_440)
            }.labelsHidden()
        }
        GroupedRow("Volume", symbol: "chart.bar", isOn: showsVolume)
    }
}

enum StockFaceSample {
    static func item(kind: String) -> DockItem {
        var item = DockItem.widget(kind)
        let snapshot = StockMarketSnapshot(symbol: "AAPL", points: [181.2, 182.5, 181.8, 185.1, 184.3, 186.2, 185.9].enumerated().map { index, value in
            StockMarketPoint(date: .now.addingTimeInterval(Double(index - 6) * 86400), close: value, volume: 0)
        }, currency: "USD", fetchedAt: .now)
        item.widgetConfiguration?.stockSymbol = "AAPL"
        item.widgetConfiguration?.stockSnapshot = snapshot
        item.widgetConfiguration?.watchlistStocks = [WatchlistStock(symbol: "AAPL", name: "Apple", currency: "USD", snapshot: snapshot)]
        item.widgetConfiguration?.watchlistSelectedSymbol = "AAPL"
        return item
    }
}

private struct StockPopoutView: View {
    @ObservedObject var store: ProfileStore
    /// The coordinator owns the market refresh; the popout reads its loading state instead of keeping its own.
    @ObservedObject private var coordinator: WidgetDataCoordinator
    var item: DockItem
    var profileID: UUID
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private var snapshotRendering: Bool { false }
    #endif
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var searchText = ""
    @State private var searchResults: [MarketSymbol] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchRequestID = UUID()

    init(store: ProfileStore, item: DockItem, profileID: UUID) {
        self.store = store; self.item = item; self.profileID = profileID
        coordinator = store.widgetData
    }

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }
    private var isRefreshing: Bool {
        WidgetDataQuery.make(kind: "Stock", configuration: configuration).map { coordinator.refreshing.contains($0) } ?? false
    }
    /// "AAPL · Apple": the ticker this popout reads, with the display name when there is one.
    private var stockIdentity: String {
        let name = configuration.stockName.trimmingCharacters(in: .whitespacesAndNewlines)
        return configuration.stockSymbol + (name.isEmpty ? "" : " · " + name)
    }
    private var currentConfiguration: WidgetConfiguration? {
        store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id && $0.widgetKind == "Stock" })?.widgetConfiguration
    }
    private var snapshot: StockMarketSnapshot? { configuration.stockSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                if configuration.stockSymbol.isEmpty {
                    WidgetPopoutHero(value: "Choose a ticker", caption: "Search by ticker or company name.")
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(stockIdentity)
                            .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1).widgetPopoutHeroAligned()
                        chartContent
                    }
                    GroupedSection {
                        GroupedRow("Open on Yahoo Finance", role: .button, symbol: "arrow.up.right") {
                            MarketPopoutSupport.openFinance(configuration.stockSymbol)
                        }
                    }
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning)
            }
            if configuration.stockSymbol.isEmpty { controls } else { WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) { controls } }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: "\(configuration.stockSymbol)|\(configuration.stockCurrency)|\(configuration.stockRefreshIntervalMinutes)") {
            guard !snapshotRendering, !configuration.stockSymbol.isEmpty else { return }
            await refresh()
        }
        .onChange(of: "\(configuration.stockSymbol)|\(configuration.stockCurrency)") { _ in
            errorMessage = nil
        }
        .onChange(of: searchText) { _ in
            searchRequestID = UUID()
            searchResults = []
            isSearching = false
        }
        .onDisappear {
            searchRequestID = UUID()
            isSearching = false
        }
    }

    private var resultsList: some View {
        DockScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { result in
                    Button {
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
                            if $0.stockSymbol != result.symbol || $0.stockCurrency != result.currency {
                                $0.stockSnapshot = nil
                            }
                            $0.stockSymbol = result.symbol
                            $0.stockName = result.name
                            $0.stockCurrency = result.currency
                        }
                        searchResults = []
                        searchText = ""
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.symbol).font(.callout.weight(.semibold))
                                Text(result.name).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(result.region).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                            Image(systemName: "plus.circle").foregroundStyle(.tint)
                        }
                        .contentShape(Rectangle()).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 130)
        .padding(.horizontal, 8)

    }

    @ViewBuilder private var chartContent: some View {
        if let snapshot, let latest = snapshot.latest {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(latest.close.formatted(.currency(code: snapshot.currency)))
                        .font(DockDesign.Module.valueLarge)
                    if let change = snapshot.change, let percent = snapshot.changePercent {
                        Text(StockFaceFormatting.changeText(change, percent: percent))
                            .font(DockDesign.Grouped.subtitleFont.weight(.medium)).foregroundStyle(StockFaceFormatting.changeColor(change))
                    }
                }
                .widgetPopoutHeroAligned()
                Text(StockFaceFormatting.closeCaption(latest.date))
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).widgetPopoutHeroAligned()
                let visiblePoints = Array(snapshot.points.suffix(configuration.stockRange.pointCount))
                MarketSparkline(points: visiblePoints,
                                color: StockFaceFormatting.changeColor(StockFaceFormatting.rangeChange(visiblePoints)),
                                currency: snapshot.currency, showsVolume: configuration.stockShowsVolume)
                    .frame(height: 100)
                HStack {
                    Text(visiblePoints.first.map { StockFaceFormatting.sessionDate($0.date) } ?? "")
                    Spacer()
                    Text(StockFaceFormatting.sessionDate(latest.date))
                }
                .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                if configuration.stockShowsVolume {
                    Text("Volume \(latest.volume.formatted())").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                }
            }
        } else if isRefreshing {
            ProgressView("Loading market data…").frame(maxWidth: .infinity, minHeight: 100)
        } else {
            Label("No saved market data", systemImage: "chart.xyaxis.line")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 100)
        }
    }

    private var controls: some View {
        GroupedSection(footer: MarketPopoutSupport.footer) {
            GroupedRow("Search") {
                HStack(spacing: 8) {
                    TextField("Ticker or company", text: $searchText).textFieldStyle(.plain)
                        .onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: {
                        if isSearching { ProgressView().controlSize(.small) }
                        else { Image(systemName: "magnifyingglass") }
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    .help("Search market symbols").accessibilityLabel("Search market symbols")
                }
            }
            if !configuration.stockSymbol.isEmpty {
                GroupedRow("Display name", subtitle: configuration.stockSymbol) {
                    TextField("Display name", text: stockNameBinding).textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Display name for \(configuration.stockSymbol)")
                }
            }
            if !searchResults.isEmpty { resultsList }

            if !configuration.stockSymbol.isEmpty {
                MarketPopoutSupport.displayOptionRows(range: rangeBinding, interval: intervalBinding, showsVolume: volumeBinding)
            }
        }
        .help(MarketPopoutSupport.help)
    }

    private func search() async {
        let requestID = UUID()
        searchRequestID = requestID
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true
        errorMessage = nil
        defer { if searchRequestID == requestID { isSearching = false } }
        do {
            let results = try await AlphaVantageMarketProvider().search(query, apiKey: try MarketPopoutSupport.requiredAPIKey())
            guard searchRequestID == requestID,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                  currentConfiguration != nil, !Task.isCancelled else { return }
            searchResults = results
        } catch {
            guard searchRequestID == requestID,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                  currentConfiguration != nil, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Opening the popout loads only a reading older than the update interval; the refresh button forces a fetch.
    /// Market data keys allow few requests a day.
    private func refresh() async {
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID, force: false)
    }

    private var rangeBinding: Binding<StockChartRange> {
        Binding(get: { configuration.stockRange }, set: { value in update { $0.stockRange = value } })
    }
    private var intervalBinding: Binding<Int> {
        Binding(get: { configuration.stockRefreshIntervalMinutes }, set: { value in update { $0.stockRefreshIntervalMinutes = value } })
    }
    private var volumeBinding: Binding<Bool> {
        Binding(get: { configuration.stockShowsVolume }, set: { value in update { $0.stockShowsVolume = value } })
    }

    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }

    /// Stored as typed (spaces between words survive); the popout trims it where it shows it.
    private var stockNameBinding: Binding<String> {
        Binding(get: { configuration.stockName }, set: { value in update { $0.stockName = String(value.prefix(120)) } })
    }
}

private struct WatchlistPopoutView: View {
    @ObservedObject var store: ProfileStore
    /// The coordinator owns the market refresh; the popout reads its loading state instead of keeping its own.
    @ObservedObject private var coordinator: WidgetDataCoordinator
    var item: DockItem
    var profileID: UUID
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private var snapshotRendering: Bool { false }
    #endif
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @State private var showsSettings = false
    @State private var searchText = ""
    @State private var searchResults: [MarketSymbol] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var searchRequestID = UUID()

    init(store: ProfileStore, item: DockItem, profileID: UUID) {
        self.store = store; self.item = item; self.profileID = profileID
        coordinator = store.widgetData
    }

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }
    private var isRefreshing: Bool {
        WidgetDataQuery.make(kind: "Watchlist", configuration: configuration).map { coordinator.refreshing.contains($0) } ?? false
    }
    private var currentConfiguration: WidgetConfiguration? {
        store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id && $0.widgetKind == "Watchlist" })?.widgetConfiguration
    }
    /// The saved selection, or the first ticker when it is empty or missing: the same stock the Dock face shows.
    private var selected: WatchlistStock? {
        configuration.watchlistStocks.first { $0.symbol == configuration.watchlistSelectedSymbol } ?? configuration.watchlistStocks.first
    }
    private var interval: Int { configuration.stockRefreshIntervalMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsHero {
                if configuration.watchlistStocks.isEmpty {
                    WidgetPopoutHero(value: "Your watchlist is empty", caption: "Search for a ticker to add it.")
                } else {
                    if let selected { selectedChart(selected) }
                    watchlistTabs
                }
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(WidgetPalette.warning)
            }
            if configuration.watchlistStocks.isEmpty { controls } else { WidgetPopoutSettingsDisclosure(isExpanded: $showsSettings) { controls } }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: "\(selected?.symbol ?? "")|\(selected?.currency ?? "")|\(interval)") {
            guard !snapshotRendering, selected != nil else { return }
            await refreshWatchlist()
        }
        .onChange(of: "\(selected?.symbol ?? "")|\(selected?.currency ?? "")") { _ in
            errorMessage = nil
        }
        .onChange(of: searchText) { _ in
            searchRequestID = UUID()
            searchResults = []
            isSearching = false
        }
        .onDisappear {
            searchRequestID = UUID()
            isSearching = false
        }
    }

    private var searchResultsList: some View {
        DockScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { result in
                    Button { add(result) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.symbol).font(.callout.weight(.semibold))
                                Text(result.name).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: configuration.watchlistStocks.contains(where: { $0.symbol == result.symbol }) ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(.tint)
                        }
                        .contentShape(Rectangle()).padding(.vertical, 7)
                    }
                    .buttonStyle(.plain).disabled(configuration.watchlistStocks.contains(where: { $0.symbol == result.symbol }))
                    Divider()
                }
            }
        }
        .frame(maxHeight: 120).padding(.horizontal, 8)

    }

    private var watchlistTabs: some View {
        DockScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                ForEach(configuration.watchlistStocks) { stock in
                    Button { update { $0.watchlistSelectedSymbol = stock.symbol } } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(stock.symbol).font(.callout.weight(.semibold)).lineLimit(1)
                            Text(stock.displayName).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                            if let snapshot = stock.snapshot, let latest = snapshot.latest {
                                Text(latest.close.formatted(.currency(code: snapshot.currency)))
                                    .font(DockDesign.Grouped.subtitleFont.monospacedDigit()).lineLimit(1)
                            } else {
                                Text("No quote").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(width: 112, alignment: .leading)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .overlay(alignment: .bottom) {
                            if selected?.symbol == stock.symbol {
                                Capsule().fill(Color.primary).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stock.displayName), \(stock.symbol)")
                    .accessibilityAddTraits(selected?.symbol == stock.symbol ? .isSelected : [])
                    // The context menu's commands, named for VoiceOver's Actions rotor.
                    .accessibilityAction(named: "Move Earlier") { move(stock.symbol, by: -1) }
                    .accessibilityAction(named: "Move Later") { move(stock.symbol, by: 1) }
                    .accessibilityAction(named: "Remove \(stock.symbol)") { remove(stock.symbol) }
                    .contextMenu {
                        Button("Move Earlier", systemImage: "arrow.left") { move(stock.symbol, by: -1) }
                            .disabled(configuration.watchlistStocks.first?.symbol == stock.symbol)
                        Button("Move Later", systemImage: "arrow.right") { move(stock.symbol, by: 1) }
                            .disabled(configuration.watchlistStocks.last?.symbol == stock.symbol)
                        Divider()
                        Button("Remove \(stock.symbol)", systemImage: "trash", role: .destructive) { remove(stock.symbol) }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity).frame(height: 96)
        .help("Choose a ticker. Open a ticker's context menu to change its order or remove it.")
    }

    @ViewBuilder private func selectedChart(_ stock: WatchlistStock) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(stock.symbol + " · " + stock.displayName)
                .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).widgetPopoutHeroAligned()
            if let snapshot = stock.snapshot, let latest = snapshot.latest {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(latest.close.formatted(.currency(code: snapshot.currency))).font(DockDesign.Module.valueLarge)
                        // The same change and percent as the Stock popout.
                        if let change = snapshot.change, let percent = snapshot.changePercent {
                            Text(StockFaceFormatting.changeText(change, percent: percent))
                                .font(DockDesign.Grouped.subtitleFont.weight(.medium)).foregroundStyle(StockFaceFormatting.changeColor(change))
                        }
                    }
                    .widgetPopoutHeroAligned()
                    Text(StockFaceFormatting.closeCaption(latest.date))
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).widgetPopoutHeroAligned()
                    let visiblePoints = Array(snapshot.points.suffix(configuration.stockRange.pointCount))
                    MarketSparkline(points: visiblePoints,
                                    color: StockFaceFormatting.changeColor(StockFaceFormatting.rangeChange(visiblePoints)),
                                    currency: snapshot.currency, showsVolume: configuration.stockShowsVolume)
                        .frame(height: 72)
                    Text("\(visiblePoints.count) trading sessions · \(visiblePoints.first.map { StockFaceFormatting.sessionDate($0.date) } ?? "")–\(StockFaceFormatting.sessionDate(latest.date))")
                        .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                    if configuration.stockShowsVolume { Text("Volume \(latest.volume.formatted())").font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary) }
                }
            } else if isRefreshing {
                ProgressView("Loading \(stock.symbol)…").frame(maxWidth: .infinity, minHeight: 75)
            } else {
                Label("No saved quote for \(stock.symbol)", systemImage: "chart.xyaxis.line")
                    .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 75)
            }
            GroupedSection {
                GroupedRow("Open on Yahoo Finance", role: .button, symbol: "arrow.up.right") { MarketPopoutSupport.openFinance(stock.symbol) }
            }
        }
    }

    private var controls: some View {
        GroupedSection(footer: MarketPopoutSupport.footer) {
            GroupedRow("Search") {
                HStack(spacing: 8) {
                    TextField("Ticker or company", text: $searchText).textFieldStyle(.plain)
                        .onSubmit { Task { await search() } }
                    Button { Task { await search() } } label: {
                        if isSearching { ProgressView().controlSize(.small) }
                        else { Image(systemName: "magnifyingglass") }
                    }
                    .buttonStyle(.borderless)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    .help("Search market symbols").accessibilityLabel("Search market symbols")
                }
            }
            if let selected {
                GroupedRow("Display name", subtitle: selected.symbol) {
                    TextField("Display name", text: displayNameBinding(for: selected))
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .accessibilityLabel("Display name for \(selected.symbol)")
                }
                // Removing is also reachable without the tab's context menu, for keyboard users.
                GroupedRow("Remove \(selected.symbol)", role: .destructive, symbol: "trash") { remove(selected.symbol) }
            }
            if !searchResults.isEmpty { searchResultsList }

            if !configuration.watchlistStocks.isEmpty {
                MarketPopoutSupport.displayOptionRows(range: rangeBinding, interval: intervalBinding, showsVolume: volumeBinding)
            }
        }
        .help(MarketPopoutSupport.help)
    }

    private func search() async {
        let requestID = UUID()
        searchRequestID = requestID
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true
        errorMessage = nil
        defer { if searchRequestID == requestID { isSearching = false } }
        do {
            let results = try await AlphaVantageMarketProvider().search(query, apiKey: try MarketPopoutSupport.requiredAPIKey())
            guard searchRequestID == requestID,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                  currentConfiguration != nil, !Task.isCancelled else { return }
            searchResults = results
        } catch {
            guard searchRequestID == requestID,
                  query == searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                  currentConfiguration != nil, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// One query loads every symbol, so opening the popout or switching symbol loads only a reading older than the
    /// update interval; the refresh button forces a fetch.
    private func refreshWatchlist() async {
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID, force: false)
    }

    private func add(_ result: MarketSymbol) {
        update { configuration in
            guard !configuration.watchlistStocks.contains(where: { $0.symbol == result.symbol }) else { return }
            configuration.watchlistStocks.append(WatchlistStock(symbol: result.symbol, name: result.name,
                                                                currency: result.currency, snapshot: nil))
            if configuration.watchlistSelectedSymbol.isEmpty { configuration.watchlistSelectedSymbol = result.symbol }
        }
        searchResults = []
        searchText = ""
    }

    private func remove(_ symbol: String) {
        update { configuration in
            configuration.watchlistStocks.removeAll { $0.symbol == symbol }
            if configuration.watchlistSelectedSymbol == symbol {
                configuration.watchlistSelectedSymbol = configuration.watchlistStocks.first?.symbol ?? ""
            }
        }
    }

    private func move(_ symbol: String, by offset: Int) {
        update { configuration in
            guard let index = configuration.watchlistStocks.firstIndex(where: { $0.symbol == symbol }) else { return }
            let destination = index + offset
            guard configuration.watchlistStocks.indices.contains(destination) else { return }
            configuration.watchlistStocks.swapAt(index, destination)
        }
    }

    private func displayNameBinding(for stock: WatchlistStock) -> Binding<String> {
        Binding(get: {
            configuration.watchlistStocks.first(where: { $0.symbol == stock.symbol })?.customName ?? ""
        }, set: { value in
            update { configuration in
                guard let index = configuration.watchlistStocks.firstIndex(where: { $0.symbol == stock.symbol }) else { return }
                let trimmed = String(value.prefix(120)).trimmingCharacters(in: .whitespacesAndNewlines)
                configuration.watchlistStocks[index].customName = trimmed.isEmpty ? nil : trimmed
            }
        })
    }

    private var rangeBinding: Binding<StockChartRange> {
        Binding(get: { configuration.stockRange }, set: { value in update { $0.stockRange = value } })
    }
    private var intervalBinding: Binding<Int> {
        Binding(get: { configuration.stockRefreshIntervalMinutes }, set: { value in update { $0.stockRefreshIntervalMinutes = value } })
    }
    private var volumeBinding: Binding<Bool> {
        Binding(get: { configuration.stockShowsVolume }, set: { value in update { $0.stockShowsVolume = value } })
    }

    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }
}

private struct MarketSparkline: View {
    var points: [StockMarketPoint]
    /// The shown range's direction, not the last session's.
    var color: Color
    var currency: String
    /// Volume shows in the tooltip and for VoiceOver only when the Volume setting is on.
    var showsVolume: Bool
    @State private var selectedIndex: Int?

    var body: some View {
        GeometryReader { geometry in
            let values = points.map(\.close)
            let lower = values.min() ?? 0
            let upper = values.max() ?? 1
            let span = max(upper - lower, max(abs(upper) * 0.002, 0.01))
            ZStack(alignment: .topLeading) {
                Path { path in
                    guard !values.isEmpty else { return }
                    for (index, value) in values.enumerated() {
                        let x = values.count == 1 ? geometry.size.width / 2 : geometry.size.width * CGFloat(index) / CGFloat(values.count - 1)
                        let y = geometry.size.height * (1 - CGFloat((value - lower) / span))
                        if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                if let selectedIndex, points.indices.contains(selectedIndex) {
                    let point = points[selectedIndex]
                    let x = points.count == 1 ? geometry.size.width / 2
                        : geometry.size.width * CGFloat(selectedIndex) / CGFloat(points.count - 1)
                    let y = geometry.size.height * (1 - CGFloat((point.close - lower) / span))
                    Rectangle().fill(color.opacity(0.45)).frame(width: 1)
                        .position(x: x, y: geometry.size.height / 2)
                    Circle().fill(color).frame(width: 7, height: 7).position(x: x, y: y)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(StockFaceFormatting.sessionDate(point.date))
                        Text(point.close.formatted(.currency(code: currency)))
                            .fontWeight(.semibold)
                        if showsVolume { Text("Volume \(point.volume.formatted())") }
                    }
                    .font(DockDesign.Module.label)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .dockGlass(.regular, in: RoundedRectangle(cornerRadius: 5))
                    .position(x: min(max(x, 60), max(60, geometry.size.width - 60)), y: 24)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    selectedIndex = MarketChartSelection.index(forX: location.x,
                                                                width: geometry.size.width,
                                                                pointCount: points.count)
                case .ended:
                    selectedIndex = nil
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    selectedIndex = MarketChartSelection.index(forX: value.location.x,
                                                                width: geometry.size.width,
                                                                pointCount: points.count)
                }
            )
        }
        .onChange(of: points) { _ in selectedIndex = nil }
        .accessibilityElement()
        .accessibilityLabel("Stock price chart")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(showsVolume ? "Use the increment and decrement actions to inspect dates, closing prices, and volume."
                                       : "Use the increment and decrement actions to inspect dates and closing prices.")
        .accessibilityAdjustableAction { direction in
            guard !points.isEmpty else { return }
            let current = selectedIndex ?? (points.count - 1)
            switch direction {
            case .increment: selectedIndex = min(current + 1, points.count - 1)
            case .decrement: selectedIndex = max(current - 1, 0)
            @unknown default: break
            }
        }
    }

    private var accessibilityValue: String {
        guard let selectedIndex, points.indices.contains(selectedIndex) else {
            guard let latest = points.last else { return "No chart data" }
            return "Latest: " + describe(latest)
        }
        return describe(points[selectedIndex])
    }

    private func describe(_ point: StockMarketPoint) -> String {
        "\(StockFaceFormatting.sessionDate(point.date)), \(point.close.formatted(.currency(code: currency)))"
            + (showsVolume ? ", volume \(point.volume.formatted())" : "")
    }
}

enum MarketChartSelection {
    static func index(forX x: CGFloat, width: CGFloat, pointCount: Int) -> Int? {
        guard pointCount > 0, x.isFinite, width.isFinite, width > 0 else { return nil }
        guard pointCount > 1 else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        return Int((fraction * CGFloat(pointCount - 1)).rounded())
    }
}
