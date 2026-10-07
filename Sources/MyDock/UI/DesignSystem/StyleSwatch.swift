import SwiftUI

/// A selectable style card: a mini Dock over a sample wallpaper, a title underneath and an
/// accent ring when selected. It is a button with the `isSelected` trait.
struct StyleSwatch<Preview: View>: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    var preview: Preview
    @State private var hovered = false
    @DockAccessibilityStyle() private var accessibility

    static var cardSize: CGSize { CGSize(width: 116, height: 76) }
    static var cardRadius: CGFloat { 12 }

    init(_ title: String, isSelected: Bool, action: @escaping () -> Void, @ViewBuilder preview: () -> Preview) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.preview = preview()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                preview
                    .frame(width: Self.cardSize.width, height: Self.cardSize.height)
                    .clipShape(shape)
                    .overlay {
                        // Cards need an edge on light pages; under Increase Contrast it becomes clearly visible.
                        shape.strokeBorder(DockDesign.Outline.color(accessibility.contrast), lineWidth: DockDesign.Outline.controlWidth(accessibility.contrast))
                    }
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cardRadius + 3, style: .continuous)
                            .strokeBorder(DockDesign.accent, lineWidth: 2.5)
                            .opacity(isSelected ? 1 : 0)
                    }
                    .dockHover(hovered && !isSelected)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension StyleSwatch where Preview == DockSwatchPreview {
    /// A swatch drawn from a simple description of the Dock look.
    init(_ title: String, look: DockSwatchLook, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title, isSelected: isSelected, action: action) { DockSwatchPreview(look: look) }
    }
}

/// Describes a Dock look in miniature, independent of the persisted settings model.
struct DockSwatchLook: Hashable {
    enum Surface: Hashable, CaseIterable { case clearGlass, glass, frosted, solid, midnight }
    enum ModuleSurface: Hashable, CaseIterable { case glass, plain, tile }
    var surface: Surface
    var showsEdge: Bool = true
    var moduleSurface: ModuleSurface = .tile
    var iconCount: Int = 3
    var moduleCount: Int = 1
    var tint: Color? = nil
}

/// Mini Dock: a few dummy icons and modules on the described surface, over a sample wallpaper.
/// The wallpaper follows the window like the Settings hero's; the Dock follows the same scheme
/// source as the real Dock (`DockColorSchemePolicy`): the Dock theme, then the system appearance.
struct DockSwatchPreview: View {
    var look: DockSwatchLook
    @Environment(\.dockSwatchTheme) private var theme
    @ObservedObject private var systemAppearance = DockSystemAppearance.shared
    @DockAccessibilityStyle() private var accessibility

    private static let iconColors: [Color] = [
        Color(red: 0.29, green: 0.56, blue: 0.95), Color(red: 0.96, green: 0.62, blue: 0.24),
        Color(red: 0.36, green: 0.75, blue: 0.47), Color(red: 0.86, green: 0.38, blue: 0.48),
        Color(red: 0.58, green: 0.45, blue: 0.86)
    ]
    private let dockShape = RoundedRectangle(cornerRadius: 9, style: .continuous)

    var body: some View {
        ZStack(alignment: .bottom) {
            SwatchWallpaper()
            dock.padding(.bottom, 8)
        }
    }

    /// The scheme the real Dock would use for this look.
    private var dockScheme: ColorScheme {
        DockColorSchemePolicy.scheme(theme: theme, material: look.surface == .midnight ? .dark : .liquidGlass,
                                     system: systemAppearance.scheme)
    }
    private var darkSurface: Bool { look.surface == .midnight || dockScheme == .dark }

    private var dock: some View {
        HStack(spacing: 3.5) {
            ForEach(0..<max(0, min(look.iconCount, 5)), id: \.self) { index in
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Self.iconColors[index % Self.iconColors.count].gradient)
                    .frame(width: 14, height: 14)
            }
            ForEach(0..<max(0, min(look.moduleCount, 2)), id: \.self) { _ in module }
        }
        .padding(4)
        .background { surface }
        .overlay {
            if look.showsEdge || accessibility.contrast == .increased {
                dockShape.strokeBorder(edgeColor, lineWidth: accessibility.contrast == .increased ? 1 : 0.5)
            }
        }
        .environment(\.colorScheme, darkSurface ? .dark : .light)
    }

    private var edgeColor: Color {
        if accessibility.contrast == .increased { return DockDesign.Outline.color(.increased) }
        return darkSurface ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
    }

    @ViewBuilder private var surface: some View {
        if accessibility.reduceTransparency {
            dockShape.fill(look.surface == .midnight ? DockDesign.Glass.midnightFill : DockDesign.Glass.opaqueFill(darkSurface ? .dark : .light))
        } else {
            ZStack {
                switch look.surface {
                case .clearGlass:
                    // Clear glass in miniature: the wallpaper shows through, lit at the top edge.
                    dockShape.fill(Color.white.opacity(darkSurface ? 0.05 : 0.10))
                    glassHighlight
                case .glass:
                    dockShape.fill(.ultraThinMaterial)
                    dockShape.fill(Color.white.opacity(darkSurface ? 0.03 : 0.16))
                    glassHighlight
                case .frosted:
                    dockShape.fill(.regularMaterial)
                case .solid:
                    dockShape.fill(Color(nsColor: .windowBackgroundColor))
                case .midnight:
                    dockShape.fill(DockDesign.Glass.midnightFill)
                }
                if let tint = look.tint { dockShape.fill(tint.opacity(0.14)) }
            }
        }
    }

    /// Liquid Glass catches light along its upper edge.
    private var glassHighlight: some View {
        dockShape.strokeBorder(LinearGradient(colors: [Color.white.opacity(darkSurface ? 0.35 : 0.75), Color.white.opacity(0.0)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
    }

    @ViewBuilder private var module: some View {
        let shape = RoundedRectangle(cornerRadius: 4.5, style: .continuous)
        VStack(alignment: .leading, spacing: 1.5) {
            Capsule().fill(Color.primary.opacity(0.75)).frame(width: 12, height: 3)
            Capsule().fill(Color.primary.opacity(0.35)).frame(width: 18, height: 2)
        }
        .frame(width: 30, height: 14)
        .background {
            switch look.moduleSurface {
            case .plain: Color.clear
            case .glass: shape.fill(Color.white.opacity(darkSurface ? 0.10 : 0.35))
            case .tile: shape.fill(darkSurface ? Color.white.opacity(0.08) : Color.white.opacity(0.7))
            }
        }
    }
}

/// A calm sample wallpaper so swatches compare surfaces, not backgrounds.
struct SwatchWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            LinearGradient(colors: scheme == .dark
                           ? [Color(red: 0.11, green: 0.18, blue: 0.38), Color(red: 0.40, green: 0.19, blue: 0.31)]
                           : [Color(red: 0.40, green: 0.60, blue: 0.93), Color(red: 0.95, green: 0.63, blue: 0.50)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(scheme == .dark ? 0.10 : 0.28), .clear],
                           center: UnitPoint(x: 0.22, y: 0.18), startRadius: 0, endRadius: 70)
        }
        .accessibilityHidden(true)
    }
}

private struct DockSwatchThemeKey: EnvironmentKey { static let defaultValue: CustomDockTheme = .system }
extension EnvironmentValues {
    /// The Dock colour theme swatches preview in; `.system` follows the system appearance.
    var dockSwatchTheme: CustomDockTheme {
        get { self[DockSwatchThemeKey.self] }
        set { self[DockSwatchThemeKey.self] = newValue }
    }
}
