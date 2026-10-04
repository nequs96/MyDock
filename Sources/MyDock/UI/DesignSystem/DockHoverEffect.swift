import SwiftUI

extension View {
    /// Shared hover response: a ≈3% lift and a slight brightening on a spring.
    /// Under Reduce Motion the lift is dropped and the brightening is instant.
    func dockHover(_ isHovered: Bool) -> some View {
        modifier(DockHoverEffect(isHovered: isHovered))
    }
}

struct DockHoverEffect: ViewModifier {
    var isHovered: Bool
    @DockAccessibilityStyle() private var accessibility
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let reduceMotion = accessibility.reduceMotion
        // Brightening a dark surface reads as a lift; on light surfaces it would wash out, so stay subtler.
        let brightness = isHovered ? DockDesign.Motion.hoverBrightness * (scheme == .dark ? 1 : 0.6) : 0
        content
            .scaleEffect(isHovered && !reduceMotion ? DockDesign.Motion.hoverScale : 1)
            .brightness(brightness)
            .animation(DockDesign.Motion.animation(DockDesign.Motion.hover, reduceMotion: reduceMotion), value: isHovered)
    }
}
