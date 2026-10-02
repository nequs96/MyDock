import AppKit

@MainActor
enum AppLauncher {
    private static let icons: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.countLimit = 256; return cache }()
    static func resolvedURL(for item: DockItem) -> URL? {
        // Keep the selected installed copy/version. Bundle-ID resolution is a
        // relocation fallback, never a reason to substitute another live bundle.
        if item.type == .application, let saved = item.url,
           FileManager.default.fileExists(atPath: saved.path) { return saved }
        if item.type == .application, let identifier = item.bundleIdentifier,
           let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           InstalledAppCatalog.validatedApplication(at: installed) != nil { return installed }
        return item.url
    }

    static func isMissingTarget(_ item: DockItem) -> Bool {
        guard [.application, .folder, .file].contains(item.type) else { return false }
        guard let url = resolvedURL(for: item), url.isFileURL else { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    static func open(_ item: DockItem) {
        guard let url = resolvedURL(for: item), !isMissingTarget(item) else {
            showFailure("The saved location for \(item.displayName) is unavailable. Use Locate… in its Dock menu to choose its current location.")
            return
        }
        if item.type == .application {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                guard let error else { return }
                Task { @MainActor in showFailure("Could not open \(item.displayName): \(error.localizedDescription)") }
            }
        } else if !NSWorkspace.shared.open(url) {
            showFailure("macOS could not open \(item.displayName). Check the file, address, and its access permissions.")
        }
    }

    static func chooseReplacement(for item: DockItem) -> DockItem? {
        let panel = NSOpenPanel()
        panel.title = "Locate \(item.displayName)"
        panel.prompt = "Use Location"
        panel.canChooseDirectories = item.type == .folder
        panel.canChooseFiles = item.type != .folder
        panel.allowsMultipleSelection = false
        if item.type == .application { panel.allowedContentTypes = [.applicationBundle] }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        var repaired = item
        repaired.url = url
        if item.type == .application { repaired.bundleIdentifier = Bundle(url: url)?.bundleIdentifier }
        return repaired
    }

    private static func showFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could not open item"
        alert.informativeText = message
        alert.runModal()
    }

    static func icon(for item: DockItem, size: CGFloat = 48) -> NSImage {
        if item.type == .link {
            let image: NSImage
            if let symbol = item.linkIcon,
               let chosen = NSImage(systemSymbolName: symbol.rawValue, accessibilityDescription: item.title) { image = chosen }
            else if let data = item.linkFaviconData, let favicon = NSImage(data: data) { image = favicon }
            else { image = NSImage(systemSymbolName: "globe", accessibilityDescription: item.title) ?? NSImage() }
            image.size = NSSize(width: size, height: size)
            return image
        }
        if let url = resolvedURL(for: item), url.isFileURL {
            let day = item.bundleIdentifier == "com.apple.iCal" ? String(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0) : ""
            let key = "\(url.path)|\(size)|\(day)" as NSString
            if let cached = icons.object(forKey: key) { return cached }
            let original = NSWorkspace.shared.icon(forFile: url.path)
            let icon = original.copy() as? NSImage ?? original
            icon.size = NSSize(width: size, height: size)
            icons.setObject(icon, forKey: key)
            return icon
        }
        let symbol = item.type == .widget ? "square.grid.2x2" : "questionmark.app"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title) ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        return image
    }
}
