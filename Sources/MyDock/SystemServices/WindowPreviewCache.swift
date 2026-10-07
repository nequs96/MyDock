import AppKit
import CryptoKit
import Foundation

struct CachedWindowPreview {
    var image: NSImage
    var storedAt: Date
}

/// A disk entry belongs to one native window for one run of its app: the key includes the app's launch
/// date and the window's AX object, so a later window that reuses a common title ("Untitled", "New Tab")
/// never shows an earlier window's screenshot. Previews therefore do not survive an app relaunch.
enum WindowPreviewCacheIdentity {
    private struct TitleKey: Hashable {
        var bundleIdentifier: String
        var installationPath: String
        var lifetime: String
        var window: String
        var title: String
    }

    static func uniqueKeys(for descriptors: [DockWindowDescriptor]) -> [String: String] {
        let keyedDescriptors = descriptors.compactMap { descriptor -> (DockWindowDescriptor, TitleKey)? in
            let bundleIdentifier = descriptor.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = normalizedTitle(descriptor.identityTitle)
            guard !bundleIdentifier.isEmpty, !title.isEmpty else { return nil }
            let lifetime = descriptor.applicationIdentity?.launchDate.map { String($0.timeIntervalSince1970) } ?? ""
            let window = descriptor.accessibilityObservation.map { String($0.nativeHash) } ?? ""
            return (descriptor, TitleKey(bundleIdentifier: bundleIdentifier,
                                         installationPath: descriptor.applicationIdentity.map { InstalledApplicationIdentity.normalizedURL($0.bundleURL).path } ?? "",
                                         lifetime: lifetime, window: window, title: title))
        }
        let counts = Dictionary(grouping: keyedDescriptors, by: \.1).mapValues(\.count)
        let idCounts = Dictionary(grouping: keyedDescriptors, by: { $0.0.id }).mapValues(\.count)
        var result: [String: String] = [:]
        for (descriptor, key) in keyedDescriptors {
            guard counts[key] == 1, idCounts[descriptor.id] == 1 else { continue }
            let identity = "\(Product.bundleIdentifier).window-preview.v3\n\(key.bundleIdentifier)\n\(key.installationPath)\n\(key.lifetime)\n\(key.window)\n\(key.title)"
            let digest = SHA256.hash(data: Data(identity.utf8))
                .map { String(format: "%02x", $0) }
                .joined()
            result[descriptor.id] = digest
        }
        return result
    }

    private static func normalizedTitle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }
}

@MainActor
final class WindowPreviewDiskCache {
    static let maximumAge: TimeInterval = 24 * 60 * 60
    static let maximumEntryCount = 100
    static let maximumTotalBytes = 20 * 1024 * 1024
    private static let maximumEntryBytes = 512 * 1024

    private let directoryURL: URL
    private let now: () -> Date
    private let maximumAge: TimeInterval
    private let maximumEntryCount: Int
    private let maximumTotalBytes: Int

    init(directoryURL: URL = WindowPreviewDiskCache.defaultDirectory,
         now: @escaping () -> Date = { .now },
         maximumAge: TimeInterval = WindowPreviewDiskCache.maximumAge,
         maximumEntryCount: Int = WindowPreviewDiskCache.maximumEntryCount,
         maximumTotalBytes: Int = WindowPreviewDiskCache.maximumTotalBytes) {
        self.directoryURL = directoryURL
        self.now = now
        self.maximumAge = maximumAge
        self.maximumEntryCount = maximumEntryCount
        self.maximumTotalBytes = maximumTotalBytes
        prepareDirectory()
        prune()
    }

    func pruneExpired() {
        prepareDirectory()
        prune()
    }

    func image(for key: String) -> NSImage? {
        preview(for: key)?.image
    }

    func preview(for key: String) -> CachedWindowPreview? {
        guard isValidKey(key) else { return nil }
        let url = fileURL(for: key)
        let referenceNow = now()
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              referenceNow.timeIntervalSince(modified) >= 0,
              referenceNow.timeIntervalSince(modified) <= maximumAge,
              let byteCount = attributes[.size] as? NSNumber,
              byteCount.intValue > 0,
              byteCount.intValue <= Self.maximumEntryBytes,
              let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return CachedWindowPreview(image: image, storedAt: modified)
    }

    func store(_ image: NSImage, for key: String) {
        guard isValidKey(key), let data = Self.jpegData(from: image),
              !data.isEmpty, data.count <= Self.maximumEntryBytes else { return }
        prepareDirectory()
        let url = fileURL(for: key)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            prune()
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func removeAll() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private func prune() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let referenceNow = now()
        let cutoff = referenceNow.addingTimeInterval(-maximumAge)
        var entries: [(url: URL, modified: Date, size: Int)] = []
        for url in urls {
            guard isValidKey(url.deletingPathExtension().lastPathComponent),
                  url.pathExtension == "jpg",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate,
                  modified <= referenceNow,
                  let size = values.fileSize,
                  size > 0,
                  size <= Self.maximumEntryBytes,
                  modified >= cutoff else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            entries.append((url, modified, size))
        }

        entries.sort { $0.modified > $1.modified }
        var retainedBytes = 0
        for (index, entry) in entries.enumerated() {
            let withinCount = index < maximumEntryCount
            let withinBytes = retainedBytes + entry.size <= maximumTotalBytes
            if withinCount && withinBytes {
                retainedBytes += entry.size
            } else {
                try? FileManager.default.removeItem(at: entry.url)
            }
        }
    }

    private func prepareDirectory() {
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
        } catch {
            // A failed cache setup falls back to app icons without affecting window management.
        }
    }

    private func fileURL(for key: String) -> URL {
        directoryURL.appendingPathComponent(key, isDirectory: false).appendingPathExtension("jpg")
    }

    private func isValidKey(_ key: String) -> Bool {
        key.utf8.count == 64 && key.utf8.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0)
        }
    }

    private static func jpegData(from image: NSImage) -> Data? {
        var bounds = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        return representation.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }

    static var defaultDirectory: URL {
        AppRuntimeEnvironment.windowPreviewDirectory
    }
}
