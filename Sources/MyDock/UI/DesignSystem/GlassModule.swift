import SwiftUI

/// The Control Center module: a continuous rounded rectangle of `DockDesign.Glass`.
///
/// The caller owns geometry. Pass the width and height you already use (a Dock widget
/// stays 54 pt × Dock size tall); nil leaves that axis to the content. The module never
/// pads or resizes its content; use `DockDesign.Module.insets` inside if you need them.
struct GlassModule<Content: View>: View {
    var width: CGFloat?
    var height: CGFloat?
    var radius: CGFloat
    var style: DockDesign.Glass.Style
    var tint: Color?
    var interactive: Bool
    var hoverEffect: Bool
    var content: Content
    @State private var hovered = false

    init(width: CGFloat? = nil, height: CGFloat? = nil, radius: CGFloat = DockDesign.Module.defaultRadius,
         style: DockDesign.Glass.Style = .regular, tint: Color? = nil, interactive: Bool = false,
         hoverEffect: Bool = true, @ViewBuilder content: () -> Content) {
        self.width = width
        self.height = height
        self.radius = max(0, radius)
        self.style = style
        self.tint = tint
        self.interactive = interactive
        self.hoverEffect = hoverEffect
        self.content = content()
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    var body: some View {
        content
            .frame(width: width, height: height)
            .clipShape(shape)
            .contentShape(shape)
            .dockGlass(style, in: shape, tint: tint, interactive: interactive)
            .dockHover(hoverEffect && hovered)
            .onHover { hovered = $0 }
    }
}

/// The module grammar: one glyph or value, one short label, optionally one secondary line.
/// Faces may compose their own layouts; this is the default arrangement.
struct ModuleValueLabel: View {
    var value: String
    var label: String?
    var symbol: String?
    var size: DockDesign.Module.ValueSize = .large
    var valueColor: Color = .primary
    var body: some View {
        VStack(alignment: .leading, spacing: DockDesign.Module.lineSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: DockDesign.Module.pointSize(size) * 0.72, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(value).font(DockDesign.Module.value(size)).foregroundStyle(valueColor)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if let label {
                Text(label).font(DockDesign.Module.label).foregroundStyle(.secondary)
                    .lineLimit(DockDesign.Module.maxTextLines)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
