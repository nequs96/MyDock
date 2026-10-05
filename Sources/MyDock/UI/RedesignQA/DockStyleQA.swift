#if DEBUG
import AppKit
import SwiftUI

/// RD-04 render matrix (`MYDOCK_DOCKSTYLE_QA=1`). The five redesign Dock styles are defined
/// here exactly as the redesign ledger defines them, until RD-07 wires them into Settings.
///
/// Offscreen `cacheDisplay` captures cannot see the Liquid Glass compositor, so glass styles
/// draw their fallback here (`dockSnapshotRendering`). Judge geometry, edges, layers and
/// indicators from these images, not the native glass itself.
@MainActor
enum DockStyleQA {
    struct Style {
        let name: String
        let apply: (inout AppSettings) -> Void
    }

    static let styles: [Style] = [
        Style(name: "clear") {
            $0.customDockMaterial = .liquidGlassClear; $0.customDockEdgeStyle = .none
            $0.customDockWidgetSurface = .plain; $0.customDockTintMode = .custom
            $0.customDockTintStrength = 0; $0.customDockGlassOpacity = 0
        },
        Style(name: "glass") {
            $0.customDockMaterial = .liquidGlass; $0.customDockEdgeStyle = .hairline; $0.customDockWidgetSurface = .glass
        },
        Style(name: "frosted") { $0.customDockMaterial = .frosted; $0.customDockWidgetSurface = .tile },
        Style(name: "solid") { $0.customDockMaterial = .solid; $0.customDockWidgetSurface = .tile },
        // Midnight keeps the System theme so the dark material resolves to a dark scheme.
        Style(name: "midnight") { $0.customDockMaterial = .dark; $0.customDockWidgetSurface = .glass; $0.customDockTheme = .system }
    ]

    /// Every style starts from today's defaults so one never inherits another's values.
    static func resetAppearance(_ settings: inout AppSettings) {
        let defaults = AppSettings()
        settings.customDockMaterial = defaults.customDockMaterial
        settings.customDockEdgeStyle = defaults.customDockEdgeStyle
        settings.customDockWidgetSurface = defaults.customDockWidgetSurface
        settings.customDockTintMode = defaults.customDockTintMode
        settings.customDockTintStrength = defaults.customDockTintStrength
        settings.customDockGlassOpacity = defaults.customDockGlassOpacity
        settings.customDockFloatingInset = defaults.customDockFloatingInset
        settings.customDockCornerRadius = defaults.customDockCornerRadius
    }

    static let runningBundleIdentifiers: Set<String> = ["com.apple.finder", "com.apple.Safari"]
    static let badges = ["com.apple.mail": "3"]

    static func schemeName(_ scheme: ColorScheme) -> String { scheme == .dark ? "dark" : "light" }

    static var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.25, green: 0.42, blue: 0.62), Color(red: 0.60, green: 0.45, blue: 0.31)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 40) {
                ForEach(0..<14, id: \.self) { _ in Rectangle().fill(.white.opacity(0.16)).frame(width: 35).rotationEffect(.degrees(25)) }
            }
        }.clipped().ignoresSafeArea()
    }

    static func indicatorFixtures<Content: View>(_ content: Content) -> some View {
        content
            .environment(\.dockPreviewRunningBundleIdentifiers, runningBundleIdentifiers)
            .environment(\.dockPreviewBadges, badges)
    }

    /// Same host as `PremiumVisualQA.render`: a titled window with the accessibility preview injected.
    static func render<Content: View>(_ view: Content, name: String, size: NSSize, scheme: ColorScheme, directory: URL,
                                      contrast: ColorSchemeContrast = .standard, reduceTransparency: Bool = false) async throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: contrast == .increased
            ? (scheme == .dark ? .accessibilityHighContrastDarkAqua : .accessibilityHighContrastAqua)
            : (scheme == .dark ? .darkAqua : .aqua))
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view
            .font(DockDesign.body).environment(\.colorScheme, scheme).preferredColorScheme(scheme)
            .environment(\.dockSnapshotRendering, true).environment(\.controlActiveState, .active)
            .environment(\.dockAccessibilityPreview, DockAccessibilityPreview(contrast: contrast, reduceTransparency: reduceTransparency)))
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(350))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        window.close()
    }

    /// The GLASS export's transparent-host capture: the production `DockSurfaceHostingView` in a
    /// clear, shadowless panel. Every 6×6 corner block must stay transparent.
    static func renderTransparentDock(store: ProfileStore, profile: DockProfile, name: String, directory: URL,
                                      contrast: ColorSchemeContrast = .standard, reduceTransparency: Bool = false) async throws {
        let settings = store.effectiveSettings(for: profile)
        let size = settings.customDockPosition == .bottom ? NSSize(width: 560, height: 76) : NSSize(width: 76, height: 420)
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false; panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: settings.customDockTheme == .dark || settings.customDockMaterial == .dark ? .darkAqua : .aqua)
        let root = indicatorFixtures(CustomDockView(store: store, profile: profile, isPreview: true, openSettings: { _ in }))
            .environment(\.dockSnapshotRendering, true)
            .environment(\.dockAccessibilityPreview, DockAccessibilityPreview(contrast: contrast, reduceTransparency: reduceTransparency))
        let host = DockSurfaceHostingView(rootView: root)
        host.surfaceCornerRadius = CGFloat(settings.customDockCornerRadius)
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
        guard visiblePixelCount > 50 else {
            throw NSError(domain: "MyDockDockStyleQA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty corner fixture in \(name)"])
        }
        let block = 6
        for (cornerX, cornerY) in [(0, 0), (bitmap.pixelsWide - block, 0), (0, bitmap.pixelsHigh - block),
                                   (bitmap.pixelsWide - block, bitmap.pixelsHigh - block)] {
            for y in cornerY..<(cornerY + block) {
                for x in cornerX..<(cornerX + block) {
                    guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent < 0.01 else {
                        throw NSError(domain: "MyDockDockStyleQA", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "Opaque panel corner in \(name) at \(x),\(y)"])
                    }
                }
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name + ".png"))
        panel.close()
    }

    /// D4: in side Docks a badge stays inside its one-tile-wide column. The badge is measured as it
    /// renders (one, two and three characters at the smallest, default and largest Dock sizes).
    static func assertSideBadgesFitTheColumn() throws {
        for scale in [CGFloat(0.65), 1, 1.5] {
            for text in ["3", "24", "99+"] {
                let badge = NSHostingView(rootView: DockBadgeView(text: text, scale: scale).environment(\.dockSnapshotRendering, true))
                let size = badge.fittingSize
                for position in [DockPosition.left, .right] {
                    var settings = AppSettings()
                    settings.customDockPosition = position
                    let tile = CGSize(width: DockSurfaceMetrics.itemLength(.application(at: URL(fileURLWithPath: "/System/Applications/Mail.app")), settings: settings, scale: scale),
                                      height: 54 * scale)
                    let frame = DockBadgePlacement.frame(badgeSize: size, tileSize: tile, position: position, scale: scale)
                    guard size.width > 0, frame.minX >= 0, frame.maxX <= tile.width + 0.5, frame.minY >= 0 else {
                        throw NSError(domain: "MyDockDockStyleQA", code: 3, userInfo: [NSLocalizedDescriptionKey:
                            "Badge \"\(text)\" at \(scale)x leaves the \(position.rawValue) Dock column: \(frame) in \(tile)"])
                    }
                }
            }
        }
    }

    static func dockScene(store: ProfileStore, profile: DockProfile, horizontal: Bool) -> some View {
        ZStack {
            wallpaper
            indicatorFixtures(DockLayoutPreview(store: store, profile: profile, maximumSideLength: 560))
                .padding(horizontal ? 24 : 12)
        }
    }

    /// Reveal handle at its real 38×6 size, magnified for review, in standard / IC / RT.
    static func revealHandleSheet() -> some View {
        let variants: [(String, ColorSchemeContrast, Bool)] = [("Standard", .standard, false),
                                                              ("Increase Contrast", .increased, false),
                                                              ("Reduce Transparency", .standard, true)]
        return ZStack {
            wallpaper
            HStack(spacing: 28) {
                ForEach(variants.indices, id: \.self) { index in
                    let variant = variants[index]
                    VStack(spacing: 18) {
                        RevealHandleView(position: .bottom, isVisible: true)
                            .frame(width: DockPanelGeometry.revealHandleLength, height: DockPanelGeometry.revealHandleThickness)
                            .scaleEffect(3).frame(width: 120, height: 24)
                        RevealHandleView(position: .left, isVisible: true)
                            .frame(width: DockPanelGeometry.revealHandleThickness, height: DockPanelGeometry.revealHandleLength)
                            .scaleEffect(3).frame(width: 24, height: 120)
                        Text(variant.0).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    }
                    .environment(\.dockAccessibilityPreview, DockAccessibilityPreview(contrast: variant.1, reduceTransparency: variant.2))
                }
            }
        }
    }

    /// Panel, reveal strip and keep-visible area on a mock 1440×900 screen, from `DockPanelGeometry`.
    static func insetSheet(settings: AppSettings) -> some View {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let factor: CGFloat = 0.28
        let cross = DockSurfaceMetrics.crossLength(settings: settings, scale: 1)
        func rect(_ frame: NSRect) -> CGRect {
            CGRect(x: frame.minX * factor, y: (screen.height - frame.maxY) * factor, width: frame.width * factor, height: frame.height * factor)
        }
        return VStack(alignment: .leading, spacing: 14) {
            ForEach([0.0, 24.0], id: \.self) { inset in
                HStack(spacing: 14) {
                    ForEach([DockPosition.bottom, .left, .right], id: \.self) { position in
                        let frame = DockPanelGeometry.frame(position: position, placementArea: visible, contentLength: 620,
                                                            crossLength: cross, floatingInset: inset)
                        let reveal = DockPanelGeometry.revealFrame(position: position, placementArea: visible)
                        let hover = DockPanelGeometry.hoverFrame(expanded: frame, position: position, floatingInset: inset)
                        ZStack(alignment: .topLeading) {
                            wallpaper
                            let hoverRect = rect(hover)
                            Rectangle().strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2])).foregroundStyle(.yellow)
                                .frame(width: hoverRect.width, height: hoverRect.height).offset(x: hoverRect.minX, y: hoverRect.minY)
                            let panelRect = rect(frame)
                            DockMaterialSurface(settings: settings, color: DockProfileColor.blue.displayColor)
                                .frame(width: panelRect.width, height: panelRect.height).offset(x: panelRect.minX, y: panelRect.minY)
                            let revealRect = rect(reveal)
                            Rectangle().fill(.red)
                                .frame(width: max(2, revealRect.width), height: max(2, revealRect.height))
                                .offset(x: revealRect.minX, y: revealRect.minY)
                            Text("\(position.rawValue) · inset \(Int(inset))").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white).padding(6)
                        }
                        .frame(width: screen.width * factor, height: screen.height * factor, alignment: .topLeading)
                        .clipped()
                    }
                }
            }
        }.padding(14)
    }
}

extension PremiumVisualQA {
    static func exportDockStyleUI(to directory: URL, store: ProfileStore) async throws {
        try DockStyleQA.assertSideBadgesFitTheColumn()
        let id = try store.createProfileAndPersist(kind: .custom, name: "Dock style preview")
        store.updateSettings {
            $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false
            $0.magnificationEnabled = false
        }
        for bundle in ["com.apple.finder", "com.apple.Safari", "com.apple.mail"] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { store.add(.application(at: url), to: id) }
        }
        store.add(.spacer(.regular), to: id)
        store.add(.widget("Clock"), to: id)
        store.add(.widget("System Activity"), to: id)
        var folder = DockItem.file(at: URL(fileURLWithPath: "/Applications", isDirectory: true), isFolder: true)
        folder.folderIconColor = .blue
        folder.folderIconLetter = "A"
        store.add(folder, to: id)
        store.activate(id)
        func profile() -> DockProfile { store.state.profiles.first { $0.id == id }! }

        for style in DockStyleQA.styles {
            for position in [DockPosition.bottom, .left, .right] {
                for scheme in [ColorScheme.light, .dark] {
                    store.updateSettings {
                        DockStyleQA.resetAppearance(&$0)
                        $0.customDockPosition = position
                        $0.customDockTheme = scheme == .dark ? .dark : .light
                        style.apply(&$0)
                    }
                    let horizontal = position == .bottom
                    try await DockStyleQA.render(DockStyleQA.dockScene(store: store, profile: profile(), horizontal: horizontal),
                        name: "dockstyle-\(style.name)-\(position.rawValue)-\(DockStyleQA.schemeName(scheme))",
                        size: horizontal ? NSSize(width: 820, height: 150) : NSSize(width: 300, height: 640),
                        scheme: scheme, directory: directory)
                }
                // Transparent host: corners of the real panel stay clear.
                store.updateSettings {
                    DockStyleQA.resetAppearance(&$0)
                    $0.customDockPosition = position
                    $0.customDockTheme = .light
                    style.apply(&$0)
                }
                try await DockStyleQA.renderTransparentDock(store: store, profile: profile(),
                    name: "dockstyle-\(style.name)-\(position.rawValue)-corners", directory: directory)
            }
            // Accessibility variants at the bottom position.
            for scheme in [ColorScheme.light, .dark] {
                store.updateSettings {
                    DockStyleQA.resetAppearance(&$0)
                    $0.customDockPosition = .bottom
                    $0.customDockTheme = scheme == .dark ? .dark : .light
                    style.apply(&$0)
                }
                for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true),
                                                          ("increase-contrast", .increased, false)] {
                    let name = "dockstyle-\(style.name)-bottom-\(DockStyleQA.schemeName(scheme))-\(variant)"
                    try await DockStyleQA.render(DockStyleQA.dockScene(store: store, profile: profile(), horizontal: true),
                        name: name, size: NSSize(width: 820, height: 150), scheme: scheme, directory: directory,
                        contrast: contrast, reduceTransparency: transparency)
                    try await DockStyleQA.renderTransparentDock(store: store, profile: profile(), name: name + "-corners",
                        directory: directory, contrast: contrast, reduceTransparency: transparency)
                }
            }
        }

        for scheme in [ColorScheme.light, .dark] {
            try await DockStyleQA.render(DockStyleQA.revealHandleSheet(), name: "dockstyle-reveal-handle-\(DockStyleQA.schemeName(scheme))",
                                         size: NSSize(width: 560, height: 230), scheme: scheme, directory: directory)
        }
        store.updateSettings {
            DockStyleQA.resetAppearance(&$0)
            $0.customDockTheme = .light
            DockStyleQA.styles[1].apply(&$0)
        }
        try await DockStyleQA.render(DockStyleQA.insetSheet(settings: store.state.settings), name: "dockstyle-floating-inset",
                                     size: NSSize(width: 1280, height: 560), scheme: .light, directory: directory)
    }
}
#endif
