import SwiftUI

/// The layers a Dock surface draws. A layer exists only when it contributes, so the
/// Clear style (clear glass, no edge, no tint, no backing) is the native glass alone.
struct DockSurfaceLayers: Equatable {
    enum Base: Equatable { case opaque, solid, frosted, dark, glass(DockDesign.Glass.Style) }
    struct Edge: Equatable {
        var width: CGFloat
        var contrast: ColorSchemeContrast
    }
    var base: Base
    /// `windowBackgroundColor` behind glass at `customDockGlassOpacity`; nil when it would be invisible.
    var backingOpacity: Double?
    /// Profile-colour tint strength; nil when it would be invisible.
    var tintStrength: Double?
    /// The Dock outline; nil when the edge style and contrast draw none.
    var edge: Edge?

    var drawsOnlyNativeGlass: Bool {
        guard case .glass = base else { return false }
        return backingOpacity == nil && tintStrength == nil && edge == nil
    }

    /// `.auto` tints with the profile colour at `DockAppearanceBounds.autoTintStrength`;
    /// `.custom` uses `customDockTintStrength`.
    static func effectiveTintStrength(_ settings: AppSettings) -> Double {
        let strength = settings.customDockTintMode == .auto ? DockAppearanceBounds.autoTintStrength : settings.customDockTintStrength
        return strength.isFinite ? max(0, strength) : 0
    }

    /// Increase Contrast always shows an edge. Otherwise `.hairline` keeps the historical
    /// 1 pt outline, and `.contrastOnly` / `.none` draw nothing.
    static func edge(_ style: DockEdgeStyle, contrast: ColorSchemeContrast) -> Edge? {
        if contrast == .increased { return Edge(width: DockDesign.Outline.dockWidth(.increased), contrast: .increased) }
        switch style {
        case .hairline: return Edge(width: DockDesign.Outline.dockWidth(.standard), contrast: .standard)
        case .contrastOnly, .none: return nil
        }
    }

    static func resolve(_ settings: AppSettings, reduceTransparency: Bool, contrast: ColorSchemeContrast) -> DockSurfaceLayers {
        let edge = edge(settings.customDockEdgeStyle, contrast: contrast)
        // Reduce Transparency: one opaque surface, no translucent backing or tint.
        guard !reduceTransparency else { return DockSurfaceLayers(base: .opaque, edge: edge) }
        let base: Base
        switch settings.customDockMaterial {
        case .solid: base = .solid
        case .frosted: base = .frosted
        case .dark: base = .dark
        case .liquidGlass: base = .glass(.regular)
        case .liquidGlassClear: base = .glass(.clear)
        }
        var backing: Double?
        if case .glass = base, settings.customDockGlassOpacity.isFinite, settings.customDockGlassOpacity > 0 {
            backing = min(settings.customDockGlassOpacity, 1)
        }
        let tint = effectiveTintStrength(settings)
        return DockSurfaceLayers(base: base, backingOpacity: backing, tintStrength: tint > 0 ? tint : nil, edge: edge)
    }
}

/// Shared by the live panel and editor so material, tint, and accessibility
/// preferences always describe the Dock the user will actually activate.
struct DockMaterialSurface: View {
    let settings: AppSettings
    let color: Color
    @DockAccessibilityStyle() private var accessibility
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    #if DEBUG
    /// Offscreen bitmap captures cannot see the glass compositor; exports draw the fallback.
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private let snapshotRendering = false
    #endif
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: CGFloat(settings.customDockCornerRadius), style: .continuous) }

    var body: some View {
        let layers = DockSurfaceLayers.resolve(settings, reduceTransparency: accessibility.reduceTransparency,
                                               contrast: accessibility.contrast)
        ZStack {
            if let backing = layers.backingOpacity {
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(backing))
            }
            surface(layers.base)
            if let tint = layers.tintStrength { shape.fill(color.opacity(tint)) }
        }
        // Glass owns its edge lighting. Keep its backing layers inside the
        // surface rather than casting a shadow from the rectangular host.
        .clipShape(shape)
        .overlay {
            if let edge = layers.edge {
                shape.strokeBorder(DockDesign.Outline.color(edge.contrast), lineWidth: edge.width)
            }
        }
        .environment(\.colorScheme, DockColorSchemePolicy.scheme(theme: settings.customDockTheme, material: settings.customDockMaterial,
                                                                  system: systemAppearance.scheme))
    }

    @ViewBuilder private func surface(_ base: DockSurfaceLayers.Base) -> some View {
        switch base {
        case .opaque, .solid: shape.fill(Color(nsColor: .windowBackgroundColor))
        case .frosted: shape.fill(.ultraThinMaterial)
        case .dark: shape.fill(DockDesign.Glass.midnightFill)
        case .glass(let style):
            if !snapshotRendering, #available(macOS 26.0, *) {
                // The glass is the surface: nothing else is drawn for the Clear style.
                shape.fill(.clear).glassEffect(style == .clear ? .clear : .regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
    }
}
