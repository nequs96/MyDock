import AppKit
import SwiftUI

/// A starter Dock in the presets list and onboarding: its name, one line and a text-free mini Dock.
struct PresetLibraryTile: View {
    var preset: DockStarterPreset
    @State private var hovered = false
    @State private var items: [DockItem] = []
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme

    /// Thumbnail metrics: one height for icons and modules, a concentric strip radius.
    static let chipHeight: CGFloat = 28
    static let stripPadding: CGFloat = 6
    static let chipRadius: CGFloat = 8
    private var stripShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.chipRadius + Self.stripPadding, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.title).font(.system(size: 15, weight: .semibold))
                Text(preset.detail).font(DockDesign.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            // A text-free mini Dock: app icons, then each widget as a glyph in its module shape.
            // Real faces at this size would shrink their text to about 5 pt.
            // Every widget is shown, apps fill the rest, and anything beyond the strip is counted
            // so the thumbnail never hides what the preset contains.
            let apps = items.filter { $0.type == .application }
            let plan = PresetThumbnailPlan(appCount: apps.count, widgetCount: preset.widgetKinds.count)
            HStack(spacing: 5) {
                ForEach(apps.prefix(plan.shownApps)) { item in
                    Image(nsImage: AppLauncher.icon(for: item, size: Self.chipHeight)).resizable().scaledToFit()
                        .frame(width: Self.chipHeight, height: Self.chipHeight)
                }
                ForEach(preset.widgetKinds.prefix(plan.shownWidgets), id: \.self) { kind in
                    PresetModuleChip(kind: kind, height: Self.chipHeight, radius: Self.chipRadius)
                }
                if plan.hidden > 0 {
                    Text("+\(plan.hidden)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        .frame(minWidth: Self.chipHeight, minHeight: Self.chipHeight)
                }
            }
            .padding(Self.stripPadding)
            .background { strip }
            .overlay {
                if accessibility.contrast == .increased {
                    stripShape.dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                }
            }
            .accessibilityHidden(true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? DockDesign.hover : Color.clear, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .task { items = preset.resolve().items }
    }

    /// Material behind the mini Dock; opaque under Reduce Transparency.
    @ViewBuilder private var strip: some View {
        if accessibility.reduceTransparency {
            stripShape.fill(DockDesign.Glass.opaqueFill(scheme))
        } else {
            stripShape.fill(.regularMaterial)
        }
    }
}

/// How many apps and widgets a preset thumbnail shows: widgets first (they define the preset),
/// apps fill the remaining slots, and the rest becomes a "+N" count.
struct PresetThumbnailPlan: Equatable {
    static let slots = 6
    var shownApps: Int
    var shownWidgets: Int
    var hidden: Int
    init(appCount: Int, widgetCount: Int) {
        shownWidgets = min(widgetCount, Self.slots)
        shownApps = min(appCount, Self.slots - shownWidgets)
        hidden = appCount + widgetCount - shownApps - shownWidgets
    }
}

/// One widget in a preset thumbnail: the family's SF Symbol in the shape of its default
/// module (a circle for icon-only families), monochrome like a new widget, with no text.
struct PresetModuleChip: View {
    var kind: String
    var height: CGFloat = 28
    var radius: CGFloat = 8
    @DockAccessibilityStyle() private var accessibility

    /// The default module's aspect at `height`, kept between square and two squares.
    static func width(for kind: String, height: CGFloat) -> CGFloat {
        let layout = WidgetGalleryModel.defaultLayout(for: kind)
        guard layout != .icon else { return height }
        let moduleWidth = CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout))
        return min(height * 2, max(height, (height * moduleWidth / 54).rounded()))
    }
    private var isIcon: Bool { WidgetGalleryModel.defaultLayout(for: kind) == .icon }
    private var shape: AnyShape {
        isIcon ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    var body: some View {
        let contrast = accessibility.contrast == .increased
        Image(systemName: WidgetRegistry.definition(named: kind)?.symbol ?? "square.grid.2x2")
            .font(.system(size: height * 0.46, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.primary.opacity(contrast ? 0.95 : 0.78))
            .frame(width: Self.width(for: kind, height: height), height: height)
            .background(shape.fill(Color.primary.opacity(contrast ? 0.16 : 0.09)))
            .overlay {
                if contrast { shape.dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: 1) }
            }
            .accessibilityHidden(true)
    }
}
