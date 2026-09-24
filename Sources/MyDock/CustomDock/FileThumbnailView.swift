import AppKit
import QuickLookThumbnailing
import SwiftUI

@MainActor
private final class DockFileThumbnailModel: ObservableObject {
    @Published private(set) var image: NSImage?
    private var currentKey: String?
    private static let cache = NSCache<NSString, NSImage>()

    func load(url: URL, size: CGFloat) {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.standardizedFileURL.path)|\(modified)"
        guard key != currentKey else { return }
        currentKey = key
        image = Self.cache.object(forKey: key as NSString)
        guard image == nil else { return }

        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: size * 2, height: size * 2),
                                                   scale: 1,
                                                   representationTypes: .thumbnail)
        Task { [weak self] in
            guard let self else { return }
            do {
                let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
                guard self.currentKey == key else { return }
                let thumbnail = representation.nsImage
                Self.cache.setObject(thumbnail, forKey: key as NSString)
                self.image = thumbnail
            } catch {
                // Keep the Launch Services icon when Quick Look has no preview.
            }
        }
    }
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
        .task(id: item.url?.path) {
            guard let url = item.url else { return }
            model.load(url: url, size: size)
        }
        .accessibilityLabel(item.title)
    }
}
