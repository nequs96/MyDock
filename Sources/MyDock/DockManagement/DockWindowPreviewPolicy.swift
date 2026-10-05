import CoreGraphics
import Foundation

// PX-2: window previews on hover. Pure policy only: timing, geometry, layout and the
// permission → presentation mapping. `DockWindowPreviewController` owns every native effect.

/// Hover timing for the window preview panel.
///
/// - A running app tile must stay hovered for `showDelay` before the panel opens.
/// - While the panel is open, moving to another running app swaps its content at once.
/// - Leaving both the tile and the panel closes it after `closeGrace`; re-entering either cancels.
/// - Deadlines are absolute times on one monotonic clock; the caller wakes once per deadline,
///   so nothing runs while idle.
struct WindowPreviewHoverMachine: Equatable {
    static let defaultShowDelay: TimeInterval = 0.5
    static let defaultCloseGrace: TimeInterval = 0.3
    /// Timer wake-ups may land a hair early; treat them as on time.
    static let tolerance: TimeInterval = 0.001

    enum Phase: Equatable {
        case idle
        /// Waiting for the show delay on one tile (target key, deadline).
        case arming(String, TimeInterval)
        /// The panel shows the target's windows; the pointer is over the tile or the panel.
        case open(String)
        /// The pointer left both; the panel closes at the deadline unless it returns.
        case closing(String, TimeInterval)
    }

    enum Event: Equatable {
        case enterTile(String)
        case exitTile(String)
        case enterPanel
        case exitPanel
        /// A deadline wake-up.
        case tick
        /// Escape, a click, the Dock hiding or the setting turning off.
        case dismiss
    }

    enum Effect: Equatable {
        case noChange
        case show(String)
        case swap(String)
        case close
    }

    let showDelay: TimeInterval
    let closeGrace: TimeInterval
    private(set) var phase: Phase = .idle
    private(set) var hoveredTile: String?
    private(set) var pointerInPanel = false

    init(showDelay: TimeInterval = Self.defaultShowDelay, closeGrace: TimeInterval = Self.defaultCloseGrace) {
        self.showDelay = max(0, showDelay)
        self.closeGrace = max(0, closeGrace)
    }

    /// The tile whose windows the panel currently shows.
    var displayedTarget: String? {
        switch phase {
        case .open(let target), .closing(let target, _): return target
        case .idle, .arming: return nil
        }
    }

    /// The one pending wake-up, if any. Idle and open (pointer inside) need none.
    var nextDeadline: TimeInterval? {
        switch phase {
        case .arming(_, let deadline), .closing(_, let deadline): return deadline
        case .idle, .open: return nil
        }
    }

    /// Keys whose tile information the caller must keep.
    var retainedTargets: Set<String> {
        var keys = Set<String>()
        if let hoveredTile { keys.insert(hoveredTile) }
        switch phase {
        case .arming(let target, _), .open(let target), .closing(let target, _): keys.insert(target)
        case .idle: break
        }
        return keys
    }

    mutating func handle(_ event: Event, at now: TimeInterval) -> Effect {
        switch event {
        case .enterTile(let key):
            hoveredTile = key
            switch phase {
            case .idle:
                phase = .arming(key, now + showDelay)
                return .noChange
            case .arming(let target, _):
                if target != key { phase = .arming(key, now + showDelay) }
                return .noChange
            case .open(let target), .closing(let target, _):
                phase = .open(key)
                return target == key ? .noChange : .swap(key)
            }

        case .exitTile(let key):
            // A late exit from the previous tile must not close the panel for the new one.
            guard hoveredTile == key else { return .noChange }
            hoveredTile = nil
            switch phase {
            case .arming:
                phase = .idle
            case .open(let target):
                if !pointerInPanel { phase = .closing(target, now + closeGrace) }
            case .idle, .closing:
                break
            }
            return .noChange

        case .enterPanel:
            pointerInPanel = true
            if case .closing(let target, _) = phase { phase = .open(target) }
            return .noChange

        case .exitPanel:
            pointerInPanel = false
            if case .open(let target) = phase, hoveredTile == nil {
                phase = .closing(target, now + closeGrace)
            }
            return .noChange

        case .tick:
            switch phase {
            case .arming(let target, let deadline) where now + Self.tolerance >= deadline:
                phase = .open(target)
                return .show(target)
            case .closing(_, let deadline) where now + Self.tolerance >= deadline:
                phase = .idle
                pointerInPanel = false
                return .close
            default:
                return .noChange
            }

        case .dismiss:
            let wasShowing = displayedTarget != nil
            phase = .idle
            pointerInPanel = false
            // The pointer may still rest on the tile: it must leave and return to arm again.
            return wasShowing ? .close : .noChange
        }
    }
}

/// Where window discovery stands for the hovered app.
enum WindowPreviewDiscoveryState: Equatable {
    case pending
    case windows(Int)
    case permissionRequired
    case unavailable
}

/// What the panel shows, derived from observed permissions and discovery only.
struct WindowPreviewPresentation: Equatable {
    enum Body: Equatable {
        case loading
        /// One line explaining window access needs Accessibility, with an action.
        case accessibilityRequired
        case unavailable
        case empty
        case thumbnails
        /// App icon and window title per window.
        case titles
    }

    var body: Body
    /// One "Show thumbnails…" row that explains and opens the Permissions flow.
    var offersThumbnails: Bool
}

enum WindowPreviewPresentationPolicy {
    /// - Parameters:
    ///   - captureSupported: the system can capture window thumbnails (macOS 14 or later).
    ///   - screenRecordingAllowed: Screen Recording was observed as allowed (never requested here).
    static func presentation(accessibilityTrusted: Bool, screenRecordingAllowed: Bool,
                             captureSupported: Bool, discovery: WindowPreviewDiscoveryState) -> WindowPreviewPresentation {
        guard accessibilityTrusted, discovery != .permissionRequired else {
            return WindowPreviewPresentation(body: .accessibilityRequired, offersThumbnails: false)
        }
        switch discovery {
        case .pending, .permissionRequired:
            return WindowPreviewPresentation(body: .loading, offersThumbnails: false)
        case .unavailable:
            return WindowPreviewPresentation(body: .unavailable, offersThumbnails: false)
        case .windows(let count) where count <= 0:
            return WindowPreviewPresentation(body: .empty, offersThumbnails: false)
        case .windows:
            if captureSupported && screenRecordingAllowed {
                return WindowPreviewPresentation(body: .thumbnails, offersThumbnails: false)
            }
            return WindowPreviewPresentation(body: .titles, offersThumbnails: captureSupported && !screenRecordingAllowed)
        }
    }
}

/// Which windows the panel lists: open windows first, then minimized ones, each group in the
/// order the app reports them; bounded so a window-heavy app cannot grow the panel without limit.
enum WindowPreviewListPolicy {
    static func displayed(_ windows: [DockWindowDescriptor],
                          limit: Int = WindowPreviewPanelLayout.maximumWindows) -> [DockWindowDescriptor] {
        let ordered = windows.filter { !$0.isMinimized } + windows.filter(\.isMinimized)
        return Array(ordered.prefix(max(0, limit)))
    }
}

/// Fixed panel metrics. The SwiftUI panel lays out to exactly these sizes.
enum WindowPreviewPanelLayout {
    static let padding: CGFloat = 10
    static let spacing: CGFloat = 8
    static let radius: CGFloat = DockDesign.Module.defaultRadius
    static let headerHeight: CGFloat = 20
    static let thumbnailSize = CGSize(width: 176, height: 110)
    static let cardTitleSpacing: CGFloat = 4
    static let cardTitleHeight: CGFloat = 18
    static var cardSize: CGSize {
        CGSize(width: thumbnailSize.width, height: thumbnailSize.height + cardTitleSpacing + cardTitleHeight)
    }
    static let rowHeight: CGFloat = 30
    static let listWidth: CGFloat = 280
    static let noticeHeight: CGFloat = 44
    static let maximumWindows = 12
    /// A bottom Dock shows a horizontal strip; side Docks show a column.
    static let maximumVisibleCardsInStrip = 4
    static let maximumVisibleCardsInColumn = 3
    static let maximumVisibleRows = 8

    static func usesStrip(position: DockPosition) -> Bool { position == .bottom }

    static func size(for presentation: WindowPreviewPresentation, windowCount: Int, position: DockPosition) -> CGSize {
        let chrome = padding * 2 + headerHeight + spacing
        let count = min(max(windowCount, 1), maximumWindows)
        switch presentation.body {
        case .thumbnails:
            let card = cardSize
            if usesStrip(position: position) {
                let visible = CGFloat(min(count, maximumVisibleCardsInStrip))
                return CGSize(width: padding * 2 + visible * card.width + (visible - 1) * spacing,
                              height: chrome + card.height)
            }
            let visible = CGFloat(min(count, maximumVisibleCardsInColumn))
            return CGSize(width: padding * 2 + card.width,
                          height: chrome + visible * card.height + (visible - 1) * spacing)
        case .titles:
            let rows = CGFloat(min(count, maximumVisibleRows))
            let offer = presentation.offersThumbnails ? spacing + noticeHeight : 0
            return CGSize(width: listWidth, height: chrome + rows * rowHeight + offer)
        case .loading, .accessibilityRequired, .unavailable, .empty:
            return CGSize(width: listWidth, height: chrome + noticeHeight)
        }
    }
}

/// Places the panel next to its tile in AppKit screen coordinates (origin bottom-left):
/// above the Dock for a bottom Dock, beside it for side Docks, centred on the tile along the
/// Dock and kept on screen.
enum WindowPreviewPanelGeometry {
    /// The gap between the Dock and the panel. It stays inside the reveal policy's
    /// keep-visible margins, so an auto-hidden Dock does not hide while crossing it.
    static let gap: CGFloat = 8
    static let screenMargin: CGFloat = 8

    static func frame(size: CGSize, tile: CGRect, dock: CGRect, position: DockPosition, bounds: CGRect) -> CGRect {
        let width = max(0, min(size.width, bounds.width - screenMargin * 2))
        let height = max(0, min(size.height, bounds.height - screenMargin * 2))
        switch position {
        case .bottom:
            let x = clamp(tile.midX - width / 2, lower: bounds.minX + screenMargin, upper: bounds.maxX - screenMargin - width)
            let y = clamp(dock.maxY + gap, lower: bounds.minY + screenMargin, upper: bounds.maxY - screenMargin - height)
            return CGRect(x: x, y: y, width: width, height: height)
        case .left:
            let x = clamp(dock.maxX + gap, lower: bounds.minX + screenMargin, upper: bounds.maxX - screenMargin - width)
            let y = clamp(tile.midY - height / 2, lower: bounds.minY + screenMargin, upper: bounds.maxY - screenMargin - height)
            return CGRect(x: x, y: y, width: width, height: height)
        case .right:
            let x = clamp(dock.minX - gap - width, lower: bounds.minX + screenMargin, upper: bounds.maxX - screenMargin - width)
            let y = clamp(tile.midY - height / 2, lower: bounds.minY + screenMargin, upper: bounds.maxY - screenMargin - height)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        // A panel larger than the room keeps its leading edge on screen.
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }
}

/// Which Dock tiles carry the hover region: running apps in the live Dock, with the setting on
/// and no widget or folder popout open.
enum WindowPreviewEligibility {
    static func showsRegion(itemType: DockItemType, isRunning: Bool, isPreview: Bool,
                            popoutOpen: Bool, enabled: Bool) -> Bool {
        enabled && !isPreview && !popoutOpen && isRunning && itemType == .application
    }
}

/// A small in-memory thumbnail cache: bounded by count and age, least recently used first out.
/// It is filled only while the panel is open and cleared when the feature turns off.
struct WindowPreviewThumbnailCache<Image> {
    static var defaultCapacity: Int { 24 }
    static var defaultMaximumAge: TimeInterval { 5 * 60 }

    private struct Entry {
        var image: Image
        var storedAt: TimeInterval
    }

    let capacity: Int
    let maximumAge: TimeInterval
    private var entries: [String: Entry] = [:]
    /// Least recently used first.
    private var recency: [String] = []

    init(capacity: Int = Self.defaultCapacity, maximumAge: TimeInterval = Self.defaultMaximumAge) {
        self.capacity = max(0, capacity)
        self.maximumAge = max(0, maximumAge)
    }

    var count: Int { entries.count }

    mutating func store(_ image: Image, for key: String, at now: TimeInterval) {
        guard capacity > 0 else { return }
        entries[key] = Entry(image: image, storedAt: now)
        touch(key)
        while entries.count > capacity, let oldest = recency.first {
            recency.removeFirst()
            entries[oldest] = nil
        }
    }

    mutating func image(for key: String, at now: TimeInterval) -> Image? {
        guard let entry = entries[key] else { return nil }
        let age = now - entry.storedAt
        guard age >= 0, age <= maximumAge else {
            remove(key)
            return nil
        }
        touch(key)
        return entry.image
    }

    /// True when the key was captured within `interval`; such windows are not recaptured.
    func isFresh(_ key: String, within interval: TimeInterval, at now: TimeInterval) -> Bool {
        guard let entry = entries[key] else { return false }
        let age = now - entry.storedAt
        return age >= 0 && age < interval
    }

    mutating func removeAll() {
        entries = [:]
        recency = []
    }

    private mutating func remove(_ key: String) {
        entries[key] = nil
        recency.removeAll { $0 == key }
    }

    private mutating func touch(_ key: String) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}
