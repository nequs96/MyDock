#if DEBUG
import AppKit
import SwiftUI

/// RD-06 render matrix (`MYDOCK_GALLERY_QA=1`): the Add Item gallery in light and dark at
/// 920×740 and 700×600, plus Reduce Transparency and Increase Contrast variants injected
/// through `dockAccessibilityPreview`. Glass draws its fallback in these captures.
///
/// The Apps segment uses this Mac's real application scan, awaited once, plus one synthetic
/// copy of the first app at `/Volumes/Archive/Applications` so duplicate-name disambiguation is
/// visible. Nothing is added to a real Dock; every `add` closure is a no-op.
extension PremiumVisualQA {
    static func exportGalleryUI(to directory: URL, store: ProfileStore) async throws {
        var scan = await InstalledAppCatalog.scan()
        if let first = scan.applications.first {
            var copy = first
            copy.url = URL(fileURLWithPath: "/Volumes/Archive/Applications/\(first.name).app")
            copy.version = "1.0"
            scan.applications.insert(copy, at: 1)
        }
        let everyday = DockProfile(name: "Everyday", kind: .custom, items: [.widget("Battery"), .widget("Stopwatch")])
        var withApp = everyday
        if let app = scan.applications.dropFirst(2).first { withApp.items.append(app.dockItem) }
        let native = DockProfile(name: "System Dock", kind: .native, items: [])
        let detailFamilies = ["Quick Checklist", "Calendar", "System Activity", "Clock", "Weather", "Stock", "AI Limits"]

        func library(_ profile: DockProfile, query: String = "", category: String = "All", allowsAdding: Bool = true,
                     state: AddLibraryPreviewState = AddLibraryPreviewState()) -> some View {
            var state = state
            state.scan = scan
            return AddLibrary(store: store, profile: profile, allowsAdding: allowsAdding, initialQuery: query, initialCategory: category,
                              add: { _ in }, switchProfile: { _ in }, newDock: {}, settings: {}, browse: { _ in }, close: {})
                .environment(\.addLibraryPreview, state)
        }

        var presetThumbnails: some View {
            VStack(spacing: 8) {
                ForEach(DockStarterPreset.allCases) { PresetLibraryTile(preset: $0) }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DockDesign.page)
        }

        let sizes: [(String, NSSize)] = [("920", NSSize(width: 920, height: 740)), ("700", NSSize(width: 700, height: 600))]
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            for (sizeName, size) in sizes {
                let tag = "\(sizeName)-\(suffix)"
                try await render(library(everyday, category: "Widgets"), name: "gallery-widgets-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(startSection: .time)),
                                 name: "gallery-widgets-scrolled-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(withApp, category: "Applications"), name: "gallery-apps-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(everyday, category: "System"), name: "gallery-more-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(everyday, query: "clock", category: "Widgets"), name: "gallery-search-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(everyday, query: "no-match-xyz", category: "Widgets"), name: "gallery-search-empty-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(native, category: "Widgets"), name: "gallery-native-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(native, category: "System"), name: "gallery-native-more-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(recentlyAdded: ["widget:Calendar", "widget:Clock"])),
                                 name: "gallery-added-\(tag)", size: size, scheme: scheme, directory: directory)
                try await render(library(everyday, category: "Widgets", allowsAdding: false), name: "gallery-no-dock-\(tag)", size: size, scheme: scheme, directory: directory)
                for family in detailFamilies {
                    let slug = family.lowercased().replacingOccurrences(of: " ", with: "-")
                    try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(detailFamily: family)),
                                     name: "gallery-detail-\(slug)-\(tag)", size: size, scheme: scheme, directory: directory)
                }
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(detailFamily: "Battery")),
                                 name: "gallery-detail-added-battery-\(tag)", size: size, scheme: scheme, directory: directory)
                // FX-07: keyboard focus ring on a hero tile, and on a grid tile beside the search highlight's wash.
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(focusedTile: "suggested:Weather")),
                                 name: "gallery-focused-\(tag)", size: size, scheme: scheme, directory: directory)
            }
            // FX-07: the text-free preset thumbnails (glyph-only module chips in a mini Dock).
            try await render(presetThumbnails, name: "gallery-presets-\(suffix)", size: NSSize(width: 640, height: 560), scheme: scheme, directory: directory)
            for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true), ("increase-contrast", .increased, false)] {
                let size = NSSize(width: 920, height: 740)
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(recentlyAdded: ["widget:Calendar"])),
                                 name: "gallery-widgets-\(variant)-\(suffix)", size: size, scheme: scheme, directory: directory,
                                 contrast: contrast, reduceTransparency: transparency)
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(detailFamily: "Weather", detailLayout: .wide)),
                                 name: "gallery-detail-\(variant)-\(suffix)", size: size, scheme: scheme, directory: directory,
                                 contrast: contrast, reduceTransparency: transparency)
                try await render(library(withApp, category: "Applications"), name: "gallery-apps-\(variant)-\(suffix)", size: size, scheme: scheme,
                                 directory: directory, contrast: contrast, reduceTransparency: transparency)
                try await render(library(everyday, category: "Widgets", state: AddLibraryPreviewState(focusedTile: "suggested:Weather")),
                                 name: "gallery-focused-\(variant)-\(suffix)", size: size, scheme: scheme, directory: directory,
                                 contrast: contrast, reduceTransparency: transparency)
                try await render(presetThumbnails, name: "gallery-presets-\(variant)-\(suffix)", size: NSSize(width: 640, height: 560),
                                 scheme: scheme, directory: directory, contrast: contrast, reduceTransparency: transparency)
            }
        }
        try await render(WidgetGalleryView(add: { _, _ in }, onClose: {}), name: "gallery-debug-catalog", size: NSSize(width: 960, height: 680),
                         scheme: .dark, directory: directory)
    }
}
#endif
