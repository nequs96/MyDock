import AppKit
import SwiftUI
import Testing
@testable import MyDock

@MainActor
struct RedesignDockSurfaceTests {
    private func clearStyle() -> AppSettings {
        var settings = AppSettings()
        settings.customDockMaterial = .liquidGlassClear
        settings.customDockEdgeStyle = .none
        settings.customDockWidgetSurface = .plain
        settings.customDockTintMode = .custom
        settings.customDockTintStrength = 0
        settings.customDockGlassOpacity = 0
        return settings
    }

    // MARK: Surface layers

    @Test func clearStyleDrawsOnlyNativeClearGlass() {
        let layers = DockSurfaceLayers.resolve(clearStyle(), reduceTransparency: false, contrast: .standard)
        #expect(layers.base == .glass(.clear))
        #expect(layers.backingOpacity == nil)
        #expect(layers.tintStrength == nil)
        #expect(layers.edge == nil)
        #expect(layers.drawsOnlyNativeGlass)
    }

    @Test func eachLayerIsDrawnOnlyWhenItContributes() {
        var settings = clearStyle()
        settings.customDockGlassOpacity = 0.3
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).backingOpacity == 0.3)
        settings.customDockMaterial = .liquidGlass
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).backingOpacity == 0.3)
        // The backing only exists behind glass.
        for material in [CustomDockMaterial.frosted, .solid, .dark] {
            settings.customDockMaterial = material
            #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).backingOpacity == nil)
        }
        settings = clearStyle()
        settings.customDockTintStrength = 0.2
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).tintStrength == 0.2)
        settings.customDockTintStrength = .nan
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).tintStrength == nil)
    }

    @Test func autoTintUsesTheFixedProfileColourStrength() {
        var settings = clearStyle()
        settings.customDockTintMode = .auto
        #expect(DockSurfaceLayers.effectiveTintStrength(settings) == DockAppearanceBounds.autoTintStrength)
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).tintStrength == 0.06)
        settings.customDockTintStrength = 0.4
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).tintStrength == 0.06)
        settings.customDockTintMode = .custom
        #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard).tintStrength == 0.4)
    }

    @Test func edgeStylesAndIncreaseContrast() {
        let hairline = DockSurfaceLayers.Edge(width: DockDesign.Outline.dockWidth(.standard), contrast: .standard)
        let increased = DockSurfaceLayers.Edge(width: DockDesign.Outline.dockWidth(.increased), contrast: .increased)
        #expect(DockSurfaceLayers.edge(.hairline, contrast: .standard) == hairline)
        #expect(DockSurfaceLayers.edge(.contrastOnly, contrast: .standard) == nil)
        #expect(DockSurfaceLayers.edge(.none, contrast: .standard) == nil)
        // Increase Contrast always shows the edge, whatever the style.
        for style in DockEdgeStyle.allCases {
            #expect(DockSurfaceLayers.edge(style, contrast: .increased) == increased)
            var settings = clearStyle()
            settings.customDockEdgeStyle = style
            for transparency in [false, true] {
                #expect(DockSurfaceLayers.resolve(settings, reduceTransparency: transparency, contrast: .increased).edge == increased)
            }
        }
    }

    @Test func reduceTransparencyStaysOpaque() {
        for material in CustomDockMaterial.allCases {
            var settings = AppSettings()
            settings.customDockMaterial = material
            settings.customDockGlassOpacity = 0.5
            settings.customDockTintStrength = 0.3
            let layers = DockSurfaceLayers.resolve(settings, reduceTransparency: true, contrast: .standard)
            #expect(layers.base == .opaque)
            #expect(layers.backingOpacity == nil)
            #expect(layers.tintStrength == nil)
            #expect(!layers.drawsOnlyNativeGlass)
        }
    }

    @Test func oldProfilesRenderTheirHistoricalLayers() {
        // Pre-redesign appearance snapshots carry no edge, surface, inset or tint-mode keys.
        var appearance = ProfileAppearance(settings: AppSettings())
        appearance.edgeStyle = nil; appearance.widgetSurface = nil; appearance.floatingInset = nil; appearance.tintMode = nil
        for material in CustomDockMaterial.allCases {
            appearance.material = material
            let settings = appearance.applying(to: AppSettings())
            #expect(settings.customDockEdgeStyle == .hairline)
            #expect(settings.customDockTintStrength == 0.08)
            let layers = DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .standard)
            // Today: 1 pt standard outline, profile tint at 0.08, and a zero-opacity backing (invisible).
            #expect(layers.edge == DockSurfaceLayers.Edge(width: 1, contrast: .standard))
            #expect(layers.tintStrength == 0.08)
            #expect(layers.backingOpacity == nil)
            let contrast = DockSurfaceLayers.resolve(settings, reduceTransparency: false, contrast: .increased)
            #expect(contrast.edge == DockSurfaceLayers.Edge(width: 2, contrast: .increased))
        }
    }

    // MARK: Floating inset geometry

    private let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)

    /// The frame formula before the floating inset existed.
    private func legacyFrame(_ position: DockPosition, contentLength: CGFloat, cross: CGFloat, visible: NSRect) -> NSRect {
        let maxLength = position == .bottom ? visible.width - 40 : visible.height - 60
        let length = min(max(contentLength, 100), max(maxLength, 100))
        switch position {
        case .bottom: return NSRect(x: visible.midX - length / 2, y: visible.minY + 10, width: length, height: cross)
        case .left: return NSRect(x: visible.minX + 10, y: visible.midY - length / 2, width: cross, height: length)
        case .right: return NSRect(x: visible.maxX - cross - 10, y: visible.midY - length / 2, width: cross, height: length)
        }
    }

    @Test func zeroInsetKeepsTodaysFrame() {
        let areas = [visible, NSRect(x: -1920, y: 40, width: 1920, height: 1040), NSRect(x: 0, y: 0, width: 120, height: 90)]
        for area in areas {
            for position in [DockPosition.bottom, .left, .right] {
                let lengths: [CGFloat] = [40, 420, 5000]
                let crosses: [CGFloat] = [49.4, 76, 147]
                for length in lengths {
                    for cross in crosses {
                        #expect(DockPanelGeometry.frame(position: position, placementArea: area, contentLength: length,
                                                        crossLength: cross, floatingInset: 0)
                                == legacyFrame(position, contentLength: length, cross: cross, visible: area))
                    }
                }
            }
        }
    }

    @Test func insetMovesThePanelAwayFromItsEdge() {
        for inset in [1.0, 12, 24] {
            let base = { (position: DockPosition) in
                DockPanelGeometry.frame(position: position, placementArea: self.visible, contentLength: 600, crossLength: 76, floatingInset: 0)
            }
            let moved = { (position: DockPosition) in
                DockPanelGeometry.frame(position: position, placementArea: self.visible, contentLength: 600, crossLength: 76, floatingInset: inset)
            }
            #expect(moved(.bottom) == base(.bottom).offsetBy(dx: 0, dy: CGFloat(inset)))
            #expect(moved(.left) == base(.left).offsetBy(dx: CGFloat(inset), dy: 0))
            #expect(moved(.right) == base(.right).offsetBy(dx: -CGFloat(inset), dy: 0))
            for position in [DockPosition.bottom, .left, .right] { #expect(moved(position).size == base(position).size) }
        }
    }

    @Test func insetIsClamped() {
        #expect(DockPanelGeometry.floatingInset(-5) == 0)
        #expect(DockPanelGeometry.floatingInset(.nan) == 0)
        #expect(DockPanelGeometry.floatingInset(.infinity) == 0)
        #expect(DockPanelGeometry.floatingInset(100) == 24)
        #expect(DockPanelGeometry.floatingInset(13.5) == 13.5)
        for position in [DockPosition.bottom, .left, .right] {
            let maximum = DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 600, crossLength: 76, floatingInset: 24)
            #expect(DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 600, crossLength: 76, floatingInset: 300) == maximum)
            let zero = DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 600, crossLength: 76, floatingInset: 0)
            #expect(DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 600, crossLength: 76, floatingInset: -3) == zero)
            #expect(DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 600, crossLength: 76, floatingInset: .nan) == zero)
        }
    }

    @Test func revealStripStaysAtTheScreenEdge() {
        #expect(DockPanelGeometry.revealFrame(position: .bottom, placementArea: visible) == NSRect(x: 701, y: 1, width: 38, height: 6))
        #expect(DockPanelGeometry.revealFrame(position: .left, placementArea: visible) == NSRect(x: 1, y: 418.5, width: 6, height: 38))
        #expect(DockPanelGeometry.revealFrame(position: .right, placementArea: visible) == NSRect(x: 1433, y: 418.5, width: 6, height: 38))
        let dock = NSRect(x: 400, y: 10, width: 600, height: 76)
        #expect(DockPanelGeometry.hoverFrame(expanded: dock, position: .bottom, floatingInset: 0) == dock)
    }

    /// With any inset, a pointer at the very screen edge reaches the reveal strip, and the
    /// path from the edge into a visible Dock never crosses a gap that would hide it.
    @Test func pointerPathFromScreenEdgeToFloatingDockIsContinuous() {
        for inset in [0.0, 8, 16, 24] {
            for position in [DockPosition.bottom, .left, .right] {
                let dock = DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 600, crossLength: 76, floatingInset: inset)
                let reveal = DockPanelGeometry.revealFrame(position: position, placementArea: visible)
                let hover = DockPanelGeometry.hoverFrame(expanded: dock, position: position, floatingInset: inset)
                let steps = Int(DockPanelGeometry.edgeMargin + CGFloat(inset)) + 20
                for step in 0...steps {
                    let distance = CGFloat(step)
                    let point: NSPoint
                    switch position {
                    case .bottom: point = NSPoint(x: visible.midX, y: visible.minY + distance)
                    case .left: point = NSPoint(x: visible.minX + distance, y: visible.midY)
                    case .right: point = NSPoint(x: visible.maxX - distance, y: visible.midY)
                    }
                    if step == 0 {
                        #expect(CustomDockVisibilityPolicy.isAtRevealEdge(mouseLocation: point, revealFrame: reveal))
                    }
                    let keepsVisible = CustomDockVisibilityPolicy.shouldRevealImmediately(mouseLocation: point, expandedFrame: hover)
                        || CustomDockVisibilityPolicy.isAtRevealEdge(mouseLocation: point, revealFrame: reveal)
                    #expect(keepsVisible, "gap at \(distance) pt for \(position) inset \(inset)")
                }
            }
        }
    }

    // MARK: Presentation signature, module radius, indicators

    @Test func presentationSettingsTrackRedesignAppearance() {
        let base = DockPresentationSettings(AppSettings())
        let changes: [(inout AppSettings) -> Void] = [
            { $0.customDockEdgeStyle = .none }, { $0.customDockWidgetSurface = .glass },
            { $0.customDockFloatingInset = 12 }, { $0.customDockTintMode = .auto }]
        for change in changes {
            var settings = AppSettings()
            change(&settings)
            #expect(DockPresentationSettings(settings) != base)
        }
    }

    @Test func moduleRadiusIsConcentricAsRendered() {
        var settings = AppSettings()
        settings.customDockCornerRadius = 24
        #expect(DockSurfaceMetrics.moduleRadius(settings: settings, scale: 1) == 13)
        for magnification in [false, true] {
            settings.magnificationEnabled = magnification
            for radius in stride(from: 0.0, through: 50, by: 5) {
                settings.customDockCornerRadius = radius
                for scale in [CGFloat(0.65), 1, 1.25, 1.5] {
                    let module = DockSurfaceMetrics.moduleRadius(settings: settings, scale: scale)
                    let padding = DockSurfaceMetrics.padding(settings: settings, scale: scale)
                    #expect(module >= 0)
                    if CGFloat(radius) >= padding { #expect(abs(module * scale + padding - CGFloat(radius)) < 0.0001) }
                }
            }
        }
        #expect(DockSurfaceMetrics.moduleRadius(settings: settings, scale: 0) == DockDesign.Module.defaultRadius)
    }

    @Test func runningIndicatorPolicy() {
        let url = URL(fileURLWithPath: "/Applications/Safari.app")
        let app = DockItem.application(at: url)
        let running: Set<URL> = [InstalledApplicationIdentity.normalizedURL(url)]
        #expect(DockRunningIndicatorPolicy.isRunning(app, pinned: true, runningURLs: running, resolvedURL: { nil }))
        #expect(!DockRunningIndicatorPolicy.isRunning(app, pinned: true, runningURLs: [], resolvedURL: { nil }))
        #expect(DockRunningIndicatorPolicy.isRunning(app, pinned: false, runningURLs: [], resolvedURL: { nil }))
        var moved = app
        moved.url = URL(fileURLWithPath: "/Volumes/Old/Safari.app")
        #expect(DockRunningIndicatorPolicy.isRunning(moved, pinned: true, runningURLs: running, resolvedURL: { url }))
        #expect(!DockRunningIndicatorPolicy.isRunning(.widget("Clock"), pinned: false, runningURLs: running, resolvedURL: { nil }))
        #expect(!DockRunningIndicatorPolicy.isRunning(.file(at: url), pinned: true, runningURLs: running, resolvedURL: { url }))
    }
}
