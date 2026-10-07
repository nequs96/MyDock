import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// RD-05 widget chrome: palette resolution, per-widget presentation values and unchanged widths.
struct RedesignWidgetChromeTests {
    @Test func paletteResolvesEveryAccentChoice() {
        for definition in WidgetRegistry.all {
            // Auto is Mono at rest and keeps the family colour only while active.
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .auto) == WidgetPalette.resolved(kind: definition.name, accent: .mono))
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .auto) == Color.primary)
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .auto, active: true) == WidgetPalette.accent(definition.name))
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .mono) == Color.primary)
            #expect(WidgetPalette.resolved(kind: definition.name, accent: .mono, active: true) == Color.primary)
            for color in DockProfileColor.allCases {
                // A named accent tints at rest and when active, exactly as before.
                #expect(WidgetPalette.resolved(kind: definition.name, accent: .profile(color)) == color.displayColor)
                #expect(WidgetPalette.resolved(kind: definition.name, accent: .profile(color), active: true) == color.displayColor)
            }
        }
        // Unknown kinds still resolve.
        #expect(WidgetPalette.resolved(kind: "Future Widget", accent: .auto) == Color.primary)
        #expect(WidgetPalette.resolved(kind: "Future Widget", accent: .auto, active: true) == WidgetPalette.everyday)
        // Semantic state colours are not accent-dependent.
        #expect(WidgetPalette.critical != Color.primary && WidgetPalette.warning != Color.primary)
    }

    @Test func autoAccentCaptionSaysColourShowsWhenActive() {
        #expect(WidgetAppearanceOptions.autoAccentCaption == "Neutral; color shows when active")
        #expect(WidgetAppearanceOptions.accentTitle(.auto) == "Automatic")
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

    /// Widths are pinned once, in RegistryCapabilityTests' golden table; every width lookup must agree with the options.
    @Test func everyFamilyWidthLookupMatchesItsOptions() {
        for definition in WidgetRegistry.all {
            for option in WidgetPresentationCatalog.options(for: definition.name) {
                #expect(WidgetPresentationCatalog.width(for: definition.name, layout: option.layout) == option.width, "\(definition.name)")
            }
        }
    }

    @Test func iconTreatmentsKeepRawValuesAndGetRedesignTitles() {
        #expect(WidgetIconAppearance.allCases.map(\.rawValue) == ["accent", "soft", "mono", "outline"])
        #expect(WidgetIconAppearance.allCases.map(\.displayTitle) == ["Color", "Soft", "Mono", "Outline"])
    }

    @Test @MainActor func moduleTypeNeverDropsBelowTheMinimumSize() {
        for size in DockDesign.Module.ValueSize.allCases {
            #expect(DockDesign.Module.pointSize(size) * WidgetModuleMetrics.minimumScale(size) >= DockDesign.Module.minimumTextSize - 0.001)
        }
    }

    @Test func narrowNetworkRatesStayShort() {
        #expect(NetworkRateText.short(nil) == "—")
        #expect(NetworkRateText.short(.nan) == "—")
        #expect(NetworkRateText.short(0) == "0")
        #expect(NetworkRateText.short(512) == "512")
        #expect(NetworkRateText.short(148_000) == "148K")
        // The decimal separator follows the locale (AuditLaneETests covers a comma locale).
        #expect(NetworkRateText.short(2_400_000, locale: Locale(identifier: "en_US")) == "2.4M")
        #expect(NetworkRateText.short(12_600_000_000) == "13G")
        #expect(NetworkRateText.short(-5) == "0")
    }

    @Test @MainActor func samplesAndFreshnessAreMinimalAndLabelled() {
        #expect(WidgetCardPreview.accessibilityLabel(kind: "Weather") == "Weather, sample preview")
        #expect(WidgetFreshnessState.fresh.dotColor != nil)
        #expect(WidgetFreshnessState.stale.dotColor != nil)
        #expect(WidgetFreshnessState.updating.dotColor == nil)
        #expect(WidgetFreshnessState.empty.dotColor == nil)
    }
}
