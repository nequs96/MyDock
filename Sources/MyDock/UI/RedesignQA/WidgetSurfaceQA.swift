#if DEBUG
import AppKit
import SwiftUI

/// RD-05 widget chrome export (`MYDOCK_WIDGETSURFACE_QA=1`): every registry family × advertised layout ×
/// widget surface × appearance over a wallpaper and a Dock strip, plus side-Dock, accessibility, accent,
/// labels-off and sample-vs-live pages. Offscreen captures cannot see the Liquid Glass compositor, so
/// glass modules and the Dock strip draw their documented fallbacks; judge layout and type from them.
extension PremiumVisualQA {
    static func exportWidgetSurfaceUI(to directory: URL, store: ProfileStore) async throws {
        let schemes: [(ColorScheme, String)] = [(.light, "light"), (.dark, "dark")]
        var matrix = WidgetQAMatrix()
        for (scheme, schemeName) in schemes {
            for surface in DockWidgetSurface.allCases {
                for category in WidgetCategory.allCases {
                    let kinds = WidgetRegistry.all.filter { $0.category == category }.map(\.name)
                    guard !kinds.isEmpty else { continue }
                    let name = category.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
                    try await render(WidgetSurfaceQAPage(title: "\(category.rawValue) · \(surface.rawValue) · \(schemeName)") {
                        ForEach(kinds, id: \.self) { kind in WidgetSurfaceQARow(kind: kind) }
                    }.environment(\.dockWidgetSurface, surface),
                    name: "widgetsurface-matrix-\(name)-\(surface.rawValue)-\(schemeName)",
                    size: NSSize(width: 640, height: CGFloat(70 + kinds.count * 92)), scheme: scheme, directory: directory)
                    for kind in kinds {
                        for option in WidgetPresentationCatalog.options(for: kind) { matrix.record(kind, .layout(option.layout)) }
                    }
                }
                try await renderSideDock(surface: surface, scheme: scheme, schemeName: schemeName, directory: directory)
                for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true),
                                                          ("increase-contrast", .increased, false)] {
                    try await render(WidgetSurfaceQAPage(title: "\(variant.replacingOccurrences(of: "-", with: " ").capitalized) · \(surface.rawValue) · \(schemeName)") {
                        WidgetSurfaceQASampleDock(kinds: WidgetSurfaceQA.representative)
                    }.environment(\.dockWidgetSurface, surface),
                    name: "widgetsurface-\(variant)-\(surface.rawValue)-\(schemeName)", size: NSSize(width: 1180, height: 170),
                    scheme: scheme, directory: directory, contrast: contrast, reduceTransparency: transparency)
                }
            }
            try await render(WidgetSurfaceQAPage(title: "Accents and icon treatments · \(schemeName)") { WidgetSurfaceQAAccents() },
                             name: "widgetsurface-accents-\(schemeName)", size: NSSize(width: 1080, height: 640), scheme: scheme, directory: directory)
            try await render(WidgetSurfaceQAPage(title: "Labels on and off · \(schemeName)") {
                ForEach(DockWidgetSurface.allCases, id: \.self) { surface in
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetSurfaceQACaption(text: "\(surface.rawValue) · labels on")
                        WidgetSurfaceQASampleDock(kinds: WidgetSurfaceQA.representative)
                        WidgetSurfaceQACaption(text: "\(surface.rawValue) · labels off")
                        WidgetSurfaceQASampleDock(kinds: WidgetSurfaceQA.representative).environment(\.widgetShowsLabel, false)
                    }.environment(\.dockWidgetSurface, surface)
                }
            }, name: "widgetsurface-labels-\(schemeName)", size: NSSize(width: 1180, height: 600), scheme: scheme, directory: directory)
            // FX-03: long readings that used to truncate (Disk, Now Playing, Sticky Note, business periods).
            try await render(WidgetSurfaceQAPage(title: "Long readings · \(schemeName)") {
                ForEach([true, false], id: \.self) { labels in
                    VStack(alignment: .leading, spacing: 6) {
                        WidgetSurfaceQACaption(text: labels ? "labels on" : "labels off")
                        WidgetSurfaceQALongReadings().environment(\.widgetShowsLabel, labels)
                    }
                }
            }.environment(\.dockWidgetSurface, .glass),
            name: "widgetsurface-long-readings-\(schemeName)", size: NSSize(width: 1380, height: 300), scheme: scheme, directory: directory)
            try await renderSampleVersusLive(store: store, scheme: scheme, schemeName: schemeName, directory: directory)
        }
        // Layout coverage only; setup states are covered by MYDOCK_WIDGET_QA.
        let missingLayouts = matrix.missing().filter { !$0.hasSuffix(WidgetQAState.setup.description) }
        if !missingLayouts.isEmpty { throw WidgetQAMatrix.Failure(missing: missingLayouts) }
    }

    private static func renderSideDock(surface: DockWidgetSurface, scheme: ColorScheme, schemeName: String, directory: URL) async throws {
        let kinds = WidgetRegistry.all.map(\.name)
        let columns = stride(from: 0, to: kinds.count, by: 12).map { Array(kinds[$0..<min($0 + 12, kinds.count)]) }
        try await render(WidgetSurfaceQAPage(title: "Side Dock · \(surface.rawValue) · \(schemeName)") {
            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    WidgetSurfaceQADockStrip(axis: .vertical) {
                        ForEach(column, id: \.self) { kind in
                            // Side Docks use the narrow 54 pt presentation: icon for quick actions, compact otherwise.
                            let layout: WidgetLayout = WidgetPresentationCatalog.options(for: kind).first?.layout == .icon ? .icon : .compact
                            WidgetCardPreview(kind: kind, width: 54, layout: layout)
                        }
                    }
                }
            }
        }.environment(\.dockWidgetSurface, surface),
        name: "widgetsurface-side-\(surface.rawValue)-\(schemeName)", size: NSSize(width: 420, height: 880), scheme: scheme, directory: directory)
    }

    private static func renderSampleVersusLive(store: ProfileStore, scheme: ColorScheme, schemeName: String, directory: URL) async throws {
        let id = try store.createProfileAndPersist(kind: .custom, name: "Widget surface QA \(schemeName)")
        let items = WidgetSurfaceQA.liveFixtures()
        for item in items { store.add(item, to: id) }
        var settings = store.state.settings
        settings.customDockPosition = .bottom
        settings.customDockWidgetStyle = .cards
        // FX-09: samples pass no appearance, so they show the creation appearance (Mono) a new widget gets.
        try await render(WidgetSurfaceQAPage(title: "Sample (left, creation appearance) and live new widget (right) · same face views · \(schemeName)") {
            ForEach(DockWidgetSurface.allCases, id: \.self) { surface in
                let surfaceSettings = settings.with(surface: surface)
                VStack(alignment: .leading, spacing: 6) {
                    WidgetSurfaceQACaption(text: surface.rawValue)
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(items) { item in
                            let kind = item.widgetKind ?? item.title
                            let layout = item.widgetConfiguration?.widgetLayout ?? WidgetPresentationCatalog.defaultLayout(for: kind)
                            WidgetSurfaceQADockStrip {
                                WidgetCardPreview(kind: kind, width: CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)), layout: layout)
                                    .environment(\.dockWidgetSurface, surface)
                                WidgetCompactView(store: store, item: item, profileID: id, presentationSettings: surfaceSettings)
                            }
                        }
                    }
                }
            }
        }, name: "widgetsurface-sample-vs-live-\(schemeName)", size: NSSize(width: 1500, height: 420), scheme: scheme, directory: directory)
    }
}

enum WidgetSurfaceQA {
    /// One family per face style, at its default layout.
    static let representative = ["System Activity", "Network Activity", "Battery", "Weather", "Now Playing", "Clock",
                                 "Stock", "Stripe", "Reminders", "Calculator", "AI Activity"]

    /// Live fixtures whose faces are fully determined by their configuration (no system access, no network).
    static func liveFixtures() -> [DockItem] {
        var clock = DockItem.widget("Clock"); clock.widgetConfiguration?.widgetLayout = .standard
        var weather = DockItem.widget("Weather")
        weather.widgetConfiguration?.cachedWeatherForecast = WeatherForecast(temperature: 21, apparentTemperature: 20, relativeHumidity: 50, precipitation: 0, windSpeed: 8,
            weatherCode: 2, isDay: true, fetchedAt: .now, timeZoneIdentifier: "Europe/Warsaw",
            hourly: (1...3).map { .init(timestamp: Date.now.addingTimeInterval(Double($0) * 3600), temperature: Double(21 + $0), precipitationProbability: nil, weatherCode: 2) })
        var checklist = DockItem.widget("Quick Checklist")
        checklist.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "Plan the weekend"), QuickChecklistEntry(title: "Pick up groceries"), QuickChecklistEntry(title: "Book appointment")]
        var stock = DockItem.widget("Stock")
        let snapshot = StockMarketSnapshot(symbol: "AAPL", points: [181.2, 182.5, 181.8, 185.1, 184.3, 186.2, 185.9].enumerated().map { index, value in
            StockMarketPoint(date: .now.addingTimeInterval(Double(index - 6) * 86400), close: value, volume: 0) }, currency: "USD", fetchedAt: .now)
        stock.widgetConfiguration?.stockSymbol = "AAPL"
        stock.widgetConfiguration?.stockSnapshot = snapshot
        stock.widgetConfiguration?.widgetLayout = .trend
        var note = DockItem.widget("Sticky Note")
        note.widgetConfiguration?.noteText = "Call Mia about the trip"
        return [clock, weather, checklist, stock, note, .widget("Calculator")]
    }
}

private extension AppSettings {
    func with(surface: DockWidgetSurface) -> AppSettings {
        var copy = self
        copy.customDockWidgetSurface = surface
        return copy
    }
}

/// A wallpaper with enough structure that glass, blur and edges are visible.
private struct WidgetSurfaceQAWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.10, green: 0.17, blue: 0.32), Color(red: 0.33, green: 0.20, blue: 0.27)]
                       : [Color(red: 0.47, green: 0.65, blue: 0.90), Color(red: 0.95, green: 0.71, blue: 0.58)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .overlay {
            HStack(spacing: 46) {
                ForEach(0..<30, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(scheme == .dark ? 0.06 : 0.16)).frame(width: 30).rotationEffect(.degrees(24))
                }
            }.frame(width: 0)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct WidgetSurfaceQACaption: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

private struct WidgetSurfaceQAPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WidgetSurfaceQAWallpaper().ignoresSafeArea())
    }
}

/// A Dock-like strip: clear glass (its fallback in captures) with Dock padding; modules stay concentric.
private struct WidgetSurfaceQADockStrip<Content: View>: View {
    var axis: Axis = .horizontal
    @ViewBuilder var content: Content
    private static var padding: CGFloat { 7 }
    var body: some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 8))
        layout { content }
            .padding(Self.padding)
            .dockGlass(.clear, in: RoundedRectangle(cornerRadius: DockDesign.Module.defaultRadius + Self.padding, style: .continuous))
            .environment(\.dockModuleRadius, DockDesign.Module.defaultRadius)
    }
}

/// One family: its name and every advertised layout on a Dock strip.
private struct WidgetSurfaceQARow: View {
    var kind: String
    var body: some View {
        let options = WidgetPresentationCatalog.options(for: kind)
        VStack(alignment: .leading, spacing: 4) {
            WidgetSurfaceQACaption(text: kind + " · " + options.map(\.title).joined(separator: ", "))
            WidgetSurfaceQADockStrip {
                ForEach(options) { option in
                    WidgetCardPreview(kind: kind, width: CGFloat(option.width), layout: option.layout)
                }
            }
        }
    }
}

/// A mixed Dock of representative families at their default layouts.
private struct WidgetSurfaceQASampleDock: View {
    var kinds: [String]
    var body: some View {
        WidgetSurfaceQADockStrip {
            ForEach(kinds, id: \.self) { kind in
                let layout = WidgetPresentationCatalog.defaultLayout(for: kind)
                WidgetCardPreview(kind: kind, width: CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)), layout: layout)
            }
        }
    }
}

/// Faces fed long, real-world values: a fractional free-space figure, a long track title, a long
/// note and every business period title.
private struct WidgetSurfaceQALongReadings: View {
    private func module<Face: View>(_ kind: String, _ layout: WidgetLayout, @ViewBuilder _ face: () -> Face) -> some View {
        let width = CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout))
        return WidgetContainer(width: width, kind: kind) { face() }
            .environment(\.dockWidgetContentWidth, width).environment(\.widgetLayout, layout)
    }
    private var note: DockItem {
        var item = DockItem.widget("Sticky Note")
        item.widgetConfiguration?.noteText = "Remember to send the quarterly report\nand book the venue for Friday"
        return item
    }
    var body: some View {
        WidgetSurfaceQADockStrip {
            module("Disk Space", .compact) { DiskDockFace(snapshot: .init(name: "Startup disk", totalBytes: 994_662_584_320, availableBytes: 120_620_000_000)) }
            module("Disk Space", .wide) { DiskDockFace(snapshot: .init(name: "Startup disk", totalBytes: 994_662_584_320, availableBytes: 120_620_000_000)) }
            module("Now Playing", .compact) { MediaDockFace(title: "Everybody Wants to Rule the World", artist: "Tears for Fears", artwork: nil, isPlaying: true) }
            module("Now Playing", .compact) { MediaDockFace(title: "Dreams", artist: "Fleetwood Mac", artwork: nil, isPlaying: false) }
            module("Sticky Note", .standard) { LocalWidgetDockFace(item: note) }
            ForEach(["Today", "7 days", "Last 30 days", "Month to date"], id: \.self) { period in
                module("Paddle", .standard) {
                    BusinessDockFace(kind: "Paddle", title: "Paddle", metric: "Revenue", amount: 12_400, currency: "USD",
                                           fullValue: "$12,400.00", context: period)
                }
            }
        }
    }
}

/// Accent choices (auto, mono, profile colours), glass tint and the four icon treatments.
private struct WidgetSurfaceQAAccents: View {
    private let kinds = ["System Activity", "Weather", "Battery", "Clock"]
    private let accents: [(String, WidgetAccent)] = [("auto", .auto), ("mono", .mono), ("profile blue", .profile(.blue)),
                                                      ("profile pink", .profile(.pink)), ("profile green", .profile(.green))]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(accents, id: \.0) { title, accent in
                HStack(spacing: 14) {
                    WidgetSurfaceQACaption(text: title).frame(width: 90, alignment: .leading)
                    WidgetSurfaceQADockStrip {
                        ForEach(kinds, id: \.self) { kind in
                            let layout = WidgetPresentationCatalog.options(for: kind).last?.layout ?? .compact
                            WidgetCardPreview(kind: kind, width: CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)), layout: layout)
                        }
                        WidgetCardPreview(kind: "Calculator", width: 54, layout: .icon)
                    }
                    .environment(\.widgetAccent, accent)
                    .environment(\.dockWidgetSurface, .glass)
                    .environment(\.widgetGlassTint, title == "auto" ? WidgetGlassTint.none : .accent)
                }
            }
            WidgetSurfaceQACaption(text: "Icon treatments: Color · Soft · Mono · Outline (toggle at rest, toggle active, glyph at 32 pt)")
            HStack(spacing: 14) {
                ForEach(WidgetIconAppearance.allCases) { appearance in
                    WidgetSurfaceQADockStrip {
                        WidgetCardPreview(kind: "Calculator", width: 54, layout: .icon, appearance: appearance)
                        WidgetContainer(width: 54, kind: "Now Playing") {
                            WidgetToggleGlyph(kind: "Now Playing", symbol: "waveform", active: true)
                        }.environment(\.widgetIconAppearance, appearance)
                        WidgetCardPreview(kind: "Weather", width: 132, layout: .standard, appearance: appearance)
                    }
                    .environment(\.dockWidgetSurface, .plain)
                }
            }
        }
    }
}
#endif
