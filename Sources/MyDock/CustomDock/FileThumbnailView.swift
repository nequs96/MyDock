import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Magnification changes the tile size by fractions of a pixel. A few resolution buckets keep Retina detail while the
/// thumbnail task restarts only when the bucket changes, not on every magnification frame.
enum DockFileThumbnailBucket {
    static func pixelSize(for size: CGFloat) -> Int { [128, 256, 512].first { CGFloat($0) >= size * 2 } ?? 512 }
}

@MainActor
private final class DockFileThumbnailModel: ObservableObject {
    @Published private(set) var image: NSImage?
    /// Path and pixel bucket of the current request; the modification date joins the cache key off the main actor.
    private var currentIdentity: String?
    private var currentPath: String?
    private var request: QLThumbnailGenerator.Request?
    private var thumbnailTask: Task<Void, Never>?
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    func load(url: URL, pixelSize: Int) {
        let path = url.standardizedFileURL.path
        let identity = "\(path)|\(pixelSize)"
        guard identity != currentIdentity else { return }
        cancel()
        // A new size of the same file keeps the current thumbnail until the sharper one is ready.
        if currentPath != path { image = nil }
        currentPath = path
        currentIdentity = identity

        thumbnailTask = Task { [weak self] in
            // The file-system read can block on a slow volume, so it runs off the main actor.
            let modified = await Task.detached(priority: .utility) {
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
            }.value
            guard !Task.isCancelled, let self, self.currentIdentity == identity else { return }
            let key = "\(identity)|\(modified)"
            if let cached = Self.cache.object(forKey: key as NSString) {
                self.image = cached
                self.thumbnailTask = nil
                return
            }
            let request = QLThumbnailGenerator.Request(fileAt: url,
                                                       size: CGSize(width: pixelSize, height: pixelSize),
                                                       scale: 1,
                                                       representationTypes: .thumbnail)
            self.request = request
            do {
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled, self.currentIdentity == identity else { return }
                let thumbnail = representation.nsImage
                Self.cache.setObject(thumbnail, forKey: key as NSString, cost: pixelSize * pixelSize * 4)
                self.image = thumbnail
                self.request = nil
                self.thumbnailTask = nil
            } catch {
                // Keep the Launch Services icon when Quick Look has no preview.
            }
        }
    }

    func cancel() {
        thumbnailTask?.cancel()
        thumbnailTask = nil
        if let request { QLThumbnailGenerator.shared.cancel(request) }
        request = nil
        currentIdentity = nil
    }

    deinit { thumbnailTask?.cancel() }
}

struct DockFileThumbnailView: View {
    var item: DockItem
    var size: CGFloat
    @StateObject private var model = DockFileThumbnailModel()

    var body: some View {
        Group {
            if let image = model.image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(nsImage: AppLauncher.icon(for: item, size: size)).resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .task(id: "\(item.url?.standardizedFileURL.path ?? "")|\(DockFileThumbnailBucket.pixelSize(for: size))") {
            guard let url = item.url else { return }
            model.load(url: url, pixelSize: DockFileThumbnailBucket.pixelSize(for: size))
        }
        .accessibilityLabel(item.title)
        .onDisappear { model.cancel() }
    }
}

enum CalendarAppIconPolicy {
    static let bundleIdentifier = "com.apple.iCal"

    static func requiresDateRefresh(_ item: DockItem) -> Bool {
        guard item.type == .application else { return false }
        // The saved identifier answers without reading the bundle; only an item saved without one reads it.
        if let identifier = item.bundleIdentifier, !identifier.isEmpty { return identifier == bundleIdentifier }
        return item.url.flatMap(Bundle.init(url:))?.bundleIdentifier == bundleIdentifier
    }
}

struct DockApplicationIconView: View {
    var item: DockItem
    var size: CGFloat

    var body: some View {
        // Decided once per render: the policy may read the bundle for an item saved without an identifier.
        let isCalendar = CalendarAppIconPolicy.requiresDateRefresh(item)
        Group {
            if isCalendar {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    icon(isCalendar: true).accessibilityLabel("Calendar, \(context.date.formatted(date: .complete, time: .omitted))")
                }
            } else {
                icon(isCalendar: false).accessibilityLabel(item.displayName)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private func icon(isCalendar: Bool) -> some View {
        if isCalendar,
           let running = NSRunningApplication.runningApplications(withBundleIdentifier: CalendarAppIconPolicy.bundleIdentifier).first,
           let runningIcon = running.icon {
            Image(nsImage: resized(runningIcon)).resizable().scaledToFit()
        } else {
            Image(nsImage: AppLauncher.icon(for: item, size: size)).resizable().scaledToFit()
        }
    }

    private func resized(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}
