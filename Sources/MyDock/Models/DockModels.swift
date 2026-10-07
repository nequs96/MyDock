import Foundation

extension KeyedDecodingContainer {
    /// A setting that does not decode (a choice written by a newer MyDock, or a changed type) falls back to its
    /// default instead of failing the whole file. User content (items, collections, notes) stays strict.
    func lenient<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    /// The choices this build knows, in stored order; unknown ones are skipped.
    func lenientChoices<T: RawRepresentable & Decodable>(_ type: T.Type, forKey key: Key) -> [T]? where T.RawValue == String {
        guard let raw = try? decodeIfPresent([String].self, forKey: key) else { return nil }
        return raw.compactMap(T.init(rawValue:))
    }
}

enum SetupMode: String, Codable, CaseIterable, Identifiable {
    case nativeOnly
    case both
    case customMain

    var id: String { rawValue }
    var title: String {
        switch self {
        case .nativeOnly: "macOS Dock only"
        case .both: "macOS Dock + Custom Dock"
        case .customMain: "Replace macOS Dock"
        }
    }
}

enum CustomDockTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DockAnimationStyle: String, Codable, CaseIterable, Identifiable {
    case fade, slide, grow
    var id: String { rawValue }
    var title: String { switch self { case .fade: "Fade"; case .slide: "Slide"; case .grow: "Gentle grow" } }
}

enum CustomDockMaterial: String, Codable, CaseIterable, Identifiable {
    case frosted
    case solid
    case liquidGlass
    case liquidGlassClear
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: "Solid · no glass"
        case .frosted: "Frosted"
        case .liquidGlass: "Liquid Glass · Frosted"
        case .liquidGlassClear: "Liquid Glass · Clear"
        case .dark: "Dark"
        }
    }
}

enum CustomDockWidgetStyle: String, Codable, CaseIterable, Identifiable {
    case cards
    case compact

    var id: String { rawValue }
    var title: String { self == .cards ? "Adaptive widgets" : "Compact defaults" }
}

enum DockEdgeStyle: String, Codable, CaseIterable {
    case none, hairline, contrastOnly
}

enum DockWidgetSurface: String, Codable, CaseIterable {
    case glass, plain, tile
}

enum DockTintMode: String, Codable {
    case custom, auto
}

enum WidgetAccent: Codable, Hashable {
    case auto, mono, profile(DockProfileColor)

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "auto": self = .auto
        case "mono": self = .mono
        default:
            if value.hasPrefix("profile."), let color = DockProfileColor(rawValue: String(value.dropFirst(8))) {
                self = .profile(color)
            } else {
                self = .auto
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto: try container.encode("auto")
        case .mono: try container.encode("mono")
        case .profile(let color): try container.encode("profile." + color.rawValue)
        }
    }
}

enum WidgetGlassTint: String, Codable {
    case none, accent
}

enum WidgetIconStyle: String, Codable, CaseIterable, Identifiable {
    case live, gradient, tinted, outline
    var id: String { rawValue }
    var title: String {
        switch self { case .live: "Live"; case .gradient: "Color"; case .tinted: "Soft"; case .outline: "Mono" }
    }
}

struct QuickChecklistEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var title: String
    var isComplete = false
}

enum WidgetCardWidth: String, Codable, CaseIterable, Identifiable {
    case compact
    case standard
    case wide

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var title: String {
        switch self {
        case .compact: "Compact · no name"
        case .standard: "Standard"
        case .wide: "Wide"
        }
    }
    var points: Double {
        switch self {
        case .compact: 66
        case .standard: 112
        case .wide: 144
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
    var folderCustomName: String?
    var showFolderLabel: Bool?
    var folderIconColor: DockProfileColor?
    var folderIconLetter: String?
    var folderIconNumber: String?
    var linkIcon: DockLinkIcon?
    var linkFaviconData: Data?

    var hasCustomFolderIcon: Bool {
        folderIconColor != nil || folderIconLetter?.isEmpty == false || folderIconNumber?.isEmpty == false
    }

    var showsFolderLabel: Bool { showFolderLabel ?? false }

    var displayName: String {
        guard type == .folder else { return title }
        if let folderCustomName,
           !folderCustomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return folderCustomName
        }
        return url?.lastPathComponent ?? title
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
        let title = isFolder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        return DockItem(type: isFolder ? .folder : .file, title: title, url: url)
    }

    static func link(_ url: URL, title: String, icon: DockLinkIcon? = nil) -> DockItem {
        DockItem(type: .link, title: title.isEmpty ? url.host() ?? url.absoluteString : title, url: url, linkIcon: icon)
    }

    static func spacer(_ kind: SpacerKind) -> DockItem {
        DockItem(type: .spacer, title: kind.title, spacerKind: kind)
    }

    /// New widgets start monochrome (redesign default). Saved widgets keep their decoded appearance;
    /// `WidgetConfiguration()` itself keeps the legacy default for items saved without one.
    static func widget(_ kind: String) -> DockItem {
        var configuration = WidgetConfiguration()
        configuration.iconAppearance = .mono
        if kind == "System Activity" { SystemDetailSections.applyCreationDefaults(to: &configuration) }
        return DockItem(type: .widget, title: kind, widgetKind: kind, widgetConfiguration: configuration)
    }
}

enum DockItemMoveDirection {
    case left
    case right
}

enum DockItemSelectionPolicy {
    static func next<ItemID: Hashable>(in orderedIDs: [ItemID], selected: Set<ItemID>, cursor: ItemID?, forward: Bool) -> ItemID? {
        guard !orderedIDs.isEmpty else { return nil }
        guard !selected.isEmpty else { return forward ? orderedIDs.first : orderedIDs.last }
        let current = cursor.flatMap { selected.contains($0) ? orderedIDs.firstIndex(of: $0) : nil }
            ?? orderedIDs.firstIndex(where: selected.contains) ?? (forward ? -1 : orderedIDs.count)
        return orderedIDs[min(orderedIDs.count - 1, max(0, current + (forward ? 1 : -1)))]
    }

    static func range<ItemID: Hashable>(in orderedIDs: [ItemID], from anchorID: ItemID, to targetID: ItemID) -> Set<ItemID> {
        guard let anchorIndex = orderedIDs.firstIndex(of: anchorID),
              let targetIndex = orderedIDs.firstIndex(of: targetID) else { return [] }
        return Set(orderedIDs[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)])
    }
}

enum DockItemOrderingPolicy {
    static func moving(_ items: [DockItem], ids: Set<UUID>, before targetID: UUID?) -> [DockItem] {
        guard !ids.isEmpty, targetID.map({ !ids.contains($0) }) ?? true else { return items }
        let moved = items.filter { ids.contains($0.id) }
        guard !moved.isEmpty else { return items }
        var remaining = items.filter { !ids.contains($0.id) }
        let target = targetID.flatMap { id in remaining.firstIndex(where: { $0.id == id }) } ?? remaining.endIndex
        remaining.insert(contentsOf: moved, at: target)
        return remaining
    }

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

enum CountdownMode: String, Codable, CaseIterable, Identifiable {
    case duration
    case targetDate

    var id: String { rawValue }
    var title: String { self == .duration ? "Duration" : "Date & Time" }
}

enum StockChartRange: String, Codable, CaseIterable, Identifiable {
    case week
    case month
    case threeMonths
    case year

    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "5D"
        case .month: "22D"
        case .threeMonths: "66D"
        case .year: "100D"
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
    var customName: String? = nil
    var currency: String
    var snapshot: StockMarketSnapshot?
    var id: String { symbol }

    var displayName: String {
        let custom = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return custom.isEmpty ? name : custom
    }
}

struct WidgetConfiguration: Codable, Hashable {
    var cardWidth: WidgetCardWidth
    // Legacy fields stay decodable for existing profiles and backups.
    var iconStyle: WidgetIconStyle
    var widgetLayout: WidgetLayout?
    var iconAppearance: WidgetIconAppearance
    // Nil preserves the inherited presentation of older configurations.
    var widgetAccent: WidgetAccent?
    var showsLabel: Bool?
    var glassTint: WidgetGlassTint?
    var aiActivitySecondaryMetric: AIActivitySecondaryMetric
    var systemSecondaryMetric: SystemSecondaryMetric
    // PX-7: related sections in the System Activity popout. Nil (saved before PX-7) shows none;
    // new System Activity widgets start with both on (`DockItem.widget`).
    var systemShowsNetwork: Bool?
    var systemShowsStorage: Bool?
    var shelfFiles: [ShelfFile]
    var textSnippets: [TextSnippet]
    var quickLinks: [QuickLink]
    var savedColors: [String]
    var checklistEntries: [QuickChecklistEntry]
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
    var aiCopilotMonthlyCreditAllowance: Int?
    var aiActivityProvider: AIProvider
    var aiActivityRange: AIActivityRange
    var aiActivityChartStyle: AIActivityChartStyle
    var aiActivitySnapshot: AIActivitySnapshot?
    var stopwatchElapsedBeforeStart: TimeInterval
    var stopwatchStartedAt: Date?
    var stopwatchClockStart: StopwatchClockSample?
    var countdownDurationSeconds: Int
    var countdownElapsedBeforeStart: TimeInterval
    var countdownStartedAt: Date?
    var countdownMode: CountdownMode
    var countdownTargetDate: Date?
    var timeProgressPeriod: TimeProgressPeriod
    var hydrationSaveHistory: Bool
    var hydrationTrackAmounts: Bool
    var hydrationRemindersEnabled: Bool
    var hydrationDefaultAmountML: Int
    var hydrationReminderIntervalMinutes: Int
    /// The one reminder-interval domain: decoding clamps to it, the validator, the stepper and the scheduler use it.
    static let hydrationReminderIntervalRange: ClosedRange<Int> = 30...240
    static func clampedHydrationReminderInterval(_ minutes: Int) -> Int {
        min(max(minutes, hydrationReminderIntervalRange.lowerBound), hydrationReminderIntervalRange.upperBound)
    }
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
    var nowPlayingEnabledSources: [NowPlayingSource]
    var nowPlayingLayout: NowPlayingLayout
    var nowPlayingSkipSeconds: Int
    var nowPlayingHidesWhenClosed: Bool
    var nowPlayingShowsTrackControls: Bool
    var nowPlayingShowsSeekControls: Bool
    var weatherLocation: WeatherLocation?
    var weatherUnit: WeatherTemperatureUnit
    var weatherLayout: WeatherWidgetLayout
    var weatherForecastHours: Int
    var weatherBackground: WeatherBackground
    var cachedWeatherForecast: WeatherForecast?

    private enum CodingKeys: String, CodingKey {
        case widgetAccent, showsLabel, glassTint
        case shelfFiles, textSnippets, quickLinks, savedColors
        case cardWidth, iconStyle, checklistEntries, widgetLayout, iconAppearance, aiActivitySecondaryMetric, systemSecondaryMetric
        case systemShowsNetwork, systemShowsStorage
        case noteText, noteBackground, focusDurationSeconds, focusElapsedBeforeStart, focusStartedAt
        case worldClockTimeZoneID, worldClockAdditionalTimeZoneIDs, stockSymbol, stockName, stockCurrency, stockRange
        case stockRefreshIntervalMinutes, stockShowsVolume, stockSnapshot, watchlistStocks, watchlistSelectedSymbol
        case stripeDisplayName, stripeColor, stripeAccountID, stripeMetric, stripeCurrency, stripePeriod, stripeSnapshot
        case paddleDisplayName, paddleColor, paddleAccountID, paddleMetric, paddlePeriod, paddleShowsChart, paddleSnapshot
        case shopifyDisplayName, shopifyColor, shopifyStoreID, shopifyMetric, shopifyPeriod, shopifyShowsChart, shopifySnapshot
        case aiLimitsLayout, aiLimitsRepresentation, aiLimitsVisibleProviders, aiLimitsProviderOrder, aiLimitsCompactProvider, aiLimitsSnapshot
        case aiCopilotMonthlyCreditAllowance
        case aiActivityProvider, aiActivityRange, aiActivityChartStyle, aiActivitySnapshot
        case stopwatchElapsedBeforeStart, stopwatchStartedAt, stopwatchClockStart
        case countdownDurationSeconds, countdownElapsedBeforeStart, countdownStartedAt
        case countdownMode, countdownTargetDate, timeProgressPeriod
        case hydrationSaveHistory, hydrationTrackAmounts, hydrationRemindersEnabled, hydrationDefaultAmountML
        case hydrationReminderIntervalMinutes, hydrationEntries, hydrationLastRemovedEntry
        case appFolderName, appFolderColor, appFolderLetter, appFolderApplications, selectedShortcutName
        case selectedCalendarIDs, calendarLayout, calendarShowsAllDayEvents
        case selectedReminderCalendarID, remindersLayout, alarms
        case nowPlayingSource, nowPlayingEnabledSources, nowPlayingLayout, nowPlayingSkipSeconds, nowPlayingHidesWhenClosed
        case nowPlayingShowsTrackControls, nowPlayingShowsSeekControls
        case weatherLocation, weatherUnit, weatherLayout, weatherForecastHours, weatherBackground, cachedWeatherForecast
    }

    init() {
        cardWidth = .standard
        iconStyle = .live
        widgetLayout = nil
        iconAppearance = .soft
        widgetAccent = nil
        showsLabel = nil
        glassTint = nil
        aiActivitySecondaryMetric = .sessions
        systemSecondaryMetric = .memory
        shelfFiles = []
        textSnippets = []
        quickLinks = []
        savedColors = []
        checklistEntries = []
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
        aiCopilotMonthlyCreditAllowance = nil
        aiActivityProvider = .codex
        aiActivityRange = .today
        aiActivityChartStyle = .sparkline
        aiActivitySnapshot = nil
        stopwatchElapsedBeforeStart = 0
        stopwatchStartedAt = nil
        stopwatchClockStart = nil
        countdownDurationSeconds = 5 * 60
        countdownElapsedBeforeStart = 0
        countdownStartedAt = nil
        countdownMode = .duration
        countdownTargetDate = nil
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
        nowPlayingEnabledSources = [.appleMusic]
        nowPlayingLayout = .full
        nowPlayingSkipSeconds = 15
        nowPlayingHidesWhenClosed = false
        nowPlayingShowsTrackControls = true
        nowPlayingShowsSeekControls = true
        weatherLocation = nil
        weatherUnit = .celsius
        weatherLayout = .current
        weatherForecastHours = 3
        weatherBackground = .themed
        cachedWeatherForecast = nil
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cardWidth = values.lenient(WidgetCardWidth.self, forKey: .cardWidth) ?? .standard
        iconStyle = values.lenient(WidgetIconStyle.self, forKey: .iconStyle) ?? .live
        iconAppearance = values.lenient(WidgetIconAppearance.self, forKey: .iconAppearance) ?? WidgetIconAppearance(legacy: iconStyle)
        widgetAccent = try? values.decodeIfPresent(WidgetAccent.self, forKey: .widgetAccent)
        showsLabel = try values.decodeIfPresent(Bool.self, forKey: .showsLabel)
        glassTint = try? values.decodeIfPresent(WidgetGlassTint.self, forKey: .glassTint)
        widgetLayout = values.lenient(WidgetLayout.self, forKey: .widgetLayout)
        if widgetLayout == nil, !values.contains(.iconAppearance), values.contains(.cardWidth) {
            widgetLayout = cardWidth == .compact ? .compact : cardWidth == .wide ? .wide : .standard
        }
        aiActivitySecondaryMetric = values.lenient(AIActivitySecondaryMetric.self, forKey: .aiActivitySecondaryMetric) ?? .sessions
        systemSecondaryMetric = values.lenient(SystemSecondaryMetric.self, forKey: .systemSecondaryMetric) ?? .memory
        systemShowsNetwork = try? values.decodeIfPresent(Bool.self, forKey: .systemShowsNetwork)
        systemShowsStorage = try? values.decodeIfPresent(Bool.self, forKey: .systemShowsStorage)
        shelfFiles = try values.decodeIfPresent([ShelfFile].self, forKey: .shelfFiles) ?? []
        textSnippets = try values.decodeIfPresent([TextSnippet].self, forKey: .textSnippets) ?? []
        quickLinks = try values.decodeIfPresent([QuickLink].self, forKey: .quickLinks) ?? []
        savedColors = try values.decodeIfPresent([String].self, forKey: .savedColors) ?? []
        checklistEntries = try values.decodeIfPresent([QuickChecklistEntry].self, forKey: .checklistEntries) ?? []
        noteText = try values.decodeIfPresent(String.self, forKey: .noteText) ?? ""
        noteBackground = values.lenient(NoteBackground.self, forKey: .noteBackground) ?? .yellow
        focusDurationSeconds = try values.decodeIfPresent(Int.self, forKey: .focusDurationSeconds) ?? 25 * 60
        focusElapsedBeforeStart = try values.decodeIfPresent(TimeInterval.self, forKey: .focusElapsedBeforeStart) ?? 0
        focusStartedAt = try values.decodeIfPresent(Date.self, forKey: .focusStartedAt)
        worldClockTimeZoneID = try values.decodeIfPresent(String.self, forKey: .worldClockTimeZoneID) ?? "Europe/Warsaw"
        worldClockAdditionalTimeZoneIDs = try values.decodeIfPresent([String].self, forKey: .worldClockAdditionalTimeZoneIDs) ?? []
        stockSymbol = try values.decodeIfPresent(String.self, forKey: .stockSymbol) ?? ""
        stockName = try values.decodeIfPresent(String.self, forKey: .stockName) ?? ""
        stockCurrency = try values.decodeIfPresent(String.self, forKey: .stockCurrency) ?? "USD"
        stockRange = values.lenient(StockChartRange.self, forKey: .stockRange) ?? .month
        stockRefreshIntervalMinutes = min(max(try values.decodeIfPresent(Int.self, forKey: .stockRefreshIntervalMinutes) ?? 360, 60), 1_440)
        stockShowsVolume = try values.decodeIfPresent(Bool.self, forKey: .stockShowsVolume) ?? false
        stockSnapshot = values.lenient(StockMarketSnapshot.self, forKey: .stockSnapshot)
        watchlistStocks = try values.decodeIfPresent([WatchlistStock].self, forKey: .watchlistStocks) ?? []
        watchlistSelectedSymbol = try values.decodeIfPresent(String.self, forKey: .watchlistSelectedSymbol) ?? ""
        stripeDisplayName = String((try values.decodeIfPresent(String.self, forKey: .stripeDisplayName) ?? "Stripe").prefix(80))
        stripeColor = try values.decodeIfPresent(String.self, forKey: .stripeColor) ?? "purple"
        stripeAccountID = try values.decodeIfPresent(String.self, forKey: .stripeAccountID) ?? ""
        stripeMetric = values.lenient(StripeMetric.self, forKey: .stripeMetric) ?? .revenue
        stripeCurrency = try values.decodeIfPresent(String.self, forKey: .stripeCurrency) ?? "USD"
        stripePeriod = values.lenient(StripePeriod.self, forKey: .stripePeriod) ?? .thirtyDays
        stripeSnapshot = values.lenient(StripeSnapshot.self, forKey: .stripeSnapshot)
        paddleDisplayName = String((try values.decodeIfPresent(String.self, forKey: .paddleDisplayName) ?? "Paddle").prefix(80))
        paddleColor = try values.decodeIfPresent(String.self, forKey: .paddleColor) ?? "blue"
        paddleAccountID = try values.decodeIfPresent(String.self, forKey: .paddleAccountID) ?? ""
        paddleMetric = values.lenient(PaddleMetric.self, forKey: .paddleMetric) ?? .netRevenue
        paddlePeriod = values.lenient(PaddlePeriod.self, forKey: .paddlePeriod) ?? .thirtyDays
        paddleShowsChart = try values.decodeIfPresent(Bool.self, forKey: .paddleShowsChart) ?? true
        paddleSnapshot = values.lenient(PaddleSnapshot.self, forKey: .paddleSnapshot)
        shopifyDisplayName = String((try values.decodeIfPresent(String.self, forKey: .shopifyDisplayName) ?? "Shopify").prefix(80))
        shopifyColor = try values.decodeIfPresent(String.self, forKey: .shopifyColor) ?? "green"
        shopifyStoreID = try values.decodeIfPresent(String.self, forKey: .shopifyStoreID) ?? ""
        shopifyMetric = values.lenient(ShopifyMetric.self, forKey: .shopifyMetric) ?? .orderValue
        shopifyPeriod = values.lenient(ShopifyPeriod.self, forKey: .shopifyPeriod) ?? .thirtyDays
        shopifyShowsChart = try values.decodeIfPresent(Bool.self, forKey: .shopifyShowsChart) ?? true
        shopifySnapshot = values.lenient(ShopifySnapshot.self, forKey: .shopifySnapshot)
        aiLimitsLayout = values.lenient(AILimitLayout.self, forKey: .aiLimitsLayout) ?? .numbers
        aiLimitsRepresentation = values.lenient(AIUsageRepresentation.self, forKey: .aiLimitsRepresentation) ?? .remaining
        aiLimitsVisibleProviders = values.lenientChoices(AIProvider.self, forKey: .aiLimitsVisibleProviders) ?? [.codex, .claude, .grok]
        aiLimitsProviderOrder = values.lenientChoices(AIProvider.self, forKey: .aiLimitsProviderOrder) ?? AIProvider.allCases
        aiLimitsCompactProvider = values.lenient(AIProvider.self, forKey: .aiLimitsCompactProvider) ?? .codex
        aiLimitsSnapshot = values.lenient(AILimitsSnapshot.self, forKey: .aiLimitsSnapshot)
        aiCopilotMonthlyCreditAllowance = try values.decodeIfPresent(Int.self, forKey: .aiCopilotMonthlyCreditAllowance)
            .flatMap { (1...1_000_000).contains($0) ? $0 : nil }
        aiActivityProvider = values.lenient(AIProvider.self, forKey: .aiActivityProvider) ?? .codex
        aiActivityRange = values.lenient(AIActivityRange.self, forKey: .aiActivityRange) ?? .today
        aiActivityChartStyle = values.lenient(AIActivityChartStyle.self, forKey: .aiActivityChartStyle) ?? .sparkline
        aiActivitySnapshot = values.lenient(AIActivitySnapshot.self, forKey: .aiActivitySnapshot)
        stopwatchElapsedBeforeStart = try values.decodeIfPresent(TimeInterval.self, forKey: .stopwatchElapsedBeforeStart) ?? 0
        stopwatchStartedAt = try values.decodeIfPresent(Date.self, forKey: .stopwatchStartedAt)
        stopwatchClockStart = values.lenient(StopwatchClockSample.self, forKey: .stopwatchClockStart)
        countdownDurationSeconds = try values.decodeIfPresent(Int.self, forKey: .countdownDurationSeconds) ?? 5 * 60
        countdownElapsedBeforeStart = try values.decodeIfPresent(TimeInterval.self, forKey: .countdownElapsedBeforeStart) ?? 0
        countdownStartedAt = try values.decodeIfPresent(Date.self, forKey: .countdownStartedAt)
        countdownMode = values.lenient(CountdownMode.self, forKey: .countdownMode) ?? .duration
        countdownTargetDate = try values.decodeIfPresent(Date.self, forKey: .countdownTargetDate)
        timeProgressPeriod = values.lenient(TimeProgressPeriod.self, forKey: .timeProgressPeriod) ?? .day
        hydrationSaveHistory = try values.decodeIfPresent(Bool.self, forKey: .hydrationSaveHistory) ?? true
        hydrationTrackAmounts = try values.decodeIfPresent(Bool.self, forKey: .hydrationTrackAmounts) ?? true
        hydrationRemindersEnabled = try values.decodeIfPresent(Bool.self, forKey: .hydrationRemindersEnabled) ?? false
        hydrationDefaultAmountML = try values.decodeIfPresent(Int.self, forKey: .hydrationDefaultAmountML) ?? 250
        hydrationReminderIntervalMinutes = Self.clampedHydrationReminderInterval(
            try values.decodeIfPresent(Int.self, forKey: .hydrationReminderIntervalMinutes) ?? 60)
        hydrationEntries = try values.decodeIfPresent([HydrationEntry].self, forKey: .hydrationEntries) ?? []
        hydrationLastRemovedEntry = try values.decodeIfPresent(HydrationEntry.self, forKey: .hydrationLastRemovedEntry)
        appFolderName = try values.decodeIfPresent(String.self, forKey: .appFolderName) ?? "App Folder"
        appFolderColor = try values.decodeIfPresent(String.self, forKey: .appFolderColor) ?? "blue"
        appFolderLetter = String((try values.decodeIfPresent(String.self, forKey: .appFolderLetter) ?? "").prefix(2)).uppercased()
        appFolderApplications = try values.decodeIfPresent([AppFolderApplication].self, forKey: .appFolderApplications) ?? []
        selectedShortcutName = try values.decodeIfPresent(String.self, forKey: .selectedShortcutName) ?? ""
        selectedCalendarIDs = try values.decodeIfPresent([String].self, forKey: .selectedCalendarIDs) ?? []
        calendarLayout = values.lenient(CalendarWidgetLayout.self, forKey: .calendarLayout) ?? .dateAndNextEvent
        calendarShowsAllDayEvents = try values.decodeIfPresent(Bool.self, forKey: .calendarShowsAllDayEvents) ?? false
        selectedReminderCalendarID = try values.decodeIfPresent(String.self, forKey: .selectedReminderCalendarID) ?? ""
        remindersLayout = values.lenient(RemindersWidgetLayout.self, forKey: .remindersLayout) ?? .list
        alarms = try values.decodeIfPresent([DockAlarm].self, forKey: .alarms) ?? []
        nowPlayingSource = values.lenient(NowPlayingSource.self, forKey: .nowPlayingSource) ?? .appleMusic
        let enabledSources = values.lenientChoices(NowPlayingSource.self, forKey: .nowPlayingEnabledSources) ?? [.appleMusic]
        nowPlayingEnabledSources = NowPlayingSource.allCases.filter(enabledSources.contains)
        nowPlayingSource = nowPlayingEnabledSources.contains(nowPlayingSource)
            ? nowPlayingSource
            : (nowPlayingEnabledSources.first ?? nowPlayingSource)
        nowPlayingLayout = values.lenient(NowPlayingLayout.self, forKey: .nowPlayingLayout) ?? .full
        nowPlayingSkipSeconds = min(max(try values.decodeIfPresent(Int.self, forKey: .nowPlayingSkipSeconds) ?? 15, 5), 60)
        nowPlayingHidesWhenClosed = try values.decodeIfPresent(Bool.self, forKey: .nowPlayingHidesWhenClosed) ?? false
        nowPlayingShowsTrackControls = try values.decodeIfPresent(Bool.self, forKey: .nowPlayingShowsTrackControls) ?? true
        nowPlayingShowsSeekControls = try values.decodeIfPresent(Bool.self, forKey: .nowPlayingShowsSeekControls) ?? true
        weatherLocation = values.lenient(WeatherLocation.self, forKey: .weatherLocation)
        weatherUnit = values.lenient(WeatherTemperatureUnit.self, forKey: .weatherUnit) ?? .celsius
        weatherLayout = values.lenient(WeatherWidgetLayout.self, forKey: .weatherLayout) ?? .current
        weatherForecastHours = min(max(try values.decodeIfPresent(Int.self, forKey: .weatherForecastHours) ?? 3, 1), 6)
        weatherBackground = values.lenient(WeatherBackground.self, forKey: .weatherBackground) ?? .themed
        cachedWeatherForecast = values.lenient(WeatherForecast.self, forKey: .cachedWeatherForecast)
        try ProfileSemanticValidator.validate(self)
    }

    mutating func selectWeatherUnit(_ unit: WeatherTemperatureUnit) {
        guard weatherUnit != unit else { return }
        weatherUnit = unit
        cachedWeatherForecast = nil
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

    func stopwatchElapsed(at date: Date = .now, clock: StopwatchClockSample? = StopwatchClock.sample()) -> TimeInterval {
        guard let stopwatchStartedAt else { return stopwatchElapsedBeforeStart }
        if let stopwatchClockStart, let clock, let elapsed = clock.elapsed(since: stopwatchClockStart) {
            return stopwatchElapsedBeforeStart + elapsed
        }
        // Older saved profiles and a new boot have no comparable monotonic anchor.
        return stopwatchElapsedBeforeStart + max(0, date.timeIntervalSince(stopwatchStartedAt))
    }

    mutating func startStopwatch(at date: Date = .now, clock: StopwatchClockSample? = StopwatchClock.sample()) {
        guard stopwatchStartedAt == nil else { return }
        stopwatchStartedAt = date
        stopwatchClockStart = clock
    }

    mutating func pauseStopwatch(at date: Date = .now, clock: StopwatchClockSample? = StopwatchClock.sample()) {
        guard stopwatchStartedAt != nil else { return }
        stopwatchElapsedBeforeStart = stopwatchElapsed(at: date, clock: clock)
        stopwatchStartedAt = nil
        stopwatchClockStart = nil
    }

    mutating func resetStopwatch() {
        stopwatchElapsedBeforeStart = 0
        stopwatchStartedAt = nil
        stopwatchClockStart = nil
    }

    func countdownRemaining(at date: Date = .now) -> TimeInterval {
        if countdownMode == .targetDate {
            return max(0, countdownTargetDate?.timeIntervalSince(date) ?? 0)
        }
        let elapsed = countdownElapsedBeforeStart + (countdownStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
        return max(0, TimeInterval(countdownDurationSeconds) - elapsed)
    }

    var countdownNotificationDeadline: Date? {
        guard countdownMode == .duration, let start = countdownStartedAt else { return nil }
        return start.addingTimeInterval(max(0, TimeInterval(countdownDurationSeconds) - countdownElapsedBeforeStart))
    }

    mutating func startCountdown(at date: Date = .now) {
        guard countdownMode == .duration else { return }
        guard countdownStartedAt == nil, countdownRemaining(at: date) > 0 else { return }
        countdownStartedAt = date
    }

    mutating func pauseCountdown(at date: Date = .now) {
        guard countdownMode == .duration else { return }
        guard countdownStartedAt != nil else { return }
        countdownElapsedBeforeStart = TimeInterval(countdownDurationSeconds) - countdownRemaining(at: date)
        countdownStartedAt = nil
    }

    mutating func resetCountdown() {
        countdownElapsedBeforeStart = 0
        countdownStartedAt = nil
        if countdownMode == .targetDate { countdownTargetDate = nil }
    }

    mutating func setCountdownMode(_ mode: CountdownMode) {
        guard countdownMode != mode else { return }
        countdownMode = mode
        countdownTargetDate = nil
        countdownElapsedBeforeStart = 0
        countdownStartedAt = nil
    }

    mutating func setCountdownTarget(_ target: Date) {
        countdownMode = .targetDate
        countdownTargetDate = target
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
    /// When a one-time alarm rings, recorded when it is armed. Nil for repeating alarms and older saved alarms.
    var scheduledFireDate: Date? = nil

    /// A copy armed from `now`: a one-time alarm records its next ring, so once that passes it reads as off.
    func armed(now: Date = .now) -> DockAlarm {
        var copy = self
        copy.scheduledFireDate = isEnabled && repeatWeekdays.isEmpty
            ? AlarmSchedule.nextFireDate(hour: hour, minute: minute, now: now) : nil
        return copy
    }

    /// A one-time alarm whose ring time has passed: it rang, so it is no longer armed.
    func hasRung(now: Date) -> Bool {
        repeatWeekdays.isEmpty && (scheduledFireDate.map { $0 <= now } ?? false)
    }
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
    var url: URL { didSet { id = Self.identity(of: url) } }
    /// The resolved bundle path, computed when the URL is set rather than on every list diff and render.
    private(set) var id: String
    var hasExistingBundlePath: Bool { url.isFileURL && FileManager.default.fileExists(atPath: url.path) }

    private enum CodingKeys: String, CodingKey { case bundleIdentifier, name, url }

    init(url: URL) {
        self.url = url
        id = Self.identity(of: url)
        let bundle = url.isFileURL ? Bundle(url: url) : nil
        bundleIdentifier = bundle?.bundleIdentifier
        name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try values.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        name = try values.decode(String.self, forKey: .name)
        url = try values.decode(URL.self, forKey: .url)
        id = Self.identity(of: url)
    }

    /// Equality and hashing cover the stored fields only; the identity is derived from the URL.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.bundleIdentifier == rhs.bundleIdentifier && lhs.name == rhs.name && lhs.url == rhs.url
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(bundleIdentifier); hasher.combine(name); hasher.combine(url)
    }

    private static func identity(of url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
}

struct DockProfile: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var kind: DockProfileKind
    var color: String = "blue"
    var items: [DockItem] = []
    var createdAt: Date = .now
    var appearance: ProfileAppearance?
    /// Optional Start Workspace selection (see DockWorkspace). Nil for existing profiles.
    var workspace: DockWorkspace?
}

extension DockProfile {
    /// Fields that have defaults may be absent; settings that no longer decode fall back. The identity, name, kind
    /// and items stay strict, so a Dock that cannot be read is set aside on its own (see `PersistentStateLoader`).
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(DockProfileKind.self, forKey: .kind)
        color = values.lenient(String.self, forKey: .color) ?? "blue"
        items = try values.decodeIfPresent([DockItem].self, forKey: .items) ?? []
        createdAt = values.lenient(Date.self, forKey: .createdAt) ?? .now
        appearance = values.lenient(ProfileAppearance.self, forKey: .appearance)
        workspace = values.lenient(DockWorkspace.self, forKey: .workspace)
    }
}

struct DockProfileDraft: Equatable {
    private(set) var original: DockProfile
    private(set) var profile: DockProfile

    var isDirty: Bool { profile != original }

    init(profile: DockProfile) {
        original = profile.strippedOfRuntimeReadings
        self.profile = original
    }

    mutating func update(_ change: (inout DockProfile) -> Void) {
        change(&profile)
        profile = profile.strippedOfRuntimeReadings
    }

    mutating func discard() {
        profile = original
    }

    mutating func markSaved(_ savedProfile: DockProfile) {
        original = savedProfile.strippedOfRuntimeReadings
        profile = original
    }

    mutating func moveItems(_ itemIDs: Set<UUID>, direction: DockItemMoveDirection) {
        profile.items = DockItemOrderingPolicy.moving(profile.items, ids: itemIDs, direction: direction)
    }
}

enum MyDockSettingsPage: String, Codable, CaseIterable, Identifiable {
    case general
    case dock
    case appearance
    case behavior
    case shortcuts
    case integrations
    case permissions

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dock: "Dock Setup"
        case .appearance: "Appearance"
        case .behavior: "Behavior"
        case .general: "General"
        case .permissions: "Permissions"
        case .integrations: "Integrations"
        case .shortcuts: "Shortcuts"
        }
    }
    var symbol: String {
        switch self {
        case .dock: "dock.rectangle"
        case .appearance: "paintbrush"
        case .behavior: "hand.draw"
        case .general: "gearshape"
        case .permissions: "hand.raised"
        case .integrations: "puzzlepiece.extension"
        case .shortcuts: "command.square"
        }
    }
    var searchTerms: String {
        switch self {
        case .dock: "dock setup profiles mode display position focus native switching auto save freeze"
        case .appearance: "appearance material glass dark frosted cards labels widget width density size spacing radius tint edge hairline contrast only surface plain tile floating inset auto clear solid midnight style"
        case .behavior: "behavior auto hide reveal desktop running apps minimized windows previews trash badges magnification accessibility"
        case .general: "general backup restore diagnostics export saved docks"
        case .permissions: "permissions privacy calendar reminders location automation notification screen recording accessibility"
        case .integrations: "integrations stripe paddle shopify market alpha vantage copilot github key token"
        case .shortcuts: "shortcuts keyboard hotkeys global profile"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var setupMode: SetupMode = .both
    var activeNativeProfileID: UUID?
    var activeCustomProfileID: UUID?
    var customDockPosition: DockPosition = .bottom
    var customDockSize: Double = 1
    var customDockItemSpacing: Double = 8
    var customDockCornerRadius: Double = 24
    var customDockTintStrength: Double = 0.08
    var customDockEdgeStyle: DockEdgeStyle = .hairline
    var customDockWidgetSurface: DockWidgetSurface = .tile
    var customDockFloatingInset: Double = 0
    var customDockTintMode: DockTintMode = .custom
    var customDockGlassOpacity: Double = 0
    var dockAnimationsEnabled = true
    var dockAnimationStyle: DockAnimationStyle = .slide
    var customDockWidgetStyle: CustomDockWidgetStyle = .cards
    var showWidgetLabels = true
    var customDockDisplayID: UInt32?
    var automaticallyHideCustomDock = false
    var showRevealHandle = true
    var hideCustomDockWhenSystemDockAppears = false
    var customDockDesktopMode = false
    var customDockMaterial: CustomDockMaterial = .frosted
    var customDockTheme: CustomDockTheme = .system
    var smoothNativeDockSwitches = false
    var showRunningApps = true
    var showRecentApps = false
    var showMinimizedWindows = false
    var showWindowPreviews = false
    /// PX-2: hover a running app tile to see its windows. Off by default.
    var showWindowPreviewsOnHover = false
    var showTrash = false
    var showAppBadges = false
    var clickFocusedAppToMinimize = false
    var magnificationEnabled = false
    var automaticallySaveNativeDockChanges = false
    var showActiveProfileNameInMenuBar = false
    var onboardingComplete = false
    var lastSettingsPage: MyDockSettingsPage = .dock
    /// Marketing version whose What's New sheet was last shown or skipped by setup. Nil on old state.
    var lastSeenWhatsNewVersion: String?
    var automaticSwitching = AutomaticSwitchingSettings()

    private enum CodingKeys: String, CodingKey {
        case customDockEdgeStyle, customDockWidgetSurface, customDockFloatingInset, customDockTintMode
        case customDockTheme
        case customDockGlassOpacity, dockAnimationsEnabled, dockAnimationStyle
        case setupMode, activeNativeProfileID, activeCustomProfileID, customDockPosition, customDockSize
        case customDockItemSpacing, customDockCornerRadius, customDockTintStrength, customDockWidgetStyle, showWidgetLabels
        case customDockDisplayID, automaticallyHideCustomDock, showRevealHandle, hideCustomDockWhenSystemDockAppears, customDockDesktopMode, customDockMaterial, smoothNativeDockSwitches, showRunningApps
        case showRecentApps
        case showMinimizedWindows, showWindowPreviews, showTrash, showAppBadges, clickFocusedAppToMinimize, magnificationEnabled
        case showWindowPreviewsOnHover
        case automaticallySaveNativeDockChanges, showActiveProfileNameInMenuBar, onboardingComplete, lastSettingsPage
        case lastSeenWhatsNewVersion
        case automaticSwitching
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        customDockTheme = values.lenient(CustomDockTheme.self, forKey: .customDockTheme) ?? .system
        customDockGlassOpacity = Self.bounded(try values.decodeIfPresent(Double.self, forKey: .customDockGlassOpacity), default: 0, range: 0...1)
        dockAnimationsEnabled = try values.decodeIfPresent(Bool.self, forKey: .dockAnimationsEnabled) ?? true
        dockAnimationStyle = (try? values.decodeIfPresent(DockAnimationStyle.self, forKey: .dockAnimationStyle)) ?? .slide
        setupMode = values.lenient(SetupMode.self, forKey: .setupMode) ?? .both
        activeNativeProfileID = values.lenient(UUID.self, forKey: .activeNativeProfileID)
        activeCustomProfileID = values.lenient(UUID.self, forKey: .activeCustomProfileID)
        customDockPosition = values.lenient(DockPosition.self, forKey: .customDockPosition) ?? .bottom
        customDockSize = Self.bounded(try values.decodeIfPresent(Double.self, forKey: .customDockSize), default: 1, range: 0.65...1.5)
        customDockItemSpacing = Self.bounded(try values.decodeIfPresent(Double.self, forKey: .customDockItemSpacing), default: 8, range: DockAppearanceBounds.itemSpacing)
        customDockCornerRadius = Self.bounded(try values.decodeIfPresent(Double.self, forKey: .customDockCornerRadius), default: 24, range: DockAppearanceBounds.cornerRadius)
        customDockTintStrength = Self.bounded(try values.decodeIfPresent(Double.self, forKey: .customDockTintStrength), default: 0.08, range: DockAppearanceBounds.tintStrength)
        customDockEdgeStyle = (try? values.decodeIfPresent(DockEdgeStyle.self, forKey: .customDockEdgeStyle)) ?? .hairline
        customDockWidgetSurface = (try? values.decodeIfPresent(DockWidgetSurface.self, forKey: .customDockWidgetSurface)) ?? .tile
        customDockFloatingInset = Self.bounded(try values.decodeIfPresent(Double.self, forKey: .customDockFloatingInset), default: 0, range: DockAppearanceBounds.floatingInset)
        customDockTintMode = (try? values.decodeIfPresent(DockTintMode.self, forKey: .customDockTintMode)) ?? .custom
        customDockWidgetStyle = values.lenient(CustomDockWidgetStyle.self, forKey: .customDockWidgetStyle) ?? .cards
        showWidgetLabels = try values.decodeIfPresent(Bool.self, forKey: .showWidgetLabels) ?? true
        customDockDisplayID = values.lenient(UInt32.self, forKey: .customDockDisplayID)
        automaticallyHideCustomDock = try values.decodeIfPresent(Bool.self, forKey: .automaticallyHideCustomDock) ?? false
        showRevealHandle = try values.decodeIfPresent(Bool.self, forKey: .showRevealHandle) ?? true
        hideCustomDockWhenSystemDockAppears = try values.decodeIfPresent(Bool.self, forKey: .hideCustomDockWhenSystemDockAppears) ?? false
        customDockDesktopMode = try values.decodeIfPresent(Bool.self, forKey: .customDockDesktopMode) ?? false
        customDockMaterial = values.lenient(CustomDockMaterial.self, forKey: .customDockMaterial) ?? .frosted
        smoothNativeDockSwitches = try values.decodeIfPresent(Bool.self, forKey: .smoothNativeDockSwitches) ?? false
        showRunningApps = try values.decodeIfPresent(Bool.self, forKey: .showRunningApps) ?? true
        showRecentApps = try values.decodeIfPresent(Bool.self, forKey: .showRecentApps) ?? false
        showMinimizedWindows = try values.decodeIfPresent(Bool.self, forKey: .showMinimizedWindows) ?? false
        showWindowPreviews = try values.decodeIfPresent(Bool.self, forKey: .showWindowPreviews) ?? false
        showWindowPreviewsOnHover = (try? values.decodeIfPresent(Bool.self, forKey: .showWindowPreviewsOnHover)) ?? false
        showTrash = try values.decodeIfPresent(Bool.self, forKey: .showTrash) ?? false
        showAppBadges = try values.decodeIfPresent(Bool.self, forKey: .showAppBadges) ?? false
        clickFocusedAppToMinimize = try values.decodeIfPresent(Bool.self, forKey: .clickFocusedAppToMinimize) ?? false
        magnificationEnabled = try values.decodeIfPresent(Bool.self, forKey: .magnificationEnabled) ?? false
        automaticallySaveNativeDockChanges = try values.decodeIfPresent(Bool.self, forKey: .automaticallySaveNativeDockChanges) ?? false
        showActiveProfileNameInMenuBar = try values.decodeIfPresent(Bool.self, forKey: .showActiveProfileNameInMenuBar) ?? false
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        lastSettingsPage = values.lenient(MyDockSettingsPage.self, forKey: .lastSettingsPage) ?? .dock
        lastSeenWhatsNewVersion = try? values.decodeIfPresent(String.self, forKey: .lastSeenWhatsNewVersion)
        automaticSwitching = (try? values.decodeIfPresent(AutomaticSwitchingSettings.self, forKey: .automaticSwitching)) ?? AutomaticSwitchingSettings()
    }

    private static func bounded(_ value: Double?, default fallback: Double, range: ClosedRange<Double>) -> Double {
        DockAppearanceBounds.clamped(value, default: fallback, to: range)
    }
}

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case left
    case bottom
    case right

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct PersistentState: Codable, Equatable {
    var schemaVersion = Product.stateSchemaVersion
    var profiles: [DockProfile] = []
    var settings = AppSettings()
}

enum WidgetCategory: String, CaseIterable {
    case utilities = "Everyday Tools"
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
    var capabilities: WidgetCapabilities
    var id: String { name }
}

enum WidgetRegistry {
    static func definition(named name: String) -> WidgetDefinition? { byName[name] }
    private static let byName: [String: WidgetDefinition] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    static let airDropSymbol = "dot.radiowaves.left.and.right"
    static let all: [WidgetDefinition] = [
        .init(name: "Stock", symbol: "chart.line.uptrend.xyaxis", category: .business, description: "Follow a market ticker.",
              capabilities: .init(layouts: WidgetLayoutPresets.market, defaultLayout: .compact, hasSetupState: true, refreshDemand: .remoteFetch)),
        .init(name: "Watchlist", symbol: "chart.xyaxis.line", category: .business, description: "Compare saved tickers.",
              capabilities: .init(layouts: WidgetLayoutPresets.market, defaultLayout: .compact, hasSetupState: true, refreshDemand: .remoteFetch)),
        .init(name: "Calendar", symbol: "calendar", category: .productivity, description: "See the date and upcoming events.",
              capabilities: .init(layouts: WidgetLayoutPresets.schedule, defaultLayout: .compact, permissions: [.calendars], hasSetupState: true, holdsPrivateContent: true, refreshDemand: .externalSource)),
        .init(name: "Reminders", symbol: "checklist", category: .productivity, description: "View and complete reminders.",
              capabilities: .init(layouts: WidgetLayoutPresets.schedule, defaultLayout: .compact, permissions: [.reminders], hasSetupState: true, holdsPrivateContent: true, refreshDemand: .externalSource)),
        .init(name: "Now Playing", symbol: "music.note", category: .personal, description: "Control Apple Music or Spotify.",
              capabilities: .init(layouts: WidgetLayoutPresets.nowPlaying, defaultLayout: .wide, permissions: [.automation], holdsPrivateContent: true, refreshDemand: .externalSource)),
        .init(name: "Weather", symbol: "cloud.sun", category: .personal, description: "See current conditions and forecast.",
              capabilities: .init(layouts: WidgetLayoutPresets.weather, defaultLayout: .standard, permissions: [.location], hasSetupState: true, refreshDemand: .remoteFetch)),
        .init(name: "Focus Timer", symbol: "timer", category: .productivity, description: "Keep a focus session close.",
              capabilities: .init(layouts: WidgetLayoutPresets.timer, defaultLayout: .compact, permissions: [.notifications], refreshDemand: .timeTick)),
        .init(name: "Sticky Note", symbol: "note.text", category: .productivity, description: "Keep a note in your Dock.",
              capabilities: .init(layouts: WidgetLayoutPresets.stickyNote, defaultLayout: .standard, holdsPrivateContent: true)),
        .init(name: "Battery", symbol: "battery.100", category: .system, description: "See Mac and accessory battery state.",
              capabilities: .init(layouts: WidgetLayoutPresets.battery, defaultLayout: .compact, refreshDemand: .localSampling)),
        .init(name: "Shortcuts", symbol: "command.square", category: .productivity, description: "Run a macOS shortcut.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickAction, defaultLayout: .icon, permissions: [.automation], hasSetupState: true)),
        .init(name: "Stripe", symbol: "creditcard", category: .business, description: "Read Stripe revenue metrics.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, needsConnection: true, hasSetupState: true, holdsPrivateContent: true, refreshDemand: .remoteFetch)),
        .init(name: "Paddle", symbol: "creditcard.fill", category: .business, description: "Read Paddle Billing metrics.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, needsConnection: true, hasSetupState: true, holdsPrivateContent: true, refreshDemand: .remoteFetch)),
        .init(name: "Shopify", symbol: "bag", category: .business, description: "Read Shopify order metrics.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, needsConnection: true, hasSetupState: true, holdsPrivateContent: true, refreshDemand: .remoteFetch)),
        .init(name: "Clock", symbol: "clock", category: .time, description: "See the local time.",
              capabilities: .init(layouts: WidgetLayoutPresets.clock, defaultLayout: .compact, refreshDemand: .timeTick)),
        .init(name: "World Clock", symbol: "globe", category: .time, description: "Track time in other places.",
              capabilities: .init(layouts: WidgetLayoutPresets.worldClock, defaultLayout: .compact, hasSetupState: true, refreshDemand: .timeTick)),
        .init(name: "Stopwatch", symbol: "stopwatch", category: .time, description: "Measure elapsed time.",
              capabilities: .init(layouts: WidgetLayoutPresets.timer, defaultLayout: .compact, refreshDemand: .timeTick)),
        .init(name: "Countdown", symbol: "hourglass", category: .time, description: "Count down to a date or duration.",
              capabilities: .init(layouts: WidgetLayoutPresets.timer, defaultLayout: .compact, permissions: [.notifications], hasSetupState: true, refreshDemand: .timeTick)),
        .init(name: "Alarm", symbol: "alarm", category: .time, description: "Keep local alarms.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, permissions: [.notifications], refreshDemand: .timeTick)),
        .init(name: "Time Progress", symbol: "chart.pie", category: .time, description: "See progress through a period.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, refreshDemand: .timeTick)),
        .init(name: "Hydration", symbol: "drop", category: .personal, description: "Track water and reminders.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, permissions: [.notifications])),
        .init(name: "System Activity", symbol: "cpu", category: .system, description: "Inspect CPU, memory, and storage.",
              capabilities: .init(layouts: WidgetLayoutPresets.systemActivity, defaultLayout: .compact, refreshDemand: .localSampling)),
        .init(name: "Network Activity", symbol: "network", category: .system, description: "See network activity and interfaces.",
              capabilities: .init(layouts: WidgetLayoutPresets.networkActivity, defaultLayout: .compact, refreshDemand: .localSampling)),
        .init(name: "Audio Output", symbol: "speaker.wave.2", category: .system, description: "Switch sound output and set volume.",
              capabilities: .init(layouts: WidgetLayoutPresets.audioOutput, defaultLayout: .compact, refreshDemand: .localSampling)),
        .init(name: "AI Limits", symbol: "gauge.with.dots.needle.67percent", category: .ai, description: "Show available provider limits.",
              capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact, needsConnection: true, hasSetupState: true, holdsPrivateContent: true, refreshDemand: .remoteFetch)),
        .init(name: "AI Activity", symbol: "sparkles.rectangle.stack", category: .ai, description: "Review local provider activity.",
              capabilities: .init(layouts: WidgetLayoutPresets.aiActivity, defaultLayout: .standard, holdsPrivateContent: true, refreshDemand: .localSampling)),
        .init(name: "AirDrop", symbol: airDropSymbol, category: .system, description: "Send files with AirDrop.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickAction, defaultLayout: .icon)),
        .init(name: "Trash", symbol: "trash", category: .system, description: "Open Trash and empty it after confirmation.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickAction, defaultLayout: .icon, permissions: [.automation], refreshDemand: .localSampling)),
        .init(name: "Disk Space", symbol: "internaldrive", category: .system, description: "Keep an eye on available startup disk space.",
              capabilities: .init(layouts: WidgetLayoutPresets.diskSpace, defaultLayout: .compact, refreshDemand: .localSampling)),
        .init(name: "Calculator", symbol: "plus.forwardslash.minus", category: .utilities, description: "Calculate expressions without leaving your Dock.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickAction, defaultLayout: .icon)),
        .init(name: "Quick Checklist", symbol: "checklist", category: .utilities, description: "Keep a small, private checklist without an account.",
              capabilities: .init(layouts: WidgetLayoutPresets.schedule, defaultLayout: .compact, holdsPrivateContent: true)),
        .init(name: "File Shelf", symbol: "tray.and.arrow.down", category: .utilities, description: "Drop files, keep them for later, copy or share with AirDrop.",
              capabilities: .init(layouts: WidgetLayoutPresets.savedCollection, defaultLayout: .compact, holdsPrivateContent: true)),
        .init(name: "Text Snippets", symbol: "doc.on.clipboard", category: .utilities, description: "Save reusable text and copy it when you need it.",
              capabilities: .init(layouts: WidgetLayoutPresets.savedCollection, defaultLayout: .compact, holdsPrivateContent: true)),
        .init(name: "Quick Links", symbol: "link", category: .utilities, description: "Keep your favorite websites in one small collection.",
              capabilities: .init(layouts: WidgetLayoutPresets.savedCollection, defaultLayout: .compact, holdsPrivateContent: true)),
        .init(name: "Unit Converter", symbol: "arrow.left.arrow.right", category: .utilities, description: "Convert length, weight, temperature, volume, speed and data.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickTool, defaultLayout: .icon)),
        .init(name: "Color Picker", symbol: "eyedropper", category: .utilities, description: "Pick a screen color, copy HEX or RGB, and save a palette.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickTool, defaultLayout: .icon)),
        .init(name: "App Folder", symbol: "square.grid.2x2", category: .productivity, description: "Group apps together.",
              capabilities: .init(layouts: WidgetLayoutPresets.quickAction, defaultLayout: .icon))
    ]
}
