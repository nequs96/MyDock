import AppKit
import SwiftUI

/// Gallery metrics: one radius family and the type scale used by every gallery surface.
enum WidgetGalleryMetrics {
    static let tileRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    static let panelRadius: CGFloat = 30
    /// Padding between a tile's backdrop edge and its illustration; captions start at the same inset.
    static let tileInset: CGFloat = 18
    static let gridSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 30
    static let pageInset: CGFloat = 24
    static let controlHeight: CGFloat = 34
    static let sectionTitle = Font.system(size: 15, weight: .semibold)
    static let tileTitle = Font.system(size: 13, weight: .medium)
    static let tileDetail = Font.system(size: 12)
    static let searchMaximumWidth: CGFloat = 420

    /// The search highlight of a tile or row: one accent wash for every gallery surface.
    static func highlightFill(_ scheme: ColorScheme) -> Color {
        DockDesign.accent.opacity(scheme == .dark ? 0.20 : 0.12)
    }
}

/// Spoken feedback for changes VoiceOver cannot see, such as the highlight moving while focus
/// stays in a search field, or an add that changes nothing on screen.
@MainActor
enum GalleryAnnouncement {
    static func post(_ message: String) {
        guard !message.isEmpty, let app = NSApp else { return }
        let element: Any
        if let window = app.keyWindow ?? app.mainWindow { element = window } else { element = app }
        NSAccessibility.post(element: element, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// The centred search pill. The AppKit field keeps arrow, Return and Escape routing.
struct GallerySearchPill: View {
    var placeholder: String
    @Binding var text: String
    var move: (Int) -> Void = { _ in }
    var choose: () -> Void = {}
    var cancel: () -> Void = {}
    var focusOnAppear = true
    var tab: (() -> Bool)? = nil
    var didBeginEditing: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            LibrarySearchField(placeholder: placeholder, text: $text, move: move, choose: choose, cancel: cancel,
                               compact: false, fontSize: 14, focusOnAppear: focusOnAppear, tab: tab,
                               didBeginEditing: didBeginEditing)
                .frame(height: 20)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 13).padding(.trailing, 9)
        .frame(height: WidgetGalleryMetrics.controlHeight)
        .dockGlass(.regular, in: Capsule())
    }
}

/// A Control Center–style segmented control: glass capsule track, a selected capsule that
/// slides between segments (instantly under Reduce Motion), and ⌘1… shortcuts.
struct GallerySegmentedControl<Value: Hashable>: View {
    var items: [(value: Value, title: String)]
    @Binding var selection: Value
    var accessibilityLabel: String
    var minimumSegmentWidth: CGFloat = 78
    var keyboardShortcuts = true
    @Namespace private var namespace
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                segment(item.value, title: item.title, index: index)
            }
        }
        .padding(3)
        .dockGlass(.regular, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private func segment(_ value: Value, title: String, index: Int) -> some View {
        let selected = value == selection
        let button = Button {
            guard value != selection else { return }
            DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: accessibility.reduceMotion) { selection = value }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color.primary : Color.primary.opacity(0.68))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(minWidth: minimumSegmentWidth, minHeight: 28)
                .background {
                    if selected {
                        Capsule()
                            .fill(selectedFill)
                            .shadow(color: .black.opacity(scheme == .dark || accessibility.reduceTransparency ? 0 : 0.10), radius: 3, y: 1)
                            .overlay {
                                if accessibility.contrast == .increased {
                                    Capsule().dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                                }
                            }
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        if keyboardShortcuts && index < 9 {
            button.keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        } else {
            button
        }
    }

    private var selectedFill: Color {
        if accessibility.reduceTransparency { return scheme == .dark ? Color(white: 0.30) : .white }
        return scheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.92)
    }
}

/// Small glass header buttons: Done, Back and the capability filter.
struct GalleryGlassButtonStyle: ButtonStyle {
    var circular = false
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, circular: circular)
    }
    private struct GlassButtonBody: View {
        let configuration: ButtonStyle.Configuration
        var circular: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, circular ? 0 : 14)
                .frame(minWidth: WidgetGalleryMetrics.controlHeight, minHeight: WidgetGalleryMetrics.controlHeight)
                .contentShape(Capsule())
                .dockGlass(.regular, in: Capsule(), interactive: true)
                .overlay(Capsule().fill(configuration.isPressed ? DockDesign.selection : hovered ? DockDesign.hover : Color.clear).allowsHitTesting(false))
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }
    }
}

/// The soft surface behind gallery previews: glass on macOS 26, the material fallback before,
/// opaque under Reduce Transparency, with a visible edge under Increase Contrast.
struct GalleryBackdrop: ViewModifier {
    var radius: CGFloat
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .dockGlass(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                        .strokeBorder(DockDesign.accent, lineWidth: 2.5)
                        .padding(-4)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    /// Reports the viewport's width minus the page insets. Measured outside the content so
    /// fixed-width tiles can never widen what they are sized from.
    func galleryContentWidth(_ width: Binding<CGFloat>) -> some View {
        background {
            GeometryReader { proxy in
                let inner = max(200, proxy.size.width - 2 * WidgetGalleryMetrics.pageInset)
                Color.clear
                    .onAppear { width.wrappedValue = inner }
                    .onChange(of: inner) { width.wrappedValue = $0 }
            }
        }
    }

    func galleryBackdrop(radius: CGFloat = WidgetGalleryMetrics.tileRadius, highlighted: Bool = false) -> some View {
        modifier(GalleryBackdrop(radius: radius, highlighted: highlighted))
    }

    /// The area behind a widget tile's floating preview: nothing at rest, a soft highlight on
    /// hover, an accent wash for the search highlight and a focus ring for keyboard focus.
    func galleryTileBackdrop(radius: CGFloat, hovered: Bool, selected: Bool, focused: Bool) -> some View {
        modifier(GalleryTileBackdrop(radius: radius, hovered: hovered, selected: selected, focused: focused))
    }

    /// Makes a gallery tile keyboard-focusable. On macOS 14 and later the system focus effect
    /// is replaced by the tile's own ring (`galleryTileBackdrop`), which follows the tile shape.
    @ViewBuilder func galleryFocusable(_ enabled: Bool = true) -> some View {
        if #available(macOS 14.0, *) {
            focusable(enabled).focusEffectDisabled()
        } else {
            focusable(enabled)
        }
    }
}

/// No tile, no stroke: the live preview floats on the page like the iOS widget gallery, so
/// only the module's own radius shows. States stay visible without a nested frame. Increase
/// Contrast keeps a visible edge around the tile area.
struct GalleryTileBackdrop: ViewModifier {
    var radius: CGFloat
    var hovered: Bool
    var selected: Bool
    var focused: Bool
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    private var fill: Color {
        if selected { return WidgetGalleryMetrics.highlightFill(scheme) }
        if hovered { return DockDesign.hover }
        return .clear
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(fill)
                    .animation(accessibility.animation(DockDesign.Motion.hover), value: hovered)
            }
            .overlay {
                // Under Increase Contrast the module draws its own edge; the tile adds one only for state.
                if accessibility.contrast == .increased, selected || hovered {
                    shape.dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                } else if selected {
                    shape.dockInnerEdge(DockDesign.accent.opacity(0.55), lineWidth: 1)
                }
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                        .strokeBorder(DockDesign.accent, lineWidth: 3)
                        .padding(-4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// The added state of an app row: a plain check with no circle, deliberately unlike the filled
/// accent plus. It uses the accent, the same colour as the widgets' added badge, so "Added" reads
/// the same in every segment.
struct GalleryAddedCheck: View {
    var generation: Int = 0
    @DockAccessibilityStyle() private var accessibility
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: WidgetGalleryRowAccessory.added.symbol)
            .font(.system(size: 14, weight: accessibility.contrast == .increased ? .bold : .semibold))
            .foregroundStyle(DockDesign.accent)
            .frame(width: 22, height: 22)
            .scaleEffect(scale)
            .accessibilityHidden(true)
            .onChange(of: generation) { _ in
                guard !accessibility.reduceMotion else { return }
                scale = 1.28
                withAnimation(DockDesign.Motion.appear) { scale = 1 }
            }
    }
}

/// The check badge of an added item. Each add bumps `generation`, which springs the badge
/// (instantly under Reduce Motion).
struct GalleryAddedBadge: View {
    var generation: Int = 0
    var size: CGFloat = 22
    /// Spoken when the badge stands alone; `nil` when the owner's label already says "Added".
    var spokenLabel: String? = nil
    @DockAccessibilityStyle() private var accessibility
    @State private var scale: CGFloat = 1

    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.48, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(DockDesign.accent))
            .overlay {
                if accessibility.contrast == .increased {
                    Circle().dockInnerEdge(Color.white.opacity(0.9), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(accessibility.reduceTransparency ? 0 : 0.18), radius: 2, y: 1)
            .scaleEffect(scale)
            .accessibilityLabel(spokenLabel ?? "")
            .accessibilityHidden(spokenLabel == nil)
            .onChange(of: generation) { _ in
                guard !accessibility.reduceMotion else { return }
                scale = 1.28
                withAnimation(DockDesign.Motion.appear) { scale = 1 }
            }
    }
}

/// Section heading in the gallery's type scale.
struct GallerySectionTitle: View {
    var title: String
    var body: some View {
        Text(title)
            .font(WidgetGalleryMetrics.sectionTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Short empty state: one glyph, one title, one line, optional actions.
struct GalleryEmptyState<Actions: View>: View {
    var title: String
    var detail: String
    var symbol = "magnifyingglass"
    /// Smaller glyph and padding for empty states inside a fixed-height area.
    var compact = false
    @ViewBuilder var actions: Actions
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: compact ? 24 : 30, weight: .light)).foregroundStyle(.tertiary)
                .padding(.bottom, 4).accessibilityHidden(true)
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions.padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, compact ? 12 : 64)
        .accessibilityElement(children: .contain)
    }
}

extension GalleryEmptyState where Actions == EmptyView {
    /// Empty state without an action.
    init(title: String, detail: String, symbol: String = "magnifyingglass", compact: Bool = false) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.compact = compact
        self.actions = EmptyView()
    }
}
