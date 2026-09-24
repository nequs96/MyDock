import AppKit
import CoreGraphics

/// Reads only visible window owner/process IDs and bounds; it never captures a window image.
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
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else {
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
                  let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue,
                  alpha > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  quartzFrame.width > 0, quartzFrame.height > 0 else { return nil }
            return NSRect(x: quartzFrame.minX,
                          y: mainDisplayFrame.maxY - quartzFrame.maxY,
                          width: quartzFrame.width,
                          height: quartzFrame.height)
        }
        return cachedFrames
    }
}

enum SystemDockOverlapPolicy {
    static func shouldHideCustomDock(customDockFrame: NSRect, systemDockFrames: [NSRect]) -> Bool {
        systemDockFrames.contains { $0.intersects(customDockFrame) }
    }
}
