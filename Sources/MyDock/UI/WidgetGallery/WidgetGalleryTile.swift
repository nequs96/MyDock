import SwiftUI

/// A gallery tile: a large live sample preview on a soft glass backdrop, the family name below,
/// and a check badge once added. Click opens the detail, double-click adds the default layout.
struct WidgetGalleryTile: View {
    enum Style { case grid, hero }

    var widget: WidgetDefinition
    var layout: WidgetLayout
    var width: CGFloat
    var style: Style = .grid
    var added = false
    var selected = false
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                WidgetCardPreview(kind: widget.name, width: CGFloat(option.width), displayScale: previewScale, layout: option.layout)
                    .allowsHitTesting(false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if added {
                    GalleryAddedBadge(generation: addGeneration, size: style == .hero ? 24 : 22)
                        .padding(10)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .frame(width: width, height: backdropHeight)
            .galleryBackdrop(radius: radius, highlighted: selected)
            .dockHover(hovered)
            VStack(alignment: .leading, spacing: 2) {
                Text(title ?? widget.name)
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
        .accessibilityLabel("\(title ?? widget.name), widget, sample preview" + (added ? ", Added" : ""))
        .accessibilityHint(open == nil ? "" : "Shows sizes and details.")
        .accessibilityAddTraits(open == nil ? [] : .isButton)
        .help(open == nil ? "" : addDefault == nil ? "Show sizes" : "Click to see sizes. Double-click to add.")
    }
}

/// Click opens, double-click adds; VoiceOver gets the same two actions by name.
private struct TileActivation: ViewModifier {
    var open: (() -> Void)?
    var addDefault: (() -> Void)?
    func body(content: Content) -> some View {
        if let open {
            if let addDefault {
                content
                    .gesture(TapGesture(count: 2).onEnded { addDefault() }.exclusively(before: TapGesture().onEnded { open() }))
                    .accessibilityAction(.default) { open() }
                    .accessibilityAction(named: "Add") { addDefault() }
            } else {
                content.onTapGesture(perform: open).accessibilityAction(.default) { open() }
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
