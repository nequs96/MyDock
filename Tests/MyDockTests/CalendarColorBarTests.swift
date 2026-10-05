import CoreGraphics
import Foundation
import Testing
@testable import MyDock

/// FU-W: the runtime-only calendar colour, and the thin leading bar that shows it on Calendar events.
struct CalendarColorBarTests {
    private let blue = CalendarColorSnapshot(red: 0.04, green: 0.52, blue: 1.0)

    @Test func colourSnapshotClampsAndRejectsMissingColours() {
        let clamped = CalendarColorSnapshot(red: -1, green: 2, blue: .nan)
        #expect(clamped.red == 0 && clamped.green == 1 && clamped.blue == 0)
        #expect(CalendarColorSnapshot(cgColor: nil) == nil)
    }

    @Test func colourSnapshotConvertsCGColorToSRGB() throws {
        let red = try #require(CalendarColorSnapshot(cgColor: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)))
        #expect(abs(red.red - 1) < 0.01 && red.green < 0.01 && red.blue < 0.01)
        let grey = try #require(CalendarColorSnapshot(cgColor: CGColor(gray: 0.5, alpha: 1)))
        #expect(abs(grey.red - grey.green) < 0.01 && abs(grey.green - grey.blue) < 0.01)
        #expect(grey.red > 0.3 && grey.red < 0.8)
    }

    @Test func eventsCarryNoColourUnlessEventKitSuppliesOne() {
        let now = Date()
        let event = CalendarEventSnapshot(id: "e", title: "Review", startDate: now, endDate: now.addingTimeInterval(60),
                                          isAllDay: false, calendarID: "c", calendarTitle: "Work", meetingURL: nil)
        #expect(event.calendarColor == nil)
        var coloured = event
        coloured.calendarColor = blue
        #expect(coloured != event)
    }

    @Test func monoStaysNeutralAndColourFollowsTheCalendar() {
        #expect(CalendarEventBarStyle.resolve(color: blue, monochrome: false) == .calendar(blue))
        #expect(CalendarEventBarStyle.resolve(color: blue, monochrome: true) == .neutral(emphasized: false))
        #expect(CalendarEventBarStyle.resolve(color: blue, monochrome: true, emphasized: true) == .neutral(emphasized: true))
        #expect(CalendarEventBarStyle.resolve(color: nil, monochrome: false) == .neutral(emphasized: false))
    }

    @Test func monochromeFollowsTheAccentAndIconTreatment() {
        #expect(CalendarEventBarStyle.isMonochrome(accent: .mono, appearance: .soft))
        #expect(CalendarEventBarStyle.isMonochrome(accent: .auto, appearance: .mono))
        #expect(!CalendarEventBarStyle.isMonochrome(accent: .auto, appearance: .soft))
        #expect(!CalendarEventBarStyle.isMonochrome(accent: .auto, appearance: .accent))
    }

    @Test func increaseContrastWidensTheBar() {
        #expect(CalendarEventBarStyle.width(increasedContrast: true) > CalendarEventBarStyle.width(increasedContrast: false))
    }

    #if DEBUG
    @Test func qaFixtureEventsCarryDistinctColours() {
        for fixture in [CalendarQAFixture.ongoing, .upcoming] {
            let colours = fixture.events().compactMap(\.calendarColor)
            #expect(colours.count == 2, "\(fixture)")
            #expect(Set(colours).count == 2, "\(fixture)")
        }
        #expect(CalendarQAFixture.empty.events().isEmpty)
        #expect(Set(CalendarQAFixture.ongoing.events().map(\.calendarID)).isSubset(of: Set(CalendarQAFixture.ongoing.calendars.map(\.id))))
    }
    #endif
}
