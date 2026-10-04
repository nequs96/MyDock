import AppKit
import SwiftUI

enum DockSurfaceMetrics {
    static func padding(settings: AppSettings, scale: CGFloat) -> CGFloat {
        (settings.magnificationEnabled ? 16 : 11) * scale
    }
    static func crossLength(settings: AppSettings, scale: CGFloat) -> CGFloat {
        (settings.magnificationEnabled ? 98 : 76) * scale
    }
    static func placementArea(frame: NSRect, visibleFrame: NSRect, mode: SetupMode) -> NSRect {
        guard mode == .customMain else { return visibleFrame }
        return NSRect(x: frame.minX, y: frame.minY, width: frame.width,
                      height: visibleFrame.maxY - frame.minY)
    }

    static func itemLength(_ item: DockItem, settings: AppSettings, scale: CGFloat) -> CGFloat {
        if item.type == .spacer { return CGFloat(item.spacerKind == .small ? 8 : 18) * scale }
        if item.type == .widget && settings.customDockPosition == .bottom {
            let kind = item.widgetKind ?? item.title
            let layout = WidgetPresentationCatalog.resolvedLayout(for: kind, configuration: item.widgetConfiguration ?? WidgetConfiguration(), compactDefault: settings.customDockWidgetStyle == .compact)
            return CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)) * scale
        }
        return 54 * scale
    }

    static func length(_ itemLengths: [CGFloat], spacing: CGFloat, scale: CGFloat) -> CGFloat {
        itemLengths.reduce(0, +) + CGFloat(max(itemLengths.count - 1, 0)) * spacing * scale + 2
    }

    static func contentLength(items: [DockItem], settings: AppSettings, scale: CGFloat) -> CGFloat {
        var lengths = items.map { itemLength($0, settings: settings, scale: scale) }
        if settings.showTrash && !items.contains(where: { $0.widgetKind == "Trash" }) {
            lengths.append(itemLength(.widget("Trash"), settings: settings, scale: scale))
        }
        return length(lengths, spacing: CGFloat(settings.customDockItemSpacing), scale: scale) + 22 * scale
    }

    /// Concentric module radius for `dockModuleRadius`, in the widget's own (unscaled)
    /// coordinates: widgets lay out at 1× and the Dock scales them by `scale`. As rendered,
    /// `moduleRadius × scale + padding == customDockCornerRadius` (clamped at 0).
    static func moduleRadius(settings: AppSettings, scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 0 else { return DockDesign.Module.defaultRadius }
        let rendered = DockDesign.Module.radius(dockRadius: CGFloat(settings.customDockCornerRadius),
                                                dockPadding: padding(settings: settings, scale: scale))
        return rendered / scale
    }
}

/// Pure panel placement shared by the window controller and tests. The floating inset
/// moves the panel away from its screen edge; the reveal strip stays at the edge and the
/// hover area grows back over the gap so the pointer path from edge to Dock is continuous.
enum DockPanelGeometry {
    /// Historical gap between the panel and its screen edge.
    static let edgeMargin: CGFloat = 10
    static let revealHandleThickness: CGFloat = 6
    static let revealHandleLength: CGFloat = 38

    /// `customDockFloatingInset` bounded to `DockAppearanceBounds.floatingInset`; non-finite is 0.
    static func floatingInset(_ value: Double) -> CGFloat {
        guard value.isFinite else { return 0 }
        let bounds = DockAppearanceBounds.floatingInset
        return CGFloat(min(max(value, bounds.lowerBound), bounds.upperBound))
    }

    /// `contentLength` is the item run plus the Dock's own padding; `crossLength` the panel thickness.
    static func frame(position: DockPosition, placementArea visible: NSRect, contentLength: CGFloat,
                      crossLength: CGFloat, floatingInset: Double) -> NSRect {
        let maxLength = position == .bottom ? visible.width - 40 : visible.height - 60
        let length = min(max(contentLength, 100), max(maxLength, 100))
        let offset = edgeMargin + Self.floatingInset(floatingInset)
        switch position {
        case .bottom:
            return NSRect(x: visible.midX - length / 2, y: visible.minY + offset, width: length, height: crossLength)
        case .left:
            return NSRect(x: visible.minX + offset, y: visible.midY - length / 2, width: crossLength, height: length)
        case .right:
            return NSRect(x: visible.maxX - crossLength - offset, y: visible.midY - length / 2, width: crossLength, height: length)
        }
    }

    /// The reveal strip always hugs the screen edge, whatever the inset.
    static func revealFrame(position: DockPosition, placementArea visible: NSRect) -> NSRect {
        let size = revealHandleThickness, length = revealHandleLength
        switch position {
        case .bottom: return NSRect(x: visible.midX - length / 2, y: visible.minY + 1, width: length, height: size)
        case .left: return NSRect(x: visible.minX + 1, y: visible.midY - length / 2, width: size, height: length)
        case .right: return NSRect(x: visible.maxX - size - 1, y: visible.midY - length / 2, width: size, height: length)
        }
    }

    /// The panel frame extended toward its screen edge by the inset, used for
    /// keep-visible decisions so crossing the gap does not hide a floating Dock.
    static func hoverFrame(expanded: NSRect, position: DockPosition, floatingInset: Double) -> NSRect {
        let inset = Self.floatingInset(floatingInset)
        switch position {
        case .bottom: return NSRect(x: expanded.minX, y: expanded.minY - inset, width: expanded.width, height: expanded.height + inset)
        case .left: return NSRect(x: expanded.minX - inset, y: expanded.minY, width: expanded.width + inset, height: expanded.height)
        case .right: return NSRect(x: expanded.minX, y: expanded.minY, width: expanded.width + inset, height: expanded.height)
        }
    }
}

/// Running-app dots. Unpinned runtime entries are running by construction; pinned apps
/// match by their installed-copy URL (saved, or resolved after relocation).
enum DockRunningIndicatorPolicy {
    /// `resolvedURL` touches the file system, so it is consulted only when an app with the item's
    /// bundle identifier is running (`runningBundleIdentifiers` nil skips that gate).
    static func isRunning(_ item: DockItem, pinned: Bool, runningURLs: Set<URL>,
                          runningBundleIdentifiers: Set<String>? = nil, resolvedURL: () -> URL?) -> Bool {
        guard item.type == .application else { return false }
        guard pinned else { return true }
        if let url = item.url, runningURLs.contains(InstalledApplicationIdentity.normalizedURL(url)) { return true }
        if let identifiers = runningBundleIdentifiers, !identifiers.contains(item.bundleIdentifier ?? "") { return false }
        if let url = resolvedURL(), runningURLs.contains(InstalledApplicationIdentity.normalizedURL(url)) { return true }
        return false
    }
}

/// Only settings that change Dock presentation, placement, monitoring or reveal
/// behaviour. UI-only state (last Settings page, onboarding, native-Dock switching
/// preferences) must never reassign the hosting root view.
struct DockPresentationSettings: Equatable {
    var setupMode: SetupMode
    var position: DockPosition
    var size: Double
    var itemSpacing: Double
    var cornerRadius: Double
    var tintStrength: Double
    var glassOpacity: Double
    var animationsEnabled: Bool
    var animationStyle: DockAnimationStyle
    var widgetStyle: CustomDockWidgetStyle
    var showWidgetLabels: Bool
    var displayID: UInt32?
    var automaticallyHide: Bool
    var showRevealHandle: Bool
    var hideWhenSystemDockAppears: Bool
    var desktopMode: Bool
    var material: CustomDockMaterial
    var theme: CustomDockTheme
    var showRunningApps: Bool
    var showMinimizedWindows: Bool
    var showWindowPreviews: Bool
    var showTrash: Bool
    var showAppBadges: Bool
    var clickFocusedAppToMinimize: Bool
    var magnificationEnabled: Bool
    var edgeStyle: DockEdgeStyle
    var widgetSurface: DockWidgetSurface
    var floatingInset: Double
    var tintMode: DockTintMode

    init(_ s: AppSettings) {
        setupMode = s.setupMode; position = s.customDockPosition; size = s.customDockSize
        itemSpacing = s.customDockItemSpacing; cornerRadius = s.customDockCornerRadius
        tintStrength = s.customDockTintStrength; glassOpacity = s.customDockGlassOpacity
        animationsEnabled = s.dockAnimationsEnabled; animationStyle = s.dockAnimationStyle
        widgetStyle = s.customDockWidgetStyle; showWidgetLabels = s.showWidgetLabels
        displayID = s.customDockDisplayID; automaticallyHide = s.automaticallyHideCustomDock
        showRevealHandle = s.showRevealHandle; hideWhenSystemDockAppears = s.hideCustomDockWhenSystemDockAppears
        desktopMode = s.customDockDesktopMode; material = s.customDockMaterial; theme = s.customDockTheme
        showRunningApps = s.showRunningApps; showMinimizedWindows = s.showMinimizedWindows
        showWindowPreviews = s.showWindowPreviews; showTrash = s.showTrash; showAppBadges = s.showAppBadges
        clickFocusedAppToMinimize = s.clickFocusedAppToMinimize; magnificationEnabled = s.magnificationEnabled
        edgeStyle = s.customDockEdgeStyle; widgetSurface = s.customDockWidgetSurface
        floatingInset = s.customDockFloatingInset; tintMode = s.customDockTintMode
    }
}

struct DockPresentationSignature: Equatable {
    var profileID: UUID
    var color: String
    var settings: DockPresentationSettings
    /// Reveal/auto-hide/monitoring read the global settings after the signature gate.
    var global: DockPresentationSettings
    var displayFrame: NSRect
    var entries: [String]
}

enum DockResizeGripGeometry {
    static let minimumThinDimension: CGFloat = 14
    private static func clamped(_ scale: CGFloat) -> CGFloat { min(max(scale, 0.65), 1.5) }
    /// `horizontal` means a horizontal dock: thin width, long height.
    static func layoutSize(horizontal: Bool, scale: CGFloat) -> CGSize {
        let thin = 14 * clamped(scale), long = 42 * clamped(scale)
        return CGSize(width: horizontal ? thin : long, height: horizontal ? long : thin)
    }
    static func hitSize(horizontal: Bool, scale: CGFloat) -> CGSize {
        let layout = layoutSize(horizontal: horizontal, scale: scale)
        let thin = max(minimumThinDimension, horizontal ? layout.width : layout.height)
        return CGSize(width: horizontal ? thin : layout.width, height: horizontal ? layout.height : thin)
    }
    static func hitOutset(horizontal: Bool, scale: CGFloat) -> CGSize {
        let layout = layoutSize(horizontal: horizontal, scale: scale), hit = hitSize(horizontal: horizontal, scale: scale)
        return CGSize(width: (hit.width - layout.width) / 2, height: (hit.height - layout.height) / 2)
    }
}

enum DockResizePolicy {
    static func size(start: CGFloat, translation: CGSize, position: DockPosition) -> CGFloat {
        let delta: CGFloat
        switch position {
        case .bottom: delta = -translation.height
        case .left: delta = translation.width
        case .right: delta = -translation.width
        }
        return min(max(start + delta / 180, 0.65), 1.5)
    }
}

@MainActor enum DockInteractionState { static var isResizing = false }

enum CustomDockVisibilityPolicy {
    static func canPresent(mode: SetupMode, hasActiveProfile: Bool) -> Bool {
        mode != .nativeOnly && hasActiveProfile
    }
    static func showsSystemTrash(isEnabled: Bool, hasProfileTrashWidget: Bool) -> Bool {
        isEnabled && !hasProfileTrashWidget
    }

    static func shouldReveal(mouseLocation: NSPoint,
                             expandedFrame: NSRect,
                             revealFrame: NSRect,
                             popoutFrames: [NSRect] = []) -> Bool {
        shouldRevealImmediately(mouseLocation: mouseLocation,
                                expandedFrame: expandedFrame,
                                popoutFrames: popoutFrames)
            || isAtRevealEdge(mouseLocation: mouseLocation, revealFrame: revealFrame)
    }

    static func shouldRevealImmediately(mouseLocation: NSPoint,
                                       expandedFrame: NSRect,
                                       popoutFrames: [NSRect] = []) -> Bool {
        expandedFrame.insetBy(dx: -10, dy: -10).contains(mouseLocation)
            || popoutFrames.contains { $0.insetBy(dx: -6, dy: -6).contains(mouseLocation) }
    }

    static func isAtRevealEdge(mouseLocation: NSPoint, revealFrame: NSRect) -> Bool {
        revealFrame.insetBy(dx: -6, dy: -6).contains(mouseLocation)
    }

    static func shouldHideForSystemDock(customDockFrame: NSRect, systemDockFrames: [NSRect]) -> Bool {
        SystemDockOverlapPolicy.shouldHideCustomDock(customDockFrame: customDockFrame,
                                                     systemDockFrames: systemDockFrames)
    }
}

enum DockProfileSwipePolicy {
    static func destinationIndex(currentIndex: Int,
                                 perpendicularDelta: CGFloat,
                                 parallelDelta: CGFloat,
                                 profileCount: Int) -> Int? {
        guard profileCount > 1,
              (0..<profileCount).contains(currentIndex),
              abs(perpendicularDelta) >= 48,
              abs(perpendicularDelta) > abs(parallelDelta) * 1.2 else { return nil }
        let direction = perpendicularDelta > 0 ? 1 : -1
        return (currentIndex + direction + profileCount) % profileCount
    }
}

enum DockOverflowPolicy {
    static func needsJumpControls(contentLength: CGFloat, viewportLength: CGFloat) -> Bool {
        contentLength > viewportLength + 1
    }
}

struct DockPopoutSelection: Equatable {
    private(set) var anchorID: UUID?
    private(set) var activeID: UUID?
    private(set) var tabIDs: [UUID] = []

    mutating func toggle(_ itemID: UUID) {
        if activeID == itemID {
            dismiss()
        } else {
            open(itemID)
        }
    }

    mutating func open(_ itemID: UUID) {
        if !tabIDs.contains(itemID) { tabIDs.append(itemID) }
        if anchorID == nil { anchorID = itemID }
        activeID = itemID
    }

    mutating func select(_ itemID: UUID) {
        guard tabIDs.contains(itemID) else { return }
        activeID = itemID
    }

    mutating func close(_ itemID: UUID) {
        tabIDs.removeAll { $0 == itemID }
        if tabIDs.isEmpty {
            dismiss()
            return
        }
        if activeID == itemID { activeID = tabIDs.last }
        if anchorID == itemID { anchorID = activeID ?? tabIDs.first }
    }

    mutating func retain(only validIDs: Set<UUID>) {
        tabIDs.removeAll { !validIDs.contains($0) }
        if tabIDs.isEmpty {
            dismiss()
            return
        }
        if activeID.map({ !validIDs.contains($0) }) ?? true { activeID = tabIDs.last }
        if anchorID.map({ !validIDs.contains($0) }) ?? true { anchorID = activeID ?? tabIDs.first }
    }

    mutating func dismiss() {
        anchorID = nil
        activeID = nil
        tabIDs.removeAll()
    }
}

enum DockMagnification {
    static func scale(for itemIndex: Int, focusedIndex: Int, isWidget: Bool = false,
                      enabled: Bool, reduceMotion: Bool) -> CGFloat {
        guard enabled, !reduceMotion else { return 1 }
        let distance = abs(itemIndex - focusedIndex)
        guard distance <= 2 else { return 1 }
        let applicationIntensity: CGFloat = distance == 0 ? 0.38 : distance == 1 ? 0.2 : 0.08
        let intensity = isWidget ? applicationIntensity * 0.55 : applicationIntensity
        return 1 + intensity
    }
}
