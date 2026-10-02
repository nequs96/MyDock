import AppKit
import Foundation

struct InstalledApplication: Identifiable, Sendable {
    var url: URL
    var bundleIdentifier: String
    var name: String
    var version: String
    var iconData: Data?
    var id: String { url.path }

    var dockItem: DockItem {
        var item = DockItem.application(at: url)
        item.title = name
        item.bundleIdentifier = bundleIdentifier
        return item
    }
}

struct InstalledAppScan: Sendable {
    var applications: [InstalledApplication]
    var unreadableLocations: Int = 0
}

/// Filesystem inventory, never Launch Services' historical registrations. Package
/// boundaries and a depth/entry budget keep helpers and support trees out of browse.
enum InstalledAppCatalog {
    static var searchRoots: [URL] {
        var roots = FileManager.default.urls(for: .applicationDirectory, in: [.userDomainMask, .localDomainMask, .systemDomainMask])
        roots += [URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Library/CoreServices/Applications")]
        return roots
    }

    static func load() async -> [DockItem] {
        (await scan()).applications.map(\.dockItem)
    }

    static func scan() async -> InstalledAppScan {
        let roots = searchRoots
        let finder = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        let worker = Task.detached(priority: .userInitiated) { discover(roots: roots, additionalURLs: [finder].compactMap { $0 }) }
        return await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
    }

    static func validatedApplication(at candidate: URL) -> InstalledApplication? {
        let fm = FileManager.default
        guard candidate.isFileURL else { return nil }
        let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
        guard url.pathExtension.lowercased() == "app",
              !url.pathComponents.dropLast().contains(where: { ["app", "xpc", "appex", "bundle", "plugin", "framework"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }),
              let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey, .isAliasFileKey]),
              values.isDirectory == true, values.isReadable == true, values.isAliasFile != true,
              fm.isReadableFile(atPath: url.path),
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundlePackageType"] as? String == "APPL",
              let identifier = info["CFBundleIdentifier"] as? String, !identifier.trimmingCharacters(in: .whitespaces).isEmpty,
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty,
              !executable.contains("/"), executable != ".", executable != "..",
              !flag(info["LSBackgroundOnly"]), !flag(info["LSUIElement"]) else { return nil }
        let executableURL = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
        guard let executableValues = try? executableURL.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]),
              executableValues.isRegularFile == true, executableValues.isReadable == true,
              fm.isExecutableFile(atPath: executableURL.path), supportsCurrentMac(executableURL) else { return nil }
        // Classic and obsolete architecture-only remnants cannot run on this Mac.
        if flag(info["LSRequiresClassic"]) { return nil }
        let names = [info["CFBundleDisplayName"] as? String, info["CFBundleName"] as? String]
        guard let name = names.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }).first(where: { !$0.isEmpty }) else { return nil }
        return InstalledApplication(url: url, bundleIdentifier: identifier, name: name,
                                    version: info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "")
    }

    private static func supportsCurrentMac(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512), data.count >= 8 else { return false }
        func word(_ offset: Int, little: Bool = false) -> UInt32 {
            guard offset + 4 <= data.count else { return 0 }
            let bytes = Array(data[offset..<(offset + 4)])
            return (little ? Array(bytes.reversed()) : bytes).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        func supported(_ cpu: UInt32) -> Bool {
            #if arch(arm64)
            return cpu == 0x0100000c || cpu == 0x01000007
            #else
            return cpu == 0x01000007
            #endif
        }
        let magic = word(0)
        if magic == 0xcffaedfe { return supported(word(4, little: true)) }
        if magic == 0xfeedfacf { return supported(word(4)) }
        if magic == 0xcafebabe || magic == 0xcafebabf {
            let count = min(20, Int(word(4)))
            let stride = magic == 0xcafebabf ? 32 : 20
            return (0..<count).contains { supported(word(8 + $0 * stride)) }
        }
        return false
    }

    private static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String { return ["true", "yes", "1"].contains(string.lowercased()) }
        return false
    }

    static func discover(roots: [URL], additionalURLs: [URL] = [], loadIcons: Bool = false) -> InstalledAppScan {
        let fm = FileManager.default
        var candidates = additionalURLs
        var seenRoots = Set<String>()
        var unreadable = 0
        var remaining = 8_000
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isAliasFileKey]
        func visit(_ root: URL, depth: Int) {
            guard !Task.isCancelled, remaining > 0 else { return }
            guard fm.fileExists(atPath: root.path) else { return }
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: .skipsHiddenFiles) else { unreadable += 1; return }
            for child in children.sorted(by: { $0.path < $1.path }) {
                guard !Task.isCancelled, remaining > 0 else { return }
                remaining -= 1
                if child.pathExtension.lowercased() == "app" { candidates.append(child); continue }
                guard depth < 3, let v = try? child.resourceValues(forKeys: keys),
                      v.isDirectory == true, v.isPackage != true, v.isSymbolicLink != true, v.isAliasFile != true else { continue }
                // These are resources, not application installation directories.
                if ["support", "application support", "scripts", "scripting.localized", "plug-ins", "plugins", "resources", "frameworks", "installers"].contains(child.lastPathComponent.lowercased()) { continue }
                visit(child, depth: depth + 1)
            }
        }
        for root in roots where seenRoots.insert(root.standardizedFileURL.resolvingSymlinksInPath().path).inserted { visit(root, depth: 0) }
        var paths = Set<String>()
        var products = Set<String>()
        var applications: [InstalledApplication] = []
        for candidate in candidates {
            guard !Task.isCancelled else { break }
            guard var app = validatedApplication(at: candidate), paths.insert(app.url.path).inserted else { continue }
            // Preserve distinct versions, prefer the first standard installation for
            // identical ID/version copies. Never deduplicate unrelated display names.
            guard products.insert(app.bundleIdentifier + "|" + app.version).inserted else { continue }
            if loadIcons {
                app.iconData = InstalledApplicationIconLoader.load(at: app.url)
            }
            applications.append(app)
        }
        applications.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return InstalledAppScan(applications: applications, unreadableLocations: unreadable)
    }
}

/// Load only visible icons, at the browser's Retina size. NSWorkspace documents
/// icon(forFile:) as thread-safe; no full-resolution TIFF archive crosses actors.
enum InstalledApplicationIconLoader {
    // NSCache synchronizes concurrent reads/writes internally.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>(); cache.countLimit = 256; return cache
    }()
    static func load(at url: URL) -> Data? {
        guard !Task.isCancelled, InstalledAppCatalog.validatedApplication(at: url) != nil else { return nil }
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)" as NSString
        if let data = cache.object(forKey: key) { return data as Data }
        let data: Data? = autoreleasepool {
            var rect = NSRect(x: 0, y: 0, width: 64, height: 64)
            guard let source = NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: &rect, context: nil, hints: nil),
                  let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            guard let image = context.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        }
        if let data, !Task.isCancelled { cache.setObject(data as NSData, forKey: key) }
        return data
    }
}
