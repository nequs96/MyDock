import SwiftUI

/// The prominent capsule action ("Add Widget"). Native `.glassProminent` on macOS 26,
/// a filled accent capsule elsewhere and under Reduce Transparency. Callers add
/// `.keyboardShortcut(...)`, `.disabled(...)` and `.tint(...)` as with any button.
struct PillButton: View {
    var title: String
    var systemImage: String?
    var action: () -> Void
    @DockAccessibilityStyle() private var accessibility
    #if DEBUG
    @Environment(\.dockSnapshotRendering) private var snapshotRendering
    #else
    private let snapshotRendering = false
    #endif

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        if !accessibility.reduceTransparency, !snapshotRendering, #available(macOS 26.0, *) {
            button
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        } else {
            button.buttonStyle(PillButtonFallbackStyle())
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(DockDesign.sectionTitle).accessibilityHidden(true)
                }
                Text(title).font(DockDesign.sectionTitle).lineLimit(1)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityLabel(title)
    }
}

struct PillButtonFallbackStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PillButtonFallbackBody(configuration: configuration)
    }
    private struct PillButtonFallbackBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @DockAccessibilityStyle() private var accessibility
        @State private var hovered = false
        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(Capsule().fill(.tint))
                .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.18 : 0)))
                .overlay(Capsule().fill(Color.white.opacity(hovered && !configuration.isPressed ? 0.08 : 0)))
                .overlay {
                    if accessibility.contrast == .increased {
                        Capsule().dockInnerEdge(DockDesign.Outline.color(.increased), lineWidth: DockDesign.Outline.controlWidth(.increased))
                    }
                }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { hovered = $0 }
        }
    }
}
