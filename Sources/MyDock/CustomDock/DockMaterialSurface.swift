import SwiftUI

/// Shared by the live panel and editor so material, tint, and accessibility
/// preferences always describe the Dock the user will actually activate.
struct DockMaterialSurface: View {
    let settings: AppSettings
    let color: Color
    @DockAccessibilityStyle() private var accessibility
    private var reduceTransparency: Bool { accessibility.reduceTransparency }
    private var contrast: ColorSchemeContrast { accessibility.contrast }
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: CGFloat(settings.customDockCornerRadius), style: .continuous) }
    var body: some View {
        ZStack {
            if !reduceTransparency && [.liquidGlass, .liquidGlassClear].contains(settings.customDockMaterial) {
                shape.fill(Color(nsColor: .windowBackgroundColor).opacity(settings.customDockGlassOpacity))
            }
            surface
            if !reduceTransparency { shape.fill(color.opacity(settings.customDockTintStrength)) }
        }
        // Glass owns its edge lighting. Keep its backing layers inside the
        // surface rather than casting a shadow from the rectangular host.
        .clipShape(shape)
        .overlay(shape.strokeBorder(DockDesign.Outline.color(contrast), lineWidth: DockDesign.Outline.dockWidth(contrast)))
        .environment(\.colorScheme, settings.customDockTheme == .dark ? .dark : settings.customDockTheme == .light ? .light : settings.customDockMaterial == .dark ? .dark : systemAppearance.scheme)
    }
    @ViewBuilder private var surface: some View {
        if reduceTransparency { shape.fill(Color(nsColor: .windowBackgroundColor)) }
        else {
            switch settings.customDockMaterial {
            case .solid: shape.fill(Color(nsColor: .windowBackgroundColor))
            case .frosted: shape.fill(.ultraThinMaterial)
            case .dark: shape.fill(Color(red: 0.10, green: 0.12, blue: 0.16))
            case .liquidGlass:
                if #available(macOS 26.0, *) { shape.fill(.clear).glassEffect(.regular, in: shape) }
                else { shape.fill(.ultraThinMaterial) }
            case .liquidGlassClear:
                if #available(macOS 26.0, *) { shape.fill(.clear).glassEffect(.clear, in: shape) }
                else { shape.fill(.ultraThinMaterial) }
            }
        }
    }
}
