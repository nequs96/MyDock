import Foundation
import Testing
@testable import MyDock

#if DEBUG
@MainActor
struct WidgetQACoverageTests {
    private static func fullMatrix() -> WidgetQAMatrix {
        var matrix = WidgetQAMatrix()
        for definition in WidgetRegistry.all {
            for state in WidgetQAMatrix.required(for: definition) { matrix.record(definition.name, state) }
        }
        return matrix
    }

    @Test func requiredStatesDeriveFromCapabilities() {
        for definition in WidgetRegistry.all {
            let required = WidgetQAMatrix.required(for: definition)
            for option in definition.capabilities.layouts { #expect(required.contains(.layout(option.layout))) }
            #expect(required.contains(.setup) == definition.capabilities.hasSetupState, "\(definition.name)")
        }
        #expect(WidgetRegistry.all.contains { $0.capabilities.hasSetupState })
    }

    @Test func completeInventoryValidatesAndMissingExportFails() throws {
        try Self.fullMatrix().validate()
        #expect(WidgetQAMatrix().missing().count >= WidgetRegistry.all.count)
        #expect(throws: WidgetQAMatrix.Failure.self) { try WidgetQAMatrix().validate() }
    }

    @Test func missingSetupFixtureAndNewFamilyFail() throws {
        let calendar = try #require(WidgetRegistry.definition(named: "Calendar"))
        #expect(calendar.capabilities.hasSetupState)
        var matrix = WidgetQAMatrix()
        for option in calendar.capabilities.layouts { matrix.record("Calendar", .layout(option.layout)) }
        #expect(matrix.missing(in: [calendar]) == ["Calendar setup/empty state"])
        let invented = WidgetDefinition(name: "Invented", symbol: "star", category: calendar.category, description: "x",
                                        capabilities: .init(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact))
        #expect(!Self.fullMatrix().missing(in: WidgetRegistry.all + [invented]).isEmpty)
    }

    @Test func accessNoteComesFromCapabilitiesOnly() throws {
        let calendar = try #require(WidgetRegistry.definition(named: "Calendar")?.capabilities.accessNote)
        #expect(calendar.contains("Calendar") && calendar.contains("personal content"))
        #expect(!calendar.lowercased().contains("granted"))
        let plain = WidgetCapabilities(layouts: WidgetLayoutPresets.generic, defaultLayout: .compact)
        #expect(plain.accessNote == nil)
    }

    @Test func calendarFixtureSelection() {
        let key = CalendarQAFixture.environmentKey
        #expect(CalendarQAFixture.selection(override: nil, environment: [:]) == nil)
        #expect(CalendarQAFixture.selection(override: nil, environment: [key: "bogus"]) == nil)
        #expect(CalendarQAFixture.selection(override: nil, environment: [key: "Ongoing"]) == .ongoing)
        #expect(CalendarQAFixture.selection(override: .empty, environment: [key: "upcoming"]) == .empty)
    }

    @Test func calendarFixtureEventsMatchState() {
        let now = Date()
        #expect(CalendarQAFixture.empty.events(now: now).isEmpty)
        let ongoing = CalendarQAFixture.ongoing.events(now: now)
        #expect(ongoing.first.map { $0.startDate <= now && $0.endDate > now } == true)
        let upcoming = CalendarQAFixture.upcoming.events(now: now)
        #expect(upcoming.allSatisfy { $0.startDate > now })
        #expect(CalendarEventOrdering.compactEvent(from: upcoming, now: now)?.id == "qa-next")
    }
}
#endif
