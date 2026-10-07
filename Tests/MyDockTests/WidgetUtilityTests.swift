import Foundation
import Testing
@testable import MyDock

struct WidgetUtilityTests {
    @Test func calculatorRespectsPrecedenceAndPercent() throws {
        #expect(try QuickCalculator.calculate("(120 + 35) × 2") == 310)
        #expect(try QuickCalculator.calculate("2 + 3 * 4") == 14)
        #expect(try QuickCalculator.calculate("200 × 15%") == 30)
        #expect(try QuickCalculator.calculate("−(4 + 2) ÷ 3") == -2)
        #expect(try QuickCalculator.calculate(".5 + 1.25") == 1.75)
    }
    @Test func calculatorRejectsInvalidAndUnboundedInput() {
        for input in ["", "1/0", "1 +", "(2+3", "2..3", "2(3)", "hello", String(repeating: "1", count: 257)] {
            #expect(throws: QuickCalculator.CalculationError.self) { try QuickCalculator.calculate(input) }
        }
    }
    @Test func oldConfigurationsDefaultToLiveAndNewStylesRoundTrip() throws {
        let old = try JSONDecoder().decode(WidgetConfiguration.self, from: Data("{}".utf8))
        #expect(old.iconStyle == .live)
        #expect(old.checklistEntries.isEmpty)
        for style in WidgetIconStyle.allCases {
            var configuration = old
            configuration.iconStyle = style
            configuration.checklistEntries = [QuickChecklistEntry(title: "A task", isComplete: true)]
            let restored = try JSONDecoder().decode(WidgetConfiguration.self, from: JSONEncoder().encode(configuration))
            #expect(restored == configuration)
        }
    }
    @Test func privateChecklistIsExcludedFromPublicPresetByDefault() throws {
        var item = DockItem.widget("Quick Checklist")
        item.widgetConfiguration?.checklistEntries = [QuickChecklistEntry(title: "Private task")]
        item.widgetConfiguration?.iconStyle = .gradient
        let profile = DockProfile(name: "Tasks", kind: .custom, items: [item])
        let sanitized = ProfileSanitizer.sanitize(profile)
        #expect(sanitized.items.first?.widgetConfiguration?.checklistEntries.isEmpty == true)
        #expect(sanitized.items.first?.widgetConfiguration?.iconStyle == .gradient)
        #expect(ProfileSanitizer.sanitize(profile, includeNotes: true).items.first?.widgetConfiguration?.checklistEntries.count == 1)
        try ProfileSemanticValidator.validate([profile])
        var config = try #require(item.widgetConfiguration)
        config.checklistEntries.append(config.checklistEntries[0])
        #expect(throws: ProfileValidationError.self) { try ProfileSemanticValidator.validate(config) }
    }
    @Test func diskFractionIsBoundedAndWidgetsAreDiscoverable() {
        #expect(DiskSpaceSnapshot(name: "Disk", totalBytes: 100, availableBytes: 25).usedFraction == 0.75)
        #expect(DiskSpaceSnapshot(name: "Disk", totalBytes: 100, availableBytes: 200).usedFraction == 0)
        #expect(DiskSpaceSnapshot(name: "Disk", totalBytes: 100, availableBytes: -1).usedFraction == 1)
        #expect(DiskSpaceSnapshot(name: "Disk", totalBytes: 0, availableBytes: 0).usedFraction == 0)
        for kind in ["Disk Space", "Calculator", "Quick Checklist"] {
            #expect(WidgetRegistry.all.contains { $0.name == kind })
        }
    }
}
