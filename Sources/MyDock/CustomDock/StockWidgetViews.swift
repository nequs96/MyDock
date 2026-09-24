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

private struct StockCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.system(size: 17)).foregroundStyle(tint)
            if let snapshot = configuration.stockSnapshot, let latest = snapshot.latest {
                Text(latest.close.formatted(.currency(code: snapshot.currency)))
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(configuration.stockSymbol).font(.system(size: 7, weight: .medium)).lineLimit(1)
            } else {
                Text(configuration.stockSymbol.isEmpty ? "Set ticker" : configuration.stockSymbol)
                    .font(.system(size: 8, weight: .medium)).lineLimit(1)
            }
        }
        .frame(width: 54, height: 54)
        .help(tooltip)
    }

    private var tint: Color { (configuration.stockSnapshot?.change ?? 0) >= 0 ? .green : .red }
    private var tooltip: String {
        guard let snapshot = configuration.stockSnapshot, let latest = snapshot.latest else { return "Configure a stock ticker" }
        let change = snapshot.changePercent.map { String(format: "%+.2f%%", $0) } ?? ""
        return "\(configuration.stockName.isEmpty ? configuration.stockSymbol : configuration.stockName) · \(latest.close.formatted(.currency(code: snapshot.currency))) \(change) · End of day, updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
    }
}

private struct WatchlistCompactView: View {
    var item: DockItem
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        let selected = configuration.watchlistStocks.first { $0.symbol == configuration.watchlistSelectedSymbol }
        VStack(spacing: 2) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 17)).foregroundStyle(.tint)
            if let selected, let latest = selected.snapshot?.latest {
                Text(latest.close.formatted(.currency(code: selected.snapshot?.currency ?? "USD")))
                    .font(.system(size: 9, weight: .semibold, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                Text(selected.symbol).font(.system(size: 7, weight: .medium)).lineLimit(1)
            } else {
                Text(configuration.watchlistStocks.isEmpty ? "Add tickers" : configuration.watchlistSelectedSymbol)
                    .font(.system(size: 8, weight: .medium)).lineLimit(1)
            }
            if configuration.watchlistStocks.count > 1 {
                Text("+\(configuration.watchlistStocks.count - 1)").font(.system(size: 7)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 54, height: 54)
        .help("Watchlist · \(configuration.watchlistStocks.count) symbols")
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

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var snapshot: StockMarketSnapshot? { configuration.stockSnapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Stock").font(.headline)
                Spacer()
                Button("Refresh") { Task { await refresh() } }
                    .disabled(configuration.stockSymbol.isEmpty || isRefreshing)
            }
            HStack {
                TextField("Search ticker or company", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button { Task { await search() } } label: {
                    if isSearching { ProgressView().controlSize(.small) }
                    else { Image(systemName: "magnifyingglass") }
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                .help("Search market symbols")
            }
            if !searchResults.isEmpty { resultsList }
            if !configuration.stockSymbol.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(configuration.stockName.isEmpty ? configuration.stockSymbol : configuration.stockName)
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(configuration.stockSymbol).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isRefreshing { ProgressView().controlSize(.small) }
                }
                chartContent
                controls
                if let snapshot {
                    Text("End-of-day data · Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
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
        .frame(width: 390).frame(minHeight: 230, alignment: .topLeading)
        .task(id: "\(configuration.stockSymbol)|\(configuration.stockRefreshIntervalMinutes)") {
            guard !configuration.stockSymbol.isEmpty else { return }
            await refresh()
            for await _ in RefreshScheduler.shared.ticks(every: TimeInterval(configuration.stockRefreshIntervalMinutes) * 60) {
                guard !Task.isCancelled else { return }
                await refresh()
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { result in
                    Button {
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
                            if $0.stockSymbol != result.symbol { $0.stockSnapshot = nil }
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
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var chartContent: some View {
        if let snapshot, let latest = snapshot.latest {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(latest.close.formatted(.currency(code: snapshot.currency)))
                        .font(.system(size: 25, weight: .medium, design: .rounded).monospacedDigit())
                    if let change = snapshot.change, let percent = snapshot.changePercent {
                        Text("\(change >= 0 ? "+" : "")\(change.formatted(.number.precision(.fractionLength(2)))) (\(String(format: "%+.2f%%", percent)))")
                            .font(.caption.weight(.medium)).foregroundStyle(change >= 0 ? .green : .red)
                    }
                }
                MarketSparkline(points: Array(snapshot.points.suffix(configuration.stockRange.pointCount)),
                                color: (snapshot.change ?? 0) >= 0 ? .green : .red,
                                currency: snapshot.currency)
                    .frame(height: 100)
                HStack {
                    Text(snapshot.points.first?.date.formatted(date: .abbreviated, time: .omitted) ?? "")
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
        VStack(alignment: .leading, spacing: 8) {
            Picker("Range", selection: rangeBinding) {
                ForEach(StockChartRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("Refresh", selection: refreshIntervalBinding) {
                    Text("1 hour").tag(60)
                    Text("3 hours").tag(180)
                    Text("6 hours").tag(360)
                    Text("12 hours").tag(720)
                    Text("24 hours").tag(1_440)
                }
                Toggle("Volume", isOn: volumeBinding).toggleStyle(.checkbox)
            }
            .font(.caption)
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
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            searchResults = try await AlphaVantageMarketProvider().search(searchText, apiKey: try requiredAPIKey())
        } catch { errorMessage = error.localizedDescription }
    }

    private func refresh() async {
        guard !configuration.stockSymbol.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let data = try await AlphaVantageMarketProvider().snapshot(symbol: configuration.stockSymbol,
                                                                          currency: configuration.stockCurrency,
                                                                          apiKey: try requiredAPIKey())
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                guard value.stockSymbol == data.symbol else { return }
                value.stockSnapshot = data
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
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

private struct WatchlistPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var searchText = ""
    @State private var searchResults: [MarketSymbol] = []
    @State private var isSearching = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var selected: WatchlistStock? { configuration.watchlistStocks.first { $0.symbol == configuration.watchlistSelectedSymbol } }
    private var interval: Int { configuration.stockRefreshIntervalMinutes }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Watchlist").font(.headline)
                Spacer()
                Button("Refresh") { Task { await refreshSelected() } }
                    .disabled(selected == nil || isRefreshing)
            }
            HStack {
                TextField("Search ticker or company", text: $searchText).textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await search() } }
                Button { Task { await search() } } label: {
                    if isSearching { ProgressView().controlSize(.small) }
                    else { Image(systemName: "magnifyingglass") }
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
            }
            if !searchResults.isEmpty { searchResultsList }
            if configuration.watchlistStocks.isEmpty {
                VStack(spacing: 7) {
                    Label("Your watchlist is empty", systemImage: "chart.xyaxis.line").font(.callout.weight(.medium))
                    Text("Search for a ticker to add it.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                watchlistRows
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
        .frame(width: 410).frame(minHeight: 240, alignment: .topLeading)
        .task(id: "\(configuration.watchlistSelectedSymbol)|\(interval)") {
            guard !configuration.watchlistSelectedSymbol.isEmpty else { return }
            await refreshSelected()
            for await _ in RefreshScheduler.shared.ticks(every: TimeInterval(interval) * 60) {
                guard !Task.isCancelled else { return }
                await refreshSelected()
            }
        }
    }

    private var searchResultsList: some View {
        ScrollView {
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
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
    }

    private var watchlistRows: some View {
        VStack(spacing: 2) {
            ForEach(configuration.watchlistStocks) { stock in
                HStack(spacing: 4) {
                    Button { update { $0.watchlistSelectedSymbol = stock.symbol } } label: {
                        HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stock.symbol).font(.callout.weight(.semibold))
                            Text(stock.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let snapshot = stock.snapshot, let latest = snapshot.latest {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(latest.close.formatted(.currency(code: snapshot.currency))).font(.caption.monospacedDigit())
                                if let percent = snapshot.changePercent {
                                    Text(String(format: "%+.2f%%", percent)).font(.caption2).foregroundStyle(percent >= 0 ? .green : .red)
                                }
                            }
                        } else {
                            Text("—").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(configuration.watchlistSelectedSymbol == stock.symbol ? Color.accentColor.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    Button { remove(stock.symbol) } label: {
                        Image(systemName: "xmark.circle").foregroundStyle(.secondary).padding(5)
                    }
                    .buttonStyle(.plain).help("Remove \(stock.symbol)")
                }
            }
        }
    }

    @ViewBuilder private func selectedChart(_ stock: WatchlistStock) -> some View {
        if let snapshot = stock.snapshot, let latest = snapshot.latest {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(latest.close.formatted(.currency(code: snapshot.currency))).font(.system(size: 22, weight: .medium, design: .rounded).monospacedDigit())
                    if let change = snapshot.changePercent {
                        Text(String(format: "%+.2f%%", change)).font(.caption.weight(.medium)).foregroundStyle(change >= 0 ? .green : .red)
                    }
                    Spacer()
                }
                MarketSparkline(points: Array(snapshot.points.suffix(configuration.stockRange.pointCount)),
                                color: (snapshot.change ?? 0) >= 0 ? .green : .red,
                                currency: snapshot.currency)
                    .frame(height: 72)
                if configuration.stockShowsVolume { Text("Volume \(latest.volume.formatted())").font(.caption2).foregroundStyle(.secondary) }
            }
        } else if isRefreshing {
            ProgressView("Loading \(stock.symbol)…").frame(maxWidth: .infinity, minHeight: 75)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("Range", selection: Binding(get: { configuration.stockRange }, set: { value in update { $0.stockRange = value } })) {
                ForEach(StockChartRange.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Picker("Refresh", selection: Binding(get: { interval }, set: { value in update { $0.stockRefreshIntervalMinutes = value } })) {
                    Text("1 hour").tag(60); Text("3 hours").tag(180); Text("6 hours").tag(360)
                    Text("12 hours").tag(720); Text("24 hours").tag(1_440)
                }
                Toggle("Volume", isOn: Binding(get: { configuration.stockShowsVolume }, set: { value in update { $0.stockShowsVolume = value } }))
                    .toggleStyle(.checkbox)
            }
            .font(.caption)
        }
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do { searchResults = try await AlphaVantageMarketProvider().search(searchText, apiKey: try requiredAPIKey()) }
        catch { errorMessage = error.localizedDescription }
    }

    private func refreshSelected() async {
        guard let selected else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let snapshot = try await AlphaVantageMarketProvider().snapshot(symbol: selected.symbol,
                                                                             currency: selected.currency,
                                                                             apiKey: try requiredAPIKey())
            update { configuration in
                guard let index = configuration.watchlistStocks.firstIndex(where: { $0.symbol == snapshot.symbol }) else { return }
                configuration.watchlistStocks[index].snapshot = snapshot
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
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
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Rectangle().fill(.primary.opacity(0.08)).frame(height: 1)
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 0.5)

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
                    .font(.system(size: 9, design: .rounded))
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
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
                .onEnded { _ in selectedIndex = nil })
        }
        .accessibilityLabel("Stock price chart. Move or drag over the chart to inspect a date, close, and volume.")
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
