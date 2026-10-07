import AppKit
import SwiftUI

enum DockSurfaceMetrics {
    /// The Dock size (tile scale) range used by layout, panel sizing, resizing and VoiceOver adjustment.
    static let scaleRange: ClosedRange<CGFloat> = 0.65...1.5

    /// `customDockSize` bounded to `scaleRange`; a non-finite value is the default size.
    static func clampedScale(_ size: Double) -> CGFloat {
        guard size.isFinite else { return 1 }
        return min(max(CGFloat(size), scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func padding(settings: AppSettings, scale: CGFloat) -> CGFloat {
        (DockMagnificationSupport.isActive(settings) ? 16 : 11) * scale
    }
    static func crossLength(settings: AppSettings, scale: CGFloat) -> CGFloat {
        (DockMagnificationSupport.isActive(settings) ? 98 : 76) * scale
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

/// The running dot of one live Dock tile. Pinned apps use the matched running copies; recent apps
/// can be running too when the running section is hidden, so they match by bundle identifier;
/// the other unpinned apps are the running section and run by construction.
enum DockTileRunningState {
    static func isRunning(_ item: DockItem, pinned: Bool, isRecent: Bool, runningPinnedIDs: Set<UUID>,
                          runningBundleIdentifiers: Set<String>) -> Bool {
        guard item.type == .application else { return false }
        if pinned { return runningPinnedIDs.contains(item.id) }
        if isRecent { return item.bundleIdentifier.map { runningBundleIdentifiers.contains($0) } ?? false }
        return true
    }
}

/// What VoiceOver reads after a tile's name: the states the Dock otherwise shows only visually.
enum DockTileAccessibility {
    static func value(isRunning: Bool, isMissing: Bool, badge: String?) -> String {
        [isRunning ? "Running" : nil,
         isMissing ? "Saved location unavailable" : nil,
         badge.map { "Badge \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Running applications matched against a profile's pinned apps (FX-02, Codex #7). URL normalization
/// resolves symlinks, which touches the file system per path component, so it runs only here, when
/// the running applications or the pinned apps change, never on a hover or magnification re-render.
struct DockRunningAppMatches: Equatable {
    /// Normalized installed-copy URLs of pinned apps (saved location, plus a relocation when consulted).
    var pinnedURLs: Set<URL> = []
    /// Runtime entries that are not a pinned app's installed copy, in runtime order.
    var unpinnedRuntime: [DockItem] = []
    /// Pinned apps whose installed copy is running.
    var runningPinnedItemIDs: Set<UUID> = []

    /// The resolver (a disk stat, possibly a Launch Services lookup) is consulted only for a pinned app
    /// whose saved copy is not running while an app with its bundle identifier is: only then can a
    /// relocated copy be the running one.
    static func compute(runtime: [DockItem], profileItems: [DockItem],
                        normalize: (URL) -> URL, resolve: (DockItem) -> URL?) -> DockRunningAppMatches {
        let running = runtime.compactMap { item in item.url.map { (item: item, url: normalize($0)) } }
        guard !running.isEmpty else { return DockRunningAppMatches() }
        let runningURLs = Set(running.map(\.url))
        let runningIdentifiers = Set(runtime.compactMap(\.bundleIdentifier))
        var matches = DockRunningAppMatches()
        for item in profileItems where item.type == .application {
            var urls: [URL] = []
            if let url = item.url { urls.append(normalize(url)) }
            if !urls.contains(where: runningURLs.contains), runningIdentifiers.contains(item.bundleIdentifier ?? ""),
               let resolved = resolve(item) {
                urls.append(normalize(resolved))
            }
            matches.pinnedURLs.formUnion(urls)
            if urls.contains(where: runningURLs.contains) { matches.runningPinnedItemIDs.insert(item.id) }
        }
        matches.unpinnedRuntime = running.filter { !matches.pinnedURLs.contains($0.url) }.map(\.item)
        return matches
    }
}

/// Holds the last `DockRunningAppMatches` keyed by its inputs. The key comparison is plain equality,
/// so a body evaluation with unchanged inputs does no file-system work.
@MainActor
final class DockRunningAppCache {
    private struct Key: Equatable {
        var runtime: [DockItem]
        var pinnedApplications: [DockItem]
    }
    private let normalize: (URL) -> URL
    private let resolve: @MainActor (DockItem) -> URL?
    private var key: Key?
    private var value = DockRunningAppMatches()
    /// How many times the matches were recomputed (tests).
    private(set) var computations = 0

    init(normalize: @escaping (URL) -> URL = InstalledApplicationIdentity.normalizedURL,
         resolve: @escaping @MainActor (DockItem) -> URL?) {
        self.normalize = normalize
        self.resolve = resolve
    }

    func matches(runtime: [DockItem], profileItems: [DockItem]) -> DockRunningAppMatches {
        let key = Key(runtime: runtime, pinnedApplications: profileItems.filter { $0.type == .application })
        if key == self.key { return value }
        self.key = key
        computations += 1
        value = DockRunningAppMatches.compute(runtime: runtime, profileItems: key.pinnedApplications,
                                              normalize: normalize, resolve: { resolve($0) })
        return value
    }
}

extension DockRenderModel {
    /// The same entries as the designated initializer, from runtime apps already matched against the
    /// profile (`DockRunningAppMatches.unpinnedRuntime`), so building the model normalizes no URL.
    init(profile: DockProfile, settings: AppSettings, unpinnedRunningApplications: [DockItem],
         windows: [DockWindowDescriptor], runningMediaSources: Set<NowPlayingSource>,
         recentApplications: [DockItem] = []) {
        self.init(profile: profile, settings: settings, runningApplications: [], windows: windows,
                  runningMediaSources: runningMediaSources, pinnedApplicationURLs: [])
        if settings.showRunningApps, !unpinnedRunningApplications.isEmpty,
           let boundary = entries.firstIndex(where: { $0.id == DockRenderEntry.boundary(.running).id }) {
            entries.insert(contentsOf: unpinnedRunningApplications.map { DockRenderEntry.item($0, pinned: false) }, at: boundary + 1)
        }
        insertRecentApplications(recentApplications, settings: settings)
    }
}

/// Separator lines in the Dock (FX-02). The pinned-end line (the resize grip in the live Dock) and the
/// minimized-windows boundary draw a line only between content: never at either end of the Dock and
/// never twice in a row. The running-apps boundary is an invisible drop target and never draws one.
enum DockSeparatorPolicy {
    static func isContent(_ entry: DockRenderEntry) -> Bool {
        switch entry {
        case .item(let item, _): item.type != .spacer
        case .window: true
        case .boundary, .insertion: false
        }
    }

    static func drawsLineWhenBetweenContent(_ entry: DockRenderEntry) -> Bool {
        switch entry {
        case .insertion: true
        case .boundary(let kind): kind != .running
        case .item, .window: false
        }
    }

    /// IDs of the separator entries whose line is visible.
    static func visibleSeparatorIDs(_ entries: [DockRenderEntry]) -> Set<String> {
        guard let lastContent = entries.lastIndex(where: isContent) else { return [] }
        var visible: Set<String> = []
        var contentSinceLine = false
        for (index, entry) in entries.enumerated() {
            if isContent(entry) { contentSinceLine = true; continue }
            guard drawsLineWhenBetweenContent(entry), contentSinceLine, index < lastContent else { continue }
            visible.insert(entry.id)
            contentSinceLine = false
        }
        return visible
    }

    /// Previews only: the slots after the last tile (the pinned-end grip, an empty running-apps
    /// boundary) draw no line and take no live interaction, so they collapse and a preview Dock
    /// ends at its last tile with even padding. The live Dock keeps them: the grip resizes and
    /// accepts drops at the end of the pinned items.
    static func previewCollapsedEntryIDs(_ entries: [DockRenderEntry]) -> Set<String> {
        guard let lastContent = entries.lastIndex(where: isContent) else { return [] }
        return Set(entries[(lastContent + 1)...].map(\.id))
    }

    /// `DockRenderModel.contentLength` without the collapsed preview slots.
    static func previewContentLength(_ entries: [DockRenderEntry], settings: AppSettings, scale: CGFloat) -> CGFloat {
        let collapsed = previewCollapsedEntryIDs(entries)
        return DockSurfaceMetrics.length(entries.filter { !collapsed.contains($0.id) }.map { $0.length(settings: settings, scale: scale) },
                                         spacing: CGFloat(settings.customDockItemSpacing), scale: scale)
    }
}

/// Where a notification badge sits on its tile (FX-02, D4). Bottom Docks hang it outward from the
/// top-trailing corner like the system Dock. Side Docks keep it inside the tile: their item column is
/// exactly one tile wide and the scroll axis is vertical, so an outward overhang is clipped.
enum DockBadgePlacement {
    static func offset(position: DockPosition, scale: CGFloat) -> CGSize {
        position == .bottom ? CGSize(width: 4 * scale, height: -2 * scale) : .zero
    }

    /// The badge's frame in its tile's coordinates (origin top-leading), from a top-trailing alignment.
    static func frame(badgeSize: CGSize, tileSize: CGSize, position: DockPosition, scale: CGFloat) -> CGRect {
        let offset = offset(position: position, scale: scale)
        return CGRect(x: tileSize.width - badgeSize.width + offset.width, y: offset.height,
                      width: badgeSize.width, height: badgeSize.height)
    }
}

/// The colour scheme a Dock renders in: an explicit Dock theme, then the Midnight material (dark),
/// then the system appearance. The window or app scheme never decides how the Dock looks.
enum DockColorSchemePolicy {
    static func scheme(theme: CustomDockTheme, material: CustomDockMaterial, system: ColorScheme) -> ColorScheme {
        switch theme {
        case .dark: .dark
        case .light: .light
        case .system: material == .dark ? .dark : system
        }
    }
}

/// Which editor items settle after a reorder (FX-02). A move keeps every item, so the moved ones are
/// the selection when moving it alone explains the new order, else the items outside the longest run
/// that kept its relative order. Adds, removals and unchanged orders settle nothing.
enum DockReorderSettlePolicy {
    static func movedItems(from old: [UUID], to new: [UUID], selection: Set<UUID> = []) -> Set<UUID> {
        guard old != new, old.count == new.count, Set(old) == Set(new), Set(new).count == new.count else { return [] }
        let selected = selection.intersection(new)
        if !selected.isEmpty, old.filter({ !selected.contains($0) }) == new.filter({ !selected.contains($0) }) {
            return selected
        }
        // Longest increasing subsequence of old positions, in new order (patience sorting).
        let oldIndex = Dictionary(uniqueKeysWithValues: old.enumerated().map { ($1, $0) })
        let positions = new.map { oldIndex[$0]! }
        var tails: [Int] = [], tailIndex: [Int] = [], previous = Array(repeating: -1, count: positions.count)
        for (index, value) in positions.enumerated() {
            var low = 0, high = tails.count
            while low < high { let mid = (low + high) / 2; if tails[mid] < value { low = mid + 1 } else { high = mid } }
            if low > 0 { previous[index] = tailIndex[low - 1] }
            if low == tails.count { tails.append(value); tailIndex.append(index) }
            else { tails[low] = value; tailIndex[low] = index }
        }
        var kept: Set<UUID> = []
        var cursor = tailIndex.last ?? -1
        while cursor >= 0 { kept.insert(new[cursor]); cursor = previous[cursor] }
        return Set(new).subtracting(kept)
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
    var showRecentApps: Bool
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
        showRunningApps = s.showRunningApps; showRecentApps = s.showRecentApps; showMinimizedWindows = s.showMinimizedWindows
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
    private static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, DockSurfaceMetrics.scaleRange.lowerBound), DockSurfaceMetrics.scaleRange.upperBound)
    }
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
    /// Pointer travel, in points, that changes the Dock size by 1 (100%).
    static let pointsPerUnit: CGFloat = 180

    static func size(start: CGFloat, translation: CGSize, position: DockPosition) -> CGFloat {
        let delta: CGFloat
        switch position {
        case .bottom: delta = -translation.height
        case .left: delta = translation.width
        case .right: delta = -translation.width
        }
        let size = start + delta / pointsPerUnit
        return min(max(size, DockSurfaceMetrics.scaleRange.lowerBound), DockSurfaceMetrics.scaleRange.upperBound)
    }
}

@MainActor enum DockInteractionState { static var isResizing = false }

/// "Main display" is the primary display (menu bar, origin at zero), which AppKit lists first. `NSScreen.main`
/// follows keyboard focus, so it never stands in for it: the Dock would follow the focused window between displays.
enum DockDisplaySelection {
    /// The chosen display while it is connected; otherwise the primary display. `isFallback` is true only while a
    /// chosen display is missing.
    static func resolve<Display>(_ displays: [Display], selectedID: UInt32?,
                                 id: (Display) -> UInt32?) -> (display: Display?, isFallback: Bool) {
        if let selectedID, let selected = displays.first(where: { id($0) == selectedID }) { return (selected, false) }
        return (displays.first, selectedID != nil)
    }

    @MainActor static func screen(selectedID: UInt32?) -> (screen: NSScreen?, isFallback: Bool) {
        let resolved = resolve(NSScreen.screens, selectedID: selectedID) { $0.displayNumber }
        return (resolved.display, resolved.isFallback)
    }
}

extension NSScreen {
    /// The Core Graphics display ID that Settings stores for a chosen display.
    var displayNumber: UInt32? { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value }
}

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

/// macOS 13 clips a ScrollView's content to its bounds (`scrollClipDisabled` is macOS 14+), so a
/// magnified tile would be cut off at the Dock's edge. Magnification runs on macOS 14 and later only.
enum DockMagnificationSupport {
    static var isAvailable: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// Whether the Dock magnifies, and so reserves room for it. Below macOS 14 it never does, so a stored
    /// Magnification setting must not make the Dock larger there either.
    static func isActive(_ settings: AppSettings, available: Bool = isAvailable) -> Bool {
        settings.magnificationEnabled && available
    }
}

/// Where the Dock's `GlassEffectContainer` sits (RD-04, re-examined in RD-11).
///
/// The container wraps the item stack only; the Dock surface glass is drawn behind it, outside.
/// A container unions every glass shape that lies within `spacing` of another. A module sits
/// entirely inside the Dock surface, so its signed distance to the surface is negative and no
/// spacing keeps it apart: sharing one container would fuse every module into the Dock glass and
/// erase the module edges at rest. The stack container also stays inside the scroll viewport, so
/// scrolled-out modules are clipped by `DockScrollClip` like every other item.
enum DockGlassComposition {
    enum Scope: Equatable {
        /// No container: non-glass materials and Reduce Transparency.
        case none
        /// One container around the item stack, inside the scroll viewport.
        case itemStack
    }

    /// Spacing 0: modules blend only when they touch (morphs), never at rest.
    static let moduleSpacing: CGFloat = 0

    static func scope(material: CustomDockMaterial, reduceTransparency: Bool) -> Scope {
        [.liquidGlass, .liquidGlassClear].contains(material) && !reduceTransparency ? .itemStack : .none
    }
}

/// RD-11 motion for the live Dock. Every animation is nil under Reduce Motion
/// (and when the user turned Dock animations off), and every transform rests at identity.
enum DockMotionPolicy {
    // MARK: Popout open

    /// Popout content opens from 96% with a fade on `Motion.appear`.
    static let popoutStartScale: CGFloat = 0.96

    /// A frame of the appear spring, 0 (closed) … 1 (open); render exports pin intermediate frames.
    static func popoutContentScale(progress: Double, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 1 }
        let clamped = progress.isFinite ? min(max(progress, 0), 1) : 1
        return popoutStartScale + (1 - popoutStartScale) * CGFloat(clamped)
    }
    static func popoutContentOpacity(progress: Double, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 1 }
        return progress.isFinite ? min(max(progress, 0), 1) : 1
    }

    // MARK: Popout anchor

    /// The module a popout hangs from reads as pressed while it is open.
    static let anchorActiveScale: CGFloat = 0.97
    static let anchorActiveBrightness: Double = 0.05

    static func anchorScale(isActive: Bool, reduceMotion: Bool) -> CGFloat {
        isActive && !reduceMotion ? anchorActiveScale : 1
    }
    /// Brightening washes out on light surfaces, so light schemes use a smaller step.
    static func anchorBrightness(isActive: Bool, dark: Bool) -> Double {
        isActive ? anchorActiveBrightness * (dark ? 1 : 0.6) : 0
    }
    static func anchorAnimation(reduceMotion: Bool) -> Animation? {
        DockDesign.Motion.animation(DockDesign.Motion.hover, reduceMotion: reduceMotion)
    }

    // MARK: Reorder

    static func reorderAnimation(reduceMotion: Bool, animationsEnabled: Bool) -> Animation? {
        DockDesign.Motion.animation(DockDesign.Motion.reorder, reduceMotion: reduceMotion || !animationsEnabled)
    }
    static func profileTransformAnimation(reduceMotion: Bool, animationsEnabled: Bool) -> Animation? {
        DockDesign.Motion.animation(DockDesign.Motion.transform, reduceMotion: reduceMotion || !animationsEnabled)
    }

    /// Items dropped into a new place settle from 94% on `Motion.morph`.
    static let settleStartScale: CGFloat = 0.94

    static func settleAnimation(reduceMotion: Bool, animationsEnabled: Bool) -> Animation? {
        DockDesign.Motion.animation(DockDesign.Motion.morph, reduceMotion: reduceMotion || !animationsEnabled)
    }
    static func settleScale(isSettling: Bool, reduceMotion: Bool) -> CGFloat {
        isSettling && !reduceMotion ? settleStartScale : 1
    }

    // MARK: Hover and scrolling

    /// Tiles settle back when the pointer leaves the Dock on `Motion.hover`.
    static func hoverAnimation(reduceMotion: Bool, animationsEnabled: Bool) -> Animation? {
        DockDesign.Motion.animation(DockDesign.Motion.hover, reduceMotion: reduceMotion || !animationsEnabled)
    }
}

/// Which file-backed items point at a missing target. The check stats the file system (and may ask
/// LaunchServices), so the Dock computes it on item, launch and volume changes, never per render.
enum DockMissingTargets {
    static func ids(in items: [DockItem], isMissing: (DockItem) -> Bool) -> Set<UUID> {
        Set(items.filter { [.application, .file, .folder].contains($0.type) && isMissing($0) }.map(\.id))
    }
}

extension DockDesign {
    /// Chrome the live Dock draws itself: section separators, the resize grip and the reveal handle.
    /// Increase Contrast strengthens each one; Reduce Transparency makes the reveal handle opaque.
    enum DockChrome {
        static func separator(_ contrast: ColorSchemeContrast) -> Color {
            contrast == .increased ? Outline.color(.increased) : Color.primary.opacity(0.2)
        }
        /// The resize grip under the pointer.
        static func separatorHighlight(_ contrast: ColorSchemeContrast) -> Color {
            Color.primary.opacity(contrast == .increased ? 0.8 : 0.45)
        }
        static func revealHandle(_ contrast: ColorSchemeContrast, reduceTransparency: Bool) -> Color {
            let increased = contrast == .increased
            if reduceTransparency { return increased ? .primary : Color(nsColor: .systemGray) }
            return Color.primary.opacity(increased ? 0.8 : 0.26)
        }
    }
}
