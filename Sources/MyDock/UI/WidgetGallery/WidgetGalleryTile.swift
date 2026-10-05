import SwiftUI

/// A gallery tile: a large live sample preview floating on the page, as in the iOS widget
/// gallery, the family name below, and a check badge once added. Click opens the detail,
/// double-click adds the default layout. Hover, the search highlight and keyboard focus show
/// as a soft backdrop and a focus ring around the preview (see `galleryTileBackdrop`).
struct WidgetGalleryTile: View {
    enum Style { case grid, hero }

    var widget: WidgetDefinition
    var layout: WidgetLayout
    var width: CGFloat
    var style: Style = .grid
    var added = false
    /// The search field's highlighted result.
    var selected = false
    /// Keyboard focus is on this tile.
    var focused = false
    var addGeneration = 0
    /// Overrides the family name, e.g. a layout title in the DEBUG variant catalog.
    var title: String? = nil
    var open: (() -> Void)? = nil
    var addDefault: (() -> Void)? = nil

    @State private var hovered = false

    private var option: WidgetLayoutOption {
        WidgetPresentationCatalog.options(for: widget.name).first { $0.layout == layout }
            ?? WidgetPresentationCatalog.options(for: widget.name).first!
    }
    private var backdropHeight: CGFloat { style == .hero ? 164 : 122 }
    private var maximumScale: CGFloat { style == .hero ? 2.0 : 1.6 }
    private var previewScale: CGFloat {
        let horizontal = (width - 36) / CGFloat(option.width)
        let vertical = (backdropHeight - 34) / 54
        return max(0.6, min(maximumScale, horizontal, vertical))
    }
    private var radius: CGFloat { style == .hero ? WidgetGalleryMetrics.heroRadius : WidgetGalleryMetrics.tileRadius }
    private var name: String { title ?? widget.name }
    private var badgeSize: CGFloat { style == .hero ? 24 : 22 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            WidgetGalleryPreview(kind: widget.name, width: CGFloat(option.width), displayScale: previewScale, layout: option.layout)
                .allowsHitTesting(false)
                // With no tile around the module, the check sits on the module's own corner.
                .overlay(alignment: .topTrailing) {
                    if added {
                        GalleryAddedBadge(generation: addGeneration, size: badgeSize)
                            .offset(x: badgeSize * 0.35, y: -badgeSize * 0.35)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                }
                .dockHover(hovered)
                .frame(width: width, height: backdropHeight)
            .galleryTileBackdrop(radius: radius, hovered: hovered && open != nil, selected: selected, focused: focused)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(style == .hero ? .system(size: 14, weight: .semibold) : WidgetGalleryMetrics.tileTitle)
                    .lineLimit(1)
                if style == .hero {
                    Text(widget.description)
                        .font(WidgetGalleryMetrics.tileDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .modifier(TileActivation(open: open, addDefault: addDefault))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), widget, sample preview" + (added ? ", Added" : ""))
        .accessibilityHint(open == nil ? "" : WidgetGalleryKeymap.tileHint(canAdd: addDefault != nil))
        .accessibilityAddTraits(open == nil ? [] : .isButton)
        .help(open == nil ? "" : WidgetGalleryKeymap.tileHelp(canAdd: addDefault != nil))
    }
}

/// A widget sample drawn the way the gallery creates the widget: the creation configuration's
/// icon appearance, accent and glass tint (`WidgetGalleryPreviewStyle.creation`), so what the
/// gallery shows is what gets added.
struct WidgetGalleryPreview: View {
    var kind: String
    var width: CGFloat
    var displayScale: CGFloat
    var layout: WidgetLayout

    var body: some View {
        let style = WidgetGalleryPreviewStyle.creation(kind: kind)
        WidgetCardPreview(kind: kind, width: width, displayScale: displayScale, layout: layout, appearance: style.appearance)
            .environment(\.widgetAccent, style.accent)
            .environment(\.widgetGlassTint, style.glassTint)
    }
}

/// Click opens, double-click adds; VoiceOver gets both by name ("Show Sizes", "Add").
/// The keyboard route (Return/Space, Command-Return) lives in `AddLibrary`, which owns focus.
private struct TileActivation: ViewModifier {
    var open: (() -> Void)?
    var addDefault: (() -> Void)?
    func body(content: Content) -> some View {
        if let open {
            if let addDefault {
                content
                    .gesture(TapGesture(count: 2).onEnded { addDefault() }.exclusively(before: TapGesture().onEnded { open() }))
                    .accessibilityAction(.default) { open() }
                    .accessibilityAction(named: "Show Sizes") { open() }
                    .accessibilityAction(named: "Add") { addDefault() }
            } else {
                content
                    .onTapGesture(perform: open)
                    .accessibilityAction(.default) { open() }
                    .accessibilityAction(named: "Show Sizes") { open() }
            }
        } else {
            content
        }
    }
}

/// A tile of the More segment: a glyph or spacer illustration on the same backdrop.
struct WidgetGalleryMoreTile: View {
    var entry: WidgetGalleryMoreEntry
    var width: CGFloat
    var selected = false
    var enabled = true
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                illustration
                    .frame(width: width, height: 104)
                    .galleryBackdrop(highlighted: selected)
                    .dockHover(hovered && enabled)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(WidgetGalleryMetrics.tileTitle).lineLimit(1)
                    Text(entry.detail).font(WidgetGalleryMetrics.tileDetail).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.title)
        .accessibilityHint(entry.detail)
        .accessibilityAddTraits(.isButton)
        .help(entry.detail)
    }

    @ViewBuilder private var illustration: some View {
        if let spacer = entry.item?.spacerKind {
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { _ in block }
                Color.clear.frame(width: spacer == .small ? 8 : 26, height: 1)
                ForEach(0..<2, id: \.self) { _ in block }
            }
            .accessibilityHidden(true)
        } else {
            Image(systemName: entry.symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var block: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.13)).frame(width: 30, height: 30)
    }
}
