import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
protocol DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView
    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView
}

@MainActor
enum WidgetProviderRegistry {
    private static let providers: [String: any DockWidgetProvider] = [
        "File Shelf": FileShelfWidgetProvider(),
        "Text Snippets": SavedCollectionWidgetProvider(kind: "Text Snippets"),
        "Quick Links": SavedCollectionWidgetProvider(kind: "Quick Links"),
        "Unit Converter": UnitConverterWidgetProvider(),
        "Color Picker": ColorPickerWidgetProvider(),
        "Disk Space": DiskSpaceWidgetProvider(),
        "Calculator": CalculatorWidgetProvider(),
        "Quick Checklist": QuickChecklistWidgetProvider(),
        "Stock": StockWidgetProvider(),
        "Watchlist": WatchlistWidgetProvider(),
        "Stripe": StripeWidgetProvider(),
        "Paddle": PaddleWidgetProvider(),
        "Shopify": ShopifyWidgetProvider(),
        "AI Limits": AILimitsWidgetProvider(),
        "AI Activity": AIActivityWidgetProvider(),
        "Clock": ClockWidgetProvider(),
        "World Clock": WorldClockWidgetProvider(),
        "Stopwatch": StopwatchWidgetProvider(),
        "Countdown": CountdownWidgetProvider(),
        "Time Progress": TimeProgressWidgetProvider(),
        "Hydration": HydrationWidgetProvider(),
        "Battery": BatteryWidgetProvider(),
        "App Folder": AppFolderWidgetProvider(),
        "Shortcuts": ShortcutsWidgetProvider(),
        "Calendar": CalendarWidgetProvider(),
        "Reminders": RemindersWidgetProvider(),
        "System Activity": SystemActivityWidgetProvider(),
        "Alarm": AlarmWidgetProvider(),
        "Network Activity": NetworkActivityWidgetProvider(),
        "AirDrop": AirDropWidgetProvider(),
        "Trash": TrashWidgetProvider(),
        "Now Playing": NowPlayingWidgetProvider(),
        "Weather": WeatherWidgetProvider(),
        "Focus Timer": FocusTimerWidgetProvider(),
        "Sticky Note": StickyNoteWidgetProvider()
    ]

    static var registeredKinds: Set<String> { Set(providers.keys) }

    static func provider(for kind: String?) -> any DockWidgetProvider {
        guard let kind, let provider = providers[kind] else {
            return PlaceholderWidgetProvider(kind: kind ?? "Widget")
        }
        return provider
    }
}

struct WidgetCompactView: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    var item: DockItem
    var profileID: UUID
    var sampleMode = false
    var presentationSettings: AppSettings? = nil
    var layoutOverride: WidgetLayout? = nil
    init(store: ProfileStore, item: DockItem, profileID: UUID, sampleMode: Bool = false,
         presentationSettings: AppSettings? = nil, layoutOverride: WidgetLayout? = nil) {
        self.store = store; self.item = item; self.profileID = profileID
        self.sampleMode = sampleMode; self.presentationSettings = presentationSettings; self.layoutOverride = layoutOverride
        _runtimeCache = ObservedObject(wrappedValue: store.runtimeCache)
    }
    private var currentItem: DockItem { sampleMode ? item : store.presentationItem(item) }
    private var settings: AppSettings { presentationSettings ?? store.effectiveSettings(profileID: profileID) }
    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { currentItem.widgetConfiguration ?? WidgetConfiguration() }
    private var layout: WidgetLayout { layoutOverride ?? WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: configuration, compactDefault: settings.customDockWidgetStyle == .compact) }
    private var width: CGFloat { settings.customDockPosition == .bottom ? CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)) : 54 }
    var body: some View {
        Group {
            if sampleMode {
                WidgetCardPreview(kind: kind, width: width, layout: layout, appearance: configuration.iconAppearance)
            } else {
                WidgetContainer(width: width, kind: kind) { content }
                    .environment(\.dockWidgetContentWidth, width)
                    .environment(\.widgetLayout, settings.customDockPosition == .bottom ? layout : WidgetPresentationCatalog.options(for: kind).first?.layout == .icon ? .icon : .compact)
                    .environment(\.widgetIconAppearance, configuration.iconAppearance)
            }
        }.overlay(alignment: .topTrailing) {
            if !sampleMode { WidgetFreshnessIndicator(coordinator: store.widgetData, item: currentItem) }
        }
        // Per-widget surface, accent, label visibility and glass tint for the container and faces.
        .widgetPresentation(WidgetPresentationValues(configuration: configuration, settings: settings))
    }
    @ViewBuilder private var content: some View {
        switch kind {
        case "Clock", "Focus Timer", "Stopwatch", "Countdown", "Sticky Note", "Time Progress", "Hydration", "Quick Checklist", "Stock", "Watchlist", "Calculator", "Shortcuts", "App Folder":
            LocalWidgetDockFace(item: currentItem)
        default:
            WidgetProviderRegistry.provider(for: kind).compactView(store: store, item: currentItem, profileID: profileID)
        }
    }
}

struct WidgetPopout: View {
    @ObservedObject var store: ProfileStore
    @ObservedObject private var runtimeCache: WidgetRuntimeCache
    var item: DockItem
    var profileID: UUID
    var showsCustomize = true
    var showsHeader = true
    /// The freshness line. The settings sheet shows it in its own Data section instead.
    var showsData = true
    @Environment(\.dismiss) private var dismiss
    @DockAccessibilityStyle() private var accessibility
    @State private var showsAppearance = false
    init(store: ProfileStore, item: DockItem, profileID: UUID, showsCustomize: Bool = true, showsHeader: Bool = true, showsData: Bool = true) {
        self.store = store; self.item = item; self.profileID = profileID
        self.showsCustomize = showsCustomize; self.showsHeader = showsHeader; self.showsData = showsData
        _runtimeCache = ObservedObject(wrappedValue: store.runtimeCache)
    }
    private var currentItem: DockItem {
        store.presentationItem(store.state.profiles.first { $0.id == profileID }?.items.first { $0.id == item.id } ?? item)
    }
    private var kind: String { item.widgetKind ?? item.title }
    private var showsFreshness: Bool { showsData && item.widgetKind != "AI Activity" }

    var body: some View {
        Group {
            if showsHeader { shell } else { embedded }
        }
        .font(DockDesign.body).tint(DockDesign.accent)
        .buttonStyle(DockButtonStyle()).textFieldStyle(DockTextFieldStyle())
        .toggleStyle(SettingsSwitchStyle())
        .onExitCommand { dismiss() }
    }

    /// In the Dock: the family's name and freshness, then its content. The shell draws no surface of
    /// its own: the popover's native material is the one surface (see `WidgetPopoverSurface`), so the
    /// popout reads as a single calm sheet of glass instead of a card inside a slab.
    private var shell: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            header
            if showsAppearance {
                WidgetCustomizePanel(store: store, item: currentItem, profileID: profileID)
            }
            persistenceNotice
            familyContent
        }
        .padding(WidgetPopoutMetrics.padding)
        .frame(width: WidgetPopoutMetrics.contentWidth + 2 * WidgetPopoutMetrics.padding, alignment: .leading)
        // The shell is as tall as its content wants; containers scroll instead of squeezing it.
        // Family content is vertically compressible (scale-to-fit values such as WidgetPopoutHero),
        // so without this a hosting view that sizes its window from the shell's min/max height
        // ratchets the window down a point per pass and AppKit aborts the layout loop.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Inside the settings sheet: content only; the sheet draws the header, surface and Data.
    /// The sheet's live preview already shows the reading, so the family's hero is suppressed
    /// (`widgetPopoutShowsHero`, set by the sheet) unless the hero is a tool's own output.
    private var embedded: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            persistenceNotice
            familyContent
            if showsFreshness { freshness }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            WidgetIcon(kind: kind, size: 14, appearance: .mono)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind).font(DockDesign.Module.labelLarge).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if showsFreshness { freshness.controlSize(.small) }
            }
            Spacer(minLength: 4)
            if showsCustomize {
                Button { showsAppearance.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(WidgetCircleButtonStyle(selected: showsAppearance))
                    .help("Customize this widget").accessibilityLabel("Customize this widget")
                    .accessibilityValue(showsAppearance ? "Expanded" : "Collapsed")
            }
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(WidgetCircleButtonStyle())
                .help("Close").accessibilityLabel("Close widget")
        }
    }

    private var freshness: some View {
        WidgetFreshnessView(coordinator: store.widgetData, item: currentItem) {
            Task { await store.widgetData.refresh(item: currentItem, profileID: profileID) }
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private var persistenceNotice: some View {
        if store.hasUnpersistedChanges || store.persistenceError != nil {
            GroupedSection {
                GroupedRow(store.persistenceError ?? "Changes are waiting to be saved.", symbol: "exclamationmark.triangle.fill", color: .orange) {
                    Button("Retry Save") { store.commit() }
                        .controlSize(.small).disabled(!store.canRetryPersistence || !store.hasUnpersistedChanges)
                }
            }
        }
    }

    private var familyContent: some View {
        WidgetProviderRegistry.provider(for: currentItem.widgetKind)
            .popoutView(store: store, item: currentItem, profileID: profileID)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
extension WidgetPopout {
    /// Render QA only: the popout with its Customize panel already open.
    func customizeExpandedForQA() -> WidgetPopout {
        var copy = self
        copy._showsAppearance = State(initialValue: true)
        return copy
    }
}
#endif

/// Popout shell metrics. Grouped sections inside are concentric with the shell:
/// shell radius = grouped radius + shell padding.
enum WidgetPopoutMetrics {
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 16
    /// Width families lay out in; unchanged from the previous popout so existing content fits.
    static let contentWidth: CGFloat = 420
    static var radius: CGFloat { DockDesign.Grouped.radius + padding }
}

// MARK: - Popout vocabulary for families

/// The Dock popover's content surface. The NSPopover's own material (Liquid Glass on macOS 26, the
/// vibrant popover material before it) is the popout's one surface: the host adds no padding or
/// opaque slab and the shell no card. Under Reduce Transparency the system makes the popover opaque;
/// the content area is also filled with the opaque window colour so it never shows through.
struct WidgetPopoverSurface: ViewModifier {
    @DockAccessibilityStyle() private var accessibility
    func body(content: Content) -> some View {
        content.background {
            if accessibility.reduceTransparency { WidgetDesign.surface.ignoresSafeArea() }
        }
    }
}

private struct WidgetPopoutShowsHeroKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    /// False inside the widget settings sheet, whose live preview already shows the reading.
    var widgetPopoutShowsHero: Bool {
        get { self[WidgetPopoutShowsHeroKey.self] }
        set { self[WidgetPopoutShowsHeroKey.self] = newValue }
    }
}

/// Whether the settings sheet repeats a family's popout hero under its live preview.
enum WidgetSheetHeroPolicy {
    /// Heroes that are a tool's output rather than the reading the Dock face shows.
    static let toolOutputHeroes: Set<String> = ["Unit Converter"]
    /// Families whose popout content is only their hero: the sheet shows no Content for them.
    static let heroOnlyContent: Set<String> = ["Clock"]

    static func showsHero(kind: String, inSheet: Bool) -> Bool {
        !inSheet || toolOutputHeroes.contains(kind)
    }
    static func showsContent(kind: String, inSheet: Bool) -> Bool {
        showsHero(kind: kind, inSheet: inSheet) || !heroOnlyContent.contains(kind)
    }
}

/// Wraps a family's hero together with its decoration (a glyph above it, a card behind it) so the
/// whole group disappears where `widgetPopoutShowsHero` is false.
struct WidgetPopoutHeroGroup<Content: View>: View {
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    @ViewBuilder var content: Content
    var body: some View {
        if showsHero { content }
    }
}

/// The one large value of a popout (a time, a count) with at most one secondary line, centred.
/// Hidden inside the settings sheet (`widgetPopoutShowsHero`).
/// How a popout hero presents its value: a large reading, or a calm status sentence.
enum WidgetPopoutHeroStyle: Equatable {
    case reading, status
    /// Readings carry digits ("72%", "21°", "$2.4K"). Words such as "Connect Stripe",
    /// "Unavailable" or "Warming up" are states, not numbers, and must not shout at 40 pt.
    static func automatic(for value: String) -> Self {
        value.rangeOfCharacter(from: .decimalDigits) == nil ? .status : .reading
    }
}

struct WidgetPopoutHero: View {
    var value: String
    var caption: String?
    var valueColor: Color = .primary
    /// Optional glyph shown above a status (ignored for readings).
    var symbol: String? = nil
    @Environment(\.widgetPopoutShowsHero) private var showsHero
    var body: some View {
        if showsHero { hero }
    }
    private var style: WidgetPopoutHeroStyle { .automatic(for: value) }
    private var hero: some View {
        VStack(spacing: 3) {
            if style == .status, let symbol {
                Image(systemName: symbol).font(.system(size: 26, weight: .regular))
                    .foregroundStyle(valueColor == .primary ? Color.secondary : valueColor)
                    .padding(.bottom, 4).accessibilityHidden(true)
            }
            Text(value)
                .font(style == .reading ? .system(size: 40, weight: .semibold).monospacedDigit()
                                        : .system(size: 17, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(style == .reading ? 1 : 2).minimumScaleFactor(style == .reading ? 0.5 : 1)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(DockDesign.Module.maxTextLines).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

/// The role of a round timer control: grey secondary, green Start, orange Pause.
enum WidgetRoundButtonRole: Equatable {
    case neutral, start, pause
}

/// Colours of the tinted round controls, chosen for at least 4.5:1 text contrast.
/// Light: white text on a solid, deepened tint. Dark: bright tint text on a solid, dark tint
/// (the iOS Clock pattern). Increase Contrast deepens the fill (light) or brightens the text (dark).
enum WidgetRoundButtonPalette {
    struct RGB: Equatable {
        var red: Double, green: Double, blue: Double
        var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
        /// WCAG relative luminance.
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }
    static let white = RGB(red: 1, green: 1, blue: 1)

    /// nil for the neutral role, which uses primary text on a faint primary fill.
    static func colors(_ role: WidgetRoundButtonRole, dark: Bool, increasedContrast: Bool) -> (foreground: RGB, fill: RGB)? {
        switch (role, dark) {
        case (.neutral, _): return nil
        case (.start, false):
            return (white, increasedContrast ? RGB(red: 0.09, green: 0.40, blue: 0.17) : RGB(red: 0.12, green: 0.48, blue: 0.22))
        case (.pause, false):
            return (white, increasedContrast ? RGB(red: 0.54, green: 0.26, blue: 0.00) : RGB(red: 0.66, green: 0.33, blue: 0.00))
        case (.start, true):
            return (increasedContrast ? RGB(red: 0.45, green: 0.95, blue: 0.55) : RGB(red: 0.30, green: 0.85, blue: 0.40),
                    RGB(red: 0.10, green: 0.30, blue: 0.12))
        case (.pause, true):
            return (increasedContrast ? RGB(red: 1.00, green: 0.75, blue: 0.40) : RGB(red: 1.00, green: 0.66, blue: 0.25),
                    RGB(red: 0.32, green: 0.17, blue: 0.02))
        }
    }

    /// WCAG contrast ratio between two opaque colours.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (high, low) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (high + 0.05) / (low + 0.05)
    }
}

/// Round timer controls in the iOS Clock style: a tinted primary action and a grey secondary one.
struct WidgetRoundButtonStyle: ButtonStyle {
    var role: WidgetRoundButtonRole = .neutral
    var diameter: CGFloat = 62
    func makeBody(configuration: Configuration) -> some View { RoundBody(configuration: configuration, role: role, diameter: diameter) }
    private struct RoundBody: View {
        let configuration: ButtonStyle.Configuration
        var role: WidgetRoundButtonRole
        var diameter: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.colorScheme) private var scheme
        @DockAccessibilityStyle() private var accessibility
        @State private var hovered = false
        private var colors: (foreground: WidgetRoundButtonPalette.RGB, fill: WidgetRoundButtonPalette.RGB)? {
            WidgetRoundButtonPalette.colors(role, dark: scheme == .dark, increasedContrast: accessibility.contrast == .increased)
        }
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors?.foreground.color ?? Color.primary)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 6)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(colors?.fill.color ?? Color.primary.opacity(accessibility.contrast == .increased ? 0.14 : 0.08)))
                .overlay(Circle().fill(Color.primary.opacity(configuration.isPressed ? 0.10 : hovered ? 0.04 : 0)))
                .overlay {
                    if accessibility.contrast == .increased {
                        Circle().strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .contentShape(Circle())
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovered = $0 }
        }
    }
}

/// A small circular header control (customize, close) that sits quietly on glass.
struct WidgetCircleButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { CircleBody(configuration: configuration, selected: selected) }
    private struct CircleBody: View {
        let configuration: ButtonStyle.Configuration
        var selected: Bool
        @DockAccessibilityStyle() private var accessibility
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(selected ? DockDesign.accent : Color.primary.opacity(configuration.isPressed ? 0.16 : hovered ? 0.11 : 0.07)))
                .overlay {
                    if accessibility.contrast == .increased {
                        Circle().strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .contentShape(Circle())
                .onHover { hovered = $0 }
        }
    }
}

/// A grouped row with a value and a stepper, e.g. "Session · 25 min".
struct WidgetStepperRow: View {
    var title: String
    var value: String
    @Binding var amount: Int
    var range: ClosedRange<Int>
    var step: Int
    var body: some View {
        GroupedRow(title) {
            HStack(spacing: 8) {
                Text(value).font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary).monospacedDigit()
                Stepper(title, value: $amount, in: range, step: step).labelsHidden()
                    .accessibilityLabel(title).accessibilityValue(value)
            }
        }
    }
}

private struct ClockWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TimelineView(.periodic(from: .now, by: 1)) { context in
            WidgetPopoutHero(value: LocalClockFormatter.time(for: context.date), caption: LocalClockFormatter.date(for: context.date))
        })
    }
}

private struct FocusTimerWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(FocusTimerPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct WorldClockWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WorldClockCompactView(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(WorldClockPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct StopwatchWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StopwatchPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct CountdownWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(CountdownPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct TimeProgressWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(TimeProgressPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct HydrationWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(HydrationPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct BatteryWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(BatteryCompactView())
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(BatteryPopoutView())
    }
}

private struct AppFolderWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(AppFolderPopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct ShortcutsWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(ShortcutsPopoutView(store: store, item: item, profileID: profileID,
                                    runner: ShortcutExecutionService.shared))
    }
}

private struct ShortcutsPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @ObservedObject var runner: ShortcutExecutionService

    @State private var shortcutNames: [String] = []
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    private var selectedName: String { item.widgetConfiguration?.selectedShortcutName ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            HStack {
                Spacer()
                if runner.isRunning(selectedName) {
                    PillButton("Cancel Run", systemImage: "stop.fill") { runner.cancel(selectedName) }
                        .disabled(runner.statusByShortcut[selectedName] == ShortcutRunMessages.cancelling())
                } else {
                    PillButton("Run Shortcut", systemImage: "play.fill", action: runShortcut)
                        .disabled(selectedName.isEmpty)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            GroupedSection(footer: footer, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Shortcut") {
                    Picker("Shortcut", selection: Binding(get: { selectedName }, set: { name in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.selectedShortcutName = name }
                    })) {
                        Text("Choose…").tag("")
                        if !selectedName.isEmpty && !shortcutNames.contains(selectedName) {
                            Text("\(selectedName) (not found)").tag(selectedName)
                        }
                        ForEach(shortcutNames, id: \.self) { name in Text(name).tag(name) }
                    }
                    .labelsHidden().fixedSize().accessibilityLabel("Shortcut")
                }
                if !selectedName.isEmpty, let status = runner.statusByShortcut[selectedName] {
                    GroupedRow("Status", value: status)
                }
                GroupedRow(isRefreshing ? "Loading Shortcuts…" : "Refresh List", role: .button, action: refreshCatalog)
                    .disabled(isRefreshing)
                GroupedRow("Open Shortcuts", role: .button) { runner.openShortcutsApp() }
            }
            if let errorMessage {
                Text(errorMessage).font(DockDesign.Grouped.footerFont).foregroundStyle(Color(nsColor: .systemRed))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            }
        }
        .task { await loadCatalog() }
    }

    private var footer: String { "Shortcuts that ask for input may open a prompt and wait for you." }

    private func refreshCatalog() {
        Task { await loadCatalog() }
    }

    private func loadCatalog() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            shortcutNames = try await ShortcutsCatalog.list()
            errorMessage = shortcutNames.isEmpty ? "No shortcuts were found. Create one in Shortcuts, then refresh." : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runShortcut() {
        do {
            try runner.run(selectedName)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppFolderPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var reordering = false
    @State private var message: String?

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var applications: [AppFolderApplication] { configuration.appFolderApplications }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            if !applications.isEmpty && !reordering {
                GroupedSection { appGrid }
            }
            GroupedSection("Apps", footer: message, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                if applications.isEmpty {
                    GroupedRow("No apps yet", subtitle: "Add apps to open them from this folder.", symbol: "square.grid.2x2.fill", color: appFolderTint(configuration.appFolderColor))
                }
                if reordering {
                    ForEach(Array(applications.enumerated()), id: \.element.id) { index, application in
                        editRow(application, index: index)
                    }
                }
                GroupedRow("Add Apps…", role: .button, action: pickApplications)
                if !applications.isEmpty {
                    GroupedRow(reordering ? "Done Editing" : "Edit Apps", role: .button) { reordering.toggle() }
                }
            }
            GroupedSection("Folder", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Name") {
                    TextField("Folder name", text: Binding(get: { configuration.appFolderName }, set: { name in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderName = name }
                    }))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(maxWidth: 200)
                    .accessibilityLabel("Folder name")
                }
                GroupedRow("Icon letters", subtitle: "Up to two, instead of app icons") {
                    TextField("None", text: Binding(get: { configuration.appFolderLetter }, set: { value in
                        let letters = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2)).uppercased()
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderLetter = letters }
                    }))
                    .textFieldStyle(.plain).multilineTextAlignment(.trailing).frame(width: 80)
                    .accessibilityLabel("Icon letters")
                }
                GroupedRow("Color") {
                    HStack(spacing: 4) {
                        ForEach(DockProfileColor.allCases) { color in
                            let selected = configuration.appFolderColor == color.rawValue
                            Button { store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderColor = color.rawValue } } label: {
                                Circle().fill(appFolderTint(color.rawValue)).frame(width: 18, height: 18)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selected ? DockDesign.accent : .clear, lineWidth: 2))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain).help(color.title)
                            .accessibilityLabel(color.title).accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }

    /// The folder's apps as a launch grid, like an open folder on the Dock.
    private var appGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 6)], spacing: 10) {
            ForEach(applications) { application in
                let missing = !application.hasExistingBundlePath
                Button {
                    if missing { replaceApplication(application) } else { NSWorkspace.shared.open(application.url) }
                } label: {
                    VStack(spacing: 5) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                            .resizable().scaledToFit().frame(width: 44, height: 44)
                            .opacity(missing ? 0.4 : 1)
                            .overlay(alignment: .bottomTrailing) {
                                if missing {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 12)).foregroundStyle(.orange)
                                }
                            }
                        Text(application.name).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(missing ? "Missing · click to choose its new location" : InstalledApplicationIdentity.normalizedURL(application.url).path)
                .accessibilityLabel(missing ? "Replace missing \(application.name)" : "Open \(application.name), selected copy at \(InstalledApplicationIdentity.normalizedURL(application.url).path)")
                .contextMenu {
                    Button("Replace…") { replaceApplication(application) }
                    Button("Remove from Folder", role: .destructive) { removeApplication(application) }
                }
            }
        }
        .padding(10)
    }

    /// One app while editing: move, replace when missing, remove.
    private func editRow(_ application: AppFolderApplication, index: Int) -> some View {
        HStack(spacing: DockDesign.Grouped.glyphSpacing) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: application.url.path))
                .resizable().scaledToFit().frame(width: 24, height: 24)
                .opacity(application.hasExistingBundlePath ? 1 : 0.4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(application.name).font(DockDesign.Grouped.titleFont).lineLimit(1)
                Text(application.hasExistingBundlePath ? InstalledApplicationIdentity.normalizedURL(application.url).deletingLastPathComponent().path : "Missing")
                    .font(DockDesign.Grouped.subtitleFont)
                    .foregroundStyle(application.hasExistingBundlePath ? Color.secondary : Color.orange)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if !application.hasExistingBundlePath {
                Button("Replace…") { replaceApplication(application) }
                    .buttonStyle(.borderless).help("Choose the application's new location")
            }
            Button { moveApplication(at: index, by: -1) } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0).buttonStyle(.borderless)
                .help("Move \(application.name) up").accessibilityLabel("Move \(application.name) up")
            Button { moveApplication(at: index, by: 1) } label: { Image(systemName: "arrow.down") }
                .disabled(index == applications.count - 1).buttonStyle(.borderless)
                .help("Move \(application.name) down").accessibilityLabel("Move \(application.name) down")
            Button(role: .destructive) { removeApplication(application) } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(Color(nsColor: .systemRed))
            }
            .buttonStyle(.borderless).help("Remove from App Folder").accessibilityLabel("Remove \(application.name) from App Folder")
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(application.name)
    }

    private func pickApplications() {
        let panel = NSOpenPanel()
        panel.title = "Add Apps to \(configuration.appFolderName)"
        panel.prompt = "Add"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        var knownIDs = Set(applications.map(\.id))
        let selected = panel.urls.map(AppFolderApplication.init(url:)).filter { knownIDs.insert($0.id).inserted }
        guard !selected.isEmpty else { message = "Those apps are already in this folder."; return }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.appFolderApplications.append(contentsOf: selected) }
        message = nil
    }

    private func removeApplication(_ application: AppFolderApplication) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            $0.appFolderApplications.removeAll { $0.id == application.id }
        }
    }

    private func replaceApplication(_ application: AppFolderApplication) {
        let panel = NSOpenPanel()
        panel.title = "Replace \(application.name)"
        panel.prompt = "Replace"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let replacement = AppFolderApplication(url: url)
        guard !applications.contains(where: { $0.id == replacement.id && $0.id != application.id }) else {
            message = "That application is already in this folder."
            return
        }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { configuration in
            guard let index = configuration.appFolderApplications.firstIndex(where: { $0.id == application.id }) else { return }
            configuration.appFolderApplications[index] = replacement
        }
        message = nil
    }

    private func moveApplication(at index: Int, by offset: Int) {
        let target = index + offset
        guard applications.indices.contains(index), applications.indices.contains(target) else { return }
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            $0.appFolderApplications.swapAt(index, target)
        }
    }
}

/// App Folder colours come from the widget palette (the profile accent family), like accent swatches.
private func appFolderTint(_ name: String) -> Color {
    WidgetPalette.profile(DockProfileColor(rawValue: name) ?? .blue)
}

private struct StickyNoteWidgetProvider: DockWidgetProvider {
    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(LocalWidgetDockFace(item: item))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(StickyNotePopoutView(store: store, item: item, profileID: profileID))
    }
}

private struct PlaceholderWidgetProvider: DockWidgetProvider {
    var kind: String

    private var definition: WidgetDefinition? { WidgetRegistry.all.first(where: { $0.name == kind }) }

    func compactView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(Image(systemName: definition?.symbol ?? "square.grid.2x2").font(.system(size: 30)))
    }

    func popoutView(store: ProfileStore, item: DockItem, profileID: UUID) -> AnyView {
        AnyView(GroupedSection(footer: definition?.description) {
            GroupedRow("\(kind) is unavailable in this version of MyDock.", symbol: "questionmark.square.dashed", color: .gray)
        })
    }
}

private struct WorldClockCompactView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    var item: DockItem
    private var timeZone: TimeZone { TimeZone(identifier: item.widgetConfiguration?.worldClockTimeZoneID ?? "Europe/Warsaw") ?? .current }

    var body: some View { WorldClockDockFace(configuration: configuration) }

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
}

private struct WorldClockPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var citySearch = ""

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var timeZone: TimeZone { TimeZone(identifier: configuration.worldClockTimeZoneID) ?? .current }

    private var primaryName: String {
        WorldClockCityCatalog.all.first(where: { $0.id == configuration.worldClockTimeZoneID })?.name ?? configuration.worldClockTimeZoneID
    }
    private var trimmedSearch: String { citySearch.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                WidgetPopoutHero(value: formattedTime(context.date, timeZone: timeZone),
                                 caption: primaryName + " · " + WidgetTimingPresentation.dayRelation(offset: WorldClockCityCatalog.dayOffset(from: .current, to: timeZone, at: context.date), reference: "this Mac"))
            }
            GroupedSection("Cities", footer: configuration.worldClockAdditionalTimeZoneIDs.isEmpty ? nil : "Other cities' dates are relative to \(primaryName).") {
                GroupedRow(primaryName, subtitle: "Shown in the Dock", symbol: "star.fill", color: .orange)
                ForEach(configuration.worldClockAdditionalTimeZoneIDs, id: \.self) { id in
                    timeZoneRow(id)
                }
            }
            GroupedSection("Add a City", footer: trimmedSearch.isEmpty ? "Search by city or time zone." : WorldClockCityCatalog.matches(citySearch).isEmpty ? "No matching city or time zone." : nil, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search cities or time zones", text: $citySearch)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search cities or time zones")
                }
                .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
                if !trimmedSearch.isEmpty {
                    ForEach(WorldClockCityCatalog.matches(citySearch).prefix(8)) { city in
                        cityResult(city)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cityResult(_ city: WorldClockCityOption) -> some View {
        let isPrimary = city.id == configuration.worldClockTimeZoneID
        let added = isPrimary || configuration.worldClockAdditionalTimeZoneIDs.contains(city.id)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(city.name).font(DockDesign.Grouped.titleFont)
                Text(city.id).font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if isPrimary {
                Image(systemName: "star.fill").font(.system(size: 11)).foregroundStyle(.orange)
                    .help("Primary city").accessibilityLabel("Primary city")
            } else {
                Button("Make Primary") { setPrimaryCity(city.id) }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Make \(city.name) the primary city")
            }
            if added {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .help("Already in this clock").accessibilityLabel("Already added")
            } else {
                Button { addCity(city.id) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 15)) }
                    .buttonStyle(.borderless).help("Add city").accessibilityLabel("Add \(city.name)")
            }
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(city.name)
    }

    @ViewBuilder private func timeZoneRow(_ id: String) -> some View {
        let zone = WorldClockCityOption(id: id, name: id).timeZone
        let cityName = WorldClockCityCatalog.all.first(where: { $0.id == id })?.name ?? id
        HStack(spacing: DockDesign.Grouped.glyphSpacing) {
            GroupedRowGlyph(symbol: "globe", color: .gray)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let offset = WorldClockCityCatalog.dayOffset(from: timeZone, to: zone, at: context.date)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(cityName).font(DockDesign.Grouped.titleFont).lineLimit(1)
                        Text(offset == 0 ? "Same day" : offset > 0 ? "+\(offset) day" : "\(offset) day")
                            .font(DockDesign.Grouped.subtitleFont).foregroundStyle(.secondary)
                            .help("Local date is \(abs(offset)) day\(abs(offset) == 1 ? "" : "s") \(offset > 0 ? "ahead of" : "behind") the primary city")
                    }
                    Spacer(minLength: 8)
                    Text(formattedTime(context.date, timeZone: zone)).font(.system(size: 17, weight: .medium).monospacedDigit())
                }
            }
            Button { store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
                $0.worldClockAdditionalTimeZoneIDs.removeAll { $0 == id }
            } } label: {
                Image(systemName: "minus.circle.fill").foregroundStyle(Color(nsColor: .systemRed))
            }
            .buttonStyle(.borderless).help("Remove city").accessibilityLabel("Remove \(cityName)")
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, DockDesign.Grouped.rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: DockDesign.Grouped.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(cityName)
    }

    private func setPrimaryCity(_ id: String) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            $0.worldClockTimeZoneID = id
            $0.worldClockAdditionalTimeZoneIDs.removeAll { $0 == id }
        }
    }

    private func addCity(_ id: String) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) {
            guard $0.worldClockTimeZoneID != id, !$0.worldClockAdditionalTimeZoneIDs.contains(id) else { return }
            $0.worldClockAdditionalTimeZoneIDs.append(id)
        }
    }
}

private struct StopwatchPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    private var running: Bool { configuration.stopwatchStartedAt != nil }

    var body: some View {
        VStack(spacing: WidgetPopoutMetrics.spacing) {
            Group {
                if running {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        WidgetPopoutHero(value: stopwatchText(configuration.stopwatchElapsed(at: context.date)), caption: "Running")
                    }
                } else {
                    WidgetPopoutHero(value: stopwatchText(configuration.stopwatchElapsed()),
                                     caption: configuration.stopwatchElapsed() > 0 ? "Paused" : "Ready")
                }
            }
            HStack {
                Button("Reset") { store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetStopwatch() } }
                    .buttonStyle(WidgetRoundButtonStyle())
                    .disabled(!running && configuration.stopwatchElapsed() == 0)
                Spacer()
                Button(running ? "Pause" : "Start") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                        if value.stopwatchStartedAt == nil { value.startStopwatch() }
                        else { value.pauseStopwatch() }
                    }
                }
                .buttonStyle(WidgetRoundButtonStyle(role: running ? .pause : .start))
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct CountdownPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var notificationMessage: String?
    @State private var targetDraft = Date().addingTimeInterval(3_600)
    @State private var isSchedulingTarget = false
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            WidgetPopoutHeroGroup {
                CountdownValueText(configuration: configuration, compact: false)
                    .font(.system(size: 40, weight: .semibold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            }
            Picker("Count down to", selection: modeBinding) {
                ForEach(CountdownMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Count down to")
            if configuration.countdownMode == .duration {
                durationControls
            } else {
                targetDateControls
            }
        }
        .onAppear {
            targetDraft = configuration.countdownTargetDate ?? Date().addingTimeInterval(3_600)
        }
        .onChange(of: configuration.countdownTargetDate) { target in
            if let target { targetDraft = target }
        }
    }

    /// The alert note, then the latest scheduling result when there is one.
    private var footer: String {
        let note = configuration.countdownMode == .duration
            ? "Start asks macOS for a completion alert; the timer runs either way. Pause and Reset cancel it."
            : "Setting a target asks macOS for an alert at that time. After a backup restore, set it again."
        return [note, notificationMessage].compactMap { $0 }.joined(separator: "\n")
    }

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            HStack {
                Button("Reset") {
                    CountdownNotificationService.cancel(itemID: item.id)
                    notificationMessage = nil
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetCountdown() }
                }
                .buttonStyle(WidgetRoundButtonStyle())
                Spacer()
                Button(configuration.countdownStartedAt == nil ? "Start" : "Pause") {
                    var fireDate: Date?
                    var expectedStart: Date?
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                        if value.countdownStartedAt == nil {
                            value.startCountdown()
                            expectedStart = value.countdownStartedAt
                            fireDate = value.countdownNotificationDeadline
                        } else {
                            value.pauseCountdown()
                        }
                    }
                    if let fireDate {
                        let operationID = UUID()
                        CountdownNotificationService.begin(itemID: item.id, operationID: operationID)
                        Task { @MainActor in
                            do {
                                try await CountdownNotificationService.schedule(itemID: item.id,
                                                                               operationID: operationID,
                                                                               fireDate: fireDate)
                                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                                             operationID: operationID) else { return }
                                let isStillRunning = store.state.profiles
                                    .first(where: { $0.id == profileID })?.items
                                    .first(where: { $0.id == item.id })?.widgetConfiguration?.countdownStartedAt == expectedStart
                                guard isStillRunning else {
                                    CountdownNotificationService.cancel(itemID: item.id)
                                    return
                                }
                                notificationMessage = "Completion alert scheduled with macOS. Delivery depends on your notification settings."
                            } catch {
                                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                                             operationID: operationID) else { return }
                                notificationMessage = error.localizedDescription
                            }
                        }
                    } else {
                        CountdownNotificationService.cancel(itemID: item.id)
                        notificationMessage = nil
                    }
                }
                .buttonStyle(WidgetRoundButtonStyle(role: configuration.countdownStartedAt == nil ? .start : .pause))
                .disabled(configuration.countdownStartedAt != nil && configuration.countdownRemaining() <= 0)
            }
            .padding(.horizontal, 24)
            GroupedSection(footer: footer) {
                WidgetStepperRow(title: "Duration", value: "\(configuration.countdownDurationSeconds / 60) min",
                                 amount: durationBinding, range: 60...86_400, step: 60)
                    .disabled(configuration.countdownStartedAt != nil)
            }
        }
    }

    private var targetDateControls: some View {
        GroupedSection(footer: footer, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            GroupedRow("Target") {
                DatePicker("Target", selection: $targetDraft, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden().accessibilityLabel("Target date and time")
            }
            GroupedRow(configuration.countdownTargetDate == nil ? "Set Target" : "Update Target", role: .button) {
                setTargetDate()
            }
            .disabled(isSchedulingTarget || targetDraft <= .now)
            if configuration.countdownTargetDate != nil {
                GroupedRow("Clear Target", role: .destructive) {
                    CountdownNotificationService.cancel(itemID: item.id)
                    isSchedulingTarget = false
                    notificationMessage = nil
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetCountdown() }
                }
            }
        }
    }

    private var modeBinding: Binding<CountdownMode> {
        Binding(get: { configuration.countdownMode }, set: { mode in
            CountdownNotificationService.cancel(itemID: item.id)
            isSchedulingTarget = false
            notificationMessage = nil
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.setCountdownMode(mode) }
            if mode == .targetDate { targetDraft = Date().addingTimeInterval(3_600) }
        })
    }

    private func setTargetDate() {
        let target = targetDraft
        guard target > .now else {
            notificationMessage = "Choose a future date and time."
            return
        }
        CountdownNotificationService.cancel(itemID: item.id)
        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.setCountdownTarget(target) }
        let operationID = UUID()
        CountdownNotificationService.begin(itemID: item.id, operationID: operationID)
        isSchedulingTarget = true
        Task { @MainActor in
            defer {
                if CountdownNotificationService.isCurrent(itemID: item.id, operationID: operationID) {
                    isSchedulingTarget = false
                }
            }
            do {
                try await CountdownNotificationService.schedule(itemID: item.id,
                                                               operationID: operationID,
                                                               fireDate: target)
                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                             operationID: operationID) else { return }
                let current = store.state.profiles
                    .first(where: { $0.id == profileID })?.items
                    .first(where: { $0.id == item.id })?.widgetConfiguration
                guard current?.countdownMode == .targetDate,
                      current?.countdownTargetDate == target else {
                    CountdownNotificationService.cancel(itemID: item.id)
                    return
                }
                notificationMessage = "Target alert scheduled with macOS. Delivery depends on your notification settings."
            } catch {
                guard CountdownNotificationService.isCurrent(itemID: item.id,
                                                             operationID: operationID) else { return }
                notificationMessage = error.localizedDescription
            }
        }
    }

    private var durationBinding: Binding<Int> {
        Binding(get: { configuration.countdownDurationSeconds }, set: { seconds in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.countdownDurationSeconds = seconds }
        })
    }
}

private struct CountdownValueText: View {
    var configuration: WidgetConfiguration
    var compact: Bool
    @State private var targetCompleted = false

    var body: some View {
        Group {
            if configuration.countdownMode == .targetDate {
                if let target = configuration.countdownTargetDate {
                    if targetCompleted || target <= .now {
                        Text(compact ? "Done" : "Complete")
                    } else {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(targetCountdownText(configuration.countdownRemaining(at: context.date), compact: compact))
                        }
                    }
                } else {
                    Text(compact ? "Set date" : "Choose a target date")
                }
            } else if configuration.countdownStartedAt != nil, configuration.countdownRemaining() > 0 {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(timerText(configuration.countdownRemaining(at: context.date)))
                }
            } else {
                Text(timerText(configuration.countdownRemaining()))
            }
        }
        .task(id: configuration.countdownTargetDate) {
            targetCompleted = false
            guard configuration.countdownMode == .targetDate,
                  let target = configuration.countdownTargetDate else { return }
            while !Task.isCancelled {
                let remaining = target.timeIntervalSinceNow
                if remaining <= 0 {
                    targetCompleted = true
                    return
                }
                let nanoseconds = UInt64(max(0.05, min(remaining, 86_400)) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }
}

private struct TimeProgressPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            WidgetPopoutHeroGroup {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    let progress = TimeProgressCalculator.fraction(for: configuration.timeProgressPeriod, at: context.date)
                    VStack(spacing: 10) {
                        WidgetPopoutHero(value: "\(Int(progress * 100))%", caption: "through this \(configuration.timeProgressPeriod.rawValue)")
                        UsageBar(fraction: progress, color: WidgetPalette.accent("Time Progress"))
                            .frame(height: 6)
                            .padding(.horizontal, 24)
                            .accessibilityHidden(true)
                    }
                }
            }
            GroupedSection {
                GroupedRow("Period") {
                    Picker("Period", selection: periodBinding) {
                        ForEach(TimeProgressPeriod.allCases) { period in Text(period.title).tag(period) }
                    }
                    .labelsHidden().fixedSize().accessibilityLabel("Period")
                }
            }
        }
    }

    private var periodBinding: Binding<TimeProgressPeriod> {
        Binding(get: { configuration.timeProgressPeriod }, set: { period in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.timeProgressPeriod = period }
        })
    }
}

private struct HydrationDayGroup: Identifiable {
    var date: Date
    var entries: [HydrationEntry]
    var id: Date { date }
}

enum HydrationHistoryPolicy {
    static let recentDayCount = 7

    static func visibleDays<Day>(_ days: [Day], showingOlder: Bool) -> [Day] {
        showingOlder ? days : Array(days.prefix(recentDayCount))
    }
}

private struct HydrationPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var reminderMessage: String?
    @State private var reminderPermissionDenied = false
    @State private var reminderOperationID = UUID()
    @State private var showingOlderDrinks = false
    @State private var currentDay = Date.now

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var todayEntries: [HydrationEntry] { configuration.hydrationEntriesToday(at: currentDay) }
    private var dayGroups: [HydrationDayGroup] {
        let grouped = Dictionary(grouping: configuration.hydrationEntries) { Calendar.current.startOfDay(for: $0.timestamp) }
        return grouped.keys.sorted(by: >).map { HydrationDayGroup(date: $0, entries: (grouped[$0] ?? []).sorted { $0.timestamp > $1.timestamp }) }
    }
    private var visibleDayGroups: [HydrationDayGroup] {
        HydrationHistoryPolicy.visibleDays(dayGroups, showingOlder: showingOlderDrinks)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            WidgetPopoutHero(value: "\(todayEntries.count)", caption: (todayEntries.count == 1 ? "drink today" : "drinks today")
                             + (configuration.hydrationTrackAmounts ? " · " + configuration.hydrationVolumeSummary(at: currentDay) : ""))
            HStack(spacing: 10) {
                Spacer()
                PillButton("I Drank Water", systemImage: "drop.fill") { drinkAndRestartReminder() }
                    .help("Log a drink when history is enabled and restart the water reminder.")
                Button("Log Water") { log(amount: configuration.hydrationDefaultAmountML) }
                    .buttonStyle(GalleryGlassButtonStyle())
                    .disabled(!configuration.hydrationSaveHistory)
                    .help("Record the configured amount without changing the reminder timer.")
                Spacer()
            }
            GroupedSection("Reminders", footer: reminderMessage, separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Water reminders", isOn: Binding(get: { configuration.hydrationRemindersEnabled }, set: { enabled in
                    setReminders(enabled)
                }))
                WidgetStepperRow(title: "Every", value: "\(configuration.hydrationReminderIntervalMinutes) min",
                                 amount: binding(\.hydrationReminderIntervalMinutes), range: 30...240, step: 15)
                    .disabled(!configuration.hydrationRemindersEnabled)
                if reminderPermissionDenied {
                    GroupedRow("Open Notification Settings", role: .button) {
                        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            GroupedSection("Tracking", footer: configuration.hydrationSaveHistory ? nil : "Turn on history to log drinks. Existing entries are kept.", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                GroupedRow("Save drink history", isOn: binding(\.hydrationSaveHistory))
                GroupedRow("Track drink amounts", isOn: binding(\.hydrationTrackAmounts))
                WidgetStepperRow(title: "Drink size", value: "\(configuration.hydrationDefaultAmountML) mL",
                                 amount: binding(\.hydrationDefaultAmountML), range: 50...1_000, step: 50)
                    .disabled(!configuration.hydrationTrackAmounts)
            }
            if !dayGroups.isEmpty || configuration.hydrationLastRemovedEntry != nil {
                history
            }
        }
        .onChange(of: configuration.hydrationReminderIntervalMinutes) { minutes in
            if configuration.hydrationRemindersEnabled { setReminders(true, interval: minutes) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in currentDay = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in currentDay = .now }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in currentDay = .now }
    }

    /// Recent drinks by day in a capped scroll, with Undo for the last removal.
    private var history: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("History").font(DockDesign.Grouped.headerFont).accessibilityAddTraits(.isHeader)
                Spacer()
                if configuration.hydrationLastRemovedEntry != nil {
                    Button("Undo") { update { $0.undoHydrationRemoval() } }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("z", modifiers: .command)
                        .accessibilityLabel("Undo drink removal")
                }
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            DockScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(visibleDayGroups) { group in
                        GroupedSection(footer: group.date.formatted(date: .complete, time: .omitted), separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
                            ForEach(group.entries) { entry in
                                GroupedRow(entry.timestamp.formatted(date: .omitted, time: .shortened)) {
                                    HStack(spacing: 10) {
                                        Text(entry.amountML.map { "\($0) mL" } ?? "No amount")
                                            .font(DockDesign.Grouped.titleFont).foregroundStyle(.secondary)
                                        Button { update { $0.removeHydrationEntry(id: entry.id) } } label: {
                                            Image(systemName: "minus.circle.fill").foregroundStyle(Color(nsColor: .systemRed))
                                        }
                                        .buttonStyle(.borderless)
                                        .accessibilityLabel("Remove drink")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
            if dayGroups.count > HydrationHistoryPolicy.recentDayCount {
                Button(showingOlderDrinks ? "Show Recent Drinks" : "Show Older Drinks") { showingOlderDrinks.toggle() }
                    .buttonStyle(.borderless)
                    .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<WidgetConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in
            update { $0[keyPath: keyPath] = value }
        })
    }

    private func log(amount: Int?) {
        update { $0.logHydrationDrink(amountML: amount) }
    }

    private func drinkAndRestartReminder() {
        log(amount: nil)
        guard configuration.hydrationRemindersEnabled else { return }
        setReminders(true, interval: configuration.hydrationReminderIntervalMinutes)
    }

    private func setReminders(_ enabled: Bool) {
        setReminders(enabled, interval: configuration.hydrationReminderIntervalMinutes)
    }

    private func setReminders(_ enabled: Bool, interval: Int) {
        let operationID = UUID()
        reminderOperationID = operationID
        if !enabled {
            HydrationReminderService.cancel(itemID: item.id, operationID: operationID)
            update { $0.hydrationRemindersEnabled = false }
            reminderMessage = nil
            reminderPermissionDenied = false
            return
        }
        HydrationReminderService.begin(itemID: item.id, operationID: operationID)
        Task { @MainActor in
            do {
                try await HydrationReminderService.schedule(itemID: item.id,
                                                            operationID: operationID,
                                                            intervalMinutes: interval)
                guard reminderOperationID == operationID,
                      HydrationReminderService.isCurrent(itemID: item.id, operationID: operationID) else {
                    return
                }
                update { $0.hydrationRemindersEnabled = true }
                reminderMessage = "Reminder scheduled every \(min(max(interval, 30), 240)) minutes."
                reminderPermissionDenied = false
            } catch {
                guard reminderOperationID == operationID,
                      HydrationReminderService.isCurrent(itemID: item.id, operationID: operationID) else { return }
                HydrationReminderService.cancel(itemID: item.id, operationID: operationID)
                update { $0.hydrationRemindersEnabled = false }
                reminderMessage = error.localizedDescription
                reminderPermissionDenied = error is HydrationReminderError
            }
        }
    }

    private func update(_ change: (inout WidgetConfiguration) -> Void) {
        store.updateWidgetConfiguration(itemID: item.id, in: profileID, update: change)
    }
}

@MainActor
final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()

    @Published private(set) var readings: [BatteryReading] = []
    private var subscribers = Set<UUID>()
    private var visiblePopouts = Set<UUID>()
    private var schedulerDemand: RefreshDemandToken?
    private var refreshTask: Task<Void, Never>?
    private let scheduler: RefreshScheduler

    init(scheduler: RefreshScheduler = .shared) { self.scheduler = scheduler }

    var isSampling: Bool { refreshTask != nil }
    var holdsPopoutDemand: Bool { schedulerDemand != nil }

    func subscribe(_ identifier: UUID, popout: Bool = false) {
        subscribers.insert(identifier)
        if popout { visiblePopouts.insert(identifier) }
        scheduler.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { [weak self, scheduler] in
            for await _ in scheduler.ticks(every: 60) {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func unsubscribe(_ identifier: UUID) {
        subscribers.remove(identifier)
        visiblePopouts.remove(identifier)
        scheduler.setDemand(&schedulerDemand, kind: .popout, active: !visiblePopouts.isEmpty)
        guard subscribers.isEmpty else { return }
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func refresh() {
        #if DEBUG
        if let fixture = BatteryQAFixture.override { readings = fixture; return }
        #endif
        readings = BatteryReader.read()
    }
}

private struct BatteryCompactView: View {
    @Environment(\.dockWidgetContentWidth) private var contentWidth
    @StateObject private var monitor = BatteryMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        BatteryDockFace(readings: monitor.readings).frame(width: contentWidth, height: 54)
            .onAppear { monitor.subscribe(subscriptionID) }
            .onDisappear { monitor.unsubscribe(subscriptionID) }
            .accessibilityElement(children: .ignore).accessibilityLabel("Battery")
            .accessibilityValue(monitor.readings.map { "\($0.name), \($0.percentage) percent" }.joined(separator: ", "))
    }
}

private struct BatteryPopoutView: View {
    @StateObject private var monitor = BatteryMonitor.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        GroupedSection {
            if monitor.readings.isEmpty {
                GroupedRow("No battery information", subtitle: "This Mac reports no batteries.", symbol: "battery.0percent", color: .gray)
            } else {
                ForEach(monitor.readings) { battery in
                    BatteryRow(battery: battery)
                }
            }
        }
        .onAppear { monitor.subscribe(subscriptionID, popout: true) }
        .onDisappear { monitor.unsubscribe(subscriptionID) }
    }
}

/// One battery as a grouped row: its glyph, name, charging state and charge.
private struct BatteryRow: View {
    var battery: BatteryReading
    private var color: Color {
        if battery.isCharging { return .green }
        return battery.percentage <= 10 ? Color(nsColor: .systemRed) : battery.percentage <= 20 ? .orange : .green
    }
    var body: some View {
        GroupedRow(battery.displayName, subtitle: battery.isCharging ? "Charging" : "Not charging",
                   symbol: batterySymbol(battery.percentage, charging: battery.isCharging), color: color) {
            Text("\(battery.percentage)%")
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .accessibilityHidden(true)
        }
        .accessibilityValue("\(battery.percentage) percent, \(battery.isCharging ? "charging" : "not charging")")
    }
}

#if DEBUG
/// Render-QA seam: fixed battery readings instead of IOKit, set only by DEBUG exports.
@MainActor
enum BatteryQAFixture {
    static var override: [BatteryReading]?
}
#endif

private func batterySymbol(_ percentage: Int, charging: Bool) -> String {
    if charging { return "battery.100percent.bolt" }
    switch percentage {
    case 76...: return "battery.100percent"
    case 51...75: return "battery.75percent"
    case 26...50: return "battery.50percent"
    case 1...25: return "battery.25percent"
    default: return "battery.0percent"
    }
}

private struct FocusTimerPopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            timerTextView
            HStack {
                Button("Reset") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.resetFocusTimer() }
                }
                .buttonStyle(WidgetRoundButtonStyle())
                Spacer()
                Button(configuration.focusStartedAt == nil ? "Start" : "Pause") {
                    store.updateWidgetConfiguration(itemID: item.id, in: profileID) { value in
                        if value.focusStartedAt == nil { value.startFocusTimer() }
                        else { value.pauseFocusTimer() }
                    }
                }
                .buttonStyle(WidgetRoundButtonStyle(role: configuration.focusStartedAt == nil ? .start : .pause))
                .disabled(configuration.focusStartedAt != nil && configuration.focusRemaining() <= 0)
            }
            .padding(.horizontal, 24)
            GroupedSection {
                WidgetStepperRow(title: "Session", value: "\(configuration.focusDurationSeconds / 60) min",
                                 amount: focusDurationBinding, range: 60...7_200, step: 60)
                    .disabled(configuration.focusStartedAt != nil)
            }
        }
    }

    @ViewBuilder private var timerTextView: some View {
        if configuration.focusStartedAt != nil, configuration.focusRemaining() > 0 {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = configuration.focusRemaining(at: context.date)
                WidgetPopoutHero(value: timerText(remaining), caption: remaining <= 0 ? Self.completeCaption : "Focusing")
            }
        } else {
            let remaining = configuration.focusRemaining()
            WidgetPopoutHero(value: timerText(remaining),
                             caption: remaining <= 0 ? Self.completeCaption : remaining < Double(configuration.focusDurationSeconds) ? "Paused" : "Ready")
        }
    }

    private static let completeCaption = "Session complete · Reset to start again"

    private var focusDurationBinding: Binding<Int> {
        Binding(get: { configuration.focusDurationSeconds }, set: { seconds in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.focusDurationSeconds = seconds }
        })
    }
}

private struct StickyNotePopoutView: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    @State private var noteDraft = ""
    @State private var noteSaveTask: Task<Void, Never>?
    @State private var noteSaveError: String?
    @DockAccessibilityStyle() private var accessibility

    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }

    var body: some View {
        VStack(alignment: .leading, spacing: WidgetPopoutMetrics.spacing) {
            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $noteDraft)
                    .font(.system(size: 14))
                    .frame(minHeight: 150)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(noteForeground(configuration.noteBackground))
                    .tint(noteAccent(configuration.noteBackground))
                    .accessibilityLabel("Note text")
                    .padding(10)
                    .background(noteColor(configuration.noteBackground), in: noteShape)
                    .background(DockDesign.Grouped.fill, in: noteShape)
                    .overlay {
                        if accessibility.contrast == .increased {
                            noteShape.strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: noteDraft) { value in
                        WidgetSetupDraftStore.shared.updateNoteDraft(value, for: item.id, in: profileID)
                        noteSaveTask?.cancel()
                        noteSaveTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            guard !Task.isCancelled else { return }
                            saveNote(value)
                        }
                    }
                // The byte limit only matters near it; text above it stays in the recovery draft.
                if noteDraft.utf8.count > Self.byteLimit * 9 / 10 {
                    Text("\(noteDraft.utf8.count.formatted()) / 1,048,576 UTF-8 bytes · text above this limit stays in the recovery draft.")
                        .font(DockDesign.Grouped.footerFont)
                        .foregroundStyle(noteDraft.utf8.count > Self.byteLimit ? Color(nsColor: .systemRed) : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                }
                if let noteSaveError {
                    Text(noteSaveError).font(DockDesign.Grouped.footerFont).foregroundStyle(Color(nsColor: .systemRed))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
                        .accessibilityLabel("Note not saved. " + noteSaveError)
                }
            }
            GroupedSection {
                GroupedRow("Paper") {
                    HStack(spacing: 4) {
                        ForEach(NoteBackground.allCases) { background in
                            let selected = configuration.noteBackground == background
                            Button { noteBackgroundBinding.wrappedValue = background } label: {
                                NotePaperSwatch(background: background)
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(selected ? DockDesign.accent : .clear, lineWidth: 2))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain).help(background.title)
                            .accessibilityLabel(background.title + " paper")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
        }
        .onAppear { noteDraft = WidgetSetupDraftStore.shared.noteDraft(for: item.id, in: profileID) ?? configuration.noteText }
        .onDisappear {
            noteSaveTask?.cancel()
            saveNote(noteDraft)
        }
    }

    private static let byteLimit = 1_048_576
    private var noteShape: RoundedRectangle { RoundedRectangle(cornerRadius: DockDesign.Grouped.radius, style: .continuous) }

    private var noteBackgroundBinding: Binding<NoteBackground> {
        Binding(get: { configuration.noteBackground }, set: { background in
            store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.noteBackground = background }
        })
    }

    private func saveNote(_ text: String) {
        do {
            try WidgetSetupDraftStore.shared.saveNote(text, for: item.id, in: profileID, to: store)
            noteSaveError = nil
        } catch { noteSaveError = error.localizedDescription + " Your draft is retained." }
    }
}



private func timerText(_ interval: TimeInterval) -> String {
    TimerValueFormatter.text(interval)
}

func targetCountdownText(_ interval: TimeInterval, compact: Bool) -> String {
    let safeInterval = interval.isFinite ? min(max(0, interval), TimeInterval(Int.max / 4)) : 0
    let seconds = Int(safeInterval.rounded(.up))
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    if compact {
        if days > 0 { return "\(days)d" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return timerText(safeInterval)
    }
    if days > 0 { return "\(days)d \(String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds))" }
    if hours > 0 { return "\(hours):\(String(format: "%02d:%02d", minutes, remainingSeconds))" }
    return timerText(safeInterval)
}

func stopwatchText(_ interval: TimeInterval) -> String {
    let safeInterval = interval.isNaN ? 0 : min(max(0, interval), TimeInterval(Int.max / 4))
    let seconds = Int(safeInterval.rounded(.down))
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    let remainingSeconds = seconds % 60
    return hours > 0
        ? "\(hours):\(String(format: "%02d", minutes)):\(String(format: "%02d", remainingSeconds))"
        : String(format: "%02d:%02d", minutes, remainingSeconds)
}

func formattedTime(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = timeZone
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

func formattedDate(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.timeZone = timeZone
    formatter.dateStyle = .full
    return formatter.string(from: date)
}



/// A note paper choice as a small circle; Translucent shows as an outlined ring.
private struct NotePaperSwatch: View {
    var background: NoteBackground
    var body: some View {
        ZStack {
            Circle().fill(DockDesign.Grouped.fill)
            Circle().fill(background == .translucent ? Color.clear : noteColor(background))
            Circle().strokeBorder(Color.primary.opacity(background == .translucent ? 0.35 : 0.12), lineWidth: background == .translucent ? 1.5 : 0.5)
        }
        .frame(width: 18, height: 18)
    }
}

private func noteColor(_ background: NoteBackground) -> Color {
    switch background {
    case .yellow: .yellow.opacity(0.22)
    case .blue: .blue.opacity(0.18)
    case .pink: .pink.opacity(0.18)
    case .white: .white.opacity(0.6)
    case .black: .black.opacity(0.75)
    case .translucent: .primary.opacity(0.06)
    }
}

private func noteForeground(_ background: NoteBackground) -> Color {
    switch background {
    case .white: .black
    case .black: .white
    default: Color(nsColor: .textColor)
    }
}

private func noteAccent(_ background: NoteBackground) -> Color {
    switch background {
    case .white, .black: noteForeground(background)
    default: .accentColor
    }
}
