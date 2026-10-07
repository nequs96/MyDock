#if DEBUG
import AppKit
import SwiftUI

/// Development-only, deterministic render matrix. Uses the same views as the app
/// with an isolated ProfileStore; never starts the user's Dock or native controllers.
@MainActor
enum PremiumVisualQA {
    static let semanticLayoutPageSize = 10

    /// Registry-derived pages for the semantic layout export, so new families cannot be omitted.
    static func semanticLayoutPages(kinds: [String] = WidgetRegistry.all.map(\.name), pageSize: Int = semanticLayoutPageSize) -> [[String]] {
        let size = max(1, pageSize)
        return stride(from: 0, to: kinds.count, by: size).map { Array(kinds[$0..<min($0 + size, kinds.count)]) }
    }

    /// A fixed application list for Add Item renders. The paths are apps every supported macOS ships;
    /// renders never scan, show or export the inventory of the Mac they run on.
    static var fixtureAppScan: InstalledAppScan {
        let apps: [(String, String, String)] = [
            ("Calculator", "com.apple.calculator", "/System/Applications/Calculator.app"),
            ("Calendar", "com.apple.iCal", "/System/Applications/Calendar.app"),
            ("Finder", "com.apple.finder", "/System/Library/CoreServices/Finder.app"),
            ("Maps", "com.apple.Maps", "/System/Applications/Maps.app"),
            ("Music", "com.apple.Music", "/System/Applications/Music.app"),
            ("Notes", "com.apple.Notes", "/System/Applications/Notes.app"),
            ("Photos", "com.apple.Photos", "/System/Applications/Photos.app"),
            ("Reminders", "com.apple.reminders", "/System/Applications/Reminders.app"),
            ("TextEdit", "com.apple.TextEdit", "/System/Applications/TextEdit.app"),
        ]
        return InstalledAppScan(applications: apps.map {
            InstalledApplication(url: URL(fileURLWithPath: $0.2), bundleIdentifier: $0.1, name: $0.0, version: "1.0")
        })
    }

    private static func exportToolsUI(to directory: URL, store: ProfileStore) async throws {
        let kinds = ["File Shelf", "Text Snippets", "Quick Links", "Unit Converter", "Color Picker"]
        let file = directory.appendingPathComponent("Example.txt")
        try Data("Disposable File Shelf preview".utf8).write(to: file)
        var items = kinds.map(DockItem.widget)
        items[0].widgetConfiguration?.shelfFiles = [ShelfFile(url: file), ShelfFile(url: URL(fileURLWithPath: "/missing/Old Design.pdf"))]
        items[1].widgetConfiguration?.textSnippets = [TextSnippet(title: "A friendly reply", text: "Thanks for reaching out. I’ll take a look and get back to you tomorrow."), TextSnippet(title: "Project handoff", text: "Designs are ready for review.\nPlease leave your feedback in the project workspace.")]
        items[2].widgetConfiguration?.quickLinks = [QuickLink(title: "Project workspace", url: URL(string: "https://example.com/project")!), QuickLink(title: "Reading list", url: URL(string: "https://example.org/reading")!)]
        items[4].widgetConfiguration?.savedColors = ["#5EA3A8", "#C49961", "#CF809A", "#729DC6", "#7954AA", "#FFFFFF", "#333333"]
        let profile = DockProfile(name: "Everyday Tools", kind: .custom, items: items)
        let id = try store.createProfile(profile)
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            store.updateSettings { $0.customDockPosition = .bottom; $0.customDockWidgetStyle = .cards; $0.showRunningApps = false; $0.showTrash = false }
            try await render(AddLibrary(store: store, profile: profile, initialCategory: "Widgets", add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}), name: "tools-library-" + suffix, size: NSSize(width: 920, height: 740), scheme: scheme, directory: directory)
            try await render(VStack(alignment: .leading, spacing: 18) {
                ForEach(kinds, id: \.self) { kind in
                    HStack(spacing: 16) {
                        Text(kind).font(.caption).frame(width: 100, alignment: .leading)
                        ForEach(WidgetPresentationCatalog.options(for: kind)) { option in
                            WidgetCardPreview(kind: kind, width: option.width, layout: option.layout)
                        }
                    }
                }
            }.padding(24).background(WidgetDesign.surface), name: "tools-layouts-" + suffix, size: NSSize(width: 500, height: 430), scheme: scheme, directory: directory)
            for item in items {
                let kind = item.widgetKind!
                let name = kind.lowercased().replacingOccurrences(of: " ", with: "-")
                try await render(WidgetConfigurationSheet(store: store, item: item, profileID: id), name: "tools-configure-" + name + "-" + suffix, size: NSSize(width: 488, height: 660), scheme: scheme, directory: directory)
                try await render(WidgetPopout(store: store, item: item, profileID: id, showsCustomize: false).padding(20).background(WidgetDesign.surface), name: "tools-popout-" + name + "-" + suffix, size: NSSize(width: 460, height: 600), scheme: scheme, directory: directory)
                if ["File Shelf", "Text Snippets", "Quick Links"].contains(kind) {
                    let empty = DockItem.widget(kind)
                    try await render(WidgetPopout(store: store, item: empty, profileID: id, showsCustomize: false).padding(20).background(WidgetDesign.surface), name: "tools-empty-" + name + "-" + suffix, size: NSSize(width: 460, height: 430), scheme: scheme, directory: directory)
                }
            }
            store.updateSettings { $0.customDockPosition = .left }
            try await render(HStack(spacing: 14) {
                ForEach(items) { item in WidgetCompactView(store: store, item: item, profileID: id, sampleMode: true, presentationSettings: store.state.settings) }
            }.padding(20).background(WidgetDesign.surface), name: "tools-side-" + suffix, size: NSSize(width: 390, height: 100), scheme: scheme, directory: directory)
        }
    }

    /// The DEBUG render modes. `MYDOCK_RENDER_QA=<directory>` plus at most one of these flags set to `1`
    /// selects an exporter; no flag selects the default editor matrix.
    enum RenderMode: String, CaseIterable {
        case facesA = "MYDOCK_FACESA_QA", facesB = "MYDOCK_FACESB_QA", settings = "MYDOCK_SETTINGS_QA"
        case surfaces = "MYDOCK_SURFACES_QA", interaction = "MYDOCK_INTERACTION_QA", tools = "MYDOCK_TOOLS_QA"
        case glass = "MYDOCK_GLASS_QA", adaptive = "MYDOCK_ADAPTIVE_QA", widget = "MYDOCK_WIDGET_QA"
        case focused = "MYDOCK_FOCUSED_QA", redesign = "MYDOCK_REDESIGN_QA", dockStyle = "MYDOCK_DOCKSTYLE_QA"
        case widgetSurface = "MYDOCK_WIDGETSURFACE_QA", gallery = "MYDOCK_GALLERY_QA"
        case widgetSheet = "MYDOCK_WIDGETSHEET_QA", motion = "MYDOCK_MOTION_QA"

        /// Two flags at once would silently run only one of them, so that is an error.
        static func selected(in environment: [String: String]) throws -> RenderMode? {
            let modes = allCases.filter { environment[$0.rawValue] == "1" }
            guard modes.count <= 1 else {
                throw NSError(domain: "MyDockRenderQA", code: 3, userInfo: [NSLocalizedDescriptionKey:
                    "Set one render mode at a time, not " + modes.map(\.rawValue).joined(separator: " and ")])
            }
            return modes.first
        }
    }

    static func export(to directory: URL, store: ProfileStore) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        switch try RenderMode.selected(in: ProcessInfo.processInfo.environment) {
        case .facesA: try await exportFacesAUI(to: directory, store: store)
        case .facesB: try await exportFacesBUI(to: directory, store: store)
        case .settings: try await exportSettingsUI(to: directory, store: store)
        case .surfaces: try await exportChangedSurfacesUI(to: directory, store: store)
        case .interaction: try await exportInteractionUI(to: directory, store: store)
        case .tools: try await exportToolsUI(to: directory, store: store)
        case .glass: try await exportGlassUI(to: directory, store: store)
        case .adaptive: try await exportAdaptiveUI(to: directory, store: store)
        case .widget: try await exportWidgetUI(to: directory, store: store)
        case .focused: try await exportFocusedUI(to: directory, store: store)
        case .redesign: try await exportRedesignUI(to: directory)
        case .dockStyle: try await exportDockStyleUI(to: directory, store: store)
        case .widgetSurface: try await exportWidgetSurfaceUI(to: directory, store: store)
        case .gallery: try await exportGalleryUI(to: directory, store: store)
        case .widgetSheet: try await exportWidgetSheetUI(to: directory, store: store)
        case .motion: try await exportMotionUI(to: directory, store: store)
        case nil: try await exportEditorUI(to: directory, store: store)
        }
    }

    /// The default matrix: the Dock workspace, inspectors, Add Item, Settings, onboarding and Dock positions.
    private static func exportEditorUI(to directory: URL, store: ProfileStore) async throws {
        let names = ["System Activity", "Clock", "AI Limits"]
        let everyday = try store.createProfileAndPersist(kind: .custom, name: "Everyday")
        for bundle in ["com.apple.finder", "com.microsoft.VSCode", "com.apple.Terminal"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: everyday) }
        }
        for name in names { store.add(.widget(name), to: everyday) }
        _ = try store.createProfileAndPersist(kind: .custom, name: "Work")
        _ = try store.createProfileAndPersist(kind: .custom, name: "Minimal")
        _ = try store.createProfileAndPersist(kind: .native, name: "Essentials")
        store.activate(everyday)
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false; $0.customDockTheme = .dark }
        for (name, size) in [("small", NSSize(width: 900, height: 600)), ("medium", NSSize(width: 1160, height: 760)), ("large", NSSize(width: 1440, height: 900))] {
            try await render(DockWorkspaceView(store: store, navigation: DockWorkspaceNavigation(), onContinueSetup: {}),
                             name: "editor-dark-" + name, size: size, scheme: .dark, directory: directory)
        }
        for (name, size) in [("minimum", NSSize(width: 780, height: 600)), ("normal", NSSize(width: 1160, height: 760))] {
            try await render(DockManagerView(store: store, initialInspector: true), name: "inspector-" + name,
                             size: size, scheme: .dark, directory: directory)
        }
        if let profile = store.state.profiles.first(where: { $0.id == everyday }) {
            if let item = profile.items.first(where: { $0.type == .widget }) {
                try await render(DockManagerView(store: store, initialSelection: [item.id]), name: "editor-selected-item",
                                 size: NSSize(width: 900, height: 600), scheme: .dark, directory: directory)
            }
            let blank = try store.createProfileAndPersist(kind: .custom, name: "New Dock")
            store.activate(blank)
            try await render(DockManagerView(store: store), name: "editor-empty-dock", size: NSSize(width: 780, height: 600), scheme: .dark, directory: directory)
            store.activate(everyday)
            for (name, command, query, category) in [("add-library", false, "", "Widgets"), ("add-library-search", false, "Clock", "All"), ("add-library-empty", false, "no-match-123", "All"), ("command-palette", true, "", "All")] {
                try await render(AddLibrary(store: store, profile: profile, commandMode: command,
                                            initialQuery: query, initialCategory: category, add: { _ in }, switchProfile: { _ in },
                                            newDock: {}, settings: {}, browse: { _ in }, close: {}),
                                 name: name, size: NSSize(width: 580, height: 540), scheme: .dark, directory: directory)
            }
            let missing = DockProfile(name: "Unavailable item", kind: .custom, items: [.application(at: URL(fileURLWithPath: "/missing/MyApp.app"))])
            let missingID = try store.createProfile(missing)
            store.activate(missingID)
            try await render(DockManagerView(store: store), name: "editor-missing-item", size: NSSize(width: 900, height: 600), scheme: .dark, directory: directory)
            store.activate(everyday)
        }
        if let native = store.nativeProfiles.first {
            store.recordAppliedNativeProfile(native.id)
            store.updateSettings { $0.setupMode = .nativeOnly }
            try await render(DockManagerView(store: store), name: "editor-native-applied-empty",
                             size: NSSize(width: 780, height: 600), scheme: .dark, directory: directory)
            try await render(AddLibrary(store: store, profile: native, add: { _ in }, switchProfile: { _ in },
                                        newDock: {}, settings: {}, browse: { _ in }, close: {}),
                             name: "add-library-native", size: NSSize(width: 580, height: 540), scheme: .dark, directory: directory)
            store.updateSettings { $0.setupMode = .both }
        }
        for page in MyDockSettingsPage.allCases {
            store.updateSettings { $0.lastSettingsPage = page }
            try await render(DockManagerView(store: store, showsSettings: true),
                             name: "settings-" + page.rawValue, size: NSSize(width: 1160, height: 760), scheme: .dark, directory: directory)
            try await render(DockManagerView(store: store, showsSettings: true),
                             name: "settings-narrow-" + page.rawValue, size: NSSize(width: 780, height: 600), scheme: .dark, directory: directory)
        }
        for (name, size) in [("small", NSSize(width: 760, height: 560)), ("medium", NSSize(width: 960, height: 680)), ("large", NSSize(width: 1200, height: 800))] {
            try await render(WidgetGalleryView(add: { _, _ in }, onClose: {}), name: "gallery-" + name,
                             size: size, scheme: .dark, directory: directory)
        }
        try await render(WidgetGalleryView(add: { _, _ in }, onClose: {}), name: "gallery-minimum-height",
                         size: NSSize(width: 760, height: 480), scheme: .dark, directory: directory)
        for size in [WidgetCardWidth.compact, .wide] {
            try await render(WidgetGalleryView(add: { _, _ in }, onClose: {}, initialSize: size), name: "gallery-size-" + size.rawValue,
                             size: NSSize(width: 1040, height: 680), scheme: .dark, directory: directory)
        }
        for offset in stride(from: 0, to: WidgetRegistry.all.count, by: 6) {
            let batch = Array(WidgetRegistry.all.dropFirst(offset).prefix(6))
            try await render(VStack(alignment: .leading, spacing: 24) {
                ForEach(batch) { widget in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(widget.name).font(DockDesign.sectionTitle)
                        HStack(alignment: .top, spacing: 24) {
                            ForEach(WidgetPresentationCatalog.options(for: widget.name)) { option in
                                WidgetLibraryTile(widget: widget, layout: option.layout, showsVariantLabel: true)
                                    .frame(width: 224)
                            }
                        }
                    }
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(DockDesign.page),
                             name: "widget-catalog-\(offset / 6 + 1)", size: NSSize(width: 768, height: 1024), scheme: .dark, directory: directory)
        }
        let setupStore = ProfileStore(fileURL: directory.appendingPathComponent("setup-fixture.json"), allowsSystemChanges: false)
        for step in 0..<4 {
            try await render(OnboardingView(store: setupStore, initialStep: step, onFinish: {}), name: "onboarding-\(step + 1)", size: NSSize(width: 760, height: 600), scheme: .dark, directory: directory)
        }
        try await render(DockManagerView(store: setupStore), name: "editor-empty", size: NSSize(width: 900, height: 600), scheme: .dark, directory: directory)
        try await render(WidgetGalleryView(add: { _, _ in }, onClose: {}, initialSearch: "Calendar"), name: "gallery-search", size: NSSize(width: 960, height: 680), scheme: .dark, directory: directory)
        try await render(WidgetGalleryView(add: { _, _ in }, onClose: {}, initialSearch: "no-match-123"), name: "gallery-empty", size: NSSize(width: 760, height: 560), scheme: .dark, directory: directory)
        try await render(SettingsView(store: store, initialPage: .behavior, embeddedInWorkspace: true), name: "settings-small", size: NSSize(width: 900, height: 600), scheme: .dark, directory: directory)
        try await render(AboutView(onReplaySetup: {}), name: "about", size: NSSize(width: 420, height: 360), scheme: .dark, directory: directory)
        if let profile = store.state.profiles.first(where: { $0.id == everyday }) {
            for item in profile.items {
                guard let kind = item.widgetKind, ["Clock", "Focus Timer", "Sticky Note"].contains(kind) else { continue }
                try await render(WidgetPopout(store: store, item: item, profileID: everyday, showsCustomize: false).padding(24),
                                 name: "configure-" + kind, size: NSSize(width: 488, height: 420), scheme: .dark, directory: directory)
                try await render(WidgetConfigurationSheet(store: store, item: item, profileID: everyday, maximumHeight: 520),
                                 name: "configure-sheet-" + kind, size: NSSize(width: 488, height: 520), scheme: .dark, directory: directory)
            }
            for position in DockPosition.allCases {
                store.updateSettings { $0.customDockPosition = position }
                var draft = profile
                var appearance = ProfileAppearance(settings: store.state.settings)
                appearance.material = .dark
                appearance.size = 0.8
                draft.appearance = appearance
                try await render(DockLayoutPreview(store: store, profile: draft).padding(24), name: "dock-" + position.rawValue,
                                 size: NSSize(width: 720, height: 360), scheme: .dark, directory: directory)
            }
            store.updateSettings { $0.customDockPosition = .bottom }
            var longProfile = profile
            longProfile.items = (0..<20).map { _ in .widget("Clock") }
            try await render(DockLayoutPreview(store: store, profile: longProfile).padding(24), name: "dock-overflow",
                             size: NSSize(width: 720, height: 220), scheme: .dark, directory: directory)
        }
        try await render(DockManagerView(store: store), name: "editor-light", size: NSSize(width: 1160, height: 760), scheme: .light, directory: directory)
        try await render(SettingsView(store: store, initialPage: .behavior, embeddedInWorkspace: true), name: "settings-light", size: NSSize(width: 1160, height: 760), scheme: .light, directory: directory)
        if let profile = store.state.profiles.first(where: { $0.id == everyday }) {
            try await exportAccessibilityMatrix(store: store, profile: profile, directory: directory)
        }
    }

    private static func exportInteractionUI(to directory: URL, store: ProfileStore) async throws {
        let id = try store.createProfileAndPersist(kind: .custom, name: "Dock interactions")
        store.updateSettings {
            $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false
            $0.customDockMaterial = .liquidGlassClear; $0.customDockTintStrength = 0
        }
        for bundle in ["com.apple.finder", "com.apple.Safari"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: id) }
        }
        store.add(AIActivityPreviewData.item(), to: id); store.add(.widget("System Activity"), to: id)
        store.activate(id)
        let profile = store.state.profiles.first { $0.id == id }!
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light }
            for opacity in [0.0, 0.5, 1.0] {
                store.updateSettings { $0.customDockGlassOpacity = opacity }
                try await render(ZStack {
                    LinearGradient(colors: [.blue.opacity(0.65), .orange.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                    DockLayoutPreview(store: store, profile: profile).padding(24)
                }, name: "opacity-\(Int(opacity * 100))-\(suffix)", size: NSSize(width: 660, height: 160), scheme: scheme, directory: directory)
                try await renderTransparentDock(store: store, profile: profile, name: "opacity-\(Int(opacity * 100))-\(suffix)-corners", directory: directory)
            }
            try await render(SettingsView(store: store, initialPage: .appearance, embeddedInWorkspace: true, sidebarVisible: false), name: "navigation-appearance-\(suffix)", size: NSSize(width: 820, height: 1200), scheme: scheme, directory: directory)
            try await render(SettingsView(store: store, initialPage: .behavior, embeddedInWorkspace: true, sidebarVisible: false), name: "navigation-behavior-\(suffix)", size: NSSize(width: 820, height: 1200), scheme: scheme, directory: directory)
        }
        store.updateSettings { $0.lastSettingsPage = .appearance }
        try await render(DockManagerView(store: store, showsSettings: true), name: "navigation-minimum", size: NSSize(width: 780, height: 700), scheme: .light, directory: directory)
    }

    private static func exportGlassUI(to directory: URL, store: ProfileStore) async throws {
        let id = try store.createProfileAndPersist(kind: .custom, name: "Glass Dock preview")
        store.updateSettings {
            $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false
            $0.customDockCornerRadius = 22; $0.customDockTintStrength = 0
        }
        for bundle in ["com.apple.finder", "com.apple.Safari"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: id) }
        }
        store.add(AIActivityPreviewData.item(), to: id)
        store.add(.widget("System Activity"), to: id)
        store.activate(id)
        let profile = store.state.profiles.first { $0.id == id }!
        for scheme in [ColorScheme.dark, .light] {
            for material in [CustomDockMaterial.liquidGlassClear, .liquidGlass] {
                store.updateSettings {
                    $0.customDockMaterial = material; $0.customDockTheme = scheme == .dark ? .dark : .light
                }
                let name = "glass-\(material.rawValue)-\(scheme == .dark ? "dark" : "light")"
                try await render(ZStack {
                    LinearGradient(colors: [Color(red: 0.25, green: 0.42, blue: 0.62), Color(red: 0.60, green: 0.45, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    HStack(spacing: 40) {
                        ForEach(0..<8) { _ in Rectangle().fill(.white.opacity(0.16)).frame(width: 35).rotationEffect(.degrees(25)) }
                    }
                    DockLayoutPreview(store: store, profile: profile).padding(24)
                }, name: name, size: NSSize(width: 660, height: 160), scheme: scheme, directory: directory)
                try await renderTransparentDock(store: store, profile: profile, name: name + "-corners", directory: directory)
            }
        }
        for position in [DockPosition.left, .right] {
            store.updateSettings { $0.customDockPosition = position }
            for material in [CustomDockMaterial.liquidGlassClear, .liquidGlass] {
                store.updateSettings { $0.customDockMaterial = material }
                try await renderTransparentDock(store: store, profile: profile, name: "glass-\(material.rawValue)-\(position.rawValue)-corners", directory: directory)
            }
        }
        store.updateSettings { $0.customDockPosition = .bottom }
        for material in [CustomDockMaterial.frosted, .solid, .dark] {
            store.updateSettings { $0.customDockMaterial = material }
            try await renderTransparentDock(store: store, profile: profile, name: "glass-\(material.rawValue)-corners", directory: directory)
        }
        store.updateSettings { $0.customDockMaterial = .liquidGlass }
        try await render(DockLayoutPreview(store: store, profile: profile).padding(24), name: "glass-contrast-opaque", size: NSSize(width: 660, height: 160), scheme: .light, directory: directory, contrast: .increased, reduceTransparency: true)
        try await render(SettingsView(store: store, initialPage: .appearance), name: "glass-appearance-settings", size: NSSize(width: 1100, height: 900), scheme: .light, directory: directory)
    }

    /// Uses the production native host in a transparent, shadowless panel.
    /// Corner alpha catches a rectangular backing that a wallpaper render hides.
    private static func renderTransparentDock(store: ProfileStore, profile: DockProfile, name: String, directory: URL) async throws {
        let size = store.state.settings.customDockPosition == .bottom ? NSSize(width: 530, height: 98) : NSSize(width: 98, height: 340)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: store.state.settings.customDockTheme == .dark ? .darkAqua : .aqua)
        let host = DockSurfaceHostingView(rootView: CustomDockView(store: store, profile: profile, isPreview: true, openSettings: { _ in }).environment(\.dockSnapshotRendering, true))
        host.surfaceCornerRadius = CGFloat(store.state.settings.customDockCornerRadius)
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        var visiblePixelCount = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 8) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 8) {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 { visiblePixelCount += 1 }
            }
        }
        guard visiblePixelCount > 50 else { throw NSError(domain: "MyDockGlassQA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty corner fixture in \(name)"]) }
        for (x, y) in [(0, 0), (bitmap.pixelsWide - 1, 0), (0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
            guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent < 0.01 else {
                throw NSError(domain: "MyDockGlassQA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Opaque panel corner in \(name) at \(x),\(y)"])
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        panel.close()
    }

    private static func exportAdaptiveUI(to directory: URL, store: ProfileStore) async throws {
        let id = try store.createProfileAndPersist(kind: .custom, name: "Adaptive widget studio")
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false; $0.customDockWidgetStyle = .cards; $0.customDockItemSpacing = 9 }
        for bundle in ["com.apple.finder", "com.apple.Safari", "com.openai.chat"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: id) }
        }
        store.add(.spacer(.small), to: id)
        var ai = AIActivityPreviewData.item()
        ai.widgetConfiguration?.widgetLayout = .standard
        store.add(ai, to: id)
        for (kind, layout) in [("System Activity", WidgetLayout.compact), ("Network Activity", .trend), ("Weather", .compact), ("Now Playing", .wide), ("Battery", .compact), ("Clock", .compact)] {
            var item = DockItem.widget(kind); item.widgetConfiguration?.widgetLayout = layout
            store.add(item, to: id)
        }
        let profile = store.state.profiles.first { $0.id == id }!
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light }
            try await render(VStack(alignment: .leading, spacing: 20) {
                Text("Mixed Dock · illustrative fixtures").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                DockLayoutPreview(store: store, profile: profile)
            }.padding(24).background(DockDesign.page), name: "adaptive-mixed-" + suffix, size: NSSize(width: 1340, height: 210), scheme: scheme, directory: directory)
            try await render(VStack(alignment: .leading, spacing: 18) {
                Text("Narrow side Dock faces · illustrative fixtures").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    ForEach(["AI Activity", "System Activity", "Network Activity", "Weather", "Battery", "Now Playing", "Clock", "Shortcuts"], id: \.self) { kind in
                        WidgetCardPreview(kind: kind, width: 54, layout: WidgetPresentationCatalog.options(for: kind).first?.layout ?? .compact)
                    }
                }
            }.padding(20).background(WidgetDesign.surface), name: "adaptive-narrow-" + suffix,
                             size: NSSize(width: 610, height: 150), scheme: scheme, directory: directory)
            var longAI = AIActivityPreviewData.item()
            longAI.widgetConfiguration?.aiActivitySnapshot?.totals.totalTokens = 153_107_477
            longAI.widgetConfiguration?.aiActivitySnapshot?.partial = true
            try await render(HStack(spacing: 18) {
                ForEach(WidgetPresentationCatalog.options(for: "AI Activity")) { option in
                    WidgetContainer(width: CGFloat(option.width), kind: "AI Activity") { AIActivityCompactView(item: longAI) }
                        .environment(\.widgetLayout, option.layout).environment(\.dockWidgetContentWidth, CGFloat(option.width))
                }
            }.padding(20).background(WidgetDesign.surface), name: "adaptive-long-metric-" + suffix,
                             size: NSSize(width: 550, height: 120), scheme: scheme, directory: directory)
            var layoutMatrix = WidgetQAMatrix()
            try await renderSemanticLayoutPages(suffix: suffix, scheme: scheme, directory: directory, matrix: &layoutMatrix)
            for kind in ["AI Activity", "System Activity", "Network Activity", "Weather", "Now Playing", "Clock", "Disk Space", "Battery"] {
                let item = profile.items.first { $0.widgetKind == kind } ?? DockItem.widget(kind)
                try await render(WidgetConfigurationSheet(store: store, item: item, profileID: id, maximumHeight: 680),
                                 name: "adaptive-configure-" + kind.lowercased().replacingOccurrences(of: " ", with: "-") + "-" + suffix,
                                 size: NSSize(width: 488, height: 680), scheme: scheme, directory: directory)
            }
            try await render(VStack(alignment: .leading, spacing: 18) {
                Text("Icon treatment only · layout and information stay constant").font(.caption).foregroundStyle(.secondary)
                ForEach(["AI Activity", "System Activity", "Network Activity", "Weather", "Battery"], id: \.self) { kind in
                    HStack(spacing: 14) {
                        Text(kind).font(.system(size: 11)).frame(width: 108, alignment: .leading)
                        ForEach(WidgetIconAppearance.allCases) { appearance in
                            VStack(alignment: .leading, spacing: 5) {
                                WidgetCardPreview(kind: kind, width: 132, layout: kind == "System Activity" ? .trend : .standard, appearance: appearance)
                                Text(appearance.title).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }.padding(20).background(WidgetDesign.surface), name: "adaptive-icon-independence-" + suffix,
                             size: NSSize(width: 760, height: 470), scheme: scheme, directory: directory)
        }
        // Empty real configurations: no invented totals or history.
        for kind in ["AI Activity", "System Activity", "Weather", "Network Activity"] {
            let item = DockItem.widget(kind)
            try await render(WidgetCompactView(store: store, item: item, profileID: id, presentationSettings: store.state.settings).padding(20).background(WidgetDesign.surface),
                             name: "adaptive-empty-" + kind.lowercased().replacingOccurrences(of: " ", with: "-"), size: NSSize(width: 240, height: 110), scheme: .dark, directory: directory)
        }
    }

    private static func exportChangedSurfacesUI(to directory: URL, store: ProfileStore) async throws {
        precondition(AppRuntimeEnvironment.isIsolated, "Surface fixtures require an isolated validation root")
        let id = try store.createProfileAndPersist(kind: .custom, name: "Example Dock")
        store.setProfileColor(id, to: .orange)
        store.activate(id)
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false; $0.customDockWidgetStyle = .cards }
        var alarm = DockItem.widget("Alarm")
        alarm.widgetConfiguration?.alarms = [DockAlarm(title: "Example morning alarm", hour: 7, minute: 30, repeatWeekdays: [2, 4, 6], isEnabled: false)]
        store.add(alarm, to: id)
        let now = Date.now
        let reading = AIProviderLimitReading(provider: .copilot, availability: .available, plan: "Pro", windows: [
            AILimitWindow(name: "Monthly credits", usedPercent: 28, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 43_200)
        ], updatedAt: now.addingTimeInterval(-7_200), verifiedAccountIdentity: "example-account", lastRefreshError: "Example temporary connection failure")
        var limits = DockItem.widget("AI Limits")
        limits.widgetConfiguration?.aiLimitsVisibleProviders = [.copilot]
        limits.widgetConfiguration?.aiLimitsCompactProvider = .copilot
        let snapshot = AILimitsSnapshot(fetchedAt: now, readings: [reading], sourceScope: AIUsageSourceScope.limits(providers: [.copilot]))
        limits.widgetConfiguration?.aiLimitsSnapshot = snapshot
        store.add(limits, to: id)
        store.widgetData = WidgetDataCoordinator(store: store, loader: { _, _ in .limits(snapshot) })
        let payload = DiagnosticsPreviewPayload(data: try DiagnosticReport.makeData(state: store.state,
            hasUnpersistedChanges: false, persistenceWarningPresent: false, storageWritable: true,
            events: [DiagnosticEvent(at: now, category: .lifecycle, code: .appLaunched)], now: now,
            buildNumber: "synthetic-qa", hasIntentMetadata: false,
            osVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)))
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light; $0.customDockPosition = .bottom }
            for scope in ["dock", "defaults"] {
                // An inactive custom selection initializes the real Settings scope to app defaults,
                // while retaining the synthetic Dock in its picker.
                store.updateSettings { $0.activeCustomProfileID = scope == "dock" ? id : nil }
                for (width, label) in [(820.0, "full"), (520.0, "narrow")] {
                    try await render(SettingsView(store: store, initialPage: .appearance, embeddedInWorkspace: true, sidebarVisible: false),
                        name: "surface-appearance-\(scope)-\(label)-\(suffix)", size: NSSize(width: width, height: 1200), scheme: scheme, directory: directory)
                }
            }
            store.updateSettings { $0.activeCustomProfileID = id }
            try await render(DiagnosticsPreviewSheet(payload: payload, cancel: {}, saved: {}).background(WidgetDesign.surface),
                name: "surface-diagnostics-\(suffix)", size: NSSize(width: 620, height: 540), scheme: scheme, directory: directory)
            // Match CustomDockView's live popover wrapper so fixed-height exports scroll
            // the content instead of compressing the footer into its preceding rows.
            try await render(VStack(alignment: .leading, spacing: 10) {
                DockScrollView(.vertical) {
                    WidgetPopout(store: store, item: limits, profileID: id)
                        .frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
                }
            }.padding(20).background(WidgetDesign.surface)
                .frame(minWidth: 250, minHeight: 150, maxHeight: 800, alignment: .topLeading),
                name: "surface-ai-limits-stale-\(suffix)", size: NSSize(width: 460, height: 800), scheme: scheme, directory: directory)
            try await render(HStack(spacing: 16) {
                ForEach(WidgetPresentationCatalog.options(for: "AI Limits")) { option in
                    WidgetCompactView(store: store, item: limits, profileID: id, layoutOverride: option.layout)
                }
            }.padding(20).background(WidgetDesign.surface), name: "surface-ai-limits-stale-faces-\(suffix)",
                size: NSSize(width: 510, height: 110), scheme: scheme, directory: directory)
            // Opens the editor through a DEBUG seam; a fixed click point broke whenever the layout moved.
            AlarmQAFixture.editsFirstAlarm = true
            try await render(WidgetPopout(store: store, item: alarm, profileID: id).padding(20).background(WidgetDesign.surface),
                name: "surface-alarm-edit-\(suffix)", size: NSSize(width: 460, height: 620), scheme: scheme, directory: directory)
            AlarmQAFixture.editsFirstAlarm = false
            for fixture in CalendarQAFixture.allCases {
                // Production Calendar views fed by the DEBUG-only fixture seam (no EventKit access).
                CalendarQAFixture.override = fixture
                defer { CalendarQAFixture.override = nil }
                let calendarItem = DockItem.widget("Calendar")
                try await render(WidgetPopout(store: store, item: calendarItem, profileID: id, showsCustomize: false).padding(20).background(WidgetDesign.surface),
                    name: "surface-calendar-\(fixture.rawValue)-production-\(suffix)", size: NSSize(width: 460, height: 460), scheme: scheme, directory: directory)
                try await render(WidgetCompactView(store: store, item: calendarItem, profileID: id, layoutOverride: .wide).padding(20).background(WidgetDesign.surface),
                    name: "surface-calendar-\(fixture.rawValue)-dock-\(suffix)", size: NSSize(width: 260, height: 100), scheme: scheme, directory: directory)
            }
            for position in [DockPosition.left, .right] {
                store.updateSettings { $0.customDockPosition = position }
                for (page, kinds) in semanticLayoutPages().enumerated() {
                    let profile = DockProfile(name: "Example side Dock", kind: .custom, items: kinds.map(DockItem.widget))
                    try await render(VStack(spacing: 12) {
                        Text("Example · \(position.rawValue) · families \(page * semanticLayoutPageSize + 1)–\(page * semanticLayoutPageSize + kinds.count)").font(.caption).foregroundStyle(.secondary)
                        DockLayoutPreview(store: store, profile: profile, maximumSideLength: 780)
                    }.padding(20).background(WidgetDesign.surface), name: "surface-side-\(position.rawValue)-\(page + 1)-\(suffix)",
                        size: NSSize(width: 300, height: 900), scheme: scheme, directory: directory)
                }
            }
        }
    }

    /// Renders every registry family at every advertised layout and records each state in `matrix`.
    private static func renderSemanticLayoutPages(suffix: String, scheme: ColorScheme, directory: URL, matrix: inout WidgetQAMatrix) async throws {
        for (page, rows) in semanticLayoutPages().enumerated() {
            try await render(VStack(alignment: .leading, spacing: 12) {
                Text("Semantic layout samples · \(page + 1)").font(.system(size: 13, weight: .semibold))
                ForEach(rows, id: \.self) { kind in
                    HStack(spacing: 16) {
                        Text(kind).font(.system(size: 11, weight: .medium)).frame(width: 108, alignment: .leading)
                        ForEach(WidgetPresentationCatalog.options(for: kind)) { option in
                            VStack(alignment: .leading, spacing: 4) {
                                WidgetCardPreview(kind: kind, width: CGFloat(option.width), layout: option.layout)
                                Text(option.title).font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }.padding(20).background(WidgetDesign.surface), name: "adaptive-layouts-\(page + 1)-" + suffix,
                             size: NSSize(width: 820, height: 930), scheme: scheme, directory: directory)
            for kind in rows {
                for option in WidgetPresentationCatalog.options(for: kind) { matrix.record(kind, .layout(option.layout)) }
            }
        }
    }

    private static func exportWidgetUI(to directory: URL, store: ProfileStore) async throws {
        let id = try store.createProfileAndPersist(kind: .custom, name: "Widget studio")
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false }
        for definition in WidgetRegistry.all {
            var item = DockItem.widget(definition.name)
            if definition.name == "AI Activity" { item = AIActivityPreviewData.item() }
            if definition.name == "Quick Checklist" { item.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "Plan the next release"), QuickChecklistEntry(title: "Take a break", isComplete: true)] }
            store.add(item, to: id)
        }
        let profile = store.state.profiles.first { $0.id == id }!
        var matrix = WidgetQAMatrix()
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            for item in profile.items {
                let name = (item.widgetKind ?? "Widget").lowercased().replacingOccurrences(of: " ", with: "-")
                try await render(WidgetPopout(store: store, item: item, profileID: id).padding(20).background(WidgetDesign.surface),
                                 name: "widget-" + name + "-" + suffix, size: NSSize(width: 460, height: item.widgetKind == "System Activity" ? 1250 : 680), scheme: scheme, directory: directory)
            }
            for kind in ["AI Activity", "AI Limits", "System Activity", "Network Activity", "Calculator", "Quick Checklist", "Disk Space"] {
                let item = profile.items.first { $0.widgetKind == kind }!
                try await render(WidgetConfigurationSheet(store: store, item: item, profileID: id, maximumHeight: 580),
                                 name: "configure-" + kind.lowercased().replacingOccurrences(of: " ", with: "-") + "-" + suffix,
                                 size: NSSize(width: 488, height: 580), scheme: scheme, directory: directory)
            }
            // Capability-derived states: advertised layouts, first-run setup/empty states and Calendar's production states.
            try await renderSemanticLayoutPages(suffix: suffix, scheme: scheme, directory: directory, matrix: &matrix)
            for definition in WidgetRegistry.all where definition.capabilities.hasSetupState {
                let name = definition.name.lowercased().replacingOccurrences(of: " ", with: "-")
                try await render(WidgetPopout(store: store, item: .widget(definition.name), profileID: id, showsCustomize: false).padding(20).background(WidgetDesign.surface),
                                 name: "widget-setup-" + name + "-" + suffix, size: NSSize(width: 460, height: 520), scheme: scheme, directory: directory)
                matrix.record(definition.name, .setup)
            }
            let calendarItem = DockItem.widget("Calendar")
            for fixture in CalendarQAFixture.allCases {
                CalendarQAFixture.override = fixture
                defer { CalendarQAFixture.override = nil }
                try await render(WidgetPopout(store: store, item: calendarItem, profileID: id, showsCustomize: false).padding(20).background(WidgetDesign.surface),
                                 name: "calendar-\(fixture.rawValue)-popout-" + suffix, size: NSSize(width: 460, height: 460), scheme: scheme, directory: directory)
                try await render(WidgetCompactView(store: store, item: calendarItem, profileID: id, layoutOverride: .wide).padding(20).background(WidgetDesign.surface),
                                 name: "calendar-\(fixture.rawValue)-dock-" + suffix, size: NSSize(width: 260, height: 100), scheme: scheme, directory: directory)
            }
            try await render(VStack(alignment: .leading, spacing: 16) {
                ForEach(["AI Activity", "AI Limits", "System Activity", "Network Activity", "Disk Space", "Calculator", "Quick Checklist"], id: \.self) { kind in
                    HStack(spacing: 12) {
                        Text(kind).font(.caption).frame(width: 110, alignment: .leading)
                        WidgetCardPreview(kind: kind, width: 54)
                        ForEach(WidgetIconStyle.allCases.filter { $0 != .live }) { style in
                            WidgetIconTile(item: .widget(kind), style: style)
                        }
                        WidgetCardPreview(kind: kind, width: 144)
                    }
                }
            }.padding(20).background(WidgetDesign.surface), name: "icon-styles-" + suffix,
                             size: NSSize(width: 580, height: 530), scheme: scheme, directory: directory)
        }
        try matrix.validate()
    }

    /// Authored named states include the same attribution required by runtime projection.
    static func activityFixture(state: String) -> DockItem {
        var item = AIActivityPreviewData.item()
        if ["connected", "partial", "updating"].contains(state) {
            item.widgetConfiguration?.aiActivitySnapshot?.totals.totalTokens = 643_868_378
            item.widgetConfiguration?.aiActivitySnapshot?.totals.sessions = 12
            item.widgetConfiguration?.aiActivitySnapshot?.totals.toolCalls = 0
            item.widgetConfiguration?.aiActivitySnapshot?.partial = state == "partial"
            for index in item.widgetConfiguration!.aiActivitySnapshot!.points.indices {
                item.widgetConfiguration?.aiActivitySnapshot?.points[index].totalTokens *= 4_000
            }
        } else {
            item.widgetConfiguration?.aiActivitySnapshot?.available = false
            item.widgetConfiguration?.aiActivitySnapshot?.partial = state == "failure"
        }
        let configuration = item.widgetConfiguration!
        item.widgetConfiguration?.aiActivitySnapshot?.sourceScope = AIUsageSourceScope.activity(
            provider: configuration.aiActivityProvider, range: configuration.aiActivityRange)
        return item
    }

    private static func exportFocusedUI(to directory: URL, store: ProfileStore) async throws {
        let id = try store.createProfileAndPersist(kind: .custom, name: "Everyday")
        store.add(.widget("Clock"), to: id)
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false }
        let profile = store.state.profiles.first { $0.id == id }!
        // The fixed app list keeps the renders identical on every Mac and never exports this Mac's inventory.
        let apps = AddLibraryPreviewState(scan: fixtureAppScan)
        let settle = Duration.milliseconds(800)
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            for category in ["All", "Applications", "Widgets", "System"] {
                try await render(AddLibrary(store: store, profile: profile, initialCategory: category,
                    add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}).environment(\.addLibraryPreview, apps),
                    name: "add-" + category.lowercased() + "-" + suffix, size: NSSize(width: 820, height: 560), scheme: scheme, directory: directory, settle: settle)
            }
            try await render(AddLibrary(store: store, profile: profile, initialQuery: "no-matches-xyz", add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}).environment(\.addLibraryPreview, apps),
                name: "add-empty-" + suffix, size: NSSize(width: 740, height: 500), scheme: scheme, directory: directory, settle: settle)
            try await render(AddLibrary(store: store, profile: profile, initialQuery: "Clock", add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}).environment(\.addLibraryPreview, apps),
                name: "add-search-" + suffix, size: NSSize(width: 740, height: 500), scheme: scheme, directory: directory, settle: settle)
            for state in ["connected", "partial", "disconnected", "empty", "failure", "updating"] {
                let item = activityFixture(state: state)
                // Even a future fixture refresh must return the authored state, never read
                // local provider logs or replace it with an empty live snapshot.
                let snapshot = item.widgetConfiguration!.aiActivitySnapshot!
                store.widgetData = WidgetDataCoordinator(store: store, loader: { _, _ in
                    if state == "updating" { try await Task.sleep(for: .seconds(3)) }
                    return .activity(snapshot)
                })
                store.add(item, to: id)
                var refresh: Task<Void, Never>?
                if state == "updating" {
                    refresh = Task { await store.widgetData.refresh(item: item, profileID: id) }
                }
                let account = AIAccountStatus(state: state == "disconnected" ? .unavailable : .signedIn, message: "Preview")
                try await render(AIActivityPopoutView(store: store, item: item, profileID: id, accountOverride: account).padding(16).background(DockDesign.page),
                    name: "ai-" + state + "-" + suffix, size: NSSize(width: 404, height: state == "connected" || state == "partial" || state == "updating" ? 390 : 320), scheme: scheme, directory: directory, settle: settle)
                // The refresh must not outlive its render and write into the next fixture.
                refresh?.cancel()
                await refresh?.value
                store.removeItem(item.id, from: id)
            }
            var tile = AIActivityPreviewData.item()
            tile.widgetConfiguration?.aiActivitySnapshot?.totals.totalTokens = 643_868_378
            tile.widgetConfiguration?.aiActivitySnapshot?.partial = true
            var setup = DockItem.widget("AI Activity")
            setup.widgetConfiguration?.aiActivitySnapshot = nil
            try await render(HStack(spacing: 20) {
                ForEach([54.0, 108.0, 144.0, 196.0], id: \.self) { width in
                    AppleWidgetCard(item: tile, width: width, showsLabels: true, fallback: AnyView(AIActivityCompactView(item: tile)))
                }
                AppleWidgetCard(item: setup, width: 144, showsLabels: true, fallback: AnyView(AIActivityCompactView(item: setup)))
            }.padding(20).background(DockDesign.page), name: "ai-tiles-" + suffix, size: NSSize(width: 786, height: 100), scheme: scheme, directory: directory, settle: settle)
        }
    }

    /// Redesign vocabulary specimens in light/dark × standard, Reduce Transparency and
    /// Increase Contrast, injected through `dockAccessibilityPreview` only.
    private static func exportRedesignUI(to directory: URL) async throws {
        let variants: [(String, ColorSchemeContrast, Bool)] = [("standard", .standard, false),
                                                              ("reduce-transparency", .standard, true),
                                                              ("increase-contrast", .increased, false)]
        for component in DesignSystemGallery.Component.allCases {
            for scheme in [ColorScheme.light, .dark] {
                for (variant, contrast, transparency) in variants {
                    try await render(DesignSystemGallery(component: component),
                                     name: "redesign-\(component.rawValue)-\(scheme == .dark ? "dark" : "light")-\(variant)",
                                     size: component.renderSize, scheme: scheme, directory: directory,
                                     contrast: contrast, reduceTransparency: transparency)
                }
            }
        }
    }

    /// Inject accessibility environments; never change the host's preferences.
    private static func exportAccessibilityMatrix(store: ProfileStore, profile: DockProfile, directory: URL) async throws {
        store.updateSettings { $0.lastSettingsPage = .appearance }
        for scheme in [ColorScheme.dark, .light] {
            for (name, contrast, transparency) in [("contrast", ColorSchemeContrast.increased, false),
                                                   ("opaque", .standard, true), ("contrast-opaque", .increased, true)] {
                let prefix = "accessibility-" + (scheme == .dark ? "dark-" : "light-") + name
                try await render(DockManagerView(store: store), name: prefix + "-editor", size: NSSize(width: 1160, height: 760),
                                 scheme: scheme, directory: directory, contrast: contrast, reduceTransparency: transparency)
                try await render(DockManagerView(store: store, showsSettings: true),
                                 name: prefix + "-settings", size: NSSize(width: 1160, height: 760), scheme: scheme,
                                 directory: directory, contrast: contrast, reduceTransparency: transparency)
                var dockProfile = profile
                var appearance = ProfileAppearance(settings: store.state.settings)
                appearance.theme = scheme == .dark ? .dark : .light
                appearance.material = .frosted
                dockProfile.appearance = appearance
                try await render(DockLayoutPreview(store: store, profile: dockProfile).padding(24), name: prefix + "-dock",
                                 size: NSSize(width: 1000, height: 280), scheme: scheme, directory: directory,
                                 contrast: contrast, reduceTransparency: transparency)
            }
        }
    }

    /// `fitsContentHeight` grows the canvas to the content's height (plus the title-bar safe area) instead
    /// of trusting `size.height`, for pages whose row count varies. `settle` is how long SwiftUI's
    /// appearance and state tasks get before the capture.
    static func render<Content: View>(_ view: Content, name: String, size: NSSize,
                                              scheme: ColorScheme, directory: URL, contrast: ColorSchemeContrast = .standard,
                                              reduceTransparency: Bool = false, settle: Duration = .milliseconds(350),
                                              fitsContentHeight: Bool = false) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "MyDock"
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unifiedCompact
        window.appearance = NSAppearance(named: contrast == .increased
            ? (scheme == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (scheme == .dark ? .darkAqua : .aqua))
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view
            .font(DockDesign.body).buttonStyle(DockButtonStyle()).textFieldStyle(DockTextFieldStyle())
            .tint(DockDesign.accent).environment(\.colorScheme, scheme).preferredColorScheme(scheme).environment(\.dockSnapshotRendering, true).environment(\.controlActiveState, .active)
            .environment(\.dockAccessibilityPreview, DockAccessibilityPreview(contrast: contrast, reduceTransparency: reduceTransparency)))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        if fitsContentHeight, host.fittingSize.height.isFinite {
            let height = max(size.height, ceil(host.fittingSize.height + host.safeAreaInsets.top))
            window.setContentSize(NSSize(width: size.width, height: height))
            host.frame = NSRect(origin: .zero, size: NSSize(width: size.width, height: height))
            host.layoutSubtreeIfNeeded()
        }
        // Settle SwiftUI's appearance/state tasks before caching the native view.
        try await Task.sleep(for: settle)
        host.layoutSubtreeIfNeeded()
        warnIfClipped(host, name: name)
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }

    /// A fixed canvas smaller than its content cuts the last rows off without any other signal, so say so.
    /// Scrolling pages report a small fitting height and never warn.
    static func warnIfClipped(_ host: NSView, name: String) {
        let needed = host.fittingSize.height
        guard needed.isFinite, needed > host.bounds.height + 0.5 else { return }
        let message = "Render QA: \(name) may be clipped: its content needs \(Int(needed.rounded(.up))) pt, the canvas is \(Int(host.bounds.height)) pt.\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
#endif
