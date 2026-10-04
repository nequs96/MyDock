import SwiftUI

private struct DockWidgetContentWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 54 }
extension EnvironmentValues {
    var dockWidgetContentWidth: CGFloat { get { self[DockWidgetContentWidthKey.self] } set { self[DockWidgetContentWidthKey.self] = newValue } }
}

/// Compatibility surface for inert gallery callers. Live presentation uses WidgetContainer.
struct AppleWidgetSurface: View {
    var kind: String
    var noteBackground: NoteBackground = .yellow
    var cornerRadius: CGFloat = 16
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.primary.opacity(0.045))
    }
}

struct WidgetSparkline: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        let points = Array(values.filter(\.isFinite).suffix(100))
        guard points.count > 1, let low = points.min(), let high = points.max() else { return Path() }
        let span = max(high - low, 0.0001)
        return Path { path in
            for (index, value) in points.enumerated() {
                let point = CGPoint(x: rect.minX + CGFloat(index) / CGFloat(points.count - 1) * rect.width,
                                    y: high == low ? rect.midY : rect.maxY - CGFloat((value - low) / span) * rect.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
}

/// This is a labeled sample renderer, never used as live data or written to a profile.
/// The same semantic faces render provider data in the Dock.
struct WidgetCardPreview: View {
    var kind: String
    var width: CGFloat = 144
    var displayScale: CGFloat = 1
    var layout: WidgetLayout? = nil
    var appearance: WidgetIconAppearance = .soft
    private var selected: WidgetLayout { layout ?? WidgetPresentationCatalog.defaultLayout(for: kind) }
    var body: some View {
        WidgetContainer(width: width, kind: kind) { sample }
            .environment(\.dockWidgetContentWidth, width).environment(\.widgetLayout, selected).environment(\.widgetIconAppearance, appearance)
            .scaleEffect(displayScale).frame(width: width * displayScale, height: 54 * displayScale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.accessibilityLabel(kind: kind))
    }
    @ViewBuilder private var sample: some View {
        switch kind {
        case "Stock": StockCompactView(item: StockFaceSample.item(kind: kind))
        case "Watchlist": WatchlistCompactView(item: StockFaceSample.item(kind: kind))
        case "AI Activity": AIActivityCompactView(item: AIActivityPreviewData.item())
        case "System Activity": SystemTelemetryDockFace(cpu: 37, history: [15, 21, 30, 18, 28, 37, 29, 37], memory: nil, load: .init(oneMinute: 2.4, fiveMinutes: 1.9, fifteenMinutes: 1.4), secondary: .load)
        case "Network Activity": NetworkDockFace(download: 2_400_000, upload: 148_000, history: [1, 4, 3, 8, 5, 4, 7, 6])
        case "Battery": BatteryDockFace(readings: [.init(name: "Mac", percentage: 84, isCharging: false, isInternal: true), .init(name: "AirPods", percentage: 92, isCharging: false, isInternal: false)])
        case "Disk Space": DiskDockFace(snapshot: .init(name: "Startup disk", totalBytes: 500_000_000_000, availableBytes: 128_000_000_000))
        case "Weather": WeatherDockFace(configuration: weatherSample)
        case "Now Playing": MediaDockFace(title: "Dreams", artist: "Fleetwood Mac", artwork: nil, isPlaying: true)
        case "World Clock": WorldClockDockFace(configuration: WidgetConfiguration())
        case "Reminders": RemindersDockFace(count: 3, context: "Weekend errands")
        case "Stripe", "Paddle", "Shopify": FacesBBusinessDockFace(kind: kind, title: kind, metric: kind == "Shopify" ? "Order value" : "Revenue", amount: 2_400, currency: "USD", fullValue: "$2,400.00", context: "Today")
        case "Alarm":
            // Mirrors the live Alarm face: label and the next alarm time; its name on wider layouts.
            ModuleStack(kind: kind, label: "Alarm", value: "7:30", trailing: width >= 100 ? "Morning" : nil).moduleInsets()
        case "Calendar":
            CalendarSampleFace(kind: kind, wide: selected == .wide)
        case "AI Limits": AILimitsCompactView(item: AILimitsFaceSample.item())
        default: LocalWidgetDockFace(item: sampleItem)
        }
    }
    private var sampleItem: DockItem {
        var item = DockItem.widget(kind)
        if kind == "Sticky Note" { item.widgetConfiguration?.noteText = "Make something great.\nTake a little break." }
        if kind == "File Shelf" { item.widgetConfiguration?.shelfFiles = [ShelfFile(url: URL(fileURLWithPath: "/Sample/Presentation.pdf")), ShelfFile(url: URL(fileURLWithPath: "/Sample/Photo.jpg"))] }
        if kind == "Text Snippets" { item.widgetConfiguration?.textSnippets = [TextSnippet(title: "Email reply", text: "Thanks for getting in touch."), TextSnippet(title: "Delivery address", text: "123 Example Street")] }
        if kind == "Quick Links" { item.widgetConfiguration?.quickLinks = [QuickLink(title: "Project workspace", url: URL(string: "https://example.com")!)] }
        if kind == "Quick Checklist" { item.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "Plan the weekend"), QuickChecklistEntry(title: "Pick up groceries"), QuickChecklistEntry(title: "Book appointment")] }
        if kind == "Stock" || kind == "Watchlist" {
            let snapshot = StockMarketSnapshot(symbol: "AAPL", points: [181.2, 182.5, 181.8, 185.1, 184.3, 186.2, 185.9].enumerated().map { index, value in StockMarketPoint(date: .now.addingTimeInterval(Double(index - 6) * 86400), close: value, volume: 0) }, currency: "USD", fetchedAt: .now)
            item.widgetConfiguration?.stockSymbol = "AAPL"
            item.widgetConfiguration?.stockSnapshot = snapshot
            if kind == "Watchlist" { item.widgetConfiguration?.watchlistStocks = [.init(symbol: "AAPL", name: "Apple", currency: "USD", snapshot: snapshot)] }
        }
        return item
    }
    private var weatherSample: WidgetConfiguration {
        var config = WidgetConfiguration()
        config.cachedWeatherForecast = WeatherForecast(temperature: 21, apparentTemperature: 20, relativeHumidity: 50, precipitation: 0, windSpeed: 8, weatherCode: 2, isDay: true, fetchedAt: .now, timeZoneIdentifier: "Europe/Warsaw",
            hourly: (1...3).map { .init(timestamp: Date.now.addingTimeInterval(Double($0) * 3600), temperature: Double(21 + $0), precipitationProbability: nil, weatherCode: 2) })
        return config
    }
}

extension WidgetCardPreview {
    /// VoiceOver label for every sample: "<Family>, sample preview".
    static func accessibilityLabel(kind: String) -> String { "\(kind), sample preview" }
}

/// Sample Calendar face in the module grammar: weekday over the day, the next event on wide layouts.
private struct CalendarSampleFace: View {
    var kind: String
    var wide: Bool
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetAccent) private var accent
    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text("THU").font(DockDesign.Module.label).foregroundStyle(WidgetPalette.resolved(kind: kind, accent: accent))
                Text("1").font(DockDesign.Module.valueLarge)
            }
            if wide && width > 54 {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Design review").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("10:30 AM").font(DockDesign.Module.label).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.moduleInsets()
    }
}

/// Retained only for earlier debug QA entry points; does not define live layout.
struct AppleWidgetCard: View {
    var item: DockItem
    var width: CGFloat
    var showsLabels: Bool
    var fallback: AnyView
    var body: some View { WidgetContainer(width: width, kind: item.widgetKind ?? item.title) { fallback }.environment(\.dockWidgetContentWidth, width) }
}
