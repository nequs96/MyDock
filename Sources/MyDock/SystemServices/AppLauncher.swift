import AppKit

@MainActor
enum AppLauncher {
    static func isMissingTarget(_ item: DockItem) -> Bool {
        guard [.application, .folder, .file].contains(item.type) else { return false }
        guard let url = item.url, url.isFileURL else { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    static func open(_ item: DockItem) {
        guard let url = item.url else { return }
        NSWorkspace.shared.open(url)
    }

    static func icon(for item: DockItem, size: CGFloat = 48) -> NSImage {
        if item.type == .link, let linkIcon = item.linkIcon,
           let image = NSImage(systemSymbolName: linkIcon.rawValue, accessibilityDescription: item.title) {
            image.size = NSSize(width: size, height: size)
            return image
        }
        if item.type == .link, let iconData = item.linkFaviconData,
           let image = NSImage(data: iconData) {
            image.size = NSSize(width: size, height: size)
            return image
        }
        if let url = item.url {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: size, height: size)
            return icon
        }
        let symbol = item.type == .widget ? "square.grid.2x2" : "questionmark.app"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title) ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        return image
    }
}
