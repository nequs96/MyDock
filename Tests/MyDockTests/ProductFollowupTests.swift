import Foundation
import Testing
@testable import MyDock

struct ProductFollowupTests {
    @Test func taskSearchFindsUsefulFamiliesAcrossNameAndTaskTerms() throws {
        let calendar = try #require(WidgetRegistry.definition(named: "Calendar"))
        let checklist = try #require(WidgetRegistry.definition(named: "Quick Checklist"))
        let activity = try #require(WidgetRegistry.definition(named: "AI Activity"))
        #expect(WidgetDiscovery.matches(calendar, query: "  next   meeting "))
        #expect(WidgetDiscovery.matches(checklist, query: "private tasks"))
        #expect(WidgetDiscovery.matches(activity, query: "Claude sessions"))
        #expect(!WidgetDiscovery.matches(calendar, query: "meeting revenue"))
        #expect(WidgetRegistry.all.allSatisfy { WidgetDiscovery.matches($0, query: $0.name) })
    }

    @Test func capabilityFiltersPreserveInventoryAndDescribeOptionalPermissions() throws {
        let definitions = WidgetRegistry.all
        let noAccount = Set(definitions.filter(WidgetDiscoveryFilter.noConnection.includes).map(\.id))
        let connected = Set(definitions.filter(WidgetDiscoveryFilter.connected.includes).map(\.id))
        #expect(noAccount.isDisjoint(with: connected))
        #expect(noAccount.union(connected) == Set(definitions.map(\.id)))
        let weather = try #require(WidgetRegistry.definition(named: "Weather"))
        #expect(WidgetDiscoveryFilter.noConnection.includes(weather))
        #expect(WidgetDiscoveryFilter.permissions.includes(weather))
        #expect(WidgetDiscoveryFilter.connected.includes(try #require(WidgetRegistry.definition(named: "Stripe"))))
        #expect(WidgetDiscoveryFilter.privateContent.includes(try #require(WidgetRegistry.definition(named: "Text Snippets"))))
    }

    @Test func repeatedWidgetsCanHaveIndependentConfigurationWithoutAllowingDuplicateApps() {
        let first = DockItem.widget("Clock")
        var another = DockItem.widget("Clock")
        another.widgetConfiguration?.widgetLayout = .standard
        #expect(WidgetDiscovery.canAdd(first, alreadyAdded: true))
        #expect(first.id != another.id)
        #expect(first.widgetConfiguration?.widgetLayout != another.widgetConfiguration?.widgetLayout)
        let app = DockItem.application(at: URL(fileURLWithPath: "/Applications/Example.app"))
        #expect(!WidgetDiscovery.canAdd(app, alreadyAdded: true))
        #expect(WidgetDiscovery.canAdd(app, alreadyAdded: false))
    }

    @Test func conversionPrecisionIsPracticalAndLocaleAware() throws {
        let english = Locale(identifier: "en_US")
        let german = Locale(identifier: "de_DE")
        let units = ConversionCategory.length.units
        let footUnit = try #require(units.first { $0.id == "ft" })
        let feet = try #require(ConversionUnit.convert(1, from: units[0], to: footUnit))
        #expect(ConversionResultFormatter.text(feet, locale: english) == "3.28084")
        #expect(ConversionResultFormatter.text(feet, locale: german) == "3,28084")
        let temperatures = ConversionCategory.temperature.units
        let fahrenheit = try #require(ConversionUnit.convert(0, from: temperatures[0], to: temperatures[1]))
        #expect(ConversionResultFormatter.text(fahrenheit, locale: english) == "32")
        #expect(ConversionResultFormatter.text(-0.0, locale: english) == "0")
        #expect(ConversionResultFormatter.text(.infinity, locale: english) == "—")
    }

    @Test func extremeConversionsRemainNonzeroAndRoundWithinDisplayPrecision() {
        let locale = Locale(identifier: "en_US_POSIX")
        for value in [0.0000000123456789, -0.0000000123456789, 12_345_678_900.0] {
            let display = ConversionResultFormatter.text(value, locale: locale)
            // Parse the localized scientific exponent marker without depending on glyph style.
            let normalized = display.replacingOccurrences(of: "E", with: "e")
            let parsed = Double(normalized)
            #expect(parsed != nil)
            if let parsed {
                #expect(parsed != 0)
                #expect(abs((parsed - value) / value) < 0.00001)
            }
        }
    }
}
