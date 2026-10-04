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
    static func changeColor(_ change: Double?) -> Color {
        guard let change, change.isFinite, change < 0 else { return .secondary }
        return WidgetPalette.critical
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
    var item: DockItem
    var profileID: UUID
    @State private var searchText = ""
    @State private var searchResults: [MarketSymbol] = []
    @State private var isSearching = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var searchRequestID = UUID()
    @State private var refreshRequestID = UUID()

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }
    private var currentConfiguration: WidgetConfiguration? {
        store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id && $0.widgetKind == "Stock" })?.widgetConfiguration
    }
    private var snapshot: StockMarketSnapshot? { configuration.stockSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupedSection {
                GroupedRow("Search") {
                    HStack {
                        TextField("Search ticker or company", text: $searchText)
                            .textFieldStyle(DockTextFieldStyle())
                            .onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: {
                            if isSearching { ProgressView().controlSize(.small) }
                            else { Image(systemName: "magnifyingglass") }
                        }
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                        .help("Search market symbols")
                    }
                }
                GroupedRow("Refresh", role: .button) { Task { await refresh() } }
                    .disabled(configuration.stockSymbol.isEmpty || isRefreshing)
            }
            if !searchResults.isEmpty { resultsList }
            if !configuration.stockSymbol.isEmpty {
                GroupedSection {
                    GroupedRow("Display name") {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Display name", text: stockNameBinding)
                                .font(.subheadline.weight(.semibold)).textFieldStyle(.plain).lineLimit(1)
                            Text(configuration.stockSymbol).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Button("Yahoo Finance", systemImage: "arrow.up.right.square") { openFinance(configuration.stockSymbol) }
                            .labelStyle(.iconOnly)
                            .help("Open \(configuration.stockSymbol) on Yahoo Finance")
                        if isRefreshing { ProgressView().controlSize(.small) }
                    }
                }
                chartContent
                controls
                if let snapshot {
                    Text("End-of-day close: \(snapshot.latest?.date.formatted(date: .abbreviated, time: .omitted) ?? "Unavailable") · fetched \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            } else {
                VStack(spacing: 7) {
                    Label("Choose a ticker", systemImage: "chart.line.uptrend.xyaxis").font(.callout.weight(.medium))
                    Text("Search by ticker or company name to add a stock.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 110)
            }
            if let errorMessage {
                Label(snapshot == nil ? errorMessage : "Showing saved data. \(errorMessage)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text("Market data by Alpha Vantage. Quotes are end of day on the standard plan; request limits depend on your plan.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: "\(configuration.stockSymbol)|\(configuration.stockCurrency)|\(configuration.stockRefreshIntervalMinutes)") {
            guard !configuration.stockSymbol.isEmpty else { return }
            await refresh()
        }
        .onChange(of: "\(configuration.stockSymbol)|\(configuration.stockCurrency)") { _ in
            refreshRequestID = UUID()
            isRefreshing = false
            errorMessage = nil
        }
        .onChange(of: searchText) { _ in
            searchRequestID = UUID()
            searchResults = []
            isSearching = false
        }
        .onDisappear {
            searchRequestID = UUID()
            refreshRequestID = UUID()
            isSearching = false
            isRefreshing = false
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
                                Text(result.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(result.region).font(.caption2).foregroundStyle(.tertiary)
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
                        Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) (\(String(format: "%+.2f%%", percent)))")
                            .font(.caption.weight(.medium)).foregroundStyle(StockFaceFormatting.changeColor(change))
                    }
                }
                let visiblePoints = Array(snapshot.points.suffix(configuration.stockRange.pointCount))
                MarketSparkline(points: visiblePoints,
                                color: StockFaceFormatting.changeColor(snapshot.change),
                                currency: snapshot.currency)
                    .frame(height: 100)
                HStack {
                    Text(visiblePoints.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
                    Spacer()
                    Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption2).foregroundStyle(.tertiary)
                if configuration.stockShowsVolume {
                    Text("Volume \(latest.volume.formatted())").font(.caption).foregroundStyle(.secondary)
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
        GroupedSection("Chart", footer: "D = trading sessions. Up to 100 daily closes; percentage change compares the latest two sessions.") {
            GroupedRow("Range", symbol: "chart.xyaxis.line") {
                Picker("Range", selection: rangeBinding) {
                    ForEach(StockChartRange.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GroupedRow("Refresh", symbol: "arrow.clockwise") {
                Picker("Refresh", selection: refreshIntervalBinding) {
                    Text("1 hour").tag(60); Text("3 hours").tag(180); Text("6 hours").tag(360)
                    Text("12 hours").tag(720); Text("24 hours").tag(1_440)
                }.labelsHidden()
            }
            GroupedRow("Volume", symbol: "chart.bar", isOn: volumeBinding)
        }
    }

    private var rangeBinding: Binding<StockChartRange> {
        Binding(get: { configuration.stockRange }, set: { value in update { $0.stockRange = value } })
    }
    private var refreshIntervalBinding: Binding<Int> {
        Binding(get: { configuration.stockRefreshIntervalMinutes }, set: { value in update { $0.stockRefreshIntervalMinutes = value } })
    }
    private var volumeBinding: Binding<Bool> {
        Binding(get: { configuration.stockShowsVolume }, set: { value in update { $0.stockShowsVolume = value } })
    }

    private func search() async {
        let requestID = UUID()
        searchRequestID = requestID
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true
        errorMessage = nil
        defer { if searchRequestID == requestID { isSearching = false } }
        do {
            let results = try await AlphaVantageMarketProvider().search(query, apiKey: try requiredAPIKey())
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

    private func refresh() async {
        let requestID = UUID()
        refreshRequestID = requestID
        isRefreshing = true
        defer { if refreshRequestID == requestID { isRefreshing = false } }
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID)
        guard refreshRequestID == requestID, !Task.isCancelled else { return }
        if let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: configuration) {
            errorMessage = store.widgetData.errors[query]
        }
    }

    private func requiredAPIKey() throws -> String {
        guard let key = try MarketAPIKeyStore.read(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarketDataError.missingAPIKey
        }
        return key
    }

    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }

    private var stockNameBinding: Binding<String> {
        Binding(get: { configuration.stockName }, set: { value in update { $0.stockName = String(value.prefix(120)) } })
    }

    private func openFinance(_ symbol: String) {
        guard let url = MarketFinanceURL.url(for: symbol) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct WatchlistPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var searchText = ""
    @State private var searchResults: [MarketSymbol] = []
    @State private var isSearching = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?
    @State private var searchRequestID = UUID()
    @State private var refreshRequestID = UUID()

    private var configuration: WidgetConfiguration {
        store.presentationConfiguration(for: item, in: profileID)
    }
    private var currentConfiguration: WidgetConfiguration? {
        store.state.profiles.first(where: { $0.id == profileID })?.items
            .first(where: { $0.id == item.id && $0.widgetKind == "Watchlist" })?.widgetConfiguration
    }
    private var selected: WatchlistStock? { configuration.watchlistStocks.first { $0.symbol == configuration.watchlistSelectedSymbol } }
    private var interval: Int { configuration.stockRefreshIntervalMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupedSection {
                GroupedRow("Search") {
                    HStack {
                        TextField("Search ticker or company", text: $searchText).textFieldStyle(DockTextFieldStyle())
                            .onSubmit { Task { await search() } }
                        Button { Task { await search() } } label: {
                            if isSearching { ProgressView().controlSize(.small) }
                            else { Image(systemName: "magnifyingglass") }
                        }
                        .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                    }
                }
                GroupedRow("Refresh", role: .button) { Task { await refreshSelected() } }
                    .disabled(selected == nil || isRefreshing)
            }
            if !searchResults.isEmpty { searchResultsList }
            if configuration.watchlistStocks.isEmpty {
                VStack(spacing: 7) {
                    Label("Your watchlist is empty", systemImage: "chart.xyaxis.line").font(.callout.weight(.medium))
                    Text("Search for a ticker to add it.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                watchlistTabs
                if let selected { selectedChart(selected) }
            }
            controls
            if let errorMessage {
                Label(selected?.snapshot == nil ? errorMessage : "Showing saved data. \(errorMessage)", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Text("End-of-day quotes by Alpha Vantage. Request limits depend on your plan.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: "\(configuration.watchlistSelectedSymbol)|\(selected?.currency ?? "")|\(interval)") {
            guard !configuration.watchlistSelectedSymbol.isEmpty else { return }
            await refreshSelected()
        }
        .onChange(of: "\(configuration.watchlistSelectedSymbol)|\(selected?.currency ?? "")") { _ in
            refreshRequestID = UUID()
            isRefreshing = false
            errorMessage = nil
        }
        .onChange(of: searchText) { _ in
            searchRequestID = UUID()
            searchResults = []
            isSearching = false
        }
        .onDisappear {
            searchRequestID = UUID()
            refreshRequestID = UUID()
            isSearching = false
            isRefreshing = false
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
                                Text(result.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                            Text(stock.displayName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            if let snapshot = stock.snapshot, let latest = snapshot.latest {
                                Text(latest.close.formatted(.currency(code: snapshot.currency)))
                                    .font(.caption2.monospacedDigit()).lineLimit(1)
                                TimelineView(.periodic(from: .now, by: 60)) { context in
                                    Text(WidgetTimingPresentation.readingStatus(fetchedAt: snapshot.fetchedAt, now: context.date, maximumAge: Double(interval) * 120))
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                                }
                            } else {
                                Text("No quote").font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        .frame(width: 112, alignment: .leading)
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .overlay(alignment: .bottom) {
                            if configuration.watchlistSelectedSymbol == stock.symbol {
                                Capsule().fill(Color.primary).frame(height: 2)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stock.displayName), \(stock.symbol)")
                    .accessibilityAddTraits(configuration.watchlistSelectedSymbol == stock.symbol ? .isSelected : [])
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
            HStack(spacing: 8) {
                TextField("Display name", text: displayNameBinding(for: stock))
                    .font(.subheadline.weight(.semibold)).textFieldStyle(.plain)
                    .accessibilityLabel("Display name for \(stock.symbol)")
                Text(stock.symbol).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button { move(stock.symbol, by: -1) } label: { Image(systemName: "arrow.left") }
                    .buttonStyle(.plain).disabled(configuration.watchlistStocks.first?.symbol == stock.symbol)
                    .help("Move \(stock.symbol) earlier")
                Button { move(stock.symbol, by: 1) } label: { Image(systemName: "arrow.right") }
                    .buttonStyle(.plain).disabled(configuration.watchlistStocks.last?.symbol == stock.symbol)
                    .help("Move \(stock.symbol) later")
                Button("Open on Yahoo Finance", systemImage: "arrow.up.right.square") { openFinance(stock.symbol) }
                    .labelStyle(.iconOnly).help("Open \(stock.symbol) on Yahoo Finance")
            }
            if let snapshot = stock.snapshot, let latest = snapshot.latest {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(latest.close.formatted(.currency(code: snapshot.currency))).font(DockDesign.Module.valueLarge)
                        if let change = snapshot.changePercent {
                            Text(String(format: "%+.2f%%", change)).font(.caption.weight(.medium)).foregroundStyle(StockFaceFormatting.changeColor(change))
                        }
                        Spacer()
                    }
                    let visiblePoints = Array(snapshot.points.suffix(configuration.stockRange.pointCount))
                    MarketSparkline(points: visiblePoints,
                                    color: StockFaceFormatting.changeColor(snapshot.change),
                                    currency: snapshot.currency)
                        .frame(height: 72)
                    Text("\(visiblePoints.count) trading sessions · \(visiblePoints.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")–\(latest.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("Change compares the latest two sessions; up to 100 daily closes are available.")
                        .font(.caption2).foregroundStyle(.secondary)
                    if configuration.stockShowsVolume { Text("Volume \(latest.volume.formatted())").font(.caption2).foregroundStyle(.secondary) }
                }
            } else if isRefreshing {
                ProgressView("Loading \(stock.symbol)…").frame(maxWidth: .infinity, minHeight: 75)
            } else {
                Label("No saved quote for \(stock.symbol)", systemImage: "chart.xyaxis.line")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 75)
            }
        }
    }

    private var controls: some View {
        GroupedSection("Chart", footer: "D = trading sessions. Up to 100 daily closes; percentage change compares the latest two sessions.") {
            GroupedRow("Range", symbol: "chart.xyaxis.line") {
                Picker("Range", selection: Binding(get: { configuration.stockRange }, set: { value in update { $0.stockRange = value } })) {
                    ForEach(StockChartRange.allCases) { Text($0.title).tag($0) }
                }.labelsHidden()
            }
            GroupedRow("Refresh", symbol: "arrow.clockwise") {
                Picker("Refresh", selection: Binding(get: { interval }, set: { value in update { $0.stockRefreshIntervalMinutes = value } })) {
                    Text("1 hour").tag(60); Text("3 hours").tag(180); Text("6 hours").tag(360)
                    Text("12 hours").tag(720); Text("24 hours").tag(1_440)
                }.labelsHidden()
            }
            GroupedRow("Volume", symbol: "chart.bar", isOn: Binding(get: { configuration.stockShowsVolume }, set: { value in update { $0.stockShowsVolume = value } }))
        }
    }

    private func search() async {
        let requestID = UUID()
        searchRequestID = requestID
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = true
        errorMessage = nil
        defer { if searchRequestID == requestID { isSearching = false } }
        do {
            let results = try await AlphaVantageMarketProvider().search(query, apiKey: try requiredAPIKey())
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

    private func refreshSelected() async {
        let requestID = UUID()
        refreshRequestID = requestID
        isRefreshing = true
        defer { if refreshRequestID == requestID { isRefreshing = false } }
        var currentItem = item
        currentItem.widgetConfiguration = configuration
        await store.widgetData.refresh(item: currentItem, profileID: profileID)
        guard refreshRequestID == requestID, !Task.isCancelled else { return }
        if let query = WidgetDataQuery.make(kind: item.widgetKind, configuration: configuration) {
            errorMessage = store.widgetData.errors[query]
        }
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

    private func openFinance(_ symbol: String) {
        guard let url = MarketFinanceURL.url(for: symbol) else { return }
        NSWorkspace.shared.open(url)
    }

    private func requiredAPIKey() throws -> String {
        guard let key = try MarketAPIKeyStore.read(), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarketDataError.missingAPIKey
        }
        return key
    }

    private func update(_ body: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: body)
    }
}

private struct MarketSparkline: View {
    var points: [StockMarketPoint]
    var color: Color
    var currency: String
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
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                        Text(point.close.formatted(.currency(code: currency)))
                            .fontWeight(.semibold)
                        Text("Volume \(point.volume.formatted())")
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
        .accessibilityHint("Use the increment and decrement actions to inspect dates, closing prices, and volume.")
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
            return "Latest: \(latest.date.formatted(date: .abbreviated, time: .omitted)), \(latest.close.formatted(.currency(code: currency))), volume \(latest.volume.formatted())"
        }
        let point = points[selectedIndex]
        return "\(point.date.formatted(date: .abbreviated, time: .omitted)), \(point.close.formatted(.currency(code: currency))), volume \(point.volume.formatted())"
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
