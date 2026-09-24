import Foundation

enum SetupMode: String, Codable, CaseIterable, Identifiable {
    case nativeOnly
    case both
    case customMain

    var id: String { rawValue }
    var title: String {
        switch self {
        case .nativeOnly: "macOS Dock only"
        case .both: "macOS Dock + Custom Dock"
        case .customMain: "Custom Dock as main Dock"
        }
    }
}

enum CustomDockMaterial: String, Codable, CaseIterable, Identifiable {
    case frosted
    case liquidGlass
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frosted: "Frosted"
        case .liquidGlass: "Liquid Glass (macOS 26+)"
        case .dark: "Dark"
        }
    }
}

enum DockProfileKind: String, Codable, CaseIterable, Identifiable {
    case native
    case custom

    var id: String { rawValue }
    var title: String { self == .native ? "macOS Dock" : "Custom Dock" }
}

enum DockProfileColor: String, CaseIterable, Identifiable, Codable, Hashable {
    case blue
    case purple
    case teal
    case green
    case orange
    case pink
    case red

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum SpacerKind: String, Codable, CaseIterable, Identifiable {
    case small
    case regular

    var id: String { rawValue }
    var title: String { self == .small ? "Small spacer" : "Regular spacer" }
}

enum DockLinkIcon: String, Codable, CaseIterable, Identifiable {
    case globe
    case link
    case house
    case envelope
    case playRectangle = "play.rectangle"
    case docText = "doc.text"
    case calendar
    case cloud
    case bag
    case cart
    case creditcard
    case chartBar = "chart.bar"
    case musicNote = "music.note"
    case map
    case bookmark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .globe: "Globe"
        case .link: "Link"
        case .house: "Home"
        case .envelope: "Mail"
        case .playRectangle: "Video"
        case .docText: "Document"
        case .calendar: "Calendar"
        case .cloud: "Cloud"
        case .bag: "Shop"
        case .cart: "Cart"
        case .creditcard: "Payment"
        case .chartBar: "Chart"
        case .musicNote: "Music"
        case .map: "Map"
        case .bookmark: "Bookmark"
        }
    }
}

enum DockLinkPolicy {
    static func validatedURL(_ value: String) -> URL? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: cleaned),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return components.url
    }
}

enum DockItemType: String, Codable {
    case application
    case folder
    case file
    case link
    case spacer
    case widget
}

struct DockItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var type: DockItemType
    var title: String
    var url: URL?
    var bundleIdentifier: String?
    var spacerKind: SpacerKind?
    var widgetKind: String?
    var widgetConfiguration: WidgetConfiguration?
    var folderIconColor: DockProfileColor?
    var folderIconLetter: String?
    var folderIconNumber: String?
    var linkIcon: DockLinkIcon?
    var linkFaviconData: Data?

    var hasCustomFolderIcon: Bool {
        folderIconColor != nil || folderIconLetter?.isEmpty == false || folderIconNumber?.isEmpty == false
    }

    static func application(at url: URL) -> DockItem {
        let bundle = Bundle(url: url)
        return DockItem(
            type: .application,
            title: bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent,
            url: url,
            bundleIdentifier: bundle?.bundleIdentifier
        )
    }

    static func file(at url: URL, isFolder: Bool = false) -> DockItem {
        DockItem(type: isFolder ? .folder : .file, title: url.deletingPathExtension().lastPathComponent, url: url)
    }

    static func link(_ url: URL, title: String, icon: DockLinkIcon? = nil) -> DockItem {
        DockItem(type: .link, title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url, linkIcon: icon)
    }

    static func spacer(_ kind: SpacerKind) -> DockItem {
        DockItem(type: .spacer, title: kind.title, spacerKind: kind)
    }

    static func widget(_ kind: String) -> DockItem {
        DockItem(type: .widget, title: kind, widgetKind: kind, widgetConfiguration: WidgetConfiguration())
    }
}

enum DockItemMoveDirection {
    case left
    case right
}

enum DockItemSelectionPolicy {
    static func range<ItemID: Hashable>(in orderedIDs: [ItemID], from anchorID: ItemID, to targetID: ItemID) -> Set<ItemID> {
        guard let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID) else { return [] }
        return Set(orderedIDs[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)])
    }
}

enum DockItemOrderingPolicy {
    static func moving(_ originalItems: [DockItem], ids: Set<UUID>, direction: DockItemMoveDirection) -> [DockItem] {
        guard !ids.isEmpty else { return originalItems }
        var items = originalItems
        let selectedIDs = Set(items.map(\.id).filter(ids.contains))
        guard !selectedIDs.isEmpty else { return originalItems }

        switch direction {
        case .left:
            for index in items.indices where selectedIDs.contains(items[index].id) {
                guard index > items.startIndex, !selectedIDs.contains(items[index - 1].id) else { continue }
                items.swapAt(index, index - 1)
            }
        case .right:
            for index in items.indices.reversed() where selectedIDs.contains(items[index].id) {
                guard index < items.index(before: items.endIndex), !selectedIDs.contains(items[index + 1].id) else { continue }
                items.swapAt(index, index + 1)
            }
        }
        return items
    }
}

enum NoteBackground: String, Codable, CaseIterable, Identifiable {
    case yellow
    case blue
    case pink
    case white
    case black
    case translucent

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum StockChartRange: String, Codable, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case year

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "1W"
        case .month: "1M"
        case .threeMonths: "3M"
        case .year: "1Y"
        }
    }

    var pointCount: Int {
        switch self {
        case .week: 5
        case .month: 22
        case .threeMonths: 66
        case .year: 100
        }
    }
}

struct StockMarketPoint: Codable, Hashable, Identifiable {
    var date: Date
    var close: Double
    var volume: Int64
    var id: Date { date }
}

struct StockMarketSnapshot: Codable, Hashable {
    var symbol: String
    var points: [StockMarketPoint]
    var currency: String
    var fetchedAt: Date

    var latest: StockMarketPoint? { points.last }
    var previous: StockMarketPoint? { points.dropLast().last }
    var change: Double? {
        guard let latest, let previous else { return nil }
        return latest.close - previous.close
    }
    var changePercent: Double? {
        guard let change, let previous, previous.close != 0 else { return nil }
        return change / previous.close * 100
    }
}

struct WatchlistStock: Codable, Hashable, Identifiable {
    var symbol: String
    var name: String
    var currency: String
    var snapshot: StockMarketSnapshot?
    var id: String { symbol }
}

struct WidgetConfiguration: Codable, Hashable {
    var noteText: String
    var noteBackground: NoteBackground
    var focusDurationSeconds: Int
    var focusElapsedBeforeStart: TimeInterval
    var focusStartedAt: Date?
    var worldClockTimeZoneID: String
    var worldClockAdditionalTimeZoneIDs: [String]
    var stockSymbol: String
    var stockName: String
    var stockCurrency: String
    var stockRange: StockChartRange
    var stockRefreshIntervalMinutes: Int
    var stockShowsVolume: Bool
    var stockSnapshot: StockMarketSnapshot?
    var watchlistStocks: [WatchlistStock]
    var watchlistSelectedSymbol: String
    var stripeDisplayName: String
    var stripeColor: String
    var stripeAccountID: String
    var stripeMetric: StripeMetric
    var stripeCurrency: String
    var stripePeriod: StripePeriod
    var stripeSnapshot: StripeSnapshot?
    var paddleDisplayName: String
    var paddleColor: String
    var paddleAccountID: String
    var paddleMetric: PaddleMetric
    var paddlePeriod: PaddlePeriod
    var paddleShowsChart: Bool
    var paddleSnapshot: PaddleSnapshot?
    var shopifyDisplayName: String
    var shopifyColor: String
    var shopifyStoreID: String
    var shopifyMetric: ShopifyMetric
    var shopifyPeriod: ShopifyPeriod
    var shopifyShowsChart: Bool
    var shopifySnapshot: ShopifySnapshot?
    var aiLimitsLayout: AILimitLayout
    var aiLimitsRepresentation: AIUsageRepresentation
    var aiLimitsVisibleProviders: [AIProvider]
    var aiLimitsProviderOrder: [AIProvider]
    var aiLimitsCompactProvider: AIProvider
    var aiLimitsSnapshot: AILimitsSnapshot?
    var aiActivityProvider: AIProvider
    var aiActivityRange: AIActivityRange
    var aiActivityChartStyle: AIActivityChartStyle
    var aiActivitySnapshot: AIActivitySnapshot?
    var stopwatchElapsedBeforeStart: TimeInterval
    var stopwatchStartedAt: Date?
    var countdownDurationSeconds: Int
    var countdownElapsedBeforeStart: TimeInterval
    var countdownStartedAt: Date?
    var timeProgressPeriod: TimeProgressPeriod
    var hydrationSaveHistory: Bool
    var hydrationTrackAmounts: Bool
    var hydrationRemindersEnabled: Bool
    var hydrationDefaultAmountML: Int
    var hydrationReminderIntervalMinutes: Int
    var hydrationEntries: [HydrationEntry]
    var hydrationLastRemovedEntry: HydrationEntry?
    var appFolderName: String
    var appFolderColor: String
    var appFolderLetter: String
    var appFolderApplications: [AppFolderApplication]
    var selectedShortcutName: String
    var selectedCalendarIDs: [String]
    var calendarLayout: CalendarWidgetLayout
    var calendarShowsAllDayEvents: Bool
    var selectedReminderCalendarID: String
    var remindersLayout: RemindersWidgetLayout
    var alarms: [DockAlarm]
    var nowPlayingSource: NowPlayingSource
    var nowPlayingLayout: NowPlayingLayout
    var nowPlayingSkipSeconds: Int
    var nowPlayingHidesWhenClosed: Bool
    var weatherLocation: WeatherLocation?
    var weatherUnit: WeatherTemperatureUnit
    var weatherLayout: WeatherWidgetLayout
    var weatherForecastHours: Int
    var weatherBackground: WeatherBackground
    var cachedWeatherForecast: WeatherForecast?

    private enum CodingKeys: String, CodingKey {
        case noteText, noteBackground, focusDurationSeconds, focusElapsedBeforeStart, focusStartedAt
        case worldClockTimeZoneID, worldClockAdditionalTimeZoneIDs, stockSymbol, stockName, stockCurrency, stockRange
        case stockRefreshIntervalMinutes, stockShowsVolume, stockSnapshot, watchlistStocks, watchlistSelectedSymbol
        case stripeDisplayName, stripeColor, stripeAccountID, stripeMetric, stripeCurrency, stripePeriod, stripeSnapshot
        case paddleDisplayName, paddleColor, paddleAccountID, paddleMetric, paddlePeriod, paddleShowsChart, paddleSnapshot
        case shopifyDisplayName, shopifyColor, shopifyStoreID, shopifyMetric, shopifyPeriod, shopifyShowsChart, shopifySnapshot
        case aiLimitsLayout, aiLimitsRepresentation, aiLimitsVisibleProviders, aiLimitsProviderOrder, aiLimitsCompactProvider, aiLimitsSnapshot
        case aiActivityProvider, aiActivityRange, aiActivityChartStyle, aiActivitySnapshot
        case stopwatchElapsedBeforeStart, stopwatchStartedAt
        case countdownDurationSeconds, countdownElapsedBeforeStart, countdownStartedAt, timeProgressPeriod
        case hydrationSaveHistory, hydrationTrackAmounts, hydrationRemindersEnabled, hydrationDefaultAmountML
        case hydrationReminderIntervalMinutes, hydrationEntries, hydrationLastRemovedEntry
        case appFolderName, appFolderColor, appFolderLetter, appFolderApplications, selectedShortcutName
        case selectedCalendarIDs, calendarLayout, calendarShowsAllDayEvents
        case selectedReminderCalendarID, remindersLayout, alarms
        case nowPlayingSource, nowPlayingLayout, nowPlayingSkipSeconds, nowPlayingHidesWhenClosed
        case weatherLocation, weatherUnit, weatherLayout, weatherForecastHours, weatherBackground, cachedWeatherForecast
    }

    init() {
        noteText = ""
        noteBackground = .yellow
        focusDurationSeconds = 25 * 60
        focusElapsedBeforeStart = 0
        focusStartedAt = nil
        worldClockTimeZoneID = "Europe/Warsaw"
        worldClockAdditionalTimeZoneIDs = []
        stockSymbol = ""
        stockName = ""
        stockCurrency = "USD"
        stockRange = .month
        stockRefreshIntervalMinutes = 360
        stockShowsVolume = false
        stockSnapshot = nil
        watchlistStocks = []
        watchlistSelectedSymbol = ""
        stripeDisplayName = "Stripe"
        stripeColor = "purple"
        stripeAccountID = ""
        stripeMetric = .revenue
        stripeCurrency = "USD"
        stripePeriod = .thirtyDays
        stripeSnapshot = nil
        paddleDisplayName = "Paddle"
        paddleColor = "blue"
        paddleAccountID = ""
        paddleMetric = .netRevenue
        paddlePeriod = .thirtyDays
        paddleShowsChart = true
        paddleSnapshot = nil
        shopifyDisplayName = "Shopify"
        shopifyColor = "green"
        shopifyStoreID = ""
        shopifyMetric = .orderValue
        shopifyPeriod = .thirtyDays
        shopifyShowsChart = true
        shopifySnapshot = nil
        aiLimitsLayout = .numbers
        aiLimitsRepresentation = .remaining
        aiLimitsVisibleProviders = [.codex, .claude, .grok]
        aiLimitsProviderOrder = AIProvider.allCases
        aiLimitsCompactProvider = .codex
        aiLimitsSnapshot = nil
        aiActivityProvider = .codex
        aiActivityRange = .today
        aiActivityChartStyle = .sparkline
        aiActivitySnapshot = nil
        stopwatchElapsedBeforeStart = 0
        stopwatchStartedAt = nil
        countdownDurationSeconds = 5 * 60
        countdownElapsedBeforeStart = 0
        countdownStartedAt = nil
        timeProgressPeriod = .day
        hydrationSaveHistory = true
        hydrationTrackAmounts = true
        hydrationRemindersEnabled = false
        hydrationDefaultAmountML = 250
        hydrationReminderIntervalMinutes = 60
        hydrationEntries = []
        hydrationLastRemovedEntry = nil
        appFolderName = "App Folder"
        appFolderColor = "blue"
        appFolderLetter = ""
        appFolderApplications = []
        selectedShortcutName = ""
        selectedCalendarIDs = []
        calendarLayout = .dateAndNextEvent
        calendarShowsAllDayEvents = false
        selectedReminderCalendarID = ""
        remindersLayout = .list
        alarms = []
        nowPlayingSource = .appleMusic
        nowPlayingLayout = .full
        nowPlayingSkipSeconds = 15
        nowPlayingHidesWhenClosed = false
        weatherLocation = nil
        weatherUnit = .celsius
        weatherLayout = .current
        weatherForecastHours = 3
        weatherBackground = .themed
        cachedWeatherForecast = nil
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        noteText = try values.decodeIfPresent(String.self, forKey: .noteText) ?? ""
        noteBackground = try values.decodeIfPresent(NoteBackground.self, forKey: .noteBackground) ?? .yellow
        focusDurationSeconds = try values.decodeIfPresent(Int.self, forKey: .focusDurationSeconds) ?? 25 * 60
        focusElapsedBeforeStart = try values.decodeIfPresent(TimeInterval.self, forKey: .focusElapsedBeforeStart) ?? 0
        focusStartedAt = try values.decodeIfPresent(Date.self, forKey: .focusStartedAt)
        worldClockTimeZoneID = try values.decodeIfPresent(String.self, forKey: .worldClockTimeZoneID) ?? "Europe/Warsaw"
        worldClockAdditionalTimeZoneIDs = try values.decodeIfPresent([String].self, forKey: .worldClockAdditionalTimeZoneIDs) ?? []
        stockSymbol = try values.decodeIfPresent(String.self, forKey: .stockSymbol) ?? ""
        stockName = try values.decodeIfPresent(String.self, forKey: .stockName) ?? ""
        stockCurrency = try values.decodeIfPresent(String.self, forKey: .stockCurrency) ?? "USD"
        stockRange = try values.decodeIfPresent(StockChartRange.self, forKey: .stockRange) ?? .month
        stockRefreshIntervalMinutes = min(max(try values.decodeIfPresent(Int.self, forKey: .stockRefreshIntervalMinutes) ?? 360, 60), 1_440)
        stockShowsVolume = try values.decodeIfPresent(Bool.self, forKey: .stockShowsVolume) ?? false
        stockSnapshot = try values.decodeIfPresent(StockMarketSnapshot.self, forKey: .stockSnapshot)
        watchlistStocks = try values.decodeIfPresent([WatchlistStock].self, forKey: .watchlistStocks) ?? []
        watchlistSelectedSymbol = try values.decodeIfPresent(String.self, forKey: .watchlistSelectedSymbol) ?? ""
        stripeDisplayName = String((try values.decodeIfPresent(String.self, forKey: .stripeDisplayName) ?? "Stripe").prefix(80))
        stripeColor = try values.decodeIfPresent(String.self, forKey: .stripeColor) ?? "purple"
        stripeAccountID = try values.decodeIfPresent(String.self, forKey: .stripeAccountID) ?? ""
        stripeMetric = try values.decodeIfPresent(StripeMetric.self, forKey: .stripeMetric) ?? .revenue
        stripeCurrency = try values.decodeIfPresent(String.self, forKey: .stripeCurrency) ?? "USD"
        stripePeriod = try values.decodeIfPresent(StripePeriod.self, forKey: .stripePeriod) ?? .thirtyDays
        stripeSnapshot = try values.decodeIfPresent(StripeSnapshot.self, forKey: .stripeSnapshot)
        paddleDisplayName = String((try values.decodeIfPresent(String.self, forKey: .paddleDisplayName) ?? "Paddle").prefix(80))
        paddleColor = try values.decodeIfPresent(String.self, forKey: .paddleColor) ?? "blue"
        paddleAccountID = try values.decodeIfPresent(String.self, forKey: .paddleAccountID) ?? ""
        paddleMetric = try values.decodeIfPresent(PaddleMetric.self, forKey: .paddleMetric) ?? .netRevenue
        paddlePeriod = try values.decodeIfPresent(PaddlePeriod.self, forKey: .paddlePeriod) ?? .thirtyDays
        paddleShowsChart = try values.decodeIfPresent(Bool.self, forKey: .paddleShowsChart) ?? true
        paddleSnapshot = try values.decodeIfPresent(PaddleSnapshot.self, forKey: .paddleSnapshot)
        shopifyDisplayName = String((try values.decodeIfPresent(String.self, forKey: .shopifyDisplayName) ?? "Shopify").prefix(80))
        shopifyColor = try values.decodeIfPresent(String.self, forKey: .shopifyColor) ?? "green"
        shopifyStoreID = try values.decodeIfPresent(String.self, forKey: .shopifyStoreID) ?? ""
        shopifyMetric = try values.decodeIfPresent(ShopifyMetric.self, forKey: .shopifyMetric) ?? .orderValue
        shopifyPeriod = try values.decodeIfPresent(ShopifyPeriod.self, forKey: .shopifyPeriod) ?? .thirtyDays
        shopifyShowsChart = try values.decodeIfPresent(Bool.self, forKey: .shopifyShowsChart) ?? true
        shopifySnapshot = try values.decodeIfPresent(ShopifySnapshot.self, forKey: .shopifySnapshot)
        aiLimitsLayout = try values.decodeIfPresent(AILimitLayout.self, forKey: .aiLimitsLayout) ?? .numbers
        aiLimitsRepresentation = try values.decodeIfPresent(AIUsageRepresentation.self, forKey: .aiLimitsRepresentation) ?? .remaining
        aiLimitsVisibleProviders = try values.decodeIfPresent([AIProvider].self, forKey: .aiLimitsVisibleProviders) ?? [.codex, .claude, .grok]
        aiLimitsProviderOrder = try values.decodeIfPresent([AIProvider].self, forKey: .aiLimitsProviderOrder) ?? AIProvider.allCases
        aiLimitsCompactProvider = try values.decodeIfPresent(AIProvider.self, forKey: .aiLimitsCompactProvider) ?? .codex
        aiLimitsSnapshot = try values.decodeIfPresent(AILimitsSnapshot.self, forKey: .aiLimitsSnapshot)
        aiActivityProvider = try values.decodeIfPresent(AIProvider.self, forKey: .aiActivityProvider) ?? .codex
        aiActivityRange = try values.decodeIfPresent(AIActivityRange.self, forKey: .aiActivityRange) ?? .today
        aiActivityChartStyle = try values.decodeIfPresent(AIActivityChartStyle.self, forKey: .aiActivityChartStyle) ?? .sparkline
        aiActivitySnapshot = try values.decodeIfPresent(AIActivitySnapshot.self, forKey: .aiActivitySnapshot)
        stopwatchElapsedBeforeStart = try values.decodeIfPresent(TimeInterval.self, forKey: .stopwatchElapsedBeforeStart) ?? 0
        stopwatchStartedAt = try values.decodeIfPresent(Date.self, forKey: .stopwatchStartedAt)
        countdownDurationSeconds = try values.decodeIfPresent(Int.self, forKey: .countdownDurationSeconds) ?? 5 * 60
        countdownElapsedBeforeStart = try values.decodeIfPresent(TimeInterval.self, forKey: .countdownElapsedBeforeStart) ?? 0
        countdownStartedAt = try values.decodeIfPresent(Date.self, forKey: .countdownStartedAt)
        timeProgressPeriod = try values.decodeIfPresent(TimeProgressPeriod.self, forKey: .timeProgressPeriod) ?? .day
        hydrationSaveHistory = try values.decodeIfPresent(Bool.self, forKey: .hydrationSaveHistory) ?? true
        hydrationTrackAmounts = try values.decodeIfPresent(Bool.self, forKey: .hydrationTrackAmounts) ?? true
        hydrationRemindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .hydrationRemindersEnabled) ?? false
        hydrationDefaultAmountML = try values.decodeIfPresent(Int.self, forKey: .hydrationDefaultAmountML) ?? 250
        hydrationReminderIntervalMinutes = try values.decodeIfPresent(Int.self, forKey: .hydrationReminderIntervalMinutes) ?? 60
        hydrationEntries = try values.decodeIfPresent([HydrationEntry].self, forKey: .hydrationEntries) ?? []
        hydrationLastRemovedEntry = try values.decodeIfPresent(HydrationEntry.self, forKey: .hydrationLastRemovedEntry)
        appFolderName = try values.decodeIfPresent(String.self, forKey: .appFolderName) ?? "App Folder"
        appFolderColor = try values.decodeIfPresent(String.self, forKey: .appFolderColor) ?? "blue"
        appFolderLetter = String((try values.decodeIfPresent(String.self, forKey: .appFolderLetter) ?? "").prefix(2)).uppercased()
        appFolderApplications = try values.decodeIfPresent([AppFolderApplication].self, forKey: .appFolderApplications) ?? []
        selectedShortcutName = try values.decodeIfPresent(String.self, forKey: .selectedShortcutName) ?? ""
        selectedCalendarIDs = try values.decodeIfPresent([String].self, forKey: .selectedCalendarIDs) ?? []
        calendarLayout = try values.decodeIfPresent(CalendarWidgetLayout.self, forKey: .calendarLayout) ?? .dateAndNextEvent
        calendarShowsAllDayEvents = try values.decodeIfPresent(Bool.self, forKey: .calendarShowsAllDayEvents) ?? false
        selectedReminderCalendarID = try values.decodeIfPresent(String.self, forKey: .selectedReminderCalendarID) ?? ""
        remindersLayout = try values.decodeIfPresent(RemindersWidgetLayout.self, forKey: .remindersLayout) ?? .list
        alarms = try values.decodeIfPresent([DockAlarm].self, forKey: .alarms) ?? []
        nowPlayingSource = try values.decodeIfPresent(NowPlayingSource.self, forKey: .nowPlayingSource) ?? .appleMusic
        nowPlayingLayout = try values.decodeIfPresent(NowPlayingLayout.self, forKey: .nowPlayingLayout) ?? .full
        nowPlayingSkipSeconds = min(max(try values.decodeIfPresent(Int.self, forKey: .nowPlayingSkipSeconds) ?? 15, 5), 60)
        nowPlayingHidesWhenClosed = try values.decodeIfPresent(Bool.self, forKey: .nowPlayingHidesWhenClosed) ?? false
        weatherLocation = try values.decodeIfPresent(WeatherLocation.self, forKey: .weatherLocation)
        weatherUnit = try values.decodeIfPresent(WeatherTemperatureUnit.self, forKey: .weatherUnit) ?? .celsius
        weatherLayout = try values.decodeIfPresent(WeatherWidgetLayout.self, forKey: .weatherLayout) ?? .current
        weatherForecastHours = min(max(try values.decodeIfPresent(Int.self, forKey: .weatherForecastHours) ?? 3, 1), 6)
        weatherBackground = try values.decodeIfPresent(WeatherBackground.self, forKey: .weatherBackground) ?? .themed
        cachedWeatherForecast = try values.decodeIfPresent(WeatherForecast.self, forKey: .cachedWeatherForecast)
    }

    func focusRemaining(at date: Date = .now) -> TimeInterval {
        let elapsed = focusElapsedBeforeStart + (focusStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        return max(0, TimeInterval(focusDurationSeconds) - elapsed)
    }

    mutating func startFocusTimer(at date: Date = .now) {
        guard focusStartedAt == nil, focusRemaining(at: date) > 0 else { return }
        focusStartedAt = date
    }

    mutating func pauseFocusTimer(at date: Date = .now) {
        guard focusStartedAt != nil else { return }
        focusElapsedBeforeStart = TimeInterval(focusDurationSeconds) - focusRemaining(at: date)
        focusStartedAt = nil
    }

    mutating func resetFocusTimer() {
        focusElapsedBeforeStart = 0
        focusStartedAt = nil
    }

    func stopwatchElapsed(at date: Date = .now) -> TimeInterval {
        stopwatchElapsedBeforeStart + (stopwatchStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func startStopwatch(at date: Date = .now) {
        if stopwatchStartedAt == nil { stopwatchStartedAt = date }
    }

    mutating func pauseStopwatch(at date: Date = .now) {
        guard stopwatchStartedAt != nil else { return }
        stopwatchElapsedBeforeStart = stopwatchElapsed(at: date)
        stopwatchStartedAt = nil
    }

    mutating func resetStopwatch() {
        stopwatchElapsedBeforeStart = 0
        stopwatchStartedAt = nil
    }

    func countdownRemaining(at date: Date = .now) -> TimeInterval {
        let elapsed = countdownElapsedBeforeStart + (countdownStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        return max(0, TimeInterval(countdownDurationSeconds) - elapsed)
    }

    mutating func startCountdown(at date: Date = .now) {
        guard countdownStartedAt == nil, countdownRemaining(at: date) > 0 else { return }
        countdownStartedAt = date
    }

    mutating func pauseCountdown(at date: Date = .now) {
        guard countdownStartedAt != nil else { return }
        countdownElapsedBeforeStart = TimeInterval(countdownDurationSeconds) - countdownRemaining(at: date)
        countdownStartedAt = nil
    }

    mutating func resetCountdown() {
        countdownElapsedBeforeStart = 0
        countdownStartedAt = nil
    }

    @discardableResult
    mutating func logHydrationDrink(at date: Date = .now, amountML: Int? = nil) -> Bool {
        guard hydrationSaveHistory else { return false }
        let amount = hydrationTrackAmounts ? (amountML ?? hydrationDefaultAmountML) : nil
        hydrationEntries.append(HydrationEntry(timestamp: date, amountML: amount))
        hydrationEntries.sort { $0.timestamp < $1.timestamp }
        return true
    }

    func hydrationEntriesToday(at date: Date = .now, calendar: Calendar = .current) -> [HydrationEntry] {
        hydrationEntries.filter { calendar.isDate($0.timestamp, inSameDayAs: date) }
    }

    mutating func removeHydrationEntry(id: UUID) {
        guard let index = hydrationEntries.firstIndex(where: { $0.id == id }) else { return }
        hydrationLastRemovedEntry = hydrationEntries.remove(at: index)
    }

    mutating func undoHydrationRemoval() {
        guard let entry = hydrationLastRemovedEntry else { return }
        hydrationEntries.append(entry)
        hydrationEntries.sort { $0.timestamp < $1.timestamp }
        hydrationLastRemovedEntry = nil
    }

    func hydrationVolumeSummary(at date: Date = .now, calendar: Calendar = .current) -> String {
        let entries = hydrationEntriesToday(at: date, calendar: calendar)
        let known = entries.compactMap(\.amountML).reduce(0, +)
        guard entries.contains(where: { $0.amountML == nil }) else { return "\(known) mL" }
        return "At least \(known) mL · incomplete"
    }
}

enum CalendarWidgetLayout: String, Codable, CaseIterable, Identifiable {
    case date
    case nextEvent
    case dateAndNextEvent
    case agenda

    var id: String { rawValue }
    var title: String {
        switch self {
        case .date: "Date"
        case .nextEvent: "Next event"
        case .dateAndNextEvent: "Date + next event"
        case .agenda: "Date + agenda"
        }
    }
}

enum RemindersWidgetLayout: String, Codable, CaseIterable, Identifiable {
    case list
    case nextReminder
    case count

    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: "List"
        case .nextReminder: "Next reminder"
        case .count: "Count"
        }
    }
}

enum WeatherTemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case celsius
    case fahrenheit

    var id: String { rawValue }
    var title: String { self == .celsius ? "°C" : "°F" }
}

enum NowPlayingSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMusic
    case spotify

    var id: String { rawValue }
    var title: String { self == .appleMusic ? "Apple Music" : "Spotify" }
    var bundleIdentifier: String { self == .appleMusic ? "com.apple.Music" : "com.spotify.client" }
}

enum NowPlayingLayout: String, Codable, CaseIterable, Identifiable {
    case mini
    case full

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum WeatherWidgetLayout: String, Codable, CaseIterable, Identifiable {
    case current
    case conditions
    case hourlyForecast

    var id: String { rawValue }
    var title: String {
        switch self {
        case .current: "Current"
        case .conditions: "Conditions"
        case .hourlyForecast: "Hourly forecast"
        }
    }
}

enum WeatherBackground: String, Codable, CaseIterable, Identifiable {
    case themed
    case translucent

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TimeProgressPeriod: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month
    case year

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct HydrationEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var timestamp: Date
    var amountML: Int?
}

struct DockAlarm: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var title: String
    var hour: Int
    var minute: Int
    /// Calendar weekday values: Sunday = 1 through Saturday = 7. Empty means one-time.
    var repeatWeekdays: [Int]
    var isEnabled: Bool
}

struct WeatherLocation: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var administrativeArea: String?
    var country: String?
    var latitude: Double
    var longitude: Double
    var timeZoneIdentifier: String

    var displayName: String {
        var parts = [name]
        for value in [administrativeArea, country].compactMap({ $0 }) where !value.isEmpty && value != name {
            if parts.last != value { parts.append(value) }
        }
        return parts.joined(separator: ", ")
    }
}

struct WeatherHour: Codable, Hashable, Identifiable, Sendable {
    var timestamp: Date
    var temperature: Double
    var precipitationProbability: Int?
    var weatherCode: Int
    var id: TimeInterval { timestamp.timeIntervalSince1970 }
}

struct WeatherForecast: Codable, Hashable, Sendable {
    var temperature: Double
    var apparentTemperature: Double
    var relativeHumidity: Int
    var precipitation: Double
    var windSpeed: Double
    var weatherCode: Int
    var isDay: Bool
    var fetchedAt: Date
    var timeZoneIdentifier: String
    var hourly: [WeatherHour]
}

struct AppFolderApplication: Codable, Hashable, Identifiable, Sendable {
    var bundleIdentifier: String?
    var name: String
    var url: URL
    var id: String { bundleIdentifier ?? url.path }
    var hasExistingBundlePath: Bool { url.isFileURL && FileManager.default.fileExists(atPath: url.path) }

    init(url: URL) {
        self.url = url
        let bundle = url.isFileURL ? Bundle(url: url) : nil
        bundleIdentifier = bundle?.bundleIdentifier
        name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }
}

struct DockProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: DockProfileKind
    var color: String = "blue"
    var items: [DockItem] = []
    var createdAt: Date = .now
}

struct DockProfileDraft: Equatable {
    private(set) var original: DockProfile
    private(set) var profile: DockProfile

    var isDirty: Bool { profile != original }

    init(profile: DockProfile) {
        original = profile
        self.profile = profile
    }

    mutating func update(_ change: (inout DockProfile) -> Void) {
        change(&profile)
    }

    mutating func discard() {
        profile = original
    }

    mutating func markSaved(_ savedProfile: DockProfile) {
        original = savedProfile
        profile = savedProfile
    }

    mutating func moveItems(_ itemIDs: Set<UUID>, direction: DockItemMoveDirection) {
        profile.items = DockItemOrderingPolicy.moving(profile.items, ids: itemIDs, direction: direction)
    }
}

struct AppSettings: Codable, Equatable {
    var setupMode: SetupMode = .both
    var activeNativeProfileID: UUID?
    var activeCustomProfileID: UUID?
    var customDockPosition: DockPosition = .bottom
    var customDockSize: Double = 1
    var customDockDisplayID: UInt32?
    var automaticallyHideCustomDock = false
    var hideCustomDockWhenSystemDockAppears = false
    var customDockDesktopMode = false
    var customDockMaterial: CustomDockMaterial = .frosted
    var smoothNativeDockSwitches = false
    var showRunningApps = true
    var showMinimizedWindows = false
    var showWindowPreviews = false
    var showTrash = false
    var showAppBadges = false
    var clickFocusedAppToMinimize = false
    var magnificationEnabled = false
    var automaticallySaveNativeDockChanges = false
    var onboardingComplete = false

    private enum CodingKeys: String, CodingKey {
        case setupMode, activeNativeProfileID, activeCustomProfileID, customDockPosition, customDockSize
        case customDockDisplayID, automaticallyHideCustomDock, hideCustomDockWhenSystemDockAppears, customDockDesktopMode, customDockMaterial, smoothNativeDockSwitches, showRunningApps
        case showMinimizedWindows, showWindowPreviews, showTrash, showAppBadges, clickFocusedAppToMinimize, magnificationEnabled
        case automaticallySaveNativeDockChanges, onboardingComplete
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        setupMode = try values.decodeIfPresent(SetupMode.self, forKey: .setupMode) ?? .both
        activeNativeProfileID = try values.decodeIfPresent(UUID.self, forKey: .activeNativeProfileID)
        activeCustomProfileID = try values.decodeIfPresent(UUID.self, forKey: .activeCustomProfileID)
        customDockPosition = try values.decodeIfPresent(DockPosition.self, forKey: .customDockPosition) ?? .bottom
        customDockSize = min(max(try values.decodeIfPresent(Double.self, forKey: .customDockSize) ?? 1, 0.65), 1.5)
        customDockDisplayID = try values.decodeIfPresent(UInt32.self, forKey: .customDockDisplayID)
        automaticallyHideCustomDock = try values.decodeIfPresent(Bool.self, forKey: .automaticallyHideCustomDock) ?? false
        hideCustomDockWhenSystemDockAppears = try values.decodeIfPresent(Bool.self, forKey: .hideCustomDockWhenSystemDockAppears) ?? false
        customDockDesktopMode = try values.decodeIfPresent(Bool.self, forKey: .customDockDesktopMode) ?? false
        customDockMaterial = try values.decodeIfPresent(CustomDockMaterial.self, forKey: .customDockMaterial) ?? .frosted
        smoothNativeDockSwitches = try values.decodeIfPresent(Bool.self, forKey: .smoothNativeDockSwitches) ?? false
        showRunningApps = try values.decodeIfPresent(Bool.self, forKey: .showRunningApps) ?? true
        showMinimizedWindows = try values.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? false
        showWindowPreviews = try values.decodeIfPresent(Bool.self, forKey: .showWindowPreviews) ?? false
        showTrash = try values.decodeIfPresent(Bool.self, forKey: .showTrash) ?? false
        showAppBadges = try values.decodeIfPresent(Bool.self, forKey: .showAppBadges) ?? false
        clickFocusedAppToMinimize = try values.decodeIfPresent(Bool.self, forKey: .clickFocusedAppToMinimize) ?? false
        magnificationEnabled = try values.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? false
        automaticallySaveNativeDockChanges = try values.decodeIfPresent(Bool.self, forKey: .automaticallySaveNativeDockChanges) ?? false
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
    }
}

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case left
    case bottom
    case right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PersistentState: Codable {
    var schemaVersion = Product.stateSchemaVersion
    var profiles: [DockProfile] = []
    var settings = AppSettings()
}

enum WidgetCategory: String, CaseIterable {
    case productivity = "Productivity"
    case system = "System"
    case time = "Time"
    case personal = "Personal"
    case business = "Business"
    case ai = "AI"
}

struct WidgetDefinition: Identifiable, Hashable {
    var name: String
    var symbol: String
    var category: WidgetCategory
    var description: String
    var id: String { name }
}

enum WidgetRegistry {
    static let all: [WidgetDefinition] = [
        .init(name: "Stock", symbol: "chart.line.uptrend.xyaxis", category: .business, description: "Follow a market ticker."),
        .init(name: "Watchlist", symbol: "chart.xyaxis.line", category: .business, description: "Compare saved tickers."),
        .init(name: "Calendar", symbol: "calendar", category: .productivity, description: "See the date and upcoming events."),
        .init(name: "Reminders", symbol: "checklist", category: .productivity, description: "View and complete reminders."),
        .init(name: "Now Playing", symbol: "music.note", category: .personal, description: "Control Apple Music or Spotify."),
        .init(name: "Weather", symbol: "cloud.sun", category: .personal, description: "See current conditions and forecast."),
        .init(name: "Focus Timer", symbol: "timer", category: .productivity, description: "Keep a focus session close."),
        .init(name: "Sticky Note", symbol: "note.text", category: .productivity, description: "Keep a note in your Dock."),
        .init(name: "Battery", symbol: "battery.100", category: .system, description: "See Mac and accessory battery state."),
        .init(name: "Shortcuts", symbol: "command.square", category: .productivity, description: "Run a macOS shortcut."),
        .init(name: "Stripe", symbol: "creditcard", category: .business, description: "Read Stripe revenue metrics."),
        .init(name: "Paddle", symbol: "creditcard.fill", category: .business, description: "Read Paddle Billing metrics."),
        .init(name: "Shopify", symbol: "bag", category: .business, description: "Read Shopify order metrics."),
        .init(name: "Clock", symbol: "clock", category: .time, description: "See the local time."),
        .init(name: "World Clock", symbol: "globe", category: .time, description: "Track time in other places."),
        .init(name: "Stopwatch", symbol: "stopwatch", category: .time, description: "Measure elapsed time."),
        .init(name: "Countdown", symbol: "hourglass", category: .time, description: "Count down to a date or duration."),
        .init(name: "Alarm", symbol: "alarm", category: .time, description: "Keep local alarms."),
        .init(name: "Time Progress", symbol: "chart.pie", category: .time, description: "See progress through a period."),
        .init(name: "Hydration", symbol: "drop", category: .personal, description: "Track water and reminders."),
        .init(name: "System Activity", symbol: "waveform.path.ecg", category: .system, description: "Inspect CPU, memory, and storage."),
        .init(name: "Network Activity", symbol: "network", category: .system, description: "See network activity and interfaces."),
        .init(name: "AI Limits", symbol: "gauge.with.dots.needle.67percent", category: .ai, description: "Show available provider limits."),
        .init(name: "AI Activity", symbol: "chart.bar", category: .ai, description: "Review local provider activity."),
        .init(name: "AirDrop", symbol: "airdrop", category: .system, description: "Send files with AirDrop."),
        .init(name: "Trash", symbol: "trash", category: .system, description: "Open Trash and empty it after confirmation."),
        .init(name: "App Folder", symbol: "square.grid.2x2", category: .productivity, description: "Group apps together.")
    ]
}
