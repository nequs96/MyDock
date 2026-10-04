import SwiftUI

extension View {
    /// The one glass surface of the redesign.
    ///
    /// - macOS 26: native Liquid Glass (`.clear` or `.regular`), optionally tinted and interactive.
    /// - Earlier systems: `.ultraThinMaterial` in the shape with a quiet hairline.
    /// - Reduce Transparency: an opaque fill (the values WidgetContainer uses).
    /// - Increase Contrast: a visible `DockDesign.Outline` edge on every path.
    func dockGlass<S: Shape>(_ style: DockDesign.Glass.Style = .regular, in shape: S,
                                       tint: Color? = nil, interactive: Bool = false) -> some View {
        modifier(DockGlassModifier(style: style, shape: shape, tint: tint, interactive: interactive))
    }
}

struct DockGlassModifier<S: Shape>: ViewModifier {
    var style: DockDesign.Glass.Style
    var shape: S
    var tint: Color?
    var interactive: Bool
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme
    #if DEBUG
    /// Offscreen bitmap captures cannot see the glass compositor; exports draw the fallback.
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private let snapshotRendering = false
    #endif

    func body(content: Content) -> some View {
        surface(content)
            .overlay {
                if let edge { shape.dockInnerEdge(edge.color, lineWidth: edge.width) }
            }
    }

    /// Native glass lights its own edge. Fallbacks get one hairline; Increase Contrast always gets a visible edge.
    private var edge: (color: Color, width: CGFloat)? {
        let contrast = accessibility.contrast
        if contrast == .increased { return (DockDesign.Outline.color(contrast), DockDesign.Outline.controlWidth(contrast)) }
        if usesNativeGlass { return nil }
        return (DockDesign.Outline.color(contrast), DockDesign.Outline.controlWidth(contrast))
    }

    private var usesNativeGlass: Bool {
        guard !accessibility.reduceTransparency, !snapshotRendering else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }

    @ViewBuilder private func surface(_ content: Content) -> some View {
        if accessibility.reduceTransparency {
            content.background {
                ZStack {
                    shape.fill(DockDesign.Glass.opaqueFill(scheme))
                    if let tint { shape.fill(tint.opacity(DockDesign.Glass.fallbackTintOpacity)) }
                }
            }
        } else if usesNativeGlass, #available(macOS 26.0, *) {
            content.glassEffect(nativeGlass, in: shape)
        } else {
            content.background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(DockDesign.Glass.fallbackTintOpacity)) }
                }
            }
        }
    }

    @available(macOS 26.0, *)
    private var nativeGlass: SwiftUI.Glass {
        var glass: SwiftUI.Glass = style == .clear ? .clear : .regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// Groups glass surfaces so they blend and morph together on macOS 26.
/// Earlier systems lay the content out unchanged.
struct DockGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content
    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension Shape {
    /// An edge drawn inside the shape. Equivalent to `strokeBorder`, but built from the
    /// shape's own path so capsules keep a clean outline (an inset Capsule draws stray
    /// straight segments at its ends in offscreen renders).
    func dockInnerEdge(_ color: Color, lineWidth: CGFloat) -> some View {
        stroke(color, lineWidth: lineWidth * 2).clipShape(self).allowsHitTesting(false)
    }
}
