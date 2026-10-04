import SwiftUI

#if DEBUG
// Development catalog for comparing all widget variants; AddLibrary is the product surface.
private enum WidgetGalleryMetrics {
    static let previewScale: CGFloat = 1.5
    static let previewHeight: CGFloat = 54 * previewScale
    static let columnMinimum: CGFloat = 224
    static let columnMaximum: CGFloat = 248
    static let captionHeight: CGFloat = 24
}

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

/// Desktop gallery tiles keep their geometry unchanged when hovered or pressed.
private struct WidgetGalleryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct WidgetLibraryTile: View {
    var widget: WidgetDefinition
    var cardWidth: WidgetCardWidth = .standard
    var layout: WidgetLayout? = nil
    var added = false
    var showsVariantLabel = false
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var previewOption: WidgetLayoutOption {
        if let layout, let option = WidgetPresentationCatalog.options(for: widget.name).first(where: { $0.layout == layout }) { return option }
        return WidgetGalleryPreviewInputs.option(for: widget.name, width: cardWidth)
    }
    private var previewWidth: CGFloat { CGFloat(previewOption.width) }
    private var previewScale: CGFloat {
        min(WidgetGalleryMetrics.previewScale,
            (WidgetGalleryMetrics.columnMinimum - 2 * DockDesign.Space.xxs) / previewWidth)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: DockDesign.Space.small) {
            WidgetCardPreview(kind: widget.name, width: previewWidth, displayScale: previewScale, layout: previewOption.layout)
                .overlay(RoundedRectangle(cornerRadius: 12 * previewScale, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovered ? 0.24 : 0.06), lineWidth: 1))
                .frame(maxWidth: .infinity).frame(height: WidgetGalleryMetrics.previewHeight)
                .accessibilityHidden(true)
            Text("Example").font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel("Example preview for \(widget.name)")
            HStack(spacing: DockDesign.Space.xs) {
                Text(showsVariantLabel ? previewOption.title : widget.name)
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: DockDesign.Space.xxs)
                Image(systemName: added ? "checkmark.circle" : "plus.circle.fill")
                    .font(.system(size: 16, weight: .medium)).frame(width: 20, height: 20)
                    .foregroundStyle(added ? Color.secondary : hovered ? DockDesign.accent : Color.primary.opacity(0.55))
            }.frame(height: WidgetGalleryMetrics.captionHeight)
            if !showsVariantLabel {
                Text(added ? "Added. Click to add another." : widget.description)
                    .font(DockDesign.caption).foregroundStyle(.secondary).lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
            }
        }.padding(DockDesign.Space.xxs)
            .background(hovered ? DockDesign.hover : Color.clear, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
            .contentShape(RoundedRectangle(cornerRadius: DockDesign.Radius.group))
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: hovered)
    }
}

private enum GalleryCategory: String, CaseIterable, Identifiable {
    case all = "All Widgets", clocks = "Clocks & Timers", calendar = "Calendar", reminders = "Reminders"
    case notes = "Sticky Notes", media = "Media", system = "System", weather = "Weather", business = "Business", ai = "AI", utilities = "Utilities"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"; case .clocks: "clock"; case .calendar: "calendar"; case .reminders: "checklist"
        case .notes: "note.text"; case .media: "music.note"; case .system: "desktopcomputer"; case .weather: "cloud.sun"
        case .business: "chart.bar"; case .ai: "sparkles"; case .utilities: "square.stack.3d.up"
        }
    }
    func includes(_ widget: WidgetDefinition) -> Bool {
        switch self {
        case .all: true
        case .clocks: widget.category == .time || widget.name == "Focus Timer"
        case .calendar: widget.name == "Calendar"
        case .reminders: widget.name == "Reminders"
        case .notes: widget.name == "Sticky Note"
        case .media: widget.name == "Now Playing"
        case .system: widget.category == .system
        case .weather: widget.name == "Weather"
        case .business: widget.category == .business
        case .ai: widget.category == .ai
        case .utilities: ["App Folder", "Shortcuts", "Hydration"].contains(widget.name)
        }
    }
}

struct WidgetGalleryView: View {
    var add: (WidgetDefinition, WidgetCardWidth) -> Void
    var onClose: () -> Void
    @State private var search = ""
    @State private var category: GalleryCategory = .all
    @State private var selectedSize: WidgetCardWidth = .standard
    @State private var recentlyAdded: Set<String> = []

    init(add: @escaping (WidgetDefinition, WidgetCardWidth) -> Void, onClose: @escaping () -> Void,
         initialSearch: String = "", initialSize: WidgetCardWidth = .standard) {
        self.add = add
        self.onClose = onClose
        _search = State(initialValue: initialSearch)
        _selectedSize = State(initialValue: initialSize)
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var widgets: [WidgetDefinition] {
        let order = ["Calendar", "Reminders", "Sticky Note", "Clock", "World Clock", "Weather", "Focus Timer", "Now Playing"]
        return WidgetRegistry.all.filter { category.includes($0) && WidgetDiscovery.matches($0, query: query) }
            .sorted {
                let first = order.firstIndex(of: $0.name) ?? 100
                let second = order.firstIndex(of: $1.name) ?? 100
                return first == second ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : first < second
            }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                DockSidebarHeader(title: "Widgets", symbol: "square.grid.2x2") { EmptyView() }
                DockSearchField(placeholder: "Search widgets", text: $search)
                    .padding(.horizontal, 16).padding(.bottom, 16)
                DockScrollView {
                    VStack(spacing: 2) {
                        ForEach(GalleryCategory.allCases) { choice in
                            SidebarRow(selected: category == choice) {
                                HStack(spacing: 10) {
                                    Image(systemName: choice.symbol).font(.system(size: 16)).frame(width: 20).foregroundStyle(.secondary)
                                    Text(choice.rawValue).font(DockDesign.body)
                                }
                            } action: { category = choice }
                        }
                    }.padding(.horizontal, 12)
                }
                Text("Designed for your Dock.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(20)
            }.frame(width: DockDesign.sidebarWidth).background(DockSidebarBackground())
            Rectangle().fill(DockDesign.hairline).frame(width: 1)
            VStack(spacing: 0) {
                HStack(spacing: DockDesign.Space.medium) {
                    Text(query.isEmpty ? category.rawValue : "Search results")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: DockDesign.Space.small)
                    HStack(spacing: DockDesign.Space.xs) {
                        Text("Size").font(DockDesign.caption).foregroundStyle(.secondary)
                            .lineLimit(1).fixedSize()
                        Picker("Widget size", selection: $selectedSize) {
                            ForEach(WidgetCardWidth.allCases) { size in Text(size.label).tag(size) }
                        }.labelsHidden().pickerStyle(.menu).frame(width: 112)
                            .accessibilityLabel("Widget size").accessibilityIdentifier("gallery.size")
                            .help("Choose the size to preview and add. You can change it later in widget settings.")
                    }
                    Button("Done", action: onClose).keyboardShortcut(.cancelAction)
                }.padding(.horizontal, DockDesign.Space.page).padding(.vertical, DockDesign.Space.large)
                ScrollViewReader { proxy in
                    DockScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: WidgetGalleryMetrics.columnMinimum,
                                                              maximum: WidgetGalleryMetrics.columnMaximum),
                                                    spacing: DockDesign.Space.large, alignment: .leading)],
                                  alignment: .leading, spacing: DockDesign.Space.large) {
                            ForEach(widgets) { widget in
                                let key = widget.id + selectedSize.rawValue
                                Button {
                                    add(widget, selectedSize)
                                    recentlyAdded.insert(key)
                                } label: {
                                    WidgetLibraryTile(widget: widget, cardWidth: selectedSize, added: recentlyAdded.contains(key))
                                }.buttonStyle(WidgetGalleryButtonStyle())
                                    .accessibilityLabel("Add \(widget.name), \(selectedSize.label)")
                                    .help("Add \(widget.name) to this Dock")
                            }
                        }.padding(.horizontal, DockDesign.Space.page).padding(.top, DockDesign.Space.small)
                            .padding(.bottom, DockDesign.Space.page).id("gallery-top")
                        if widgets.isEmpty {
                            VStack(spacing: DockDesign.Space.medium) {
                                Image(systemName: "magnifyingglass").font(.system(size: 28)).foregroundStyle(.tertiary)
                                Text("No widgets found").font(DockDesign.sectionTitle)
                                Text("Try another name or choose All Widgets.").font(DockDesign.body).foregroundStyle(.secondary)
                                Button("Clear Search") { search = ""; category = .all }
                            }.frame(maxWidth: .infinity).padding(.vertical, 64)
                        }
                    }
                    .onChange(of: search) { _ in proxy.scrollTo("gallery-top", anchor: .top) }
                    .onChange(of: category) { _ in proxy.scrollTo("gallery-top", anchor: .top) }
                }
                Rectangle().fill(DockDesign.hairline).frame(height: 1)
                Text("Sample previews · Change size or configure a widget after adding it.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DockDesign.Space.page).padding(.vertical, DockDesign.Space.medium)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 760, idealWidth: 1040, maxWidth: .infinity, minHeight: 480, idealHeight: 680, maxHeight: .infinity)
            .background(DockDesign.page).buttonStyle(DockButtonStyle()).tint(DockDesign.accent)
    }
}

#endif

struct PresetLibraryTile: View {
    var preset: DockStarterPreset
    @State private var hovered = false
    @State private var items: [DockItem] = []
    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.title).font(.system(size: 15, weight: .semibold))
                Text(preset.detail).font(DockDesign.caption).foregroundStyle(.secondary).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                ForEach(items.filter { $0.type == .application }.prefix(3)) { item in
                    Image(nsImage: AppLauncher.icon(for: item, size: 28)).resizable().scaledToFit().frame(width: 28, height: 28)
                }
                ForEach(preset.widgetKinds.prefix(2), id: \.self) { kind in
                    WidgetCardPreview(kind: kind, width: 92, displayScale: 0.6)
                }
            }.padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? DockDesign.hover : Color.clear, in: RoundedRectangle(cornerRadius: DockDesign.Radius.group))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .task { items = preset.resolve().items }
    }
}
