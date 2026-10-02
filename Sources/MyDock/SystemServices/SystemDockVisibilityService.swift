import AppKit
import CoreGraphics

/// Reads only public window metadata; it never captures a window image.
@MainActor
enum SystemDockVisibilityReader {
    private static var cachedFrames: [NSRect] = []
    private static var lastRead = Date.distantPast

    static func isVisible(overlapping customDockFrame: NSRect, now: Date = .now) -> Bool {
        SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: customDockFrame,
                                                     systemDockFrames: visibleDockFrames(now: now))
    }

    static func visibleDockFrames(now: Date = .now) -> [NSRect] {
        if now.timeIntervalSince(lastRead) < 0.2 { return cachedFrames }
        lastRead = now

        guard let dockApplication = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            cachedFrames = []
            return cachedFrames
        }

        let mainDisplayFrame = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == CGMainDisplayID()
        }?.frame ?? NSScreen.screens.first?.frame ?? .zero
        let dockPID = dockApplication.processIdentifier
        cachedFrames = windows.compactMap { window in
            guard let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == dockPID,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  SystemDockWindowPolicy.isPresentationSurface(layer: layer, alpha: alpha, frame: quartzFrame) else { return nil }
            return NSRect(x: quartzFrame.minX,
                          y: mainDisplayFrame.maxY - quartzFrame.maxY,
                          width: quartzFrame.width,
                          height: quartzFrame.height)
        }
        return cachedFrames
    }
}

/// The Dock also owns desktop/background windows. Those can cover an entire display
/// without Mission Control being open and must never suppress the Custom Dock.
enum SystemDockWindowPolicy {
    static func isPresentationSurface(layer: Int, alpha: Double, frame: CGRect) -> Bool {
        layer >= 0 && alpha.isFinite && alpha > 0
            && frame.origin.x.isFinite && frame.origin.y.isFinite
            && frame.width.isFinite && frame.height.isFinite
            && frame.width > 0 && frame.height > 0
    }
}

enum SystemDockOverlapPolicy {
    static func shouldHideCustomDock(customDockFrame: NSRect, systemDockFrames: [NSRect]) -> Bool {
        systemDockFrames.contains { $0.intersects(customDockFrame) }
    }
}

/// A large visible Dock-owned surface indicates a system overview, unlike the narrow Dock shelf.
/// This uses public window metadata; supported macOS versions still require live acceptance checks.
enum SystemOverviewPolicy {
    static func isPresent(screen: NSRect, dockFrames: [NSRect]) -> Bool {
        guard screen.width > 0, screen.height > 0 else { return false }
        return dockFrames.contains { frame in
            let intersection = frame.intersection(screen)
            return !intersection.isNull && intersection.width * intersection.height >= screen.width * screen.height * 0.75
                && intersection.height >= screen.height * 0.5
        }
    }
}
