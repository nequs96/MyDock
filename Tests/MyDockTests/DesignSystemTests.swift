import SwiftUI
import Testing
@testable import MyDock

@MainActor
struct DesignSystemTests {
    @Test func moduleRadiusIsConcentricWithTheDock() {
        #expect(DockDesign.Module.radius(dockRadius: 24, dockPadding: 11) == 13)
        #expect(DockDesign.Module.radius(dockRadius: 24, dockPadding: 8) == 16)
        #expect(DockDesign.Module.radius(dockRadius: 30.5, dockPadding: 10) == 20.5)
        for radius in stride(from: 0.0, through: 40, by: 2) {
            for padding in stride(from: 0.0, through: 20, by: 1) {
                let module = DockDesign.Module.radius(dockRadius: radius, dockPadding: padding)
                #expect(module >= 0)
                if radius >= padding { #expect(module + padding == radius) }
            }
        }
    }

    @Test func moduleRadiusClampsAtZero() {
        #expect(DockDesign.Module.radius(dockRadius: 8, dockPadding: 11) == 0)
        #expect(DockDesign.Module.radius(dockRadius: 0, dockPadding: 0) == 0)
        #expect(DockDesign.Module.radius(dockRadius: -4, dockPadding: 2) == 0)
        #expect(DockDesign.Module.radius(dockRadius: .nan, dockPadding: 2) == 0)
        #expect(DockDesign.Module.radius(dockRadius: .infinity, dockPadding: 2) == 0)
        #expect(DockDesign.Module.radius(dockRadius: 24, dockPadding: .nan) == 0)
    }

    @Test func reduceMotionRemovesEveryAnimation() {
        let motions = [DockDesign.Motion.transform, DockDesign.Motion.reorder, DockDesign.Motion.disclosure,
                       DockDesign.Motion.hover, DockDesign.Motion.appear, DockDesign.Motion.morph]
        for motion in motions {
            #expect(DockDesign.Motion.animation(motion, reduceMotion: true) == nil)
            #expect(DockDesign.Motion.animation(motion, reduceMotion: false) == motion)
        }
    }

    @Test func performRunsTheChangeWithAndWithoutMotion() {
        var runs = 0
        let instant = DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: true) { () -> Int in
            runs += 1
            return 7
        }
        let animated = DockDesign.Motion.perform(DockDesign.Motion.morph, reduceMotion: false) { () -> Int in
            runs += 1
            return 3
        }
        #expect(instant == 7 && animated == 3 && runs == 2)
    }

    @Test func moduleTypeScaleStaysReadable() {
        #expect(DockDesign.Module.pointSize(.large) == 22)
        #expect(DockDesign.Module.pointSize(.medium) == 18)
        #expect(DockDesign.Module.pointSize(.small) == 13)
        #expect(DockDesign.Module.ValueSize.allCases.allSatisfy { DockDesign.Module.pointSize($0) >= DockDesign.Module.minimumTextSize })
        #expect(DockDesign.Module.maxTextLines == 2)
        #expect(DockDesign.Motion.hoverScale > 1 && DockDesign.Motion.hoverScale <= 1.04)
        #expect(DockDesign.Grouped.rowMinHeight >= 36)
    }

    @Test func accessibilityPreviewDefaultsKeepExistingCallSites() {
        let preview = DockAccessibilityPreview(contrast: .increased, reduceTransparency: true)
        #expect(preview.reduceMotion == false)
        #expect(DockAccessibilityPreview(contrast: .standard, reduceTransparency: false, reduceMotion: true).reduceMotion)
    }
}
