import AppKit
import SwiftUI

/// The hover window preview panel: one glass module anchored to a running app tile.
/// Thumbnails with Screen Recording, a titles-only list without it, and single explanatory
/// rows for missing access. Sizes come from `WindowPreviewPanelLayout`.
struct WindowPreviewPanelView: View {
    @ObservedObject var model: DockWindowPreviewModel

    private typealias Layout = WindowPreviewPanelLayout

    var body: some View {
        let presentation = model.presentation
        GlassModule(width: model.panelSize.width, height: model.panelSize.height,
                    radius: Layout.radius, hoverEffect: false) {
            VStack(alignment: .leading, spacing: Layout.spacing) {
                header
                content(presentation)
            }
            .padding(Layout.padding)
            .frame(width: model.panelSize.width, height: model.panelSize.height, alignment: .topLeading)
        }
        // Content opens from 96% with a fade; Reduce Motion keeps it still (the window only fades).
        .modifier(DockPopoutAppearEffect(anchor: appearAnchor))
        .id(model.appearanceID)
        .environment(\.colorScheme, model.colorScheme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(model.applicationName) windows")
    }

    private var appearAnchor: UnitPoint {
        switch model.position {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let icon = model.applicationIcon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            Text(model.applicationName)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(height: Layout.headerHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func content(_ presentation: WindowPreviewPresentation) -> some View {
        switch presentation.body {
        case .loading:
            HStack {
                ProgressView().controlSize(.small)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            .frame(height: Layout.noticeHeight)
            .accessibilityLabel("Loading windows")
        case .accessibilityRequired:
            GroupedRow("Window access needs Accessibility.", accessory: {
                Button("Allow…") { model.grantAccessibility() }
                    .controlSize(.small)
                    .help("Allow MyDock under Privacy & Security → Accessibility.")
            })
            .frame(height: Layout.noticeHeight)
        case .unavailable:
            notice("Windows unavailable")
        case .empty:
            notice("No open windows")
        case .thumbnails:
            thumbnailStrip
        case .titles:
            VStack(alignment: .leading, spacing: Layout.spacing) {
                DockScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Indices: window identities can repeat when an app reuses accessibility identifiers.
                        ForEach(model.windows.indices, id: \.self) { index in
                            let window = model.windows[index]
                            WindowPreviewTitleRow(window: window, icon: model.applicationIcon,
                                                  activate: { model.activate(window) },
                                                  close: { model.close(window) })
                        }
                    }
                }
                .frame(height: CGFloat(min(max(model.windows.count, 1), Layout.maximumVisibleRows)) * Layout.rowHeight)
                if presentation.offersThumbnails {
                    GroupedRow("Show thumbnails…", subtitle: "Needs Screen Recording access.", chevron: true,
                               action: { model.showThumbnailsHelp() })
                    .frame(height: Layout.noticeHeight)
                }
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(DockDesign.Grouped.titleFont)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DockDesign.Grouped.rowHorizontalPadding)
            .frame(maxWidth: .infinity, minHeight: Layout.noticeHeight, maxHeight: Layout.noticeHeight, alignment: .leading)
    }

    @ViewBuilder private var thumbnailStrip: some View {
        let strip = Layout.usesStrip(position: model.position)
        DockScrollView(strip ? .horizontal : .vertical, showsIndicators: false) {
            if strip {
                HStack(spacing: Layout.spacing) { cards }
            } else {
                VStack(spacing: Layout.spacing) { cards }
            }
        }
    }

    private var cards: some View {
        ForEach(model.windows.indices, id: \.self) { index in
            let window = model.windows[index]
            WindowPreviewCard(window: window, thumbnail: model.thumbnails[window.id], icon: model.applicationIcon,
                              activate: { model.activate(window) },
                              close: { model.close(window) })
        }
    }
}

/// One window as a thumbnail card. Hover shows a close button; minimized windows are dimmed
/// and labelled.
private struct WindowPreviewCard: View {
    var window: DockWindowDescriptor
    var thumbnail: NSImage?
    var icon: NSImage?
    var activate: @MainActor () -> Void
    var close: @MainActor () -> Void
    @State private var hovered = false
    @DockAccessibilityStyle() private var accessibility

    private typealias Layout = WindowPreviewPanelLayout
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DockDesign.Radius.row, style: .continuous) }

    var body: some View {
        Button { activate() } label: {
            VStack(alignment: .leading, spacing: Layout.cardTitleSpacing) {
                ZStack {
                    shape.fill(DockDesign.hover)
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: DockDesign.Radius.control, style: .continuous))
                            .padding(4)
                    } else if let icon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 40, height: 40)
                    }
                }
                .frame(width: Layout.thumbnailSize.width, height: Layout.thumbnailSize.height)
                .opacity(window.isMinimized ? 0.55 : 1)
                .overlay(alignment: .bottomLeading) {
                    if window.isMinimized { WindowPreviewMinimizedLabel().padding(6) }
                }
                Text(window.title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: Layout.cardTitleHeight)
            }
            .frame(width: Layout.cardSize.width, height: Layout.cardSize.height)
            .background(hovered ? DockDesign.selection : Color.clear, in: shape)
            .overlay {
                if hovered && accessibility.contrast == .increased {
                    shape.dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovered { WindowPreviewCloseButton(title: window.title, action: close).padding(6) }
        }
        .onHover { hovered = $0 }
        .help(window.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.isMinimized ? "\(window.title), minimized" : window.title)
        .accessibilityHint(window.isMinimized ? "Restores this window." : "Brings this window to the front.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate() }
        .accessibilityAction(named: "Close Window") { close() }
    }
}

/// One window as a titles-only row: app icon and title; hover shows a close button.
private struct WindowPreviewTitleRow: View {
    var window: DockWindowDescriptor
    var icon: NSImage?
    var activate: @MainActor () -> Void
    var close: @MainActor () -> Void
    @State private var hovered = false
    @DockAccessibilityStyle() private var accessibility

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DockDesign.Radius.row, style: .continuous) }

    var body: some View {
        HStack(spacing: 4) {
            Button { activate() } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                            .opacity(window.isMinimized ? 0.55 : 1)
                    }
                    Text(window.title)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    if window.isMinimized && !hovered { WindowPreviewMinimizedLabel() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if hovered { WindowPreviewCloseButton(title: window.title, action: close) }
        }
        .padding(.horizontal, 8)
        .frame(height: WindowPreviewPanelLayout.rowHeight)
        .background(hovered ? DockDesign.selection : Color.clear, in: shape)
        .overlay {
            if hovered && accessibility.contrast == .increased {
                shape.dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
            }
        }
        .onHover { hovered = $0 }
        .help(window.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(window.isMinimized ? "\(window.title), minimized" : window.title)
        .accessibilityHint(window.isMinimized ? "Restores this window." : "Brings this window to the front.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { activate() }
        .accessibilityAction(named: "Close Window") { close() }
    }
}

/// "Minimized": a quiet secondary label, no colour.
private struct WindowPreviewMinimizedLabel: View {
    var body: some View {
        Label("Minimized", systemImage: "minus.circle")
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.regularMaterial, in: Capsule())
            .accessibilityHidden(true)
    }
}

private struct WindowPreviewCloseButton: View {
    var title: String
    var action: @MainActor () -> Void
    var body: some View {
        Button { action() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close Window")
        .accessibilityLabel("Close \(title)")
    }
}
