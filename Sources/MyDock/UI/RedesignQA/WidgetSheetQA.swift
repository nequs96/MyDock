#if DEBUG
import AppKit
import SwiftUI

/// RD-08 render matrix (`MYDOCK_WIDGETSHEET_QA=1`): the widget settings sheet and the in-Dock popout shell.
///
/// - Sheets for one family per category plus Battery and Sticky Note, at every advertised layout (the
///   pager pages) in light, at the default layout in dark, and the first-run state of families with one.
///   Coverage is checked with `WidgetQAMatrix` over those families.
/// - One family on each widget surface (the Glass tint row appears only for glass).
/// - Reduce Transparency and Increase Contrast through `dockAccessibilityPreview`, never system settings.
/// - In-Dock popouts as `CustomDockView` hosts them (the popover is the one surface, scrolling), plus the
///   Trash sheet and Countdown under Reduce Transparency and Increase Contrast (FX-03).
/// - A long sheet at the default 640 pt cap.
///
/// Calendar uses the DEBUG production fixture and Battery a fixed reading, so nothing reads EventKit or IOKit.
/// Glass draws its documented fallback in these offscreen captures.
extension PremiumVisualQA {
    static func exportWidgetSheetUI(to directory: URL, store: ProfileStore) async throws {
        BatteryQAFixture.override = [BatteryReading(name: "InternalBattery-0", percentage: 84, isCharging: false, isInternal: true),
                                     BatteryReading(name: "AirPods Pro", percentage: 62, isCharging: true, isInternal: false)]
        CalendarQAFixture.override = .upcoming
        defer { BatteryQAFixture.override = nil; CalendarQAFixture.override = nil }

        let id = try store.createProfileAndPersist(kind: .custom, name: "Widget sheet QA")
        store.updateSettings {
            $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false
            $0.customDockPosition = .bottom; $0.customDockWidgetStyle = .cards
            // The Glass quick style: glass material, hairline edge, glass modules.
            $0.customDockMaterial = .liquidGlass; $0.customDockEdgeStyle = .hairline; $0.customDockWidgetSurface = .glass
        }
        let fixtures = WidgetSheetQA.fixtures()
        for item in fixtures.values { store.add(item, to: id) }
        func item(_ kind: String) -> DockItem { store.state.profiles.first { $0.id == id }!.items.first { $0.widgetKind == kind }! }
        func slug(_ text: String) -> String { text.lowercased().replacingOccurrences(of: " ", with: "-") }
        func sheet(_ kind: String, maximumHeight: CGFloat = WidgetSheetQA.fullHeight) -> some View {
            WidgetSheetQAHost { WidgetConfigurationSheet(store: store, item: item(kind), profileID: id, maximumHeight: maximumHeight) }
        }
        let size = NSSize(width: WidgetSheetMetrics.width, height: WidgetSheetQA.fullHeight)

        var matrix = WidgetQAMatrix()
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light }
            for kind in WidgetSheetQA.families {
                let options = WidgetPresentationCatalog.options(for: kind)
                let original = item(kind).widgetConfiguration?.widgetLayout
                // Light: every pager page. Dark: the default page.
                for option in scheme == .light ? options : options.filter({ $0.layout == WidgetPresentationCatalog.defaultLayout(for: kind) }) {
                    store.updateWidgetConfiguration(itemID: item(kind).id, in: id) { $0.widgetLayout = option.layout }
                    try await render(sheet(kind), name: "widgetsheet-\(slug(kind))-\(option.layout.rawValue)-\(suffix)",
                                     size: size, scheme: scheme, directory: directory)
                    matrix.record(kind, .layout(option.layout))
                }
                store.updateWidgetConfiguration(itemID: item(kind).id, in: id) { $0.widgetLayout = original }
            }
            // Surfaces: the Glass tint row exists only for glass.
            for surface in DockWidgetSurface.allCases {
                store.updateSettings { $0.customDockWidgetSurface = surface }
                try await render(sheet("Clock"), name: "widgetsheet-surface-\(surface.rawValue)-\(suffix)", size: size, scheme: scheme, directory: directory)
            }
            store.updateSettings { $0.customDockWidgetSurface = .glass }
            for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true), ("increase-contrast", .increased, false)] {
                try await render(sheet("Weather"), name: "widgetsheet-\(variant)-\(suffix)", size: size, scheme: scheme, directory: directory,
                                 contrast: contrast, reduceTransparency: transparency)
            }
            for kind in WidgetSheetQA.popoutFamilies {
                try await render(WidgetSheetQAPopoverHost { WidgetPopout(store: store, item: item(kind), profileID: id) },
                                 name: "widgetpopout-\(slug(kind))-\(suffix)",
                                 size: NSSize(width: WidgetPopoutMetrics.contentWidth + 2 * WidgetPopoutMetrics.padding + 40, height: WidgetSheetQA.popoutHeight(kind)),
                                 scheme: scheme, directory: directory)
            }
            try await render(WidgetSheetQAPopoverHost { WidgetPopout(store: store, item: item("Clock"), profileID: id).customizeExpandedForQA() },
                             name: "widgetpopout-clock-customize-\(suffix)", size: NSSize(width: 492, height: 960), scheme: scheme, directory: directory)
            // FX-09: with Customize open, the family's hero steps aside; its settings stay folded.
            try await render(WidgetSheetQAPopoverHost { WidgetPopout(store: store, item: item("Countdown"), profileID: id).customizeExpandedForQA() },
                             name: "widgetpopout-countdown-customize-\(suffix)", size: NSSize(width: 492, height: 1100), scheme: scheme, directory: directory)
            // FX-03: the Trash sheet (no repeated hero), and Start contrast under Increase Contrast.
            TrashQAFixture.override = (count: 12, errorMessage: nil)
            let trash = DockItem.widget("Trash")
            store.add(trash, to: id)
            try await render(WidgetSheetQAHost { WidgetConfigurationSheet(store: store, item: trash, profileID: id, maximumHeight: WidgetSheetQA.fullHeight) },
                             name: "widgetsheet-trash-\(suffix)", size: size, scheme: scheme, directory: directory)
            store.removeItem(trash.id, from: id)
            TrashQAFixture.override = nil
            for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true), ("increase-contrast", .increased, false)] {
                try await render(WidgetSheetQAPopoverHost { WidgetPopout(store: store, item: item("Countdown"), profileID: id) },
                                 name: "widgetpopout-countdown-\(suffix)-\(variant)",
                                 size: NSSize(width: WidgetPopoutMetrics.contentWidth + 2 * WidgetPopoutMetrics.padding + 40, height: WidgetSheetQA.popoutHeight("Countdown")),
                                 scheme: scheme, directory: directory, contrast: contrast, reduceTransparency: transparency)
            }
        }
        // First-run states of the families that have one (light).
        store.updateSettings { $0.customDockTheme = .light }
        CalendarQAFixture.override = .empty
        for kind in WidgetSheetQA.families where WidgetRegistry.definition(named: kind)?.capabilities.hasSetupState == true {
            let fresh = DockItem.widget(kind)
            store.add(fresh, to: id)
            try await render(WidgetSheetQAHost { WidgetConfigurationSheet(store: store, item: fresh, profileID: id, maximumHeight: WidgetSheetQA.fullHeight) },
                             name: "widgetsheet-\(slug(kind))-setup-light", size: size, scheme: .light, directory: directory)
            store.removeItem(fresh.id, from: id)
            matrix.record(kind, .setup)
        }
        CalendarQAFixture.override = .upcoming
        // The default 640 pt cap: a long sheet scrolls under its fixed header.
        try await render(sheet("Sticky Note", maximumHeight: 640), name: "widgetsheet-long-capped-light",
                         size: NSSize(width: WidgetSheetMetrics.width, height: 640), scheme: .light, directory: directory)
        try matrix.validate(registry: WidgetRegistry.all.filter { WidgetSheetQA.families.contains($0.name) })
    }
}

enum WidgetSheetQA {
    /// One family per category, plus Battery and Sticky Note.
    static let families = ["Quick Checklist", "Calendar", "System Activity", "Clock", "Weather", "Stock", "AI Limits", "Battery", "Sticky Note"]
    static let popoutFamilies = ["Clock", "Countdown", "Battery", "Sticky Note", "App Folder", "Hydration", "Time Progress"]
    static let fullHeight: CGFloat = 1180

    static func popoutHeight(_ kind: String) -> CGFloat {
        switch kind {
        case "Countdown": 470
        case "Sticky Note": 400
        case "App Folder": 520
        case "Hydration": 560
        default: 300
        }
    }

    /// Deterministic content: no system data, network or EventKit is read for these.
    static func fixtures() -> [String: DockItem] {
        var result: [String: DockItem] = [:]
        for item in WidgetSurfaceQA.liveFixtures() { result[item.widgetKind ?? item.title] = item }
        result["Calculator"] = nil
        result["Calendar"] = .widget("Calendar")
        result["System Activity"] = .widget("System Activity")
        result["AI Limits"] = .widget("AI Limits")
        result["Battery"] = .widget("Battery")
        var countdown = DockItem.widget("Countdown")
        countdown.widgetConfiguration?.countdownDurationSeconds = 25 * 60
        result["Countdown"] = countdown
        var hydration = DockItem.widget("Hydration")
        let morning = Calendar.current.startOfDay(for: .now)
        hydration.widgetConfiguration?.hydrationEntries = [9, 11, 14].map {
            HydrationEntry(timestamp: morning.addingTimeInterval(Double($0) * 3600), amountML: 250)
        }
        result["Hydration"] = hydration
        result["Time Progress"] = .widget("Time Progress")
        var folder = DockItem.widget("App Folder")
        folder.title = "Studio"
        folder.widgetConfiguration?.appFolderName = "Studio"
        folder.widgetConfiguration?.appFolderApplications = ["Calculator", "Notes", "Preview", "Stickies", "TextEdit", "Photo Booth"]
            .map { AppFolderApplication(url: URL(fileURLWithPath: "/System/Applications/\($0).app")) }
            + [AppFolderApplication(url: URL(fileURLWithPath: "/Applications/Archived Example.app"))]
        result["App Folder"] = folder
        return result
    }
}

/// The sheet at its own width, top-aligned on the page colour, as a sheet window shows it.
private struct WidgetSheetQAHost<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DockDesign.page)
    }
}

/// The popover content exactly as `CustomDockView` hosts a widget popout (no padding, no slab, the
/// shell draws no card), on a stand-in for the NSPopover window. Offscreen captures cannot draw the
/// popover's native material, so the stand-in is its opaque Reduce Transparency fill, over a wallpaper.
private struct WidgetSheetQAPopoverHost<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DockScrollView(.vertical) {
                content.frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
            }
        }
        .modifier(WidgetPopoverSurface())
        .fixedSize()
        .background(WidgetDesign.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DockStyleQA.wallpaper)
    }
}
#endif
