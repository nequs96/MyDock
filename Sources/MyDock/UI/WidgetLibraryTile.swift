import SwiftUI

#if DEBUG
// Development catalog for comparing widget variants, used only by render QA; AddLibrary is
// the product surface. Both are built from the same gallery components in UI/WidgetGallery.
// The shipping preset thumbnails live in PresetLibraryTile.swift.

/// Legacy size requests resolve to a family's supported semantic geometry.
enum WidgetGalleryPreviewInputs {
    static func option(for kind: String, width: WidgetCardWidth) -> WidgetLayoutOption {
        let options = WidgetGalleryModel.layoutOptions(for: kind)
        let fallback = options.first ?? WidgetLayoutPresets.generic[0]
        switch width {
        case .compact: return fallback
        case .standard: return options.first { $0.layout == WidgetPresentationCatalog.defaultLayout(for: kind) } ?? fallback
        case .wide: return options.last ?? fallback
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
                        GalleryEmptyState(title: "No Results", detail: "Try another search.") {
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
