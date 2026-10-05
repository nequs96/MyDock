#if DEBUG
import AppKit
import SwiftUI

/// RD-09 render matrix (`MYDOCK_FACESA_QA=1`): Calendar/Reminders, Alarm, the utilities, Now Playing, Weather,
/// AirDrop and Trash.
///
/// - Live Dock faces for every family × advertised layout × widget surface × appearance, with labels-off
///   and side-Dock (54 pt) columns; coverage is checked with `WidgetQAMatrix`.
/// - Empty, setup and permission states, samples beside live faces, Reduce Transparency and Increase Contrast
///   through `dockAccessibilityPreview` (never system settings).
/// - Every family's popout in the RD-08 shell and in the settings sheet, plus popout states.
///
/// Calendar, Reminders, Now Playing and Trash read DEBUG fixtures, so nothing touches EventKit, players or
/// the real Trash. Glass draws its documented fallback in these offscreen captures.
extension PremiumVisualQA {
    static func exportFacesAUI(to directory: URL, store: ProfileStore) async throws {
        CalendarQAFixture.override = .upcoming
        RemindersQAFixture.override = .list
        TrashQAFixture.override = (count: 12, errorMessage: nil)
        NowPlayingQAFixture.override = (.appleMusic, FacesAQA.track)
        NowPlayingQAFixture.runningSources = [.appleMusic]
        defer {
            CalendarQAFixture.override = nil; CalendarQAFixture.simulatesDeniedAccess = false
            RemindersQAFixture.override = nil; TrashQAFixture.override = nil
            NowPlayingQAFixture.override = nil; NowPlayingQAFixture.runningSources = nil
        }

        let id = try store.createProfileAndPersist(kind: .custom, name: "Faces A QA")
        store.updateSettings {
            $0.onboardingComplete = true; $0.showRunningApps = false; $0.showTrash = false
            $0.customDockPosition = .bottom; $0.customDockWidgetStyle = .cards
            $0.customDockMaterial = .liquidGlass; $0.customDockEdgeStyle = .hairline; $0.customDockWidgetSurface = .glass
        }
        for item in FacesAQA.fixtures() { store.add(item, to: id) }
        func item(_ kind: String) -> DockItem { store.state.profiles.first { $0.id == id }!.items.first { $0.widgetKind == kind }! }
        func slug(_ text: String) -> String { text.lowercased().replacingOccurrences(of: " ", with: "-") }
        let items = FacesAQA.families.map(item)
        let base = store.state.settings

        var matrix = WidgetQAMatrix()
        let schemes: [(ColorScheme, String)] = [(.light, "light"), (.dark, "dark")]
        for (scheme, schemeName) in schemes {
            store.updateSettings { $0.customDockTheme = scheme == .dark ? .dark : .light }
            // 1. Live faces: every layout, labels off, side Dock, per surface.
            for surface in DockWidgetSurface.allCases {
                var settings = base; settings.customDockWidgetSurface = surface
                for (part, kinds) in [("a", Array(FacesAQA.families.prefix(8))), ("b", Array(FacesAQA.families.dropFirst(8)))] {
                    try await render(FacesAQAPage(title: "Faces A · \(surface.rawValue) · \(schemeName) · layouts | labels off | side") {
                        ForEach(kinds, id: \.self) { kind in
                            FacesAQAFamilyRow(store: store, item: item(kind), profileID: id, settings: settings)
                        }
                    }, name: "facesa-faces-\(part)-\(surface.rawValue)-\(schemeName)",
                    size: NSSize(width: 1000, height: CGFloat(60 + kinds.count * 92)), scheme: scheme, directory: directory)
                }
                for kind in FacesAQA.families {
                    for option in WidgetPresentationCatalog.options(for: kind) { matrix.record(kind, .layout(option.layout)) }
                }
            }
            // 2. Empty, setup and permission states on the faces.
            try await render(FacesAQAPage(title: "Faces A · empty, setup and permission states · \(schemeName)") {
                FacesAQAStates(store: store, profileID: id, settings: base)
            }, name: "facesa-states-\(schemeName)", size: NSSize(width: 1000, height: 560), scheme: scheme, directory: directory)
            for kind in FacesAQA.families where WidgetRegistry.definition(named: kind)?.capabilities.hasSetupState == true {
                matrix.record(kind, .setup)
            }
            // 3. Samples beside live faces.
            try await render(FacesAQAPage(title: "Faces A · sample (left, creation appearance) and live (right) · \(schemeName)") {
                FacesAQASamplesVersusLive(store: store, items: items, profileID: id, settings: base)
            }, name: "facesa-sample-vs-live-\(schemeName)", size: NSSize(width: 1000, height: 640), scheme: scheme, directory: directory)
            // 4. Accessibility.
            for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true), ("increase-contrast", .increased, false)] {
                try await render(FacesAQAPage(title: "Faces A · \(variant.replacingOccurrences(of: "-", with: " ")) · \(schemeName)") {
                    ForEach(DockWidgetSurface.allCases, id: \.self) { surface in
                        FacesAQADefaultStrip(store: store, items: items, profileID: id, settings: base.facesA(surface: surface))
                    }
                }, name: "facesa-\(variant)-\(schemeName)", size: NSSize(width: 1000, height: 420), scheme: scheme, directory: directory,
                contrast: contrast, reduceTransparency: transparency)
            }
            // 5. Popouts in the RD-08 shell.
            for kind in FacesAQA.families {
                try await render(FacesAQAPopoverHost { WidgetPopout(store: store, item: item(kind), profileID: id) },
                                 name: "facesa-popout-\(slug(kind))-\(schemeName)",
                                 size: NSSize(width: WidgetPopoutMetrics.contentWidth + 2 * WidgetPopoutMetrics.padding + 40, height: FacesAQA.popoutHeight(kind)),
                                 scheme: scheme, directory: directory)
            }
        }
        // 6. Popouts inside the settings sheet (light), and the Increase Contrast / Reduce Transparency popouts.
        store.updateSettings { $0.customDockTheme = .light }
        for kind in FacesAQA.families {
            try await render(FacesAQASheetHost { WidgetConfigurationSheet(store: store, item: item(kind), profileID: id, maximumHeight: 1500) },
                             name: "facesa-sheet-\(slug(kind))-light", size: NSSize(width: WidgetSheetMetrics.width, height: 1500), scheme: .light, directory: directory)
        }
        for (variant, contrast, transparency) in [("reduce-transparency", ColorSchemeContrast.standard, true), ("increase-contrast", .increased, false)] {
            for kind in ["Calculator", "Trash", "Quick Checklist"] {
                try await render(FacesAQAPopoverHost { WidgetPopout(store: store, item: item(kind), profileID: id) },
                                 name: "facesa-popout-\(slug(kind))-\(variant)-light",
                                 size: NSSize(width: WidgetPopoutMetrics.contentWidth + 2 * WidgetPopoutMetrics.padding + 40, height: FacesAQA.popoutHeight(kind)),
                                 scheme: .light, directory: directory, contrast: contrast, reduceTransparency: transparency)
            }
        }
        // 7. Popout states.
        func popout(_ kind: String, _ state: String, item override: DockItem? = nil, height: CGFloat? = nil) async throws {
            let shown = override ?? item(kind)
            try await render(FacesAQAPopoverHost { WidgetPopout(store: store, item: shown, profileID: id) },
                             name: "facesa-popout-\(slug(kind))-\(state)-light",
                             size: NSSize(width: WidgetPopoutMetrics.contentWidth + 2 * WidgetPopoutMetrics.padding + 40, height: height ?? FacesAQA.popoutHeight(kind)),
                             scheme: .light, directory: directory)
        }
        CalendarQAFixture.override = .empty
        try await popout("Calendar", "empty")
        CalendarQAFixture.override = .ongoing
        try await popout("Calendar", "ongoing")
        CalendarQAFixture.simulatesDeniedAccess = true
        try await popout("Calendar", "denied")
        CalendarQAFixture.simulatesDeniedAccess = false
        CalendarQAFixture.override = .upcoming
        RemindersQAFixture.override = .denied
        try await popout("Reminders", "denied")
        RemindersQAFixture.override = .empty
        try await popout("Reminders", "empty")
        RemindersQAFixture.override = .list
        TrashQAFixture.override = (count: 0, errorMessage: nil)
        try await popout("Trash", "empty")
        TrashQAFixture.override = (count: 0, errorMessage: TrashStatus.isolatedMessage)
        try await popout("Trash", "unavailable")
        TrashQAFixture.override = (count: 12, errorMessage: nil)
        NowPlayingQAFixture.override = nil
        try await popout("Now Playing", "nothing-playing")
        NowPlayingQAFixture.override = (.appleMusic, FacesAQA.track)
        var unsetWeather = DockItem.widget("Weather")
        store.add(unsetWeather, to: id)
        unsetWeather = store.state.profiles.first { $0.id == id }!.items.first { $0.id == unsetWeather.id }!
        try await popout("Weather", "setup", item: unsetWeather, height: 620)
        // Dusk: a place where the next hours cross sunset, so day and night glyphs sit side by side.
        var dusk = DockItem.widget("Weather")
        dusk.widgetConfiguration = FacesAQA.duskWeatherConfiguration(now: .now)
        store.add(dusk, to: id)
        try await popout("Weather", "dusk", item: store.state.profiles.first { $0.id == id }!.items.first { $0.id == dusk.id }!, height: 620)
        for kind in ["Alarm", "Quick Checklist", "Text Snippets", "Quick Links", "File Shelf", "Color Picker"] {
            let fresh = DockItem.widget(kind)
            store.add(fresh, to: id)
            try await popout(kind, "empty", item: store.state.profiles.first { $0.id == id }!.items.first { $0.id == fresh.id }!, height: 700)
        }
        try matrix.validate(registry: WidgetRegistry.all.filter { FacesAQA.families.contains($0.name) })
    }
}

enum FacesAQA {
    static let families = ["Calendar", "Reminders", "Alarm", "Disk Space", "Calculator", "Quick Checklist", "File Shelf", "Text Snippets",
                           "Quick Links", "Unit Converter", "Color Picker", "Now Playing", "Weather", "AirDrop", "Trash"]

    static let track = NowPlayingSnapshot(title: "Dreams", artist: "Fleetwood Mac", album: "Rumours", isPlaying: true,
                                          position: 74, duration: 257, updatedAt: .now, artworkURL: nil)

    static func popoutHeight(_ kind: String) -> CGFloat {
        switch kind {
        case "Calculator": 760
        case "Now Playing", "Weather", "Text Snippets", "File Shelf", "Color Picker", "Alarm", "Quick Links": 900
        case "Trash", "Disk Space": 520
        default: 720
        }
    }

    /// Forecast hours start on the hour, as the provider's do.
    static func forecastHour(_ offset: Int, after now: Date) -> Date {
        Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600 + Double(offset) * 3600)
    }

    /// A Weather configuration at a longitude where the sun sets within the next six hours (derived with
    /// `WeatherDaylight`, so the render shows the per-hour day/night glyphs whatever time it runs). Its hours
    /// read in the place's own solar time zone.
    static func duskWeatherConfiguration(now: Date) -> WidgetConfiguration {
        let latitude = 40.0
        let longitude = stride(from: -180.0, to: 180.0, by: 5.0).first { longitude in
            WeatherDaylight.isDay(at: forecastHour(1, after: now), latitude: latitude, longitude: longitude)
                && !WeatherDaylight.isDay(at: forecastHour(4, after: now), latitude: latitude, longitude: longitude)
        } ?? 0
        let zone = TimeZone(secondsFromGMT: Int((longitude / 15).rounded()) * 3600)?.identifier ?? "UTC"
        var configuration = DockItem.widget("Weather").widgetConfiguration ?? WidgetConfiguration()
        configuration.weatherLocation = WeatherLocation(id: "qa-dusk", name: "Dusk", administrativeArea: nil, country: nil,
                                                        latitude: latitude, longitude: longitude, timeZoneIdentifier: zone)
        configuration.weatherLayout = .hourlyForecast
        configuration.weatherForecastHours = 6
        var hourly: [WeatherHour] = []
        for offset in 1...6 {
            let code: Int = offset % 2 == 0 ? 0 : 2
            hourly.append(WeatherHour(timestamp: forecastHour(offset, after: now), temperature: Double(18 - offset),
                                      precipitationProbability: nil, weatherCode: code))
        }
        configuration.cachedWeatherForecast = WeatherForecast(temperature: 18, apparentTemperature: 17, relativeHumidity: 60, precipitation: 0, windSpeed: 6,
            weatherCode: 1, isDay: true, fetchedAt: now, timeZoneIdentifier: zone, hourly: hourly)
        return configuration
    }

    static var weatherLocation: WeatherLocation {
        WeatherLocation(id: "qa-warsaw", name: "Warsaw", administrativeArea: "Masovia", country: "Poland", latitude: 52.23, longitude: 21.01, timeZoneIdentifier: "Europe/Warsaw")
    }

    /// Deterministic content: no system data, network, EventKit or players are read for these.
    static func fixtures() -> [DockItem] {
        families.map { kind in
            var item = DockItem.widget(kind)
            switch kind {
            case "Alarm":
                item.widgetConfiguration?.alarms = [DockAlarm(title: "Morning", hour: 7, minute: 30, repeatWeekdays: [2, 3, 4, 5, 6], isEnabled: true),
                                                     DockAlarm(title: "Gym", hour: 18, minute: 15, repeatWeekdays: [], isEnabled: false)]
            case "Quick Checklist":
                var done = QuickChecklistEntry(title: "Water the plants"); done.isComplete = true
                item.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "Plan the weekend"), QuickChecklistEntry(title: "Pick up groceries"), done]
            case "File Shelf":
                item.widgetConfiguration?.shelfFiles = [ShelfFile(url: URL(fileURLWithPath: "/System/Applications/Calculator.app")),
                                                        ShelfFile(url: URL(fileURLWithPath: "/Sample/Moved Presentation.pdf"))]
            case "Text Snippets":
                item.widgetConfiguration?.textSnippets = [TextSnippet(title: "Email reply", text: "Thanks for getting in touch — I’ll reply properly tomorrow."),
                                                          TextSnippet(title: "Delivery address", text: "123 Example Street, Springfield")]
            case "Quick Links":
                item.widgetConfiguration?.quickLinks = [QuickLink(title: "Project workspace", url: URL(string: "https://example.com/project")!),
                                                        QuickLink(title: "Reading list", url: URL(string: "https://example.org/reading")!)]
            case "Color Picker":
                item.widgetConfiguration?.savedColors = ["#5EA3A8", "#E07A5F", "#3D405B", "#F2CC8F"]
            case "Weather":
                item.widgetConfiguration?.weatherLocation = weatherLocation
                item.widgetConfiguration?.weatherLayout = .hourlyForecast
                item.widgetConfiguration?.cachedWeatherForecast = WeatherForecast(temperature: 21, apparentTemperature: 20, relativeHumidity: 50, precipitation: 0, windSpeed: 8,
                    weatherCode: 2, isDay: true, fetchedAt: .now, timeZoneIdentifier: "Europe/Warsaw",
                    hourly: (1...6).map { .init(timestamp: forecastHour($0, after: .now), temperature: Double(21 + $0 % 3), precipitationProbability: $0 * 5, weatherCode: $0 > 3 ? 61 : 2) })
            default: break
            }
            return item
        }
    }
}

private extension AppSettings {
    func facesA(surface: DockWidgetSurface) -> AppSettings {
        var copy = self
        copy.customDockWidgetSurface = surface
        return copy
    }
}

private struct FacesAQAWallpaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: scheme == .dark
                       ? [Color(red: 0.10, green: 0.17, blue: 0.32), Color(red: 0.33, green: 0.20, blue: 0.27)]
                       : [Color(red: 0.47, green: 0.65, blue: 0.90), Color(red: 0.95, green: 0.71, blue: 0.58)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
        .accessibilityHidden(true)
    }
}

private struct FacesAQACaption: View {
    var text: String
    var body: some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

private struct FacesAQAPage<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            content
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FacesAQAWallpaper().ignoresSafeArea())
    }
}

/// A Dock-like strip with Dock padding; modules stay concentric.
private struct FacesAQAStrip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 8) { content }
            .padding(7)
            .dockGlass(.clear, in: RoundedRectangle(cornerRadius: DockDesign.Module.defaultRadius + 7, style: .continuous))
            .environment(\.dockModuleRadius, DockDesign.Module.defaultRadius)
    }
}

/// One family: every layout, the default layout with labels off, and the side-Dock face.
private struct FacesAQAFamilyRow: View {
    @ObservedObject var store: ProfileStore
    var item: DockItem
    var profileID: UUID
    var settings: AppSettings
    var body: some View {
        let kind = item.widgetKind ?? item.title
        let options = WidgetPresentationCatalog.options(for: kind)
        var labelsOff = settings; labelsOff.showWidgetLabels = false
        var side = settings; side.customDockPosition = .left
        return VStack(alignment: .leading, spacing: 4) {
            FacesAQACaption(text: kind + " · " + options.map(\.title).joined(separator: ", "))
            HStack(spacing: 14) {
                FacesAQAStrip {
                    ForEach(options) { option in
                        WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: settings, layoutOverride: option.layout)
                    }
                }
                FacesAQAStrip {
                    WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: labelsOff,
                                      layoutOverride: WidgetPresentationCatalog.defaultLayout(for: kind))
                }
                FacesAQAStrip {
                    WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: side)
                }
            }
        }
    }
}

/// Every family at its default layout.
private struct FacesAQADefaultStrip: View {
    @ObservedObject var store: ProfileStore
    var items: [DockItem]
    var profileID: UUID
    var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FacesAQACaption(text: settings.customDockWidgetSurface.rawValue)
            FacesAQAStrip {
                ForEach(items.prefix(8)) { item in WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: settings) }
            }
            FacesAQAStrip {
                ForEach(items.dropFirst(8)) { item in WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: settings) }
            }
        }
    }
}

/// Truthful empty, setup and permission faces (the pure faces the live views render).
private struct FacesAQAStates: View {
    @ObservedObject var store: ProfileStore
    var profileID: UUID
    var settings: AppSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach([(WidgetLayout.compact, CGFloat(88)), (.wide, 154)], id: \.1) { layout, width in
                VStack(alignment: .leading, spacing: 4) {
                    FacesAQACaption(text: "Calendar denied · no events · Reminders set up · 1 overdue · Alarm off · \(layout.rawValue)")
                    FacesAQAStrip {
                        face(width, layout, "Calendar") {
                            CalendarDockFace(date: .now, showsEvent: layout == .wide, emptyTitle: "Unavailable", emptyDetail: "Allow access")
                        }
                        face(width, layout, "Calendar") { CalendarDockFace(date: .now, showsEvent: layout == .wide) }
                        face(width, layout, "Reminders") { RemindersModuleFace(count: nil, context: "Choose a list") }
                        face(width, layout, "Reminders") { RemindersModuleFace(count: 4, overdue: 1, context: "Errands") }
                        face(layout == .wide ? 124 : 88, layout == .wide ? .standard : .compact, "Alarm") { AlarmDockFace(time: nil, title: nil) }
                    }
                }
            }
            FacesAQACaption(text: "Trash empty · full · unavailable · AirDrop at rest · targeted (icon and compact)")
            FacesAQAStrip {
                ForEach([(WidgetLayout.icon, CGFloat(54)), (.compact, 88)], id: \.1) { layout, width in
                    face(width, layout, "Trash") { TrashDockFace(count: 0) }
                    face(width, layout, "Trash") { TrashDockFace(count: 3) }
                    face(width, layout, "Trash") { TrashDockFace(count: 0, errorMessage: "Unavailable") }
                    face(width, layout, "AirDrop") { AirDropDockFace() }
                    face(width, layout, "AirDrop") { AirDropDockFace(targeted: true) }
                }
            }
            FacesAQACaption(text: "Empty collections · Weather without a city · Now Playing with no players (live views)")
            FacesAQAStrip {
                ForEach(["File Shelf", "Text Snippets", "Quick Links", "Weather"], id: \.self) { kind in
                    WidgetCompactView(store: store, item: .widget(kind), profileID: profileID, sampleMode: false, presentationSettings: settings, layoutOverride: .wide)
                }
                face(186, .wide, "Now Playing") { MediaDockFace(title: "No players", artist: nil, artwork: nil, isPlaying: false) }
            }
        }
    }
    private func face<Content: View>(_ width: CGFloat, _ layout: WidgetLayout, _ kind: String, @ViewBuilder _ content: () -> Content) -> some View {
        WidgetContainer(width: width, kind: kind) { content() }
            .environment(\.dockWidgetContentWidth, width)
            .environment(\.widgetLayout, layout)
            .widgetPresentation(WidgetPresentationValues(configuration: nil, settings: settings))
    }
}

/// The gallery sample next to the live face, per family at its default layout.
private struct FacesAQASamplesVersusLive: View {
    @ObservedObject var store: ProfileStore
    var items: [DockItem]
    var profileID: UUID
    var settings: AppSettings
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: 3), alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                let kind = item.widgetKind ?? item.title
                let layout = WidgetPresentationCatalog.defaultLayout(for: kind)
                VStack(alignment: .leading, spacing: 3) {
                    FacesAQACaption(text: kind)
                    FacesAQAStrip {
                        WidgetCardPreview(kind: kind, width: CGFloat(WidgetPresentationCatalog.width(for: kind, layout: layout)), layout: layout)
                            .environment(\.dockWidgetSurface, settings.customDockWidgetSurface)
                        WidgetCompactView(store: store, item: item, profileID: profileID, presentationSettings: settings)
                    }
                }
            }
        }
    }
}

/// The popover content exactly as `CustomDockView` hosts a widget popout since FX-03: no padding, no slab,
/// the shell draws no card. Offscreen captures cannot draw the popover's native material, so the stand-in
/// is its opaque Reduce Transparency fill (as in `WidgetSheetQA`).
private struct FacesAQAPopoverHost<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DockScrollView(.vertical) {
                content.frame(minWidth: 250, minHeight: 150, alignment: .topLeading)
            }
        }
        .modifier(WidgetPopoverSurface())
        .background(WidgetDesign.surface)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(WidgetDesign.surface)
    }
}

/// The settings sheet at its own width on the page colour.
private struct FacesAQASheetHost<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(DockDesign.page)
    }
}
#endif
