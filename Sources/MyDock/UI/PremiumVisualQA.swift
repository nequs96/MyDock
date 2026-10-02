#if DEBUG
import AppKit
import SwiftUI

/// Development-only, deterministic render matrix. Uses the same views as the app
/// with an isolated ProfileStore; never starts the user's Dock or native controllers.
@MainActor
enum PremiumVisualQA {
    static func export(to directory: URL, store: ProfileStore) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if ProcessInfo.processInfo.environment["MYDOCK_ADAPTIVE_QA"] == "1" {
            try await exportAdaptiveUI(to: directory, store: store)
            return
        }
        if ProcessInfo.processInfo.environment["MYDOCK_WIDGET_QA"] == "1" {
            try await exportWidgetUI(to: directory, store: store)
            return
        }
        if ProcessInfo.processInfo.environment["MYDOCK_FOCUSED_QA"] == "1" {
            try await exportFocusedUI(to: directory, store: store)
            return
        }
        let names = ["System Activity", "Clock", "AI Limits"]
        let everyday = store.createProfile(kind: .custom, name: "Everyday")
        for bundle in ["com.apple.finder", "com.microsoft.VSCode", "com.apple.Terminal"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: everyday) }
        }
        for name in names { store.add(.widget(name), to: everyday) }
        _ = store.createProfile(kind: .custom, name: "Work")
        _ = store.createProfile(kind: .custom, name: "Minimal")
        _ = store.createProfile(kind: .native, name: "Essentials")
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
            let blank = store.createProfile(kind: .custom, name: "New Dock")
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
                            ForEach(WidgetCardWidth.allCases) { width in
                                WidgetLibraryTile(widget: widget, cardWidth: width, showsVariantLabel: true)
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

    private static func exportAdaptiveUI(to directory: URL, store: ProfileStore) async throws {
        let id = store.createProfile(kind: .custom, name: "Adaptive widget studio")
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
            try await render(VStack(alignment: .leading, spacing: 20) {
                Text("Mixed Dock · illustrative fixtures").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                DockLayoutPreview(store: store, profile: profile)
            }.padding(24).background(DockDesign.page), name: "adaptive-mixed-" + suffix, size: NSSize(width: 1340, height: 210), scheme: scheme, directory: directory)
            let kinds = WidgetRegistry.all.map(\.name)
            for page in 0..<3 {
                let rows = Array(kinds.dropFirst(page * 10).prefix(10))
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
            }
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

    private static func exportWidgetUI(to directory: URL, store: ProfileStore) async throws {
        let id = store.createProfile(kind: .custom, name: "Widget studio")
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false }
        for definition in WidgetRegistry.all {
            var item = DockItem.widget(definition.name)
            if definition.name == "AI Activity" { item = AIActivityPreviewData.item() }
            if definition.name == "Quick Checklist" { item.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "Plan the next release"), QuickChecklistEntry(title: "Take a break", isComplete: true)] }
            store.add(item, to: id)
        }
        let profile = store.state.profiles.first { $0.id == id }!
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            for item in profile.items {
                let name = (item.widgetKind ?? "Widget").lowercased().replacingOccurrences(of: " ", with: "-")
                try await render(WidgetPopout(store: store, item: item, profileID: id).padding(20).background(WidgetDesign.surface),
                                 name: "widget-" + name + "-" + suffix, size: NSSize(width: 460, height: item.widgetKind == "System Activity" ? 950 : 680), scheme: scheme, directory: directory)
            }
            for kind in ["AI Activity", "AI Limits", "System Activity", "Network Activity", "Calculator", "Quick Checklist", "Disk Space"] {
                let item = profile.items.first { $0.widgetKind == kind }!
                try await render(WidgetConfigurationSheet(store: store, item: item, profileID: id, maximumHeight: 580),
                                 name: "configure-" + kind.lowercased().replacingOccurrences(of: " ", with: "-") + "-" + suffix,
                                 size: NSSize(width: 488, height: 580), scheme: scheme, directory: directory)
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
    }

    private static func exportFocusedUI(to directory: URL, store: ProfileStore) async throws {
        let id = store.createProfile(kind: .custom, name: "Everyday")
        store.add(.widget("Clock"), to: id)
        store.updateSettings { $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false }
        let scan = await InstalledAppCatalog.scan()
        let inventory = scan.applications.map { ["name": $0.name, "path": $0.url.path, "bundleIdentifier": $0.bundleIdentifier, "version": $0.version] }
        try JSONSerialization.data(withJSONObject: inventory, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("installed-apps.json"))
        let profile = store.state.profiles.first { $0.id == id }!
        for scheme in [ColorScheme.dark, .light] {
            let suffix = scheme == .dark ? "dark" : "light"
            for category in ["All", "Applications", "Widgets", "System"] {
                try await render(AddLibrary(store: store, profile: profile, initialCategory: category,
                    add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}),
                    name: "add-" + category.lowercased() + "-" + suffix, size: NSSize(width: 820, height: 560), scheme: scheme, directory: directory)
            }
            try await render(AddLibrary(store: store, profile: profile, initialQuery: "no-matches-xyz", add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}),
                name: "add-empty-" + suffix, size: NSSize(width: 740, height: 500), scheme: scheme, directory: directory)
            try await render(AddLibrary(store: store, profile: profile, initialQuery: "Clock", add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {}),
                name: "add-search-" + suffix, size: NSSize(width: 740, height: 500), scheme: scheme, directory: directory)
            for state in ["connected", "partial", "disconnected", "empty", "failure", "updating"] {
                var item = AIActivityPreviewData.item()
                if state == "connected" || state == "partial" || state == "updating" {
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
                store.add(item, to: id)
                let snapshot = item.widgetConfiguration!.aiActivitySnapshot!
                if state == "updating" {
                    store.widgetData = WidgetDataCoordinator(store: store, loader: { _, _ in
                        try await Task.sleep(for: .seconds(3))
                        return .activity(snapshot)
                    })
                    Task { await store.widgetData.refresh(item: item, profileID: id) }
                }
                let account = AIAccountStatus(state: state == "disconnected" ? .unavailable : .signedIn, message: "Preview")
                try await render(AIActivityPopoutView(store: store, item: item, profileID: id, accountOverride: account).padding(16).background(DockDesign.page),
                    name: "ai-" + state + "-" + suffix, size: NSSize(width: 404, height: state == "connected" || state == "partial" || state == "updating" ? 390 : 320), scheme: scheme, directory: directory)
                if state == "updating" { store.widgetData = WidgetDataCoordinator(store: store) }
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
            }.padding(20).background(DockDesign.page), name: "ai-tiles-" + suffix, size: NSSize(width: 786, height: 100), scheme: scheme, directory: directory)
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

    private static func render<Content: View>(_ view: Content, name: String, size: NSSize,
                                              scheme: ColorScheme, directory: URL, contrast: ColorSchemeContrast = .standard,
                                              reduceTransparency: Bool = false) async throws {
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
        // Settle SwiftUI's appearance/state tasks before caching the native view.
        try await Task.sleep(for: .milliseconds(ProcessInfo.processInfo.environment["MYDOCK_FOCUSED_QA"] == "1" ? 800 : 350))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }
}
#endif
