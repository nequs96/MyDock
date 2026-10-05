import AppKit
import SwiftUI

private struct WidgetLayoutKey: EnvironmentKey { static let defaultValue: WidgetLayout = .standard }
private struct WidgetIconAppearanceKey: EnvironmentKey { static let defaultValue: WidgetIconAppearance = .soft }
extension EnvironmentValues {
    var widgetLayout: WidgetLayout { get { self[WidgetLayoutKey.self] } set { self[WidgetLayoutKey.self] = newValue } }
    var widgetIconAppearance: WidgetIconAppearance { get { self[WidgetIconAppearanceKey.self] } set { self[WidgetIconAppearanceKey.self] = newValue } }
}

// MARK: - Palette

/// One desaturated accent family that reads on clear glass in light and dark.
/// Each category keeps its own hue so families stay recognisable; saturation and
/// brightness are harmonised per appearance (deeper on light glass, lighter on dark glass).
enum WidgetPalette {
    /// One hue per category (matching `WidgetCategory.displayColor`), tuned per appearance:
    /// deeper on light glass, lighter and less saturated on dark glass.
    enum Family: String, CaseIterable {
        case ai, system, business, personal, weather
        case everyday   // utilities, productivity, time
        /// sRGB 0–255 for light and dark appearances.
        var rgb: (light: (Int, Int, Int), dark: (Int, Int, Int)) {
            switch self {
            case .ai: ((128, 98, 178), (181, 157, 228))
            case .system: ((56, 138, 144), (126, 198, 202))
            case .business: ((70, 140, 92), (136, 200, 156))
            case .personal: ((182, 92, 124), (230, 150, 178))
            case .weather: ((176, 136, 58), (230, 192, 110))
            case .everyday: ((186, 124, 66), (228, 170, 110))
            }
        }
        /// HSB components of a variant, for tests and QA.
        func components(dark: Bool) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
            let (r, g, b) = dark ? rgb.dark : rgb.light
            var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
            NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
                .getHue(&h, saturation: &s, brightness: &v, alpha: &a)
            return (h, s, v)
        }
    }
    static let ai = family(.ai)
    static let system = family(.system)
    static let business = family(.business)
    static let personal = family(.personal)
    static let weather = family(.weather)
    static let everyday = family(.everyday)

    /// Semantic state colours. Text stays monochrome; these mark state only.
    static let warning = Color(nsColor: .systemOrange)
    static let critical = Color(nsColor: .systemRed)
    static let positive = Color(nsColor: .systemGreen)

    /// The family accent for a widget kind (the `.auto` accent).
    static func accent(_ kind: String) -> Color {
        if kind == "Weather" { return weather }
        switch WidgetRegistry.definition(named: kind)?.category {
        case .ai: return ai
        case .system: return system
        case .business: return business
        case .personal: return personal
        default: return everyday
        }
    }

    /// Resolves a per-widget accent choice: `.auto` → family accent, `.mono` → primary, `.profile` → profile colour.
    static func resolved(kind: String, accent: WidgetAccent) -> Color {
        switch accent {
        case .auto: Self.accent(kind)
        case .mono: Color.primary
        case .profile(let color): profile(color)
        }
    }

    /// A profile colour in the widget palette: the desaturated profile family that accent swatches,
    /// App Folder colours and `.profile` accents share (never the saturated system colours).
    static func profile(_ color: DockProfileColor) -> Color { color.displayColor }

    private static func family(_ family: Family) -> Color {
        let rgb = family.rgb
        return Color(nsColor: NSColor(name: NSColor.Name("MyDock.widget." + family.rawValue)) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua])
            let (r, g, b) = match == .darkAqua || match == .accessibilityHighContrastDarkAqua ? rgb.dark : rgb.light
            return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
        })
    }
}

/// Pure resolution of the per-widget presentation values `WidgetCompactView` injects.
struct WidgetPresentationValues: Equatable {
    var surface: DockWidgetSurface
    var accent: WidgetAccent
    var showsLabel: Bool
    var glassTint: WidgetGlassTint

    init(configuration: WidgetConfiguration?, settings: AppSettings) {
        surface = settings.customDockWidgetSurface
        accent = configuration?.widgetAccent ?? .auto
        showsLabel = Self.showsLabel(configuration: configuration, dockShowsLabels: settings.showWidgetLabels)
        glassTint = configuration?.glassTint ?? WidgetGlassTint.none
    }

    /// The widget's own choice wins; nil follows the Dock's `showWidgetLabels`.
    static func showsLabel(configuration: WidgetConfiguration?, dockShowsLabels: Bool) -> Bool {
        configuration?.showsLabel ?? dockShowsLabels
    }
}

extension View {
    /// Injects the per-widget surface, accent, label visibility and glass tint for faces to read.
    func widgetPresentation(_ values: WidgetPresentationValues) -> some View {
        environment(\.dockWidgetSurface, values.surface)
            .environment(\.widgetAccent, values.accent)
            .environment(\.widgetShowsLabel, values.showsLabel)
            .environment(\.widgetGlassTint, values.glassTint)
    }
}

// MARK: - Icon

/// A widget glyph. Small glyphs are bare; at 18 pt and above Soft and Colour sit in a circle,
/// like Control Center toggles. The colour follows the per-widget accent from the environment.
struct WidgetIcon: View {
    var kind: String
    var symbol: String? = nil
    var size: CGFloat = 14
    var appearance: WidgetIconAppearance? = nil
    /// nil: enclose Soft and Colour treatments at 18 pt and above. true: always a toggle circle.
    var enclosed: Bool? = nil
    /// Active state (playing, running): a filled accent circle.
    var active = false
    @Environment(\.widgetIconAppearance) private var inheritedAppearance
    @Environment(\.widgetAccent) private var accentChoice
    @Environment(\.colorScheme) private var scheme
    @DockAccessibilityStyle() private var accessibility
    private var treatment: WidgetIconAppearance { appearance ?? inheritedAppearance }
    private var tint: Color { WidgetPalette.resolved(kind: kind, accent: accentChoice) }
    private var iconSymbol: String {
        let name = symbol ?? WidgetRegistry.definition(named: kind)?.symbol ?? "square.grid.2x2"
        return treatment == .outline ? name.replacingOccurrences(of: ".fill", with: "") : name
    }
    private var isEnclosed: Bool { enclosed ?? (size >= 18 && (treatment == .soft || treatment == .accent)) }
    private var filled: Bool { active || treatment == .accent }
    private var contrast: Bool { accessibility.contrast == .increased }
    /// Glyph colour on a filled circle; a mono accent fills with primary, so invert.
    private var onFill: Color {
        if case .mono = accentChoice { return scheme == .dark ? .black : .white }
        return .white
    }
    private var circleFill: Color {
        if filled { return tint }
        if treatment == .soft { return tint.opacity(contrast ? 0.30 : 0.16) }
        return Color.primary.opacity(contrast ? 0.20 : 0.09)
    }
    private var weight: Font.Weight { treatment == .outline ? .light : isEnclosed ? .semibold : .medium }

    var body: some View {
        Group {
            if isEnclosed {
                Circle().fill(circleFill)
                    .overlay {
                        if contrast && !filled { Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1) }
                    }
                    .overlay {
                        Image(systemName: iconSymbol)
                            .font(.system(size: size * 0.44, weight: weight))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(filled ? onFill : treatment == .soft ? tint : Color.primary)
                    }
            } else {
                Image(systemName: iconSymbol)
                    .font(.system(size: size * 0.7, weight: weight))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(treatment == .mono ? Color.primary : tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The `.icon` layout: a centred SF Symbol in a circle, filled with the accent while active.
struct WidgetToggleGlyph: View {
    var kind: String
    var symbol: String? = nil
    var active = false
    var diameter: CGFloat = 36
    var body: some View { WidgetIcon(kind: kind, symbol: symbol, size: diameter, enclosed: true, active: active) }
}

// MARK: - Container

/// The widget module. A thin switch over the Dock's widget surface:
/// `.tile` is today's tile exactly; `.glass` is a GlassModule; `.plain` sits on the Dock glass.
struct WidgetContainer<Content: View>: View {
    var width: CGFloat
    var kind: String
    @ViewBuilder var content: Content
    @Environment(\.dockWidgetSurface) private var surface
    @Environment(\.dockModuleRadius) private var moduleRadius
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetGlassTint) private var glassTint
    var body: some View {
        switch surface {
        case .tile:
            WidgetTileSurface(width: width) { content }
        case .glass:
            // Interactive glass: the native specular highlight follows the pointer (macOS 26).
            GlassModule(width: width, height: 54, radius: moduleRadius, style: .regular, tint: glassTintColor,
                        interactive: true) { content }
        case .plain:
            WidgetPlainSurface(width: width, radius: moduleRadius) { content }
        }
    }
    private var glassTintColor: Color? {
        guard glassTint == .accent else { return nil }
        if case .mono = accent { return nil }
        return WidgetPalette.resolved(kind: kind, accent: accent).opacity(0.55)
    }
}

/// Today's tile, unchanged: the migration default for every existing profile.
struct WidgetTileSurface<Content: View>: View {
    var width: CGFloat
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

/// No background: content sits on the Dock glass, Control Center style. Hover lifts it only;
/// Increase Contrast draws a visible module edge so the hit target stays perceivable.
struct WidgetPlainSurface<Content: View>: View {
    var width: CGFloat
    var radius: CGFloat
    @ViewBuilder var content: Content
    @DockAccessibilityStyle() private var accessibility
    @State private var hovered = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: max(0, radius), style: .continuous) }
    var body: some View {
        content.frame(width: width, height: 54)
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                if accessibility.contrast == .increased {
                    shape.dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                }
            }
            .dockHover(hovered)
            .onHover { hovered = $0 }
    }
}

// MARK: - Module grammar

enum WidgetModuleMetrics {
    /// Horizontal content inset for regular modules, and for narrow side-Dock modules.
    static let inset: CGFloat = DockDesign.Module.insets.leading
    static let narrowInset: CGFloat = 4
    static let labelGlyph: CGFloat = 13
    static let glyphCircle: CGFloat = 32
    static let ring: CGFloat = 26
    static func isNarrow(_ width: CGFloat) -> Bool { width <= 54 }
    static func minimumScale(_ size: DockDesign.Module.ValueSize) -> CGFloat {
        switch size { case .large: 0.6; case .medium: 0.62; case .small: DockDesign.Module.minimumTextSize / 13 }
    }
}

/// Compact period tokens for module labels, as AI Limits writes its windows: "Today", "7d", "30d".
/// Anything that is not a known period title passes through unchanged.
enum WidgetPeriodToken {
    static func compact(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "today" { return "Today" }
        if lower == "month to date" || lower == "this month" { return "Month" }
        var words = lower.split(separator: " ").map(String.init)
        if words.first == "last" || words.first == "past" { words.removeFirst() }
        guard words.count == 2, let count = Int(words[0]), count > 0 else { return trimmed }
        switch words[1] {
        case "day", "days": return "\(count)d"
        case "hour", "hours": return "\(count)h"
        case "week", "weeks": return "\(count)w"
        default: return trimmed
        }
    }
}

/// The short label line: an optional family glyph, a label and an optional trailing reading.
/// Hidden when the widget's labels are off. A trailing reading that does not fit is dropped
/// whole rather than truncated; period titles shorten to their tokens ("30 days" → "30d").
struct ModuleLabel: View {
    var kind: String
    var text: String
    var symbol: String? = nil
    var showsGlyph = true
    var trailing: String? = nil
    var trailingColor: Color = .secondary
    @Environment(\.widgetShowsLabel) private var showsLabel
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        if showsLabel {
            if let trailing {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 4) {
                        lead
                        Spacer(minLength: 4)
                        Text(WidgetPeriodToken.compact(trailing)).font(DockDesign.Module.label).foregroundStyle(trailingColor)
                            .lineLimit(1).fixedSize()
                    }
                    HStack(spacing: 4) { lead }
                }
            } else {
                HStack(spacing: 4) { lead }
            }
        }
    }
    @ViewBuilder private var lead: some View {
        if showsGlyph && !WidgetModuleMetrics.isNarrow(width) {
            WidgetIcon(kind: kind, symbol: symbol, size: WidgetModuleMetrics.labelGlyph, enclosed: false)
        }
        Text(text).font(DockDesign.Module.label).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(DockDesign.Module.minimumTextSize / 11).layoutPriority(1)
    }
}

/// The primary value in the Module value font, with an optional unit that drops when space is short.
struct ModuleValue: View {
    var value: String
    var unit: String = ""
    var size: DockDesign.Module.ValueSize = .large
    var color: Color = .primary
    var lineLimit = 1
    var body: some View {
        if unit.isEmpty {
            valueText
        } else {
            ViewThatFits(in: .horizontal) {
                (Text(value).font(DockDesign.Module.value(size)).foregroundColor(color)
                 + Text(" " + unit).font(DockDesign.Module.label).foregroundColor(.secondary))
                    .lineLimit(1).fixedSize()
                valueText
            }
        }
    }
    private var valueText: some View {
        Text(value).font(DockDesign.Module.value(size)).foregroundStyle(color)
            .lineLimit(lineLimit).minimumScaleFactor(WidgetModuleMetrics.minimumScale(size))
    }
}

/// Label above value. When labels are off the value centres; a stack that shares its row with a
/// glyph, ring or chart (`keepsLeading`) then stops filling the row, so the group centres together.
struct ModuleStack: View {
    var kind: String
    var label: String
    var value: String
    var unit: String = ""
    var size: DockDesign.Module.ValueSize = .large
    var valueColor: Color = .primary
    var symbol: String? = nil
    var showsGlyph = true
    var trailing: String? = nil
    var trailingColor: Color = .secondary
    /// Leading alignment even without a label (a chart or glyph shares the row).
    var keepsLeading = false
    @Environment(\.widgetShowsLabel) private var showsLabel
    @Environment(\.dockWidgetContentWidth) private var width
    private var narrow: Bool { WidgetModuleMetrics.isNarrow(width) }
    private var alignment: HorizontalAlignment { ModuleAlignmentPolicy.alignment(narrow: narrow, showsLabel: showsLabel, keepsLeading: keepsLeading) }
    private var fillsRow: Bool { ModuleAlignmentPolicy.fillsRow(narrow: narrow, showsLabel: showsLabel, keepsLeading: keepsLeading) }
    var body: some View {
        VStack(alignment: alignment, spacing: DockDesign.Module.lineSpacing - 1) {
            ModuleLabel(kind: kind, text: label, symbol: symbol, showsGlyph: showsGlyph && !narrow,
                        trailing: narrow ? nil : trailing, trailingColor: trailingColor)
            ModuleValue(value: value, unit: narrow ? "" : unit, size: narrow && size == .large ? .medium : size, color: valueColor)
        }
        .frame(maxWidth: fillsRow ? .infinity : nil, alignment: Alignment(horizontal: alignment, vertical: .center))
    }
}

/// How a module's value aligns: label over value on the leading edge; centred when there is no
/// label or the module is narrow. Every face follows this, so labels-off rows line up the same way.
enum ModuleAlignmentPolicy {
    static func alignment(narrow: Bool, showsLabel: Bool, keepsLeading: Bool) -> HorizontalAlignment {
        narrow || !showsLabel ? .center : .leading
    }
    /// A stack sharing its row with a glyph or chart keeps to its own width when centred.
    static func fillsRow(narrow: Bool, showsLabel: Bool, keepsLeading: Bool) -> Bool {
        narrow || showsLabel || !keepsLeading
    }
}

/// A single-weight ring with no track labels or ticks.
struct ModuleRing<Center: View>: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 3
    @ViewBuilder var center: Center
    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: lineWidth)
            Circle().trim(from: 0, to: fraction.isFinite ? min(1, max(0, fraction)) : 0)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}
extension ModuleRing where Center == EmptyView {
    init(fraction: Double, color: Color, lineWidth: CGFloat = 3) {
        self.init(fraction: fraction, color: color, lineWidth: lineWidth) { EmptyView() }
    }
}

/// Positions a face inside the module with the shared insets.
private struct ModuleInsets: ViewModifier {
    @Environment(\.dockWidgetContentWidth) private var width
    func body(content: Content) -> some View {
        content.padding(.horizontal, WidgetModuleMetrics.isNarrow(width) ? WidgetModuleMetrics.narrowInset : WidgetModuleMetrics.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
extension View {
    func moduleInsets() -> some View { modifier(ModuleInsets()) }
}

// MARK: - Compatibility primitives (shared with family files)

struct MetricText: View {
    var value: String
    var unit: String = ""
    var size: CGFloat = 20
    var body: some View { ModuleValue(value: value, unit: unit, size: Self.valueSize(size)) }
    /// Maps legacy point sizes onto the Module value scale (22/18/13).
    static func valueSize(_ size: CGFloat) -> DockDesign.Module.ValueSize {
        size >= 20 ? .large : size >= 15 ? .medium : .small
    }
}
struct WidgetHeader: View {
    var kind: String
    var title: String
    var trailing: String? = nil
    var symbol: String? = nil
    var body: some View { ModuleLabel(kind: kind, text: title, symbol: symbol, trailing: trailing) }
}
/// A single-weight meter line with a faint track.
struct UsageBar: View {
    var fraction: Double
    var color: Color = .secondary
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(Color.primary.opacity(0.10))
                .overlay(alignment: .leading) {
                    Capsule().fill(color).frame(width: geometry.size.width * (fraction.isFinite ? min(1, max(0, fraction)) : 0))
                }
        }.frame(height: 3).accessibilityHidden(true)
    }
}
/// A single-weight sparkline without axes.
struct MicroSparkline: View {
    var values: [Double]
    var color: Color = .secondary
    var body: some View {
        WidgetSparkline(values: values).stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .padding(.vertical, 1).accessibilityHidden(true)
    }
}

// MARK: - Shared faces

struct SystemTelemetryDockFace: View {
    var cpu: Double?
    var history: [Double]
    var memory: HostMemoryReading?
    var load: SystemLoadAverage?
    var secondary: SystemSecondaryMetric = .memory
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetAccent) private var accent
    private let kind = "System Activity"
    private var value: String { cpu.map { "\(Int($0.rounded()))%" } ?? "—" }
    private var stateColor: Color {
        guard let cpu else { return .primary }
        return cpu >= 90 ? WidgetPalette.critical : cpu >= 75 ? WidgetPalette.warning : .primary
    }
    private var chartColor: Color { stateColor == .primary ? WidgetPalette.resolved(kind: kind, accent: accent) : stateColor }
    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                ModuleStack(kind: kind, label: "CPU", value: value, size: .medium, valueColor: stateColor)
            } else if layout == .meter {
                // A gauge: the reading inside a ring, the short label beside it.
                HStack(spacing: 6) {
                    ModuleRing(fraction: (cpu ?? 0) / 100, color: chartColor, lineWidth: 3.5) {
                        Text(value).font(DockDesign.Module.valueSmall).foregroundStyle(stateColor)
                            .lineLimit(1).minimumScaleFactor(WidgetModuleMetrics.minimumScale(.small))
                            .padding(.horizontal, 3)
                    }.frame(width: 40, height: 40)
                    if showsLabel {
                        Text("CPU").font(DockDesign.Module.label).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    }
                }.frame(maxWidth: .infinity)
            } else if layout == .trend {
                HStack(spacing: 10) {
                    ModuleStack(kind: kind, label: "CPU", value: value, valueColor: stateColor, keepsLeading: true).fixedSize()
                    VStack(alignment: .trailing, spacing: 3) {
                        if let secondaryText { Text(secondaryText).font(DockDesign.Module.label).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.91) }
                        sparkline.frame(height: secondaryText == nil ? 26 : 16)
                    }
                }
            } else {
                // Compact: label over value like every module; the live history shares the label line.
                // Without a label the reading centres over its history.
                if showsLabel {
                    VStack(alignment: .leading, spacing: DockDesign.Module.lineSpacing - 1) {
                        HStack(spacing: 5) {
                            Text("CPU").font(DockDesign.Module.label).foregroundStyle(.secondary).fixedSize()
                            sparkline.frame(height: 11)
                        }
                        ModuleValue(value: value, color: stateColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .center, spacing: 2) {
                        ModuleValue(value: value, color: stateColor)
                        sparkline.frame(height: 11)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }.moduleInsets()
    }
    @Environment(\.widgetShowsLabel) private var showsLabel
    @ViewBuilder private var sparkline: some View {
        if history.count > 1 { MicroSparkline(values: history, color: chartColor) }
        else { Capsule().fill(Color.primary.opacity(0.10)).frame(height: 1.5).frame(maxHeight: .infinity) }
    }
    private var secondaryText: String? {
        switch secondary {
        case .memory: memory.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0.usedBytes), countStyle: .memory) + " RAM" }
        case .load: load.map { "Load \(String(format: "%.2f", $0.oneMinute))" }
        case .none: nil
        }
    }
}

enum NetworkRateText {
    static func full(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(min(Double(Int64.max / 2), max(0, value))), countStyle: .file) + "/s"
    }
    /// Narrow faces: "2.4M", "148K", "0".
    static func short(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        let bytes = max(0, value)
        let units: [(Double, String)] = [(1e9, "G"), (1e6, "M"), (1e3, "K")]
        for (scale, suffix) in units where bytes >= scale {
            let scaled = bytes / scale
            return (scaled < 10 ? String(format: "%.1f", scaled) : String(Int(scaled.rounded()))) + suffix
        }
        return String(Int(bytes.rounded()))
    }
}

struct NetworkDockFace: View {
    var download: Double?
    var upload: Double?
    var history: [Double]
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetShowsLabel) private var showsLabel
    private let kind = "Network Activity"
    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                VStack(alignment: .leading, spacing: 2) {
                    rate("arrow.down", NetworkRateText.short(download), primary: true)
                    rate("arrow.up", NetworkRateText.short(upload), primary: false)
                }
            } else {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        rate("arrow.down", NetworkRateText.full(download), primary: true)
                        rate("arrow.up", NetworkRateText.full(upload), primary: false)
                    }.layoutPriority(1)
                    if layout == .trend {
                        MicroSparkline(values: history, color: WidgetPalette.resolved(kind: kind, accent: accent)).frame(height: 26)
                    }
                }.frame(maxWidth: .infinity, alignment: showsLabel || layout == .trend ? .leading : .center)
            }
        }.moduleInsets()
    }
    private func rate(_ symbol: String, _ text: String, primary: Bool) -> some View {
        HStack(spacing: 3) {
            WidgetIcon(kind: kind, symbol: symbol, size: primary ? 14 : 12, enclosed: false)
            if primary { ModuleValue(value: text, size: WidgetModuleMetrics.isNarrow(width) ? .small : .medium) }
            else {
                Text(text).font(DockDesign.Module.labelLarge).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(DockDesign.Module.minimumTextSize / 12)
            }
        }
    }
}

/// Locale-aware byte counts short enough for a module: three significant digits ("121 GB", "9,4 GB").
enum DiskSpaceFaceText {
    static func compact(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.isAdaptive = false
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: max(0, bytes))
    }
}

struct DiskDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var snapshot: DiskSpaceSnapshot?
    @Environment(\.widgetLayout) private var layout
    @Environment(\.widgetAccent) private var accent
    private let kind = "Disk Space"
    private var ringColor: Color {
        (snapshot?.usedFraction ?? 0) > 0.9 ? WidgetPalette.warning : WidgetPalette.resolved(kind: kind, accent: accent)
    }
    /// Faces use three significant digits ("121 GB"); the popout keeps the precise figure.
    private var freeText: String { snapshot.map { DiskSpaceFaceText.compact($0.availableBytes) } ?? "—" }
    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                ModuleStack(kind: kind, label: "Free", value: freeText, size: .small)
            } else {
                HStack(spacing: 8) {
                    ModuleStack(kind: kind, label: layout == .wide ? snapshot.map { "Disk · " + DiskSpaceFaceText.compact($0.totalBytes) } ?? "Disk" : "Disk",
                                value: freeText, unit: layout == .wide ? "free" : "",
                                size: layout == .wide ? .large : .medium, keepsLeading: true)
                    if let snapshot {
                        ModuleRing(fraction: snapshot.usedFraction, color: ringColor)
                            .frame(width: layout == .wide ? WidgetModuleMetrics.ring : 22, height: layout == .wide ? WidgetModuleMetrics.ring : 22)
                    }
                }
            }
        }.moduleInsets()
    }
}

struct BatteryDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var readings: [BatteryReading]
    @Environment(\.widgetLayout) private var layout
    @Environment(\.widgetAccent) private var accent
    @Environment(\.widgetShowsLabel) private var showsLabel
    private let kind = "Battery"
    var body: some View {
        Group {
            if readings.isEmpty {
                HStack(spacing: 8) {
                    WidgetIcon(kind: kind, symbol: "battery.0", size: WidgetModuleMetrics.isNarrow(width) ? 30 : 28, enclosed: true)
                    if !WidgetModuleMetrics.isNarrow(width) {
                        ModuleStack(kind: kind, label: "Battery", value: "—", size: .medium, showsGlyph: false, keepsLeading: true)
                    }
                }
            } else if WidgetModuleMetrics.isNarrow(width) || layout == .wide {
                HStack(spacing: 12) {
                    ForEach(Array(readings.prefix(WidgetModuleMetrics.isNarrow(width) ? 1 : 3))) { reading in
                        VStack(spacing: 3) {
                            ring(reading, size: 30)
                            Text("\(reading.percentage)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(valueColor(reading)).lineLimit(1).minimumScaleFactor(0.84)
                        }
                    }
                }
            } else if let reading = readings.first {
                HStack(spacing: 8) {
                    ring(reading, size: 30)
                    ModuleStack(kind: kind, label: name(reading), value: "\(reading.percentage)%", size: .medium,
                                valueColor: valueColor(reading), showsGlyph: false, keepsLeading: true)
                }
            }
        }.moduleInsets()
    }
    private func ring(_ reading: BatteryReading, size: CGFloat) -> some View {
        ModuleRing(fraction: Double(reading.percentage) / 100, color: ringColor(reading), lineWidth: 3) {
            Image(systemName: glyph(reading)).font(.system(size: size * 0.36, weight: .semibold)).foregroundStyle(.primary)
        }.frame(width: size, height: size)
    }
    private func glyph(_ reading: BatteryReading) -> String {
        if reading.isCharging { return "bolt.fill" }
        if reading.isInternal { return "laptopcomputer" }
        let name = reading.name.lowercased()
        if name.contains("airpods") { return "airpods" }
        if name.contains("mouse") { return "magicmouse.fill" }
        if name.contains("keyboard") { return "keyboard" }
        if name.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        return "battery.100"
    }
    private func name(_ reading: BatteryReading) -> String {
        reading.isCharging ? "Charging" : reading.isInternal ? "Mac" : reading.name
    }
    private func ringColor(_ reading: BatteryReading) -> Color {
        if reading.isCharging { return WidgetPalette.positive }
        if reading.percentage <= 10 { return WidgetPalette.critical }
        if reading.percentage <= 20 { return WidgetPalette.warning }
        return WidgetPalette.resolved(kind: kind, accent: accent)
    }
    private func valueColor(_ reading: BatteryReading) -> Color {
        guard !reading.isCharging else { return .primary }
        return reading.percentage <= 10 ? WidgetPalette.critical : reading.percentage <= 20 ? WidgetPalette.warning : .primary
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
    private let kind = "Weather"
    private var place: String { configuration.weatherLocation?.name ?? "Weather" }
    var body: some View {
        Group {
            if let forecast = configuration.cachedWeatherForecast {
                let temperature = WeatherDockTemperatureFormatter.text(forecast.temperature, unit: configuration.weatherUnit)
                let symbol = WeatherCode.symbol(forecast.weatherCode, isDay: forecast.isDay)
                if WidgetModuleMetrics.isNarrow(width) {
                    VStack(spacing: 2) {
                        WidgetIcon(kind: kind, symbol: symbol, size: 20, enclosed: false)
                        ModuleValue(value: temperature, size: .medium)
                    }
                } else if layout == .wide {
                    let hours = forecast.hourly.filter { $0.timestamp > .now }
                    let columns = WeatherForecastFaceLayout.columnCount(width: width, temperatureText: temperature, availableHours: hours.count)
                    HStack(spacing: 4) {
                        ModuleStack(kind: kind, label: place, value: temperature, symbol: symbol, keepsLeading: true)
                            .frame(width: WeatherForecastFaceLayout.primaryWidth(temperatureText: temperature) + 6, alignment: .leading)
                        ForEach(Array(hours.prefix(columns)), id: \.timestamp) { hour in
                            VStack(spacing: 1) {
                                Text(hour.timestamp.formattedTime(in: forecast.timeZoneIdentifier))
                                    .font(.system(size: DockDesign.Module.minimumTextSize, weight: .medium)).foregroundStyle(.secondary)
                                    .lineLimit(1).fixedSize()
                                WidgetIcon(kind: kind, symbol: WeatherCode.symbol(hour.weatherCode, isDay: forecast.isDay), size: 15, enclosed: false)
                                Text(WeatherDockTemperatureFormatter.text(hour.temperature, unit: configuration.weatherUnit))
                                    .font(.system(size: 12, weight: .semibold)).monospacedDigit().lineLimit(1)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                } else if layout == .compact {
                    // The glyph carries the condition; the label stays short.
                    ModuleStack(kind: kind, label: place, value: temperature, symbol: symbol)
                        .help(WeatherCode.description(forecast.weatherCode))
                } else {
                    HStack(spacing: 8) {
                        WidgetIcon(kind: kind, symbol: symbol, size: WidgetModuleMetrics.glyphCircle)
                        ModuleStack(kind: kind, label: place, value: temperature, showsGlyph: false, keepsLeading: true)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    if !WidgetModuleMetrics.isNarrow(width) { WidgetIcon(kind: kind, size: 28, enclosed: true) }
                    ModuleStack(kind: kind, label: "Weather", value: configuration.weatherLocation == nil ? "Set city" : "Unavailable",
                                size: .small, showsGlyph: false, keepsLeading: !WidgetModuleMetrics.isNarrow(width))
                }
            }
        }.moduleInsets()
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
    private var kind: String { item.widgetKind ?? item.title }
    private var c: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var ticksEverySecond: Bool {
        (kind == "Focus Timer" && c.focusStartedAt != nil) || (kind == "Stopwatch" && c.stopwatchStartedAt != nil)
            || (kind == "Countdown" && (c.countdownStartedAt != nil || c.countdownMode == .targetDate))
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: ticksEverySecond ? 1 : 30)) { context in
            face(at: context.date)
        }
    }
    @ViewBuilder private func face(at date: Date) -> some View {
        switch kind {
        case "Clock": ClockFace(date: date)
        case "Sticky Note": StickyNoteFace(text: c.noteText)
        case "Focus Timer", "Stopwatch", "Countdown": TimerFace(kind: kind, configuration: c, date: date)
        case "Time Progress": TimeProgressFace(configuration: c, date: date)
        case "Hydration": HydrationFace(configuration: c, date: date)
        case "File Shelf", "Text Snippets", "Quick Links": SavedCollectionDockFace(item: item)
        case "Quick Checklist": ChecklistFace(configuration: c)
        case "Stock", "Watchlist": MarketFace(kind: kind, configuration: c)
        default: QuickToolFace(kind: kind, title: toolTitle)
        }
    }
    private var toolTitle: String {
        switch kind {
        case "Calculator": "Calculate"
        case "Shortcuts": c.selectedShortcutName.isEmpty ? "Shortcut" : c.selectedShortcutName
        case "App Folder": c.appFolderName
        default: item.displayName
        }
    }
}

private struct ClockFace: View {
    var date: Date
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        let time = LocalClockFormatter.time(for: date)
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                ModuleValue(value: ClockDockTextFormatter.text(time, narrow: true), size: .medium, lineLimit: 2)
                    .multilineTextAlignment(.center)
            } else if layout == .standard {
                ModuleStack(kind: "Clock", label: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), value: time)
            } else {
                ModuleValue(value: time).frame(maxWidth: .infinity)
            }
        }
        .moduleInsets()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clock")
        .accessibilityValue(time + (layout == .standard ? ", " + LocalClockFormatter.date(for: date) : ""))
    }
}

/// The note as a face shows it: one flowing line of text (line breaks become spaces), and the
/// first word for narrow side-Dock modules.
enum StickyNoteFaceText {
    static let placeholder = "Write a note…"
    static func flowing(_ text: String) -> String {
        let words = text.prefix(500).split(whereSeparator: \.isWhitespace)
        return words.isEmpty ? placeholder : words.joined(separator: " ")
    }
    static func firstWord(_ text: String) -> String? {
        text.prefix(500).split(whereSeparator: \.isWhitespace).first.map(String.init)
    }
}

private struct StickyNoteFace: View {
    var text: String
    @Environment(\.dockWidgetContentWidth) private var width
    private var isEmpty: Bool { StickyNoteFaceText.firstWord(text) == nil }
    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                // Narrow: the note glyph with the first word when it fits whole, else the glyph alone.
                ViewThatFits(in: .horizontal) {
                    VStack(spacing: 2) {
                        WidgetIcon(kind: "Sticky Note", size: 28, enclosed: true)
                        if let word = StickyNoteFaceText.firstWord(text) {
                            Text(word).font(.system(size: DockDesign.Module.minimumTextSize, weight: .medium))
                                .foregroundStyle(.secondary).lineLimit(1).fixedSize()
                        }
                    }
                    WidgetIcon(kind: "Sticky Note", size: 32, enclosed: true)
                }
                .frame(maxWidth: .infinity)
            } else {
                // One flowing text over at most two lines, wrapped at word boundaries.
                Text(StickyNoteFaceText.flowing(text))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEmpty ? .secondary : .primary)
                    .lineLimit(2).minimumScaleFactor(DockDesign.Module.minimumTextSize / 12)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .moduleInsets()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sticky Note")
        .accessibilityValue(isEmpty ? "Empty" : String(text.prefix(500)))
    }
}

private struct TimerFace: View {
    var kind: String
    var configuration: WidgetConfiguration
    var date: Date
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetAccent) private var accent
    private var c: WidgetConfiguration { configuration }
    private var running: Bool {
        switch kind {
        case "Focus Timer": c.focusStartedAt != nil
        case "Stopwatch": c.stopwatchStartedAt != nil
        default: c.countdownStartedAt != nil || c.countdownMode == .targetDate
        }
    }
    var body: some View {
        let duration = kind == "Focus Timer" ? c.focusRemaining(at: date) : kind == "Stopwatch" ? c.stopwatchElapsed(at: date) : c.countdownRemaining(at: date)
        let text = kind == "Stopwatch" ? stopwatchText(duration)
            : kind == "Countdown" && c.countdownMode == .targetDate ? targetCountdownText(duration, compact: true) : TimerValueFormatter.text(duration)
        let label = kind == "Focus Timer" ? "Focus" : kind == "Stopwatch" ? "Elapsed" : "Timer"
        HStack(spacing: 8) {
            ModuleStack(kind: kind, label: label, value: text, valueColor: running ? .primary : .secondary,
                        keepsLeading: layout == .standard && !WidgetModuleMetrics.isNarrow(width))
            if layout == .standard && !WidgetModuleMetrics.isNarrow(width) {
                if kind == "Stopwatch" {
                    WidgetToggleGlyph(kind: kind, symbol: running ? "pause.fill" : "play.fill", active: running, diameter: 28)
                } else {
                    let total = Double(max(1, kind == "Focus Timer" ? c.focusDurationSeconds : c.countdownDurationSeconds))
                    ModuleRing(fraction: min(1, max(0, duration / total)),
                               color: running ? WidgetPalette.resolved(kind: kind, accent: accent) : Color.secondary)
                        .frame(width: WidgetModuleMetrics.ring, height: WidgetModuleMetrics.ring)
                }
            }
        }.moduleInsets()
    }
}

private struct TimeProgressFace: View {
    var configuration: WidgetConfiguration
    var date: Date
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetAccent) private var accent
    var body: some View {
        let progress = TimeProgressCalculator.fraction(for: configuration.timeProgressPeriod, at: date)
        HStack(spacing: 8) {
            ModuleStack(kind: "Time Progress", label: configuration.timeProgressPeriod.title, value: "\(Int(progress * 100))%",
                        keepsLeading: !WidgetModuleMetrics.isNarrow(width))
            if !WidgetModuleMetrics.isNarrow(width) {
                let size: CGFloat = layout == .standard ? WidgetModuleMetrics.ring : 20
                ModuleRing(fraction: progress, color: WidgetPalette.resolved(kind: "Time Progress", accent: accent)).frame(width: size, height: size)
            }
        }.moduleInsets()
    }
}

private struct HydrationFace: View {
    var configuration: WidgetConfiguration
    var date: Date
    @Environment(\.widgetLayout) private var layout
    var body: some View {
        let count = configuration.hydrationEntriesToday(at: date).count
        ModuleStack(kind: "Hydration", label: layout == .standard ? configuration.hydrationVolumeSummary(at: date) : "Water",
                    value: "\(count)", unit: count == 1 ? "drink" : "drinks", symbol: "drop.fill")
            .moduleInsets()
    }
}

private struct ChecklistFace: View {
    var configuration: WidgetConfiguration
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        let remaining = configuration.checklistEntries.filter { !$0.isComplete }
        let wide = layout == .wide && !WidgetModuleMetrics.isNarrow(width)
        HStack(spacing: 8) {
            if wide { WidgetIcon(kind: "Quick Checklist", size: WidgetModuleMetrics.glyphCircle) }
            ModuleStack(kind: "Quick Checklist", label: wide ? remaining.first?.title ?? "All clear" : "To do", value: "\(remaining.count)",
                        unit: wide ? "to do" : "", showsGlyph: !wide, keepsLeading: wide)
        }
        .moduleInsets()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quick Checklist")
        .accessibilityValue("\(remaining.count) tasks remaining")
    }
}

private struct MarketFace: View {
    var kind: String
    var configuration: WidgetConfiguration
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    private var c: WidgetConfiguration { configuration }
    var body: some View {
        let snapshot = kind == "Stock" ? c.stockSnapshot : c.watchlistStocks.first { $0.symbol == c.watchlistSelectedSymbol }?.snapshot ?? c.watchlistStocks.first?.snapshot
        let ticker = snapshot?.symbol ?? (c.stockSymbol.isEmpty ? "Stock" : c.stockSymbol)
        let narrow = WidgetModuleMetrics.isNarrow(width)
        let trend = layout == .trend && !narrow
        let change = snapshot?.changePercent
        let changeColor = (snapshot?.change ?? 0) < 0 ? WidgetPalette.critical : WidgetPalette.positive
        HStack(spacing: 8) {
            if let snapshot, let latest = snapshot.latest {
                ModuleStack(kind: kind, label: narrow ? FinancialFacePresentation.shortTicker(ticker) : ticker,
                            value: latest.close.formatted(.number.precision(.fractionLength(2))), unit: trend ? "" : snapshot.currency,
                            size: narrow ? .small : trend ? .large : .medium,
                            trailing: trend ? change.map { String(format: "%+.1f%%", $0) } : nil, trailingColor: changeColor,
                            keepsLeading: trend)
                    .help(ticker)
                if trend {
                    MicroSparkline(values: snapshot.points.suffix(30).map(\.close), color: changeColor).frame(width: 52, height: 24)
                }
            } else {
                ModuleStack(kind: kind, label: ticker, value: kind == "Watchlist" && c.watchlistStocks.isEmpty ? "Add tickers" : "Set ticker",
                            size: .small)
            }
        }.moduleInsets()
    }
}

/// Quick tools and actions. The `.icon` layout is a Control Center toggle; wider layouts add a short name.
private struct QuickToolFace: View {
    var kind: String
    var title: String
    @Environment(\.widgetLayout) private var layout
    @Environment(\.dockWidgetContentWidth) private var width
    @Environment(\.widgetShowsLabel) private var showsLabel
    private var showsName: Bool { layout != .icon && !WidgetModuleMetrics.isNarrow(width) && showsLabel }
    var body: some View {
        // Control Center toggle: the circle, with its short name underneath on wider layouts.
        VStack(spacing: 2) {
            WidgetToggleGlyph(kind: kind, diameter: showsName ? 30 : 36)
            if showsName {
                Text(title).font(DockDesign.Module.label).lineLimit(1)
                    .minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
            }
        }.moduleInsets()
    }
}

struct MediaDockFace: View {
    @Environment(\.dockWidgetContentWidth) private var width
    var title: String
    var artist: String?
    var artwork: NSImage?
    var isPlaying: Bool
    @Environment(\.widgetLayout) private var layout
    @Environment(\.widgetShowsLabel) private var showsLabel
    @Environment(\.widgetAccent) private var accent
    private let kind = "Now Playing"
    var body: some View {
        Group {
            if WidgetModuleMetrics.isNarrow(width) {
                art
            } else {
                // No marquee: a title that fits keeps its secondary line; a longer one wraps over two
                // lines at word boundaries beside the artwork, and when even its longest word cannot
                // sit beside the artwork, the title takes the whole module.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 9) {
                        art
                        VStack(alignment: .leading, spacing: 1) {
                            titleRow(Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1))
                            if let secondary {
                                // Only the title decides the fit; the secondary line may shorten.
                                Text(secondary).font(DockDesign.Module.label).foregroundStyle(.secondary).lineLimit(1)
                                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(spacing: 9) { art; titleRow(wrappedTitle) }
                    titleRow(wrappedTitle)
                }
            }
        }.moduleInsets()
    }
    /// The title over at most two lines. Its ideal width is its longest word, so it is only chosen
    /// where no word has to break.
    private var wrappedTitle: some View {
        let font = Font.system(size: 12, weight: .semibold)
        let words: [Substring] = title.split(whereSeparator: { $0.isWhitespace })
        let longest = words.max { $0.count < $1.count }.map(String.init) ?? title
        return ZStack(alignment: .leading) {
            Text(longest).font(font).lineLimit(1).fixedSize().hidden()
            Text(title).font(font).lineLimit(2)
                .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var secondary: String? {
        if layout == .wide, let artist, !artist.isEmpty { return artist }
        return showsLabel ? (isPlaying ? "Playing" : "Paused") : nil
    }
    private func titleRow(_ text: some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if isPlaying && artwork != nil {
                WidgetIcon(kind: kind, symbol: "waveform", size: 12, appearance: .soft, enclosed: false)
            }
            text
        }
    }
    @ViewBuilder private var art: some View {
        if let artwork {
            Image(nsImage: artwork).resizable().scaledToFill().frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if isPlaying && WidgetModuleMetrics.isNarrow(width) {
                        WidgetIcon(kind: kind, symbol: "waveform", size: 16, enclosed: true, active: true).offset(x: 4, y: 4)
                    }
                }
        } else {
            WidgetToggleGlyph(kind: kind, symbol: isPlaying ? "waveform" : "music.note", active: isPlaying, diameter: 36)
        }
    }
}

enum SavedCollectionUnit {
    static func text(kind: String, count: Int) -> String {
        let (one, many) = kind == "File Shelf" ? ("file", "files") : kind == "Text Snippets" ? ("snippet", "snippets") : ("link", "links")
        return count == 1 ? one : many
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
    @Environment(\.dockWidgetContentWidth) private var width
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let zone = TimeZone(identifier: configuration.worldClockTimeZoneID) ?? .current
            let city = zone.identifier.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? "Local"
            let time = formattedTime(context.date, timeZone: zone)
            Group {
                if WidgetModuleMetrics.isNarrow(width) {
                    ModuleStack(kind: "World Clock", label: zone.abbreviation(for: context.date) ?? "World",
                                value: ClockDockTextFormatter.text(time, narrow: true).components(separatedBy: "\n").first ?? time, size: .small)
                } else {
                    ModuleStack(kind: "World Clock", label: layout == .wide ? city : zone.abbreviation(for: context.date) ?? city, value: time,
                                trailing: layout == .wide ? WorldClockFaceDateFormatter.text(context.date, timeZone: zone) : nil)
                }
            }
            .moduleInsets()
            .help("Primary city: \(zone.identifier). " + WidgetTimingPresentation.dayRelation(offset: WorldClockCityCatalog.dayOffset(from: .current, to: zone, at: context.date), reference: "this Mac"))
        }
    }
}
