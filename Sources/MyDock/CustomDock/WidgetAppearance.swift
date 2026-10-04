import AppKit
import SwiftUI

enum WidgetDesign {
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let inset = Color.primary.opacity(0.035)
}

struct WidgetEmblem: View {
    var kind: String
    var style: WidgetIconStyle = .tinted
    var size: CGFloat = 28
    var body: some View { WidgetIcon(kind: kind, size: size, appearance: .init(legacy: style)) }
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

/// Compatibility for icon-only actions. Data widgets never use this to switch layout.
struct WidgetIconTile: View {
    var item: DockItem
    var style: WidgetIconStyle
    var width: CGFloat = 54
    @Environment(\.widgetShowsLabel) private var showsLabel
    var body: some View {
        let showsName = width > 54 && showsLabel
        VStack(spacing: 2) {
            WidgetToggleGlyph(kind: item.widgetKind ?? item.title, diameter: showsName ? 30 : 36)
                .environment(\.widgetIconAppearance, .init(legacy: style))
            if showsName {
                Text(item.displayName).font(DockDesign.Module.label).lineLimit(1)
                    .minimumScaleFactor(DockDesign.Module.minimumTextSize / 11)
            }
        }.padding(.horizontal, 6).frame(width: width, height: 54)
    }
}

/// Pure choices of the per-widget Appearance editor. Raw values and persisted keys are unchanged.
enum WidgetAppearanceOptions {
    /// Automatic, Mono, then every profile colour, in display order.
    static var accentChoices: [WidgetAccent] { [.auto, .mono] + DockProfileColor.allCases.map(WidgetAccent.profile) }

    static func accentTitle(_ accent: WidgetAccent) -> String {
        switch accent {
        case .auto: "Automatic"
        case .mono: "Mono"
        case .profile(let color): color.title
        }
    }

    /// The tint only changes glass modules, so its row exists only for that surface.
    static func showsGlassTint(surface: DockWidgetSurface) -> Bool { surface == .glass }

    /// Families whose faces never draw a family icon offer no icon choice.
    static func showsIconStyle(kind: String) -> Bool { kind != "Sticky Note" && kind != "Time Progress" }
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
/// family-specific face choices. The settings sheet shows it below its size pager; the in-Dock
/// popout's Customize panel shows it with a compact Size row because it has no pager.
struct WidgetAppearanceControls: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    var showsSizeRow = false
    private var kind: String { item.widgetKind ?? item.title }
    private var configuration: WidgetConfiguration { item.widgetConfiguration ?? WidgetConfiguration() }
    private var settings: AppSettings { store.effectiveSettings(profileID: profileID) }
    private var layout: WidgetLayout {
        WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: configuration, compactDefault: settings.customDockWidgetStyle == .compact)
    }
    private var accent: WidgetAccent { configuration.widgetAccent ?? .auto }
    private var labelChoice: WidgetLabelChoice { WidgetLabelChoice(stored: configuration.showsLabel) }

    var body: some View {
        GroupedSection("Appearance", separatorInset: DockDesign.Grouped.rowHorizontalPadding) {
            if showsSizeRow && WidgetPresentationCatalog.options(for: kind).count > 1 { sizeRow }
            GroupedRow("Accent") { accentSwatches }
            if WidgetAppearanceOptions.showsIconStyle(kind: kind) { iconStyleRow }
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
            if kind == "System Activity" {
                GroupedRow("Trend secondary") {
                    Picker("Trend secondary", selection: Binding(get: { configuration.systemSecondaryMetric }, set: { value in
                        store.updateWidgetConfiguration(itemID: item.id, in: profileID) { $0.systemSecondaryMetric = value }
                    })) { ForEach(SystemSecondaryMetric.allCases) { Text($0.title).tag($0) } }
                    .labelsHidden().fixedSize().accessibilityLabel("Trend secondary")
                }
            }
        }
    }

    private var sizeRow: some View {
        GroupedRow("Size") {
            Picker("Size", selection: Binding(get: { layout }, set: { value in
                WidgetAppearanceWriter.setLayout(value, itemID: item.id, profileID: profileID, store: store)
            })) {
                ForEach(WidgetPresentationCatalog.options(for: kind)) { Text($0.title).tag($0.layout) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .accessibilityLabel("Size")
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
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
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
/// Automatic carries a small "A" so it reads as a mode rather than a colour.
struct WidgetAccentSwatch: View {
    var kind: String
    var accent: WidgetAccent
    var selected: Bool
    var diameter: CGFloat = 18
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Circle().fill(WidgetPalette.resolved(kind: kind, accent: accent))
            if case .auto = accent {
                Text("A").font(.system(size: diameter * 0.5, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay {
            if accessibility.contrast == .increased {
                Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1)
            }
        }
        .padding(3)
        .overlay(Circle().strokeBorder(selected ? DockDesign.accent : .clear, lineWidth: 2))
        .contentShape(Circle())
    }
}

struct WidgetSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            content
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(WidgetDesign.inset, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(DockDesign.hairline, lineWidth: 0.5))
    }
}
