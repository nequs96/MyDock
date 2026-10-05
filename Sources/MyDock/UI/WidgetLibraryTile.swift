import SwiftUI

#if DEBUG
// Development catalog for comparing widget variants; AddLibrary is the product surface.
// Both are built from the same gallery components in UI/WidgetGallery.

/// Legacy size requests resolve to a family's supported semantic geometry.
enum WidgetGalleryPreviewInputs {
    static func option(for kind: String, width: WidgetCardWidth) -> WidgetLayoutOption {
        let options = WidgetPresentationCatalog.options(for: kind)
        switch width {
        case .compact: return options.first!
        case .standard: return options.first { $0.layout == WidgetPresentationCatalog.defaultLayout(for: kind) } ?? options.first!
        case .wide: return options.last!
        }
    }
}

/// One catalog tile: the gallery tile at a fixed width, optionally titled by its layout.
struct WidgetLibraryTile: View {
    var widget: WidgetDefinition
    var cardWidth: WidgetCardWidth = .standard
    var layout: WidgetLayout? = nil
    var added = false
    var showsVariantLabel = false
    var width: CGFloat = 224
    private var previewOption: WidgetLayoutOption {
        if let layout, let option = WidgetPresentationCatalog.options(for: widget.name).first(where: { $0.layout == layout }) { return option }
        return WidgetGalleryPreviewInputs.option(for: widget.name, width: cardWidth)
    }
    var body: some View {
        WidgetGalleryTile(widget: widget, layout: previewOption.layout, width: width, added: added,
                          title: showsVariantLabel ? previewOption.title : nil)
    }
}

/// The DEBUG variant gallery: search pill, size segments and category sections of gallery tiles.
struct WidgetGalleryView: View {
    var add: (WidgetDefinition, WidgetCardWidth) -> Void
    var onClose: () -> Void
    @State private var search = ""
    @State private var selectedSize: WidgetCardWidth = .standard
    @State private var recentlyAdded: Set<String> = []
    @State private var contentWidth: CGFloat = 700

    init(add: @escaping (WidgetDefinition, WidgetCardWidth) -> Void, onClose: @escaping () -> Void,
         initialSearch: String = "", initialSize: WidgetCardWidth = .standard) {
        self.add = add
        self.onClose = onClose
        _search = State(initialValue: initialSearch)
        _selectedSize = State(initialValue: initialSize)
    }
    private var sections: [WidgetGallerySection] { WidgetGalleryModel.sections(query: search) }
    private var columns: Int { WidgetGalleryModel.columnCount(for: contentWidth) }
    private var tileWidth: CGFloat {
        floor((contentWidth - WidgetGalleryMetrics.gridSpacing * CGFloat(columns - 1)) / CGFloat(columns))
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                GallerySearchPill(placeholder: "Search Widgets", text: $search, cancel: { search = "" })
                    .frame(maxWidth: WidgetGalleryMetrics.searchMaximumWidth).padding(.horizontal, 64)
                HStack {
                    Spacer()
                    Button("Done", action: onClose).buttonStyle(GalleryGlassButtonStyle()).keyboardShortcut(.cancelAction)
                }
            }
            .padding(.horizontal, 18)
            GallerySegmentedControl(items: WidgetCardWidth.allCases.map { ($0, $0.label) }, selection: $selectedSize,
                                    accessibilityLabel: "Widget size", keyboardShortcuts: false)
                .accessibilityIdentifier("gallery.size")
            DockScrollView {
                VStack(alignment: .leading, spacing: WidgetGalleryMetrics.sectionSpacing) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            GallerySectionTitle(title: section.category.rawValue)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: WidgetGalleryMetrics.gridSpacing, alignment: .top), count: columns),
                                      alignment: .leading, spacing: 20) {
                                ForEach(section.widgets) { widget in
                                    let key = widget.id + selectedSize.rawValue
                                    let option = WidgetGalleryPreviewInputs.option(for: widget.name, width: selectedSize)
                                    WidgetGalleryTile(widget: widget, layout: option.layout, width: tileWidth, added: recentlyAdded.contains(key),
                                                      open: { add(widget, selectedSize); recentlyAdded.insert(key) })
                                }
                            }
                        }
                    }
                    if sections.isEmpty {
                        GalleryEmptyState(title: "No Widgets Found", detail: "Try another name.") {
                            Button("Clear Search") { search = "" }.buttonStyle(GalleryGlassButtonStyle())
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, WidgetGalleryMetrics.pageInset).padding(.vertical, 6)
            }
            .galleryContentWidth($contentWidth)
        }
        .padding(.top, 16)
        .frame(minWidth: 680, idealWidth: 1040, maxWidth: .infinity, minHeight: 480, idealHeight: 680, maxHeight: .infinity)
        .background(DockDesign.page).tint(DockDesign.accent)
    }
}

#endif

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
            HStack(spacing: 5) {
                ForEach(items.filter { $0.type == .application }.prefix(3)) { item in
                    Image(nsImage: AppLauncher.icon(for: item, size: Self.chipHeight)).resizable().scaledToFit()
                        .frame(width: Self.chipHeight, height: Self.chipHeight)
                }
                ForEach(preset.widgetKinds.prefix(2), id: \.self) { kind in
                    PresetModuleChip(kind: kind, height: Self.chipHeight, radius: Self.chipRadius)
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
