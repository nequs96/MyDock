import Foundation
import Testing
@testable import MyDock

struct WidgetPresentationTests {
    @Test func oldVisualStylesMigrateToIconTreatmentsWithoutSuppressingData() throws {
        for (legacy, expected) in [("live", WidgetIconAppearance.soft), ("gradient", .accent), ("tinted", .soft), ("outline", .mono)] {
            let raw = "{\"iconStyle\":\"\(legacy)\",\"cardWidth\":\"wide\"}"
            let configuration = try JSONDecoder().decode(WidgetConfiguration.self, from: Data(raw.utf8))
            #expect(configuration.iconAppearance == expected)
            #expect(configuration.widgetLayout == .wide)
            #expect(WidgetPresentationCatalog.resolvedLayout(for: "AI Activity", configuration: configuration) == .trend)
            #expect(try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(configuration)) == configuration)
        }
    }
    @Test func newOutlineIsDistinctFromOldMonoAndDefaultsSurviveRoundTrip() throws {
        var config = WidgetConfiguration()
        config.iconAppearance = .outline
        let restored = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(config))
        #expect(restored.iconAppearance == .outline)
        #expect(restored.widgetLayout == nil)
        #expect(restored == config)
    }
    @Test func everyWidgetHasBoundedSemanticLayoutsAndIndependentAppearance() throws {
        var settings = AppSettings()
        for widget in WidgetRegistry.all {
            let choices = WidgetPresentationCatalog.options(for: widget.name)
            #expect(!choices.isEmpty)
            #expect(Set(choices.map(\.layout)).count == choices.count)
            #expect(choices.allSatisfy { (54...200).contains($0.width) })
            for choice in choices {
                var item = DockItem.widget(widget.name)
                item.widgetConfiguration?.widgetLayout = choice.layout
                for appearance in WidgetIconAppearance.allCases {
                    item.widgetConfiguration?.iconAppearance = appearance
                    settings.showWidgetLabels = false
                    settings.customDockWidgetStyle = .compact
                    #expect(DockSurfaceMetrics.itemLength(item, settings: settings, scale: 1) == CGFloat(choice.width))
                    #expect(try JSONDecoder().decode(DockItem.self, from: JSONEncoder().encode(item)) == item)
                }
            }
        }
        #expect(WidgetPresentationCatalog.options(for: "Clock").map(\.layout) == [.compact, .standard])
        #expect(WidgetPresentationCatalog.options(for: "System Activity").map(\.layout) == [.compact, .meter, .trend])
    }
    @Test func telemetryRetainsOnlyBoundedActualReadings() {
        #expect(WidgetTelemetryHistory.appending(nil, to: []) == [])
        #expect(WidgetTelemetryHistory.appending(.nan, to: [12]) == [12])
        #expect(WidgetTelemetryHistory.appending(101, to: [12]) == [12])
        #expect(WidgetTelemetryHistory.appending(37, to: [12, 25, 30], limit: 3) == [25, 30, 37])
        #expect(WidgetTelemetryHistory.appending(0, to: []) == [0])
    }
}
