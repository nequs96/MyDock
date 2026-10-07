import AppKit
import SwiftUI

enum WidgetDesign {
    /// The render-QA stand-in for the popover's material: the grouped page colour, so grouped sections
    /// read on it exactly as they do in the settings sheet. Live popouts use the popover's own surface.
    static let surface = DockDesign.page
}

extension WidgetIconAppearance {
    /// Redesign titles for the icon treatments. Raw values and the model's `title` are unchanged.
    var displayTitle: String {
        switch self {
        case .accent: "Color"
        case .soft: "Soft"
        case .mono: "Mono"
        case .outline: "Outline"
        }
    }
}

#if DEBUG
/// Render QA only: an icon-only action in each legacy icon style.
struct WidgetIconTile: View {
    var item: DockItem
    var style: WidgetIconStyle
    var width: CGFloat = DockDesign.Module.narrowWidth
    @Environment(\.widgetShowsLabel) private var showsLabel
    var body: some View {
        let showsName = !WidgetModuleMetrics.isNarrow(width) && showsLabel
        VStack(spacing: 2) {
            WidgetToggleGlyph(kind: item.widgetKind ?? item.title, diameter: showsName ? 30 : 36)
                .environment(\.widgetIconAppearance, .init(legacy: style))
            if showsName {
                Text(item.displayName).font(DockDesign.Module.label).lineLimit(1)
                    .minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
            }
        }
        .padding(.horizontal, 6).frame(width: width, height: DockDesign.Module.height)
        .moduleAccessibility(item.displayName)
    }
}
#endif

/// Pure choices of the per-widget Appearance editor. Raw values and persisted keys are unchanged.
enum WidgetAppearanceOptions {
    /// Automatic, Mono, then every profile colour, in display order.
    static var accentChoices: [WidgetAccent] { [.auto, .mono] + DockProfileColor.allCases.map(WidgetAccent.profile) }

    /// What Automatic does: neutral at rest, the family colour only while the widget is active.
    static let autoAccentCaption = "Neutral; color shows when active"

    static func accentTitle(_ accent: WidgetAccent) -> String {
        switch accent {
        case .auto: "Automatic"
        case .mono: "Mono"
        case .profile(let color): color.title
        }
    }

    /// The tint only changes glass modules, so its row exists only for that surface.
    static func showsGlassTint(surface: DockWidgetSurface) -> Bool { surface == .glass }
}

/// Label visibility as a three-way choice: follow the Dock (nil), always shown, always hidden.
enum WidgetLabelChoice: String, CaseIterable, Identifiable {
    case followDock, shown, hidden
    var id: String { rawValue }
    init(stored: Bool?) {
        switch stored {
        case nil: self = .followDock
        case true?: self = .shown
        case false?: self = .hidden
        }
    }
    var stored: Bool? {
        switch self {
        case .followDock: nil
        case .shown: true
        case .hidden: false
        }
    }
    var title: String {
        switch self {
        case .followDock: "Auto"
        case .shown: "On"
        case .hidden: "Off"
        }
    }
}

/// Every per-widget appearance write. All of them go through `ProfileStore.updateWidgetConfiguration`,
/// the path the Dock editor's drafts, undo and merge already observe.
@MainActor
enum WidgetAppearanceWriter {
    @discardableResult
    static func setLayout(_ layout: WidgetLayout, itemID: UUID, profileID: UUID, store: ProfileStore) -> WidgetConfigurationUpdateResult {
        store.updateWidgetConfiguration(itemID: itemID, in: profileID) { $0.widgetLayout = layout }
    }
    @discardableResult
    static func setAccent(_ accent: WidgetAccent, itemID: UUID, profileID: UUID, store: ProfileStore) -> WidgetConfigurationUpdateResult {
        store.updateWidgetConfiguration(itemID: itemID, in: profileID) { $0.widgetAccent = accent }
    }
    @discardableResult
    static func setLabel(_ choice: WidgetLabelChoice, itemID: UUID, profileID: UUID, store: ProfileStore) -> WidgetConfigurationUpdateResult {
        store.updateWidgetConfiguration(itemID: itemID, in: profileID) { $0.showsLabel = choice.stored }
    }
    @discardableResult
    static func setGlassTint(_ tint: WidgetGlassTint, itemID: UUID, profileID: UUID, store: ProfileStore) -> WidgetConfigurationUpdateResult {
        store.updateWidgetConfiguration(itemID: itemID, in: profileID) { $0.glassTint = tint }
    }
    @discardableResult
    static func setIconAppearance(_ appearance: WidgetIconAppearance, itemID: UUID, profileID: UUID, store: ProfileStore) -> WidgetConfigurationUpdateResult {
        store.updateWidgetConfiguration(itemID: itemID, in: profileID) { $0.iconAppearance = appearance }
    }
}

/// The grouped Appearance section: accent, icon style, label and glass tint, plus the two
/// family-specific face choices. The settings sheet and the in-Dock popout's Customize panel
/// (`WidgetCustomizePanel`) both show it below the same size pager, so there is one vocabulary.
struct WidgetAppearanceControls: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var settings: AppSettings { store.effectiveSettings(profileID: profileID) }
    private var accent: WidgetAccent { configuration.widgetAccent ?? .auto }
    private var labelChoice: WidgetLabelChoice { WidgetLabelChoice(stored: configuration.showsLabel) }

    var body: some View {
        GroupedSection("Appearance", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            GroupedRow("Accent", subtitle: accent == .auto ? WidgetAppearanceOptions.autoAccentCaption : nil) { accentSwatches }
            // Every family draws its icon somewhere (a label glyph, a narrow face), so every family offers the choice.
            iconStyleRow
            GroupedRow("Label", subtitle: labelChoice == .followDock ? "Follows the Dock · " + (settings.showWidgetLabels ? "On" : "Off") : nil) {
                Picker("Label", selection: Binding(get: { labelChoice }, set: { choice in
                    WidgetAppearanceWriter.setLabel(choice, itemID: item.id, profileID: profileID, store: store)
                })) {
                    ForEach(WidgetLabelChoice.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .accessibilityLabel("Label")
                .accessibilityHint("Auto follows the Dock's label setting")
            }
            if WidgetAppearanceOptions.showsGlassTint(surface: settings.customDockWidgetSurface) {
                GroupedRow("Glass tint") {
                    Picker("Glass tint", selection: Binding(get: { configuration.glassTint ?? .none }, set: { tint in
                        WidgetAppearanceWriter.setGlassTint(tint, itemID: item.id, profileID: profileID, store: store)
                    })) {
                        Text("None").tag(WidgetGlassTint.none)
                        Text("Accent").tag(WidgetGlassTint.accent)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                    .accessibilityLabel("Glass tint")
                }
            }
            if kind == "AI Activity" {
                GroupedRow("Secondary metric") {
                    Picker("Secondary metric", selection: Binding(get: { configuration.aiActivitySecondaryMetric }, set: { value in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.aiActivitySecondaryMetric = value }
                    })) { ForEach(AIActivitySecondaryMetric.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize().accessibilityLabel("Secondary metric")
                }
            }
            // Only the Trend face draws the secondary reading.
            if kind == "System Activity" && WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: configuration,
                                                                                    compactDefault: settings.customDockWidgetStyle == .compact) == .trend {
                GroupedRow("Trend detail") {
                    Picker("Trend detail", selection: Binding(get: { configuration.systemSecondaryMetric }, set: { value in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.systemSecondaryMetric = value }
                    })) { ForEach(SystemSecondaryMetric.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize().accessibilityLabel("Trend detail")
                }
            }
        }
    }

    private var accentSwatches: some View {
        HStack(spacing: 4) {
            ForEach(WidgetAppearanceOptions.accentChoices, id: \.self) { choice in
                let selected = choice == accent
                Button {
                    WidgetAppearanceWriter.setAccent(choice, itemID: item.id, profileID: profileID, store: store)
                } label: {
                    WidgetAccentSwatch(kind: kind, accent: choice, selected: selected)
                }
                .buttonStyle(.plain)
                .help(WidgetAppearanceOptions.accentTitle(choice))
                .accessibilityLabel(WidgetAppearanceOptions.accentTitle(choice) + " accent")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var iconStyleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon").font(DockDesign.Grouped.titleFont).accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(WidgetIconAppearance.allCases) { appearance in
                    let selected = configuration.iconAppearance == appearance
                    Button {
                        WidgetAppearanceWriter.setIconAppearance(appearance, itemID: item.id, profileID: profileID, store: store)
                    } label: {
                        VStack(spacing: 4) {
                            WidgetIcon(kind: kind, symbol: kind == "AI Activity" ? (configuration.aiActivityProvider == .codex ? "terminal" : "sparkle") : nil,
                                       size: 28, appearance: appearance)
                                .frame(width: 40, height: 40)
                                .overlay(Circle().strokeBorder(selected ? DockDesign.accent : .clear, lineWidth: 2))
                            Text(appearance.displayTitle)
                                .font(DockDesign.Grouped.subtitleFont.weight(selected ? .semibold : .regular))
                                .foregroundStyle(selected ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(appearance.displayTitle) icon")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .environment(\.widgetAccent, accent)
        }
        .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon style")
    }
}

/// One accent choice: the colour it resolves to for this family, with a ring when selected.
/// Automatic shows the family colour it takes while active, with a small "A" so it reads as a mode rather than a colour.
struct WidgetAccentSwatch: View {
    var kind: String
    var accent: WidgetAccent
    var selected: Bool
    var diameter: CGFloat = 18
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle().fill(WidgetPalette.resolved(kind: kind, accent: accent, active: true))
            if case .auto = accent {
                Text("A").font(.system(size: diameter * 0.5, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetIcon.onFillIsBlack(treatment: .accent, accent: accent, dark: scheme == .dark) ? Color.black : Color.white)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            if accessibility.contrast == .increased {
                Circle().strokeBorder(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
            }
        }
        .padding(3)
        .overlay(Circle().strokeBorder(selected ? DockDesign.accent : .clear, lineWidth: 2))
        .contentShape(Circle())
    }
}
