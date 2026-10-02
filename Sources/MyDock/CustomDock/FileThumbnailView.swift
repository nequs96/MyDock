import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
private final class DockFileThumbnailModel: ObservableObject {
    @Published private(set) var image: NSImage?
    private var currentKey: String?
    private var request: QLThumbnailGenerator.Request?
    private var thumbnailTask: Task<Void, Never>?
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 32 * 1_024 * 1_024
        return cache
    }()

    func load(url: URL, size: CGFloat) {
        // Magnification changes by pixels. A few resolution buckets avoid a
        // Quick Look request for every frame while retaining Retina detail.
        let pixelSize = [128, 256, 512].first { CGFloat($0) >= size * 2 } ?? 512
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path)|\(modified)|\(pixelSize)"
        guard key != currentKey else { return }
        cancel()
        currentKey = key
        image = Self.cache.object(forKey: key as NSString)
        guard image == nil else { return }

        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: pixelSize, height: pixelSize),
                                                   scale: 1,
                                                   representationTypes: .thumbnail)
        self.request = request
        thumbnailTask = Task { [weak self] in
            do {
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard !Task.isCancelled, let self, self.currentKey == key else { return }
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
        currentKey = nil
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
        .task(id: "\(item.url?.standardizedFileURL.path ?? "")|\(max(1, Int((size * 2).rounded(.up))))") {
            guard let url = item.url else { return }
            model.load(url: url, size: size)
        }
        .accessibilityLabel(item.title)
        .onDisappear { model.cancel() }
    }
}

enum CalendarAppIconPolicy {
    static let bundleIdentifier = "com.apple.iCal"

    static func requiresDateRefresh(_ item: DockItem) -> Bool {
        guard item.type == .application else { return false }
        if item.bundleIdentifier == bundleIdentifier { return true }
        return item.url.flatMap(Bundle.init(url:))?.bundleIdentifier == bundleIdentifier
    }
}

struct DockApplicationIconView: View {
    var item: DockItem
    var size: CGFloat

    var body: some View {
        Group {
            if CalendarAppIconPolicy.requiresDateRefresh(item) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    icon.accessibilityLabel("Calendar, \(context.date.formatted(date: .complete, time: .omitted))")
                }
            } else {
                icon.accessibilityLabel(item.displayName)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var icon: some View {
        if CalendarAppIconPolicy.requiresDateRefresh(item),
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
