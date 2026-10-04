import SwiftUI

private struct WidgetLayoutKey: EnvironmentKey { static let defaultValue: WidgetLayout = .standard }
private struct WidgetIconAppearanceKey: EnvironmentKey { static let defaultValue: WidgetIconAppearance = .soft }
extension EnvironmentValues {
    var widgetLayout: WidgetLayout { get { self[WidgetLayoutKey.self] } set { self[WidgetLayoutKey.self] = newValue } }
    var widgetIconAppearance: WidgetIconAppearance { get { self[WidgetIconAppearanceKey.self] } set { self[WidgetIconAppearanceKey.self] = newValue } }
}

enum WidgetPalette {
    static func accent(_ kind: String) -> Color {
        switch WidgetRegistry.all.first(where: { $0.name == kind })?.category {
        case .ai: Color(red: 0.64, green: 0.48, blue: 0.75)
        case .system: Color(red: 0.37, green: 0.64, blue: 0.66)
        case .business: Color(red: 0.42, green: 0.65, blue: 0.50)
        case .personal: kind == "Weather" ? Color(red: 0.72, green: 0.61, blue: 0.39) : Color(red: 0.69, green: 0.50, blue: 0.58)
        default: Color(red: 0.75, green: 0.59, blue: 0.38)
        }
    }
}

struct WidgetIcon: View {
    var kind: String
    var symbol: String? = nil
    var size: CGFloat = 14
    var appearance: WidgetIconAppearance? = nil
    @Environment(\.widgetIconAppearance) private var inheritedAppearance
    private var treatment: WidgetIconAppearance { appearance ?? inheritedAppearance }
    private var iconSymbol: String {
        let name = symbol ?? WidgetRegistry.all.first { $0.name == kind }?.symbol ?? "square.grid.2x2"
        return treatment == .outline ? name.replacingOccurrences(of: ".fill", with: "") : name
    }
    var body: some View {
        Image(systemName: iconSymbol)
            .font(.system(size: size * 0.68, weight: treatment == .outline ? .regular : .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundColor(treatment == .mono || treatment == .outline ? Color.primary.opacity(0.75) : WidgetPalette.accent(kind))
            .frame(width: size, height: size)
            .background(treatment == .soft ? WidgetPalette.accent(kind).opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: min(8, size * 0.25)))
            .accessibilityHidden(true)
    }
}

struct WidgetContainer<Content: View>: View {
    var width: CGFloat
    var kind: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @DockAccessibilityStyle() private var accessibility
    @State private var hovered = false
    var body: some View {
        content.frame(width: width, height: 54)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accessibility.reduceTransparency
                          ? AnyShapeStyle(scheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
                          : AnyShapeStyle(scheme == .dark ? Color.white.opacity(hovered ? 0.10 : 0.065) : Color.white.opacity(hovered ? 0.76 : 0.62)))
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(accessibility.contrast == .increased ? 0.45 : hovered ? 0.15 : 0.075), lineWidth: accessibility.contrast == .increased ? 1 : 0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onHover { hovered = $0 }
    }
}

struct MetricText: View {
    var value: String
    var unit: String = ""
    var size: CGFloat = 20
    var body: some View {
        (Text(value).font(.system(size: size, weight: .semibold)) + Text(unit.isEmpty ? "" : " " + unit).font(.system(size: 9)).foregroundColor(.secondary))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
    }
}
struct WidgetHeader: View {
    var kind: String
    var title: String
    var trailing: String? = nil
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            WidgetIcon(kind: kind, symbol: symbol, size: 12)
            Text(title).font(.system(size: 9, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7).layoutPriority(1)
            Spacer(minLength: 2)
            if let trailing { Text(trailing).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
}
struct UsageBar: View {
    var fraction: Double
    var color: Color = .secondary
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(color.opacity(0.13))
                .overlay(alignment: .leading) { Capsule().fill(color.opacity(0.7)).frame(width: geometry.size.width * min(1, max(0, fraction))) }
        }.frame(height: 3).accessibilityHidden(true)
    }
}
struct MicroSparkline: View {
    var values: [Double]
    var color: Color = .secondary
    var body: some View {
        WidgetSparkline(values: values).stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
            .accessibilityHidden(true)
    }
}

struct SystemTelemetryDockFace: View {
    var cpu: Double?
    var history: [Double]
    var memory: HostMemoryReading?
    var load: SystemLoadAverage?
    var secondary: SystemSecondaryMetric = .memory
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    private var value: String { cpu.map { "\(Int($0.rounded()))%" } ?? "—" }
    var body: some View {
        if layout == .meter || width <= 54 {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 3) { WidgetIcon(kind: "System Activity", size: 9); Text("CPU").font(.system(size: 8, weight: .semibold)).fixedSize() }
                    MetricText(value: value, size: 20)
                }
                if width > 54 {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 2)
                        Circle().trim(from: 0, to: min(1, max(0, (cpu ?? 0) / 100))).stroke(WidgetPalette.accent("System Activity"), style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                    }.frame(width: 21, height: 21)
                }
            }.padding(.horizontal, 9)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 3) { WidgetIcon(kind: "System Activity", size: 10); Text("CPU").font(.system(size: 8, weight: .semibold)).fixedSize() }
                    Spacer(minLength: 2)
                    MetricText(value: value, size: layout == .trend ? 20 : 18)
                }
                if history.count > 1 { MicroSparkline(values: history, color: WidgetPalette.accent("System Activity")).frame(height: layout == .trend ? 12 : 14) }
                else { Text("Sampling…").font(.system(size: 8)).foregroundStyle(.secondary) }
                if layout == .trend, let secondaryText {
                    HStack(spacing: 5) {
                        Text(secondaryText).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        if secondary == .memory, let memory { UsageBar(fraction: Double(memory.usedBytes) / Double(max(1, memory.totalBytes))).frame(width: 38) }
                    }
                }
            }.padding(.horizontal, 9)
        }
    }
    private var secondaryText: String? {
        switch secondary {
        case .memory: memory.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0.usedBytes), countStyle: .memory) + " RAM" }
        case .load: load.map { "Load \(String(format: "%.2f", $0.oneMinute))" }
        case .none: nil
        }
    }
}

struct NetworkDockFace: View {
    var download: Double?
    var upload: Double?
    var history: [Double]
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        if width <= 54 {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 2) { WidgetIcon(kind: "Network Activity", symbol: "arrow.down", size: 8); Text(rate(download)).font(.system(size: 8, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.5) }
                HStack(spacing: 2) { WidgetIcon(kind: "Network Activity", symbol: "arrow.up", size: 8); Text(rate(upload)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.5) }
            }.padding(.horizontal, 4)
        } else { HStack(spacing: 9) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) { WidgetIcon(kind: "Network Activity", symbol: "arrow.down", size: 12); Text(rate(download)).font(.system(size: 12, weight: .semibold)).monospacedDigit() }
                HStack(spacing: 4) { WidgetIcon(kind: "Network Activity", symbol: "arrow.up", size: 12); Text(rate(upload)).font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary) }
            }.lineLimit(1).minimumScaleFactor(0.65)
            if layout == .trend { MicroSparkline(values: history, color: WidgetPalette.accent("Network Activity")).frame(maxWidth: .infinity).frame(height: 27) }
        }.padding(.horizontal, 9) }
    }
    private func rate(_ value: Double?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, value))), countStyle: .file) + "/s"
    }
}

struct DiskDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var snapshot: DiskSpaceSnapshot?
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if width <= 54 {
                Text("Free").font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
                MetricText(value: snapshot?.availableText ?? "—", size: 13)
            } else {
                WidgetHeader(kind: "Disk Space", title: "Disk", trailing: layout == .wide ? snapshot?.totalText : nil)
                MetricText(value: snapshot?.availableText ?? "—", unit: "free", size: 16)
            }
            if let snapshot { UsageBar(fraction: snapshot.usedFraction, color: snapshot.usedFraction > 0.9 ? .orange : .secondary) }
        }.padding(.horizontal, width <= 54 ? 5 : 9)
    }
}

struct BatteryDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var readings: [BatteryReading]
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        if width <= 54 {
            VStack(spacing: 4) {
                if let reading = readings.first {
                    HStack(spacing: 3) { WidgetIcon(kind: "Battery", size: 8); battery(reading).frame(width: 17, height: 10) }
                    MetricText(value: "\(reading.percentage)%", size: 18)
                } else { WidgetIcon(kind: "Battery", size: 20); Text("—").font(.caption) }
            }.padding(.horizontal, 4)
        } else { HStack(spacing: 12) {
            ForEach(Array(readings.prefix(layout == .wide ? 2 : 1))) { reading in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        battery(reading).frame(width: width <= 54 ? 17 : 27, height: 12)
                        MetricText(value: "\(reading.percentage)%", size: width <= 54 ? 14 : 17)
                    }
                    HStack(spacing: 3) { WidgetIcon(kind: "Battery", size: 10); Text(reading.isCharging ? "Charging" : reading.isInternal ? "Mac battery" : reading.name).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
            if readings.isEmpty { Label("Unavailable", systemImage: "battery.0").font(.system(size: 9)).foregroundStyle(.secondary) }
        }.padding(.horizontal, 9) }
    }
    private func battery(_ reading: BatteryReading) -> some View {
        HStack(spacing: 1) {
            RoundedRectangle(cornerRadius: 3).stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(reading.isCharging ? Color.green.opacity(0.75) : reading.percentage <= 20 ? .orange : .primary.opacity(0.6))
                        .frame(width: (width <= 54 ? 9 : 19) * CGFloat(reading.percentage) / 100, height: 7).padding(.leading, 2)
                }
            Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 2, height: 5)
        }.accessibilityHidden(true)
    }
}

enum WeatherDockTemperatureFormatter {
    /// Broad terrestrial-weather bounds, expressed in the configured unit.
    /// Validate before integer conversion, including imported cached readings.
    static func text(_ temperature: Double, unit: WeatherTemperatureUnit) -> String {
        let range: ClosedRange<Double> = unit == .celsius ? -150...150 : -238...302
        guard temperature.isFinite, range.contains(temperature) else { return "—" }
        return "\(Int(temperature.rounded()))°"
    }
}

enum WeatherForecastFaceLayout {
    static func primaryWidth(temperatureText: String) -> CGFloat {
        max(54, CGFloat(temperatureText.count) * 14)
    }

    static func columnCount(width: CGFloat, temperatureText: String, availableHours: Int) -> Int {
        let remaining = max(0, width - 18 - primaryWidth(temperatureText: temperatureText))
        return min(max(0, availableHours), 3, Int(remaining / 37))
    }
}

struct WeatherDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var configuration: WidgetConfiguration
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        if let forecast = configuration.cachedWeatherForecast {
            if width <= 54 {
                VStack(spacing: 3) {
                    WidgetIcon(kind: "Weather", symbol: WeatherCode.symbol(forecast.weatherCode, isDay: forecast.isDay), size: 16)
                    MetricText(value: WeatherDockTemperatureFormatter.text(forecast.temperature, unit: configuration.weatherUnit), size: 20)
                }.padding(.horizontal, 4)
            } else if layout == .wide {
                let temperature = WeatherDockTemperatureFormatter.text(forecast.temperature, unit: configuration.weatherUnit)
                let hours = forecast.hourly.filter { $0.timestamp > .now }
                let columns = WeatherForecastFaceLayout.columnCount(width: width, temperatureText: temperature, availableHours: hours.count)
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(configuration.weatherLocation?.name ?? "Weather").font(.system(size: 8, weight: .semibold)).lineLimit(1)
                        MetricText(value: temperature, size: 22)
                    }.frame(width: WeatherForecastFaceLayout.primaryWidth(temperatureText: temperature), alignment: .leading)
                        .layoutPriority(1)
                    ForEach(Array(hours.prefix(columns)), id: \.timestamp) { hour in
                        VStack(spacing: 2) {
                            Text(hour.timestamp.formattedTime(in: forecast.timeZoneIdentifier)).font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
                            WidgetIcon(kind: "Weather", symbol: WeatherCode.symbol(hour.weatherCode, isDay: forecast.isDay), size: 16)
                            Text(WeatherDockTemperatureFormatter.text(hour.temperature, unit: configuration.weatherUnit)).font(.system(size: 10, weight: .medium))
                        }.frame(maxWidth: .infinity)
                    }
                }.padding(.horizontal, 9)
            } else {
                HStack(spacing: 7) {
                    WidgetIcon(kind: "Weather", symbol: WeatherCode.symbol(forecast.weatherCode, isDay: forecast.isDay), size: width <= 54 ? 14 : layout == .compact ? 22 : 28)
                    VStack(alignment: .leading, spacing: 1) {
                        if layout == .standard { Text(configuration.weatherLocation?.name ?? "Weather").font(.system(size: 8, weight: .semibold)).lineLimit(1) }
                        MetricText(value: WeatherDockTemperatureFormatter.text(forecast.temperature, unit: configuration.weatherUnit), unit: width <= 54 ? "" : configuration.weatherUnit == .celsius ? "C" : "F", size: width <= 54 ? 20 : 25)
                        if layout == .standard { Text(WeatherCode.description(forecast.weatherCode)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                }.padding(.horizontal, 9)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(kind: "Weather", title: "Weather")
                Text(configuration.weatherLocation == nil ? "Set city" : "Unavailable").font(.system(size: 12, weight: .medium))
            }.padding(.horizontal, 9)
        }
    }
}

enum ClockDockTextFormatter {
    static func text(_ formattedTime: String, narrow: Bool) -> String {
        guard narrow else { return formattedTime }
        // Short locale times may use nonbreaking spaces around the day period.
        // Keep every component, but let the narrow face place it on another line.
        return formattedTime.split(whereSeparator: { $0.isWhitespace }).joined(separator: "\n")
    }
}

struct LocalWidgetDockFace: View {
    var item: DockItem
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    private var kind: String { item.widgetKind ?? item.title }
    private var c: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    var body: some View {
        TimelineView(.periodic(from: .now, by: ((kind == "Focus Timer" && c.focusStartedAt != nil) || (kind == "Stopwatch" && c.stopwatchStartedAt != nil) || (kind == "Countdown" && (c.countdownStartedAt != nil || c.countdownMode == .targetDate))) ? 1 : 30)) { context in
            face(at: context.date)
        }
    }
    @ViewBuilder private func face(at date: Date) -> some View {
        switch kind {
        case "Clock":
            VStack(alignment: width <= 54 ? .center : .leading, spacing: 3) {
                Text(ClockDockTextFormatter.text(LocalClockFormatter.time(for: date), narrow: width <= 54))
                    .font(.system(size: width <= 54 ? 17 : layout == .compact ? 18 : 22, weight: .semibold))
                    .monospacedDigit().lineLimit(width <= 54 ? 2 : 1).minimumScaleFactor(0.8)
                    .multilineTextAlignment(width <= 54 ? .center : .leading)
                if layout == .standard { HStack(spacing: 4) { WidgetIcon(kind: kind, size: 10); Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.system(size: 9)).foregroundStyle(.secondary) } }
            }.padding(.horizontal, width <= 54 ? 4 : 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Clock")
                .accessibilityValue(LocalClockFormatter.time(for: date) + (layout == .standard ? ", " + LocalClockFormatter.date(for: date) : ""))
        case "Sticky Note":
            Text(c.noteText.isEmpty ? "Write a note…" : String(c.noteText.prefix(500)))
                .font(.system(size: 10, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 54).background(Color.yellow.opacity(0.08))
        case "Focus Timer", "Stopwatch", "Countdown":
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(kind: kind, title: kind == "Focus Timer" ? "Focus" : kind == "Stopwatch" ? "Elapsed" : "Timer")
                HStack(spacing: 9) {
                    let duration = kind == "Focus Timer" ? c.focusRemaining(at: date) : kind == "Stopwatch" ? c.stopwatchElapsed(at: date) : c.countdownRemaining(at: date)
                    MetricText(value: kind == "Stopwatch" ? stopwatchText(duration) : kind == "Countdown" && c.countdownMode == .targetDate ? targetCountdownText(duration, compact: true) : TimerValueFormatter.text(duration), size: 20)
                    if layout == .standard && kind == "Stopwatch" { Text(c.stopwatchStartedAt == nil ? "Paused" : "Running").font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
                    if layout == .standard, kind != "Stopwatch" {
                        UsageBar(fraction: min(1, max(0, duration / Double(max(1, kind == "Focus Timer" ? c.focusDurationSeconds : c.countdownDurationSeconds)))), color: WidgetPalette.accent(kind)).frame(width: 25)
                    }
                }
            }.padding(.horizontal, 9)
        case "Time Progress":
            VStack(alignment: .leading, spacing: 4) {
                let progress = TimeProgressCalculator.fraction(for: c.timeProgressPeriod, at: date)
                HStack { Text(c.timeProgressPeriod.title).font(.system(size: 9, weight: .medium)); Spacer(minLength: 1); MetricText(value: "\(Int(progress * 100))%", size: 17) }
                UsageBar(fraction: progress, color: WidgetPalette.accent(kind))
                if layout == .standard { Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))).font(.system(size: 8)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 9)
        case "Hydration":
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader(kind: kind, title: "Water", symbol: "drop")
                MetricText(value: "\(c.hydrationEntriesToday(at: date).count)", unit: "drinks", size: 20)
                if layout == .standard { Text(c.hydrationVolumeSummary(at: date)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
            }.padding(.horizontal, 9)
        case "File Shelf", "Text Snippets", "Quick Links":
            SavedCollectionDockFace(item: item)
        case "Quick Checklist":
            VStack(alignment: layout == .wide && width > 54 ? .leading : .center, spacing: 3) {
                let remaining = c.checklistEntries.filter { !$0.isComplete }
                HStack(spacing: 6) {
                    if layout == .wide && width > 54 { WidgetIcon(kind: kind, size: 12) }
                    Text("\(remaining.count)").font(.system(size: 21, weight: .semibold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                Text(layout == .wide && width > 54 ? remaining.first?.title ?? "All clear" : "to do")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }.padding(.horizontal, width <= 54 ? 4 : 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Quick Checklist")
                .accessibilityValue("\(c.checklistEntries.filter { !$0.isComplete }.count) tasks remaining")
        case "Stock", "Watchlist":
            let snapshot = kind == "Stock" ? c.stockSnapshot : c.watchlistStocks.first { $0.symbol == c.watchlistSelectedSymbol }?.snapshot ?? c.watchlistStocks.first?.snapshot
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    let ticker = snapshot?.symbol ?? (c.stockSymbol.isEmpty ? "Set ticker" : c.stockSymbol)
                    if width <= 54 {
                        Text(FinancialFacePresentation.shortTicker(ticker)).font(.system(size: 8, weight: .semibold))
                            .lineLimit(1).minimumScaleFactor(0.7).help(ticker)
                        if let snapshot, let latest = snapshot.latest {
                            MetricText(value: latest.close.formatted(.number.precision(.fractionLength(2))), size: 12)
                            Text(snapshot.currency).font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    } else {
                        WidgetHeader(kind: kind, title: ticker)
                        if let snapshot, let latest = snapshot.latest { MetricText(value: latest.close.formatted(.number.precision(.fractionLength(2))), unit: snapshot.currency, size: 17) }
                    }
                }
                if layout == .trend, width > 54, let snapshot { MicroSparkline(values: snapshot.points.suffix(30).map(\.close), color: (snapshot.change ?? 0) < 0 ? .red : .green).frame(width: 53, height: 26) }
            }.padding(.horizontal, width <= 54 ? 5 : 9)
        default:
            HStack(spacing: 7) {
                WidgetIcon(kind: kind, size: layout == .icon ? 30 : 20)
                if layout != .icon { Text(kind == "Calculator" ? "Calculate" : kind == "Shortcuts" ? (c.selectedShortcutName.isEmpty ? "Shortcut" : c.selectedShortcutName) : kind == "App Folder" ? c.appFolderName : item.displayName).font(.system(size: 10, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7) }
            }.padding(.horizontal, 7)
        }
    }
}

struct MediaDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var title: String
    var artist: String?
    var artwork: NSImage?
    var isPlaying: Bool
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        HStack(spacing: 8) {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(alignment: .bottomTrailing) { WidgetIcon(kind: "Now Playing", symbol: isPlaying ? "waveform" : "pause", size: 11).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3)) }
            } else { WidgetIcon(kind: "Now Playing", symbol: isPlaying ? "waveform" : "music.note", size: 30) }
            if width > 54 { VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                if layout == .wide, let artist { Text(artist).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(.horizontal, width <= 54 ? 4 : 9)
    }
}

struct BusinessDockFace: View {
    var kind: String
    var title: String
    var metric: String
    var value: String?
    var context: String
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            WidgetHeader(kind: kind, title: title)
            MetricText(value: value ?? "Connect", size: 17)
            if layout == .standard { Text(value == nil ? "Account required" : metric + " · " + context).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(.horizontal, 9)
    }
}


enum FinancialFacePresentation {
    static func shortTicker(_ symbol: String) -> String {
        symbol.count <= 6 ? symbol : String(symbol.prefix(5)) + "+"
    }
}

enum WorldClockFaceDateFormatter {
    static func text(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
}

struct WorldClockDockFace: View {
    var configuration: WidgetConfiguration
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let zone = TimeZone(identifier: configuration.worldClockTimeZoneID) ?? .current
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) { WidgetIcon(kind: "World Clock", size: 10); Text(zone.abbreviation(for: context.date) ?? "World").font(.system(size: 8, weight: .medium)) }
                    MetricText(value: formattedTime(context.date, timeZone: zone), size: 20)
                }
                if layout == .wide {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(zone.identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? "Local").font(.system(size: 9, weight: .medium)).lineLimit(1)
                        Text(WorldClockFaceDateFormatter.text(context.date, timeZone: zone)).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }.padding(.horizontal, 9)
                .help("Primary city: \(zone.identifier). " + WidgetTimingPresentation.dayRelation(offset: WorldClockCityCatalog.dayOffset(from: .current, to: zone, at: context.date), reference: "this Mac"))
        }
    }
}

struct RemindersDockFace: View {
    var count: Int?
    var context: String
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        VStack(alignment: .leading, spacing: layout == .wide ? 2 : 4) {
            WidgetHeader(kind: "Reminders", title: layout == .compact ? "Tasks" : "Reminders")
            if let count { MetricText(value: "\(count)", unit: "to do", size: layout == .wide ? 19 : 21) }
            else { Text("Set up").font(.system(size: 12, weight: .medium)) }
            if layout == .wide { Text(context).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1) }
        }.padding(.horizontal, 9)
    }
}
