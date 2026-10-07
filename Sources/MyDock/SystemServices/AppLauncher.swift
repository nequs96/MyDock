import AppKit

@MainActor
enum AppLauncher {
    private static let icons: NSCache<NSString, NSImage> = { let cache = NSCache<NSString, NSImage>(); cache.countLimit = 256; return cache }()
    private struct IconTargetKey: Hashable {
        var type: DockItemType
        var url: URL?
        var bundleIdentifier: String?
    }
    /// Tile bodies ask for icons at frame rate during magnification; resolving the target (a stat, and for a
    /// moved app Launch Services plus two file reads) once every couple of seconds is enough for an icon.
    private static var iconTargets: [IconTargetKey: (url: URL?, resolvedAt: Date)] = [:]
    static let iconTargetLifetime: TimeInterval = 2

    static func iconTargetURL(for item: DockItem, now: Date = .now) -> URL? {
        let key = IconTargetKey(type: item.type, url: item.url, bundleIdentifier: item.bundleIdentifier)
        if let cached = iconTargets[key], now.timeIntervalSince(cached.resolvedAt) >= 0,
           now.timeIntervalSince(cached.resolvedAt) < iconTargetLifetime { return cached.url }
        let url = resolvedURL(for: item)
        if iconTargets.count >= 512 { iconTargets.removeAll(keepingCapacity: true) }
        iconTargets[key] = (url, now)
        return url
    }
    static func resolvedURL(for item: DockItem) -> URL? {
        // Keep the selected installed copy/version. Bundle-ID resolution is a
        // relocation fallback, never a reason to substitute another live bundle.
        if item.type == .application, let saved = item.url,
           FileManager.default.fileExists(atPath: saved.path) { return saved }
        if AppRuntimeEnvironment.allowsNativeEffects, item.type == .application, let identifier = item.bundleIdentifier,
           let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
           InstalledAppCatalog.validatedApplication(at: installed) != nil { return installed }
        return item.url
    }

    static func isMissingTarget(_ item: DockItem) -> Bool {
        guard [.application, .folder, .file].contains(item.type) else { return false }
        guard let url = resolvedURL(for: item), url.isFileURL else { return true }
        return !FileManager.default.fileExists(atPath: url.path)
    }

    /// The URL a click opens. Link items are validated again here, so an address stored with a scheme other
    /// than http or https (an edited or older profiles file) never opens whichever handler macOS assigns.
    static func openTarget(for item: DockItem) -> URL? {
        guard let url = resolvedURL(for: item), !isMissingTarget(item) else { return nil }
        guard item.type == .link else { return url }
        return DockLinkPolicy.validatedURL(url.absoluteString)
    }

    static func open(_ item: DockItem) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let title = "Could not open \(item.displayName)"
        guard let url = openTarget(for: item) else {
            showFailure(title, item.type == .link
                ? "Only web addresses that start with http or https can be opened. Edit the link and try again."
                : "Its saved location is unavailable. Use Locate… in its Dock menu to choose its current location.")
            return
        }
        if item.type == .application {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in
                guard let error else { return }
                Task { @MainActor in showFailure(title, error.localizedDescription) }
            }
        } else if !NSWorkspace.shared.open(url) {
            showFailure(title, "Check the file or address and its access permissions.")
        }
    }

    static func runningApplication(for item: DockItem) -> NSRunningApplication? {
        guard AppRuntimeEnvironment.allowsNativeEffects, item.type == .application, let url = resolvedURL(for: item) else { return nil }
        let matches = NSWorkspace.shared.runningApplications.filter {
            !$0.isTerminated && $0.bundleURL.map(InstalledApplicationIdentity.normalizedURL) == InstalledApplicationIdentity.normalizedURL(url)
        }
        // Multiple processes from one installed copy require an explicit choice.
        return matches.count == 1 ? matches[0] : nil
    }

    static func identity(for app: NSRunningApplication) -> NativeApplicationIdentity? {
        NativeApplicationIdentity.observing(app)
    }

    static func runningIdentity(for item: DockItem) -> NativeApplicationIdentity? {
        runningApplication(for: item).flatMap { identity(for: $0) }
    }

    static func quit(_ identity: NativeApplicationIdentity) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        guard let app = NSRunningApplication(processIdentifier: identity.processID),
              let current = self.identity(for: app), identity.matches(current) else {
            showFailure(staleInstanceTitle, staleInstanceMessage)
            return
        }
        // terminate() requests normal Quit. It does not prove exit or reveal the
        // outcome of another app's unsaved-document prompt. Never force terminate.
        if !app.terminate() {
            showFailure("Could not quit \(app.localizedName ?? identity.bundleIdentifier)", "Open the app and choose Quit from its menu.")
        }
    }

    /// Opens dropped files or addresses with the application tile they were dropped on.
    static func open(_ urls: [URL], with item: DockItem) {
        guard AppRuntimeEnvironment.allowsNativeEffects, item.type == .application, !urls.isEmpty else { return }
        let name = item.displayName
        guard let applicationURL = resolvedURL(for: item), !isMissingTarget(item) else {
            showFailure("Could not open \(name)", "Its saved location is unavailable. Use Locate… in its Dock menu to choose its current location.")
            return
        }
        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            guard let error else { return }
            Task { @MainActor in showFailure("Could not open the items with \(name)", error.localizedDescription) }
        }
    }

    /// The observed running instance, only while it is still the one the menu captured.
    private static func validatedApplication(_ identity: NativeApplicationIdentity) -> NSRunningApplication? {
        guard AppRuntimeEnvironment.allowsNativeEffects,
              let app = NSRunningApplication(processIdentifier: identity.processID),
              let current = self.identity(for: app), identity.matches(current) else { return nil }
        return app
    }

    static func isHidden(_ identity: NativeApplicationIdentity) -> Bool {
        validatedApplication(identity)?.isHidden ?? false
    }

    static func toggleHidden(_ identity: NativeApplicationIdentity) {
        guard let app = validatedApplication(identity) else {
            showFailure(staleInstanceTitle, staleInstanceMessage)
            return
        }
        if app.isHidden { _ = app.unhide() } else { _ = app.hide() }
    }

    static func showInFinder(_ identity: NativeApplicationIdentity) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        NSWorkspace.shared.activateFileViewerSelecting([identity.bundleURL])
    }

    /// Force Quit never runs without the person confirming this alert. Cancel is the default button.
    static func forceQuit(_ identity: NativeApplicationIdentity) {
        guard let app = validatedApplication(identity) else {
            showFailure(staleInstanceTitle, staleInstanceMessage)
            return
        }
        let name = app.localizedName ?? identity.bundleIdentifier
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = RunningApplicationMenuPolicy.forceQuitTitle(name: name)
        alert.informativeText = RunningApplicationMenuPolicy.forceQuitMessage
        alert.addButton(withTitle: "Cancel")
        let force = alert.addButton(withTitle: "Force Quit")
        force.hasDestructiveAction = true
        guard DockModal.run(alert) == .alertSecondButtonReturn, let current = validatedApplication(identity) else { return }
        if !current.forceTerminate() {
            showFailure("Could not force quit \(name)", "It may have quit already.")
        }
    }

    static func chooseReplacement(for item: DockItem) -> DockItem? {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return nil }
        let panel = NSOpenPanel()
        panel.title = "Locate \(item.displayName)"
        panel.prompt = "Use Location"
        panel.canChooseDirectories = item.type == .folder
        panel.canChooseFiles = item.type != .folder
        panel.allowsMultipleSelection = false
        if item.type == .application { panel.allowedContentTypes = [.applicationBundle] }
        guard DockModal.run(panel) == .OK, let url = panel.url else { return nil }
        var repaired = item
        repaired.url = url
        if item.type == .application { repaired.bundleIdentifier = Bundle(url: url)?.bundleIdentifier }
        return repaired
    }

    private static let staleInstanceTitle = "App is no longer running"
    private static let staleInstanceMessage = "It quit or restarted. Open its current menu and try again."

    private static func showFailure(_ title: String, _ message: String) {
        guard AppRuntimeEnvironment.allowsNativeEffects else { return }
        let alert = NSAlert()
        alert.messageText = title
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
        if let url = iconTargetURL(for: item), url.isFileURL {
            let day = item.bundleIdentifier == "com.apple.iCal" ? String(Calendar.current.ordinality(of: .day, in: .era, for: .now) ?? 0) : ""
            // Cache the source image, not every fractional size during a resize.
            let key = "\(url.path)|\(day)" as NSString
            let original: NSImage
            if let cached = icons.object(forKey: key) { original = cached }
            else { original = NSWorkspace.shared.icon(forFile: url.path); icons.setObject(original, forKey: key) }
            let icon = original.copy() as? NSImage ?? original
            icon.size = NSSize(width: size, height: size)
            return icon
        }
        let symbol = item.type == .widget ? "square.grid.2x2" : "questionmark.app"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: item.title) ?? NSImage(size: NSSize(width: size, height: size))
        image.size = NSSize(width: size, height: size)
        return image
    }
}
