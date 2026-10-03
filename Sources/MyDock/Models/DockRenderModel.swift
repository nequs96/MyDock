import AppKit
import CoreTransferable
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let myDockItems = UTType(exportedAs: "app.mydock.items", conformingTo: .json)
}

struct DockDragPayload: Codable, Transferable {
    var profileID: UUID?
    var itemIDs: [UUID] = []
    var runningBundleIdentifier: String?
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .myDockItems)
    }
}

/// One destination accepts internal layouts and Finder/browser URLs without
/// stacking competing drop handlers on the same view.
enum DockDropValue: Transferable {
    case items(DockDragPayload)
    case url(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (payload: DockDragPayload) in DockDropValue.items(payload) })
        ProxyRepresentation(importing: { (url: URL) in DockDropValue.url(url) })
    }
}

enum RuntimeDockIdentity {
    static func uuid(_ value: String) -> UUID {
        let bytes = Array(SHA256.hash(data: Data(value.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

enum DockRenderEntry: Identifiable {
    case item(DockItem, pinned: Bool)
    case boundary(String)
    case insertion
    case window(DockWindowDescriptor)

    var id: String {
        switch self {
        case .item(let item, _): item.id.uuidString
        case .boundary(let kind): "boundary-\(kind)"
        case .insertion: "pinned-end"
        case .window(let window): window.id
        }
    }
    func length(settings: AppSettings, scale: CGFloat) -> CGFloat {
        switch self {
        case .item(let item, _): DockSurfaceMetrics.itemLength(item, settings: settings, scale: scale)
        case .boundary: 5 * scale
        case .insertion: 14 * scale
        case .window: 48 * scale + 6
        }
    }
}

struct PositionedDockRenderEntry: Identifiable {
    var entry: DockRenderEntry
    var center: CGFloat
    var visualID: String
    var id: String { entry.id }
}

struct DockRenderModel {
    var entries: [DockRenderEntry]
    static var systemTrash: DockItem {
        var item = DockItem.widget("Trash")
        item.id = RuntimeDockIdentity.uuid("system-trash")
        return item
    }

    init(profile: DockProfile, settings: AppSettings, runningApplications: [DockItem],
         windows: [DockWindowDescriptor], runningMediaSources: Set<NowPlayingSource>) {
        entries = profile.items.filter { item in
            guard item.widgetKind == "Now Playing" else { return true }
            let c = item.widgetConfiguration ?? WidgetConfiguration()
            return NowPlayingVisibilityPolicy.showsTile(hideWhenClosed: c.nowPlayingHidesWhenClosed,
                enabledSources: Set(c.nowPlayingEnabledSources), runningSources: runningMediaSources)
        }.map { .item($0, pinned: true) }
        entries.append(.insertion)
        if settings.showRunningApps {
            entries.append(.boundary("running"))
            let pinned = Set(profile.items.filter { $0.type == .application }.compactMap { $0.url.map(InstalledApplicationIdentity.normalizedURL) })
            entries += runningApplications.filter { item in item.url.map { !pinned.contains(InstalledApplicationIdentity.normalizedURL($0)) } ?? true }.map { .item($0, pinned: false) }
        }
        let minimized = windows.filter(\.isMinimized)
        if settings.showMinimizedWindows, !minimized.isEmpty {
            entries.append(.boundary("windows"))
            entries += minimized.map(DockRenderEntry.window)
        }
        if settings.showTrash, !profile.items.contains(where: { $0.widgetKind == "Trash" }) {
            entries.append(.item(Self.systemTrash, pinned: false))
        }
    }

    func contentLength(settings: AppSettings, scale: CGFloat) -> CGFloat {
        DockSurfaceMetrics.length(entries.map { $0.length(settings: settings, scale: scale) },
                                  spacing: CGFloat(settings.customDockItemSpacing), scale: scale)
    }

    func positionedEntries(settings: AppSettings, scale: CGFloat) -> [PositionedDockRenderEntry] {
        var position: CGFloat = 1
        let tiles = DockVisualIdentity.items(entries.compactMap { entry in
            if case .item(let item, _) = entry { return item }
            return nil
        })
        let visualIDs = Dictionary(uniqueKeysWithValues: tiles.map { ($0.item.id, $0.id) })
        return entries.map { entry in
            let length = entry.length(settings: settings, scale: scale)
            defer { position += length + CGFloat(settings.customDockItemSpacing) * scale }
            let visualID: String
            if case .item(let item, _) = entry { visualID = visualIDs[item.id] ?? entry.id }
            else { visualID = entry.id }
            return PositionedDockRenderEntry(entry: entry, center: position + length / 2, visualID: visualID)
        }
    }

    func center(of id: String, settings: AppSettings, scale: CGFloat) -> CGFloat? {
        var position: CGFloat = 1
        for entry in entries {
            let length = entry.length(settings: settings, scale: scale)
            if entry.id == id { return position + length / 2 }
            position += length + CGFloat(settings.customDockItemSpacing) * scale
        }
        return nil
    }
}

@MainActor
enum RuntimeDockApplications {
    static func items() -> [DockItem] {
        let descriptors = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApplicationDescriptor? in
            guard let identifier = app.bundleIdentifier, let url = app.bundleURL else { return nil }
            return RunningApplicationDescriptor(bundleIdentifier: identifier, name: app.localizedName ?? identifier,
                bundleURL: url, isRegularApplication: app.activationPolicy == .regular, isTerminated: app.isTerminated)
        }
        return RunningApplicationFilter.visible(descriptors, excluding: []).map { descriptor in
            var item = DockItem.application(at: descriptor.bundleURL)
            item.id = RuntimeDockIdentity.uuid("running:\(descriptor.id)")
            item.title = descriptor.name
            item.bundleIdentifier = descriptor.bundleIdentifier
            return item
        }
    }
}

enum DockContinuousMagnification {
    static func scale(center: CGFloat, pointer: CGFloat?, radius: CGFloat, isWidget: Bool,
                      enabled: Bool, reduceMotion: Bool) -> CGFloat {
        guard enabled, !reduceMotion, let pointer, radius > 0 else { return 1 }
        let proximity = max(0, 1 - abs(center - pointer) / radius)
        let wave = (1 - cos(proximity * .pi)) / 2
        return 1 + wave * (isWidget ? 0.20 : 0.38)
    }
}

enum DockPanelMotion {
    static func scale(visible: Bool, style: DockAnimationStyle) -> CGFloat {
        style == .grow && !visible ? 0.94 : 1
    }
    static func duration(visible: Bool, enabled: Bool, reduceMotion: Bool) -> Double {
        enabled && !reduceMotion ? (visible ? 0.20 : 0.14) : 0
    }
    static func transitionFrame(from frame: NSRect, position: DockPosition, style: DockAnimationStyle) -> NSRect {
        switch style {
        case .fade: return frame
        case .slide: return hiddenFrame(from: frame, position: position)
        case .grow: return frame
        }
    }
    static func hiddenFrame(from frame: NSRect, position: DockPosition) -> NSRect {
        switch position {
        case .bottom: frame.offsetBy(dx: 0, dy: -8)
        case .left: frame.offsetBy(dx: -8, dy: 0)
        case .right: frame.offsetBy(dx: 8, dy: 0)
        }
    }
}

/// Visual identity is separate from persistence identity: sharing an app or
/// widget across profiles should transform one physical tile. Repeated items
/// remain distinct and never collide in matched-geometry namespaces.
struct DockVisualItem: Identifiable {
    let item: DockItem
    let id: String
}

enum DockVisualIdentity {
    static func items(_ items: [DockItem]) -> [DockVisualItem] {
        var occurrences: [String: Int] = [:]
        return items.map { item in
            let base = item.type.rawValue + ":" + (item.bundleIdentifier ?? item.url?.absoluteString ?? item.widgetKind ?? item.title)
            let occurrence = occurrences[base, default: 0]
            occurrences[base] = occurrence + 1
            return DockVisualItem(item: item, id: base + ":" + String(occurrence))
        }
    }
}
