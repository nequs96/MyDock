import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// RD-05 widget chrome: palette resolution, per-widget presentation values and unchanged widths.
struct RedesignWidgetChromeTests {
    @Test func paletteResolvesEveryAccentChoice() {
        for definition in WidgetRegistry.all {
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .auto) == WidgetPalette.accent(definition.name))
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .mono) == Color.primary)
            for color in DockProfileColor.allCases {
                #expect(WidgetPalette.resolved(kind: definition.name, accent: .profile(color)) == color.displayColor)
            }
        }
        // Unknown kinds still resolve.
        #expect(WidgetPalette.resolved(kind: "Future Widget", accent: .auto) == WidgetPalette.everyday)
    }

    @Test func paletteKeepsOneHuePerCategory() {
        let expected: [WidgetCategory: Color] = [.ai: WidgetPalette.ai, .system: WidgetPalette.system, .business: WidgetPalette.business,
                                                 .personal: WidgetPalette.personal, .utilities: WidgetPalette.everyday,
                                                 .productivity: WidgetPalette.everyday, .time: WidgetPalette.everyday]
        for definition in WidgetRegistry.all where definition.name != "Weather" {
            #expect(WidgetPalette.accent(definition.name) == expected[definition.category], "\(definition.name)")
        }
        #expect(WidgetPalette.accent("Weather") == WidgetPalette.weather)
        // Harmonised and desaturated: shared saturation/brightness bands per appearance, lighter on dark glass.
        for family in WidgetPalette.Family.allCases {
            let light = family.components(dark: false)
            let dark = family.components(dark: true)
            #expect((0.35...0.70).contains(light.saturation), "\(family) light saturation \(light.saturation)")
            #expect((0.30...0.55).contains(dark.saturation), "\(family) dark saturation \(dark.saturation)")
            #expect((0.54...0.75).contains(light.brightness), "\(family) light brightness \(light.brightness)")
            #expect((0.76...0.92).contains(dark.brightness), "\(family) dark brightness \(dark.brightness)")
            #expect(dark.brightness > light.brightness)
            #expect(dark.saturation < light.saturation)
            #expect(abs(dark.hue - light.hue) < 0.03, "\(family) keeps one hue")
        }
        #expect(Set(WidgetPalette.Family.allCases.map { Int(($0.components(dark: false).hue * 36).rounded()) }).count == WidgetPalette.Family.allCases.count)
    }

    @Test func labelVisibilityPrefersTheWidgetOverride() {
        var configuration = WidgetConfiguration()
        #expect(WidgetPresentationValues.showsLabel(configuration: nil, dockShowsLabels: true))
        #expect(!WidgetPresentationValues.showsLabel(configuration: nil, dockShowsLabels: false))
        #expect(WidgetPresentationValues.showsLabel(configuration: configuration, dockShowsLabels: true))
        #expect(!WidgetPresentationValues.showsLabel(configuration: configuration, dockShowsLabels: false))
        configuration.showsLabel = false
        #expect(!WidgetPresentationValues.showsLabel(configuration: configuration, dockShowsLabels: true))
        configuration.showsLabel = true
        #expect(WidgetPresentationValues.showsLabel(configuration: configuration, dockShowsLabels: false))
    }

    @Test func presentationValuesFollowSettingsAndConfiguration() {
        var settings = AppSettings()
        let defaults = WidgetPresentationValues(configuration: WidgetConfiguration(), settings: settings)
        #expect(defaults.surface == .tile)
        #expect(defaults.accent == .auto)
        #expect(defaults.showsLabel == settings.showWidgetLabels)
        #expect(defaults.glassTint == WidgetGlassTint.none)

        settings.customDockWidgetSurface = .glass
        settings.showWidgetLabels = false
        var configuration = WidgetConfiguration()
        configuration.widgetAccent = .profile(.teal)
        configuration.glassTint = .accent
        let custom = WidgetPresentationValues(configuration: configuration, settings: settings)
        #expect(custom.surface == .glass)
        #expect(custom.accent == .profile(.teal))
        #expect(!custom.showsLabel)
        #expect(custom.glassTint == .accent)

        settings.customDockWidgetSurface = .plain
        configuration.showsLabel = true
        configuration.widgetAccent = .mono
        let plain = WidgetPresentationValues(configuration: configuration, settings: settings)
        #expect(plain.surface == .plain)
        #expect(plain.accent == .mono)
        #expect(plain.showsLabel)
    }

    /// Snapshot of the widths before the redesign. Chrome must never change geometry.
    @Test func everyFamilyKeepsItsWidths() {
        let market: [WidgetLayout: Double] = [.compact: 108, .trend: 176]
        let schedule: [WidgetLayout: Double] = [.compact: 88, .wide: 154]
        let timer: [WidgetLayout: Double] = [.compact: 88, .standard: 124]
        let generic: [WidgetLayout: Double] = [.compact: 88, .standard: 124]
        let quickAction: [WidgetLayout: Double] = [.icon: 54, .compact: 88]
        let quickTool: [WidgetLayout: Double] = [.icon: 54, .compact: 104]
        let saved: [WidgetLayout: Double] = [.compact: 96, .wide: 164]
        let snapshot: [String: [WidgetLayout: Double]] = [
            "Stock": market, "Watchlist": market, "Calendar": schedule, "Reminders": schedule,
            "Now Playing": [.compact: 112, .wide: 186], "Weather": [.compact: 92, .standard: 132, .wide: 184],
            "Focus Timer": timer, "Sticky Note": [.standard: 120, .wide: 176], "Battery": [.compact: 90, .wide: 156],
            "Shortcuts": quickAction, "Stripe": generic, "Paddle": generic, "Shopify": generic,
            "Clock": [.compact: 104, .standard: 112], "World Clock": [.compact: 88, .wide: 164],
            "Stopwatch": timer, "Countdown": timer, "Alarm": generic, "Time Progress": generic, "Hydration": generic,
            "System Activity": [.compact: 86, .meter: 92, .trend: 158], "Network Activity": [.compact: 100, .trend: 170],
            "AI Limits": generic, "AI Activity": [.compact: 88, .standard: 126, .trend: 184],
            "AirDrop": quickAction, "Trash": quickAction, "Disk Space": [.compact: 104, .wide: 158],
            "Calculator": quickAction, "Quick Checklist": schedule, "File Shelf": saved, "Text Snippets": saved,
            "Quick Links": saved, "Unit Converter": quickTool, "Color Picker": quickTool, "App Folder": quickAction
        ]
        #expect(Set(snapshot.keys) == Set(WidgetRegistry.all.map(\.name)))
        for definition in WidgetRegistry.all {
            let options = WidgetPresentationCatalog.options(for: definition.name)
            let widths = Dictionary(uniqueKeysWithValues: options.map { ($0.layout, $0.width) })
            #expect(widths == snapshot[definition.name], "\(definition.name)")
            for option in options {
                #expect(WidgetPresentationCatalog.width(for: definition.name, layout: option.layout) == snapshot[definition.name]?[option.layout])
            }
        }
    }

    @Test func iconTreatmentsKeepRawValuesAndGetRedesignTitles() {
        #expect(WidgetIconAppearance.allCases.map(\.rawValue) == ["accent", "soft", "mono", "outline"])
        #expect(WidgetIconAppearance.allCases.map(\.displayTitle) == ["Color", "Soft", "Mono", "Outline"])
    }

    @Test func moduleTypeNeverDropsBelowTheMinimumSize() {
        for size in DockDesign.Module.ValueSize.allCases {
            #expect(DockDesign.Module.pointSize(size) * WidgetModuleMetrics.minimumScale(size) >= DockDesign.Module.minimumTextSize - 0.001)
        }
        #expect(MetricText.valueSize(22) == .large)
        #expect(MetricText.valueSize(20) == .large)
        #expect(MetricText.valueSize(19) == .medium)
        #expect(MetricText.valueSize(15) == .medium)
        #expect(MetricText.valueSize(12) == .small)
    }

    @Test func narrowNetworkRatesStayShort() {
        #expect(NetworkRateText.short(nil) == "—")
        #expect(NetworkRateText.short(.nan) == "—")
        #expect(NetworkRateText.short(0) == "0")
        #expect(NetworkRateText.short(512) == "512")
        #expect(NetworkRateText.short(148_000) == "148K")
        #expect(NetworkRateText.short(2_400_000) == "2.4M")
        #expect(NetworkRateText.short(12_600_000_000) == "13G")
        #expect(NetworkRateText.short(-5) == "0")
    }

    @Test func samplesAndFreshnessAreMinimalAndLabelled() {
        #expect(WidgetCardPreview.accessibilityLabel(kind: "Weather") == "Weather, sample preview")
        #expect(WidgetFreshnessState.fresh.dotColor != nil)
        #expect(WidgetFreshnessState.stale.dotColor != nil)
        #expect(WidgetFreshnessState.updating.dotColor == nil)
        #expect(WidgetFreshnessState.empty.dotColor == nil)
    }
}
