import SwiftUI

/// The in-place detail of one family: a big live preview in a size pager, one line of
/// description, the capability note and an Add Widget pill. Return adds; Escape (Back) returns.
struct WidgetGalleryDetail: View {
    var widget: WidgetDefinition
    @Binding var layout: WidgetLayout
    var added: Bool
    var canAdd: Bool
    var addGeneration: Int
    var add: () -> Void

    @DockAccessibilityStyle() private var accessibility
    @State private var panelWidth: CGFloat = 520

    private var options: [WidgetLayoutOption] { WidgetGalleryModel.layoutOptions(for: widget.name) }
    private var option: WidgetLayoutOption { options.first { $0.layout == layout } ?? options[0] }
    /// The tallest scale that keeps the widest page inside the pager.
    private var previewScale: CGFloat {
        let widest = CGFloat(options.map(\.width).max() ?? 120)
        let pageWidth = max(160, panelWidth - 2 * 22 - 2 * 34)
        return max(1, min(2.3, pageWidth / widest))
    }
    private var setupNote: String {
        let capabilities = widget.capabilities
        var parts: [String] = []
        if capabilities.needsConnection { parts.append("Needs an account connection.") }
        if capabilities.refreshDemand == .remoteFetch { parts.append("Reads online data.") }
        return parts.joined(separator: " ")
    }
    private var note: String {
        [setupNote, widget.capabilities.accessNote ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 5) {
                Text(widget.name).font(.system(size: 22, weight: .semibold))
                Text(widget.description)
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .multilineTextAlignment(.center)
            .padding(.bottom, 22)

            SizePager(options.map(\.layout), selection: $layout, accessibilityLabel: "\(widget.name) size",
                      caption: { selected in options.first { $0.layout == selected }?.title ?? selected.title }) { page in
                WidgetCardPreview(kind: widget.name, width: CGFloat(options.first { $0.layout == page }?.width ?? 120),
                                  displayScale: previewScale, layout: page)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .frame(height: 54 * previewScale + 8)
            }
            .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .galleryBackdrop(radius: WidgetGalleryMetrics.panelRadius)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { panelWidth = proxy.size.width }
                        .onChange(of: proxy.size.width) { panelWidth = $0 }
                }
            }

            Text(option.detail)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.top, 12)
                .animation(nil, value: layout)

            if !note.isEmpty {
                Label {
                    Text(note).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "hand.raised").accessibilityHidden(true)
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 420)
                .padding(.top, 14)
            }

            HStack(spacing: 10) {
                PillButton("Add Widget", systemImage: "plus", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
                if added {
                    GalleryAddedBadge(generation: addGeneration, size: 22)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            .padding(.top, 22)
            .accessibilityElement(children: .contain)

            Text(!canAdd ? "Choose a Dock to add widgets." : added ? "In this Dock. Adding again creates another with its own settings." : " ")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .padding(.top, 8)
                .accessibilityHidden(canAdd && !added)
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, WidgetGalleryMetrics.pageInset)
        .padding(.top, 8).padding(.bottom, 28)
        .frame(maxWidth: .infinity)
    }
}

/// Moves the detail pager with the arrow keys when no field has focus.
struct GalleryPagerKeys: View {
    var step: (Int) -> Void
    var body: some View {
        ZStack {
            Button("") { step(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { step(1) }.keyboardShortcut(.rightArrow, modifiers: [])
        }
        .buttonStyle(.plain)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
