import Foundation
import Testing
@testable import MyDock

/// OP-03 saved-content search and OP-04 next-meeting choice: pure functions only, no EventKit and no file system.
struct NextMeetingAndCollectionTests {
    // MARK: Calendar fixtures

    private func local(_ calendar: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func event(_ id: String, start: TimeInterval, end: TimeInterval, allDay: Bool = false, calendar: String = "A",
                       url: URL? = nil, location: String? = nil, declined: Bool? = nil) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: id, title: id, startDate: now.addingTimeInterval(start), endDate: now.addingTimeInterval(end),
                              isAllDay: allDay, calendarID: calendar, calendarTitle: calendar, meetingURL: url,
                              location: location, declinedByCurrentUser: declined)
    }
    private func snapshot(_ id: String, start: Date, end: Date) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: id, title: id, startDate: start, endDate: end, isAllDay: false,
                              calendarID: "A", calendarTitle: "A", meetingURL: nil)
    }

    // MARK: Selection

    @Test func ongoingBeatsUpcomingAndAllDayIsNeverNext() {
        let upcoming = event("upcoming", start: 300, end: 900)
        let ongoing = event("ongoing", start: -300, end: 300)
        let allDay = event("all-day", start: -3_600, end: 80_000, allDay: true)
        #expect(NextMeeting.next(from: [upcoming, ongoing, allDay], now: now)?.id == "ongoing")
        #expect(NextMeeting.next(from: [allDay, upcoming], now: now)?.id == "upcoming")
        #expect(NextMeeting.next(from: [allDay], now: now) == nil)
    }

    @Test func declinedEventsAreSkippedOnlyWhenStatusIsKnown() {
        let declined = event("declined", start: 60, end: 600, declined: true)
        let unknown = event("unknown", start: 120, end: 600, declined: nil)
        let accepted = event("accepted", start: 180, end: 600, declined: false)
        #expect(NextMeeting.next(from: [declined, unknown, accepted], now: now)?.id == "unknown")
        #expect(NextMeeting.next(from: [declined], now: now) == nil)
        #expect(CalendarEventOrdering.select([declined, accepted], calendarIDs: [], includeAllDay: true, now: now).map(\.id) == ["accepted"])
    }

    @Test func selectedCalendarsAreRespected() {
        let a = event("a", start: 600, end: 900, calendar: "A")
        let b = event("b", start: 60, end: 900, calendar: "B")
        #expect(NextMeeting.next(from: [a, b], calendarIDs: ["A"], now: now)?.id == "a")
        #expect(NextMeeting.next(from: [a, b], calendarIDs: ["missing"], now: now) == nil)
        #expect(NextMeeting.next(from: [a, b], calendarIDs: [], now: now)?.id == "b")
    }

    @Test func allDayQuietLineListsTodaysEventsOnly() {
        let cal = calendar("UTC")
        let today = local(cal, 2026, 10, 5, 9)
        func allDay(_ title: String, dayOffset: Int) -> CalendarEventSnapshot {
            let start = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: today))!
            return CalendarEventSnapshot(id: title, title: title, startDate: start, endDate: start.addingTimeInterval(86_399),
                                         isAllDay: true, calendarID: "A", calendarTitle: "A", meetingURL: nil)
        }
        let events = [allDay("Holiday", dayOffset: 0), allDay("Birthday", dayOffset: 0), allDay("Conference", dayOffset: 0), allDay("Tomorrow only", dayOffset: 1)]
        let covering = NextMeeting.allDayToday(from: events, now: today, calendar: cal)
        #expect(covering.map(\.title) == ["Birthday", "Conference", "Holiday"])
        #expect(NextMeeting.allDayLine(covering) == "Birthday +2")
        #expect(NextMeeting.allDayLine(Array(covering.prefix(2))) == "Birthday, Conference")
        #expect(NextMeeting.allDayLine([]) == nil)
    }

    // MARK: Time until start

    @Test func heroReadsNowAndMinutes() {
        #expect(NextMeeting.heroValue(event("e", start: -60, end: 600), now: now) == "now")
        #expect(NextMeeting.heroValue(event("e", start: 12 * 60, end: 3_600), now: now) == "in 12 min")
        #expect(NextMeeting.heroValue(event("e", start: 20, end: 3_600), now: now) == "in 1 min")
        #expect(NextMeeting.heroValue(event("e", start: 3 * 3_600 + 15 * 60, end: 20_000), now: now) == "in 3 hr 15 min")
    }

    @Test func timeUntilStartIsRightAcrossMidnight() {
        let cal = calendar("America/Los_Angeles")
        let late = local(cal, 2026, 10, 5, 23, 50)
        let soon = snapshot("soon", start: local(cal, 2026, 10, 6, 0, 10), end: local(cal, 2026, 10, 6, 1))
        #expect(NextMeeting.heroValue(soon, now: late, calendar: cal) == "in 20 min")
        let farther = snapshot("farther", start: local(cal, 2026, 10, 6, 14), end: local(cal, 2026, 10, 6, 15))
        #expect(NextMeeting.heroValue(farther, now: late, calendar: cal).hasPrefix("Tomorrow "))
    }

    @Test func timeUntilStartUsesElapsedTimeAcrossDST() {
        // US spring forward: 01:30 EST to 03:30 EDT is one real hour, not two wall-clock hours.
        let cal = calendar("America/New_York")
        let before = local(cal, 2026, 3, 8, 1, 30)
        let start = local(cal, 2026, 3, 8, 3, 30)
        #expect(start.timeIntervalSince(before) == 3_600)
        #expect(NextMeeting.heroValue(snapshot("dst", start: start, end: start.addingTimeInterval(1_800)), now: before, calendar: cal) == "in 1 hr")
    }

    @Test func dayLabelFollowsTheCalendarTimeZone() {
        let nowUTC = local(calendar("UTC"), 2026, 10, 5, 12)
        let eventUTC = local(calendar("UTC"), 2026, 10, 6, 3)
        // Tokyo is on Oct 5 evening and the event is Oct 6 noon; Los Angeles is on Oct 5 morning and the event is Oct 5 evening.
        #expect(NextMeeting.dayAndTime(eventUTC, now: nowUTC, calendar: calendar("Asia/Tokyo")).hasPrefix("Tomorrow "))
        #expect(!NextMeeting.dayAndTime(eventUTC, now: nowUTC, calendar: calendar("America/Los_Angeles")).hasPrefix("Tomorrow"))
    }

    // MARK: Links and actions

    @Test func recognisesOnlyRealMeetingHosts() {
        let good = ["https://zoom.us/j/1", "https://us02web.zoom.us/j/1", "https://meet.google.com/abc-defg-hij",
                    "https://teams.microsoft.com/l/meetup-join/x", "https://acme.webex.com/meet/room", "https://facetime.apple.com/join#v=1"]
        for text in good { #expect(MeetingLinkDetector.isRecognised(URL(string: text)!), "\(text)") }
        let bad = ["http://zoom.us/j/1", "https://evilzoom.us/j/1", "https://zoom.us.evil.com/j/1", "https://zoom.us@evil.com/x",
                   "https://example.com/zoom.us", "https://maps.apple.com/?q=zoom.us"]
        for text in bad { #expect(!MeetingLinkDetector.isRecognised(URL(string: text)!), "\(text)") }
    }

    @Test func linkComesFromTheEventURLOrLocationOnly() {
        let direct = URL(string: "https://meet.google.com/abc-defg-hij")!
        #expect(MeetingLinkDetector.link(url: direct, location: nil) == direct)
        #expect(MeetingLinkDetector.link(url: nil, location: "Join: https://example.zoom.us/j/99.")?.absoluteString == "https://example.zoom.us/j/99")
        #expect(MeetingLinkDetector.link(url: URL(string: "https://example.com/agenda"), location: "Room 4") == nil)
        #expect(MeetingLinkDetector.link(url: nil, location: nil) == nil)
        #expect(MeetingLinkDetector.link(url: nil, location: "") == nil)
    }

    @Test func actionIsJoinOnlyForARecognisedLink() {
        let link = URL(string: "https://zoom.us/j/1")!
        #expect(CalendarEventAction.action(for: event("e", start: 60, end: 600, url: link)) == .join(link))
        #expect(CalendarEventAction.action(for: event("e", start: 60, end: 600)) == .openInCalendar)
        #expect(CalendarEventAction.action(for: event("e", start: 60, end: 600, url: URL(string: "https://example.com/x"))) == .openInCalendar)
    }

    @Test func locationShowsOnlyWhenPresentAndNotJustTheLink() {
        #expect(NextMeeting.locationText(event("e", start: 60, end: 600, location: "  Studio 2 ")) == "Studio 2")
        #expect(NextMeeting.locationText(event("e", start: 60, end: 600, location: "   ")) == nil)
        #expect(NextMeeting.locationText(event("e", start: 60, end: 600, location: nil)) == nil)
        #expect(NextMeeting.locationText(event("e", start: 60, end: 600, location: "https://zoom.us/j/1")) == nil)
    }

    #if DEBUG
    @Test func meetingsFixtureCoversLinkAllDayAndLocation() throws {
        let events = CalendarQAFixture.meetings.events(now: now)
        #expect(NextMeeting.next(from: events, now: now)?.id == "qa-call")
        let call = try #require(events.first { $0.id == "qa-call" })
        #expect(CalendarEventAction.action(for: call) != .openInCalendar)
        #expect(events.first { $0.id == "qa-holiday" }?.isAllDay == true)
        #expect(NextMeeting.allDayToday(from: events, now: now).map(\.id) == ["qa-holiday"])
        let office = try #require(events.first { $0.id == "qa-office" })
        #expect(NextMeeting.locationText(office) == "Studio 2")
        #expect(CalendarEventAction.action(for: office) == .openInCalendar)
    }
    #endif

    // MARK: Saved collections

    private func profile(_ name: String, snippets: [TextSnippet] = [], links: [QuickLink] = [], files: [ShelfFile] = []) -> DockProfile {
        var snippetsItem = DockItem.widget("Text Snippets")
        snippetsItem.widgetConfiguration?.textSnippets = snippets
        var linksItem = DockItem.widget("Quick Links")
        linksItem.widgetConfiguration?.quickLinks = links
        var shelfItem = DockItem.widget("File Shelf")
        shelfItem.widgetConfiguration?.shelfFiles = files
        return DockProfile(name: name, kind: .custom, items: [snippetsItem, linksItem, shelfItem])
    }

    @Test func emptyQueryOrNoSavedContentYieldsNothing() {
        let docks = [profile("Work", snippets: [TextSnippet(title: "Reply", text: "Thanks")])]
        #expect(SavedCollectionSearch.results(in: docks, query: "", fileExists: { _ in true }).isEmpty)
        #expect(SavedCollectionSearch.results(in: docks, query: "   ", fileExists: { _ in true }).isEmpty)
        #expect(SavedCollectionSearch.results(in: [profile("Empty")], query: "reply", fileExists: { _ in true }).isEmpty)
        #expect(SavedCollectionSearch.results(in: docks, query: "zzz", fileExists: { _ in true }).isEmpty)
    }

    @Test func prefixAndWordMatchAcrossDocksWithKinds() {
        let docks = [
            profile("Work", snippets: [TextSnippet(title: "Email reply", text: "Thanks")],
                    links: [QuickLink(title: "Project workspace", url: URL(string: "https://example.com/project")!)]),
            profile("Home", files: [ShelfFile(url: URL(fileURLWithPath: "/nonexistent-dir/Reply notes.pdf"))])
        ]
        let results = SavedCollectionSearch.results(in: docks, query: "rep", fileExists: { _ in false })
        #expect(Set(results.map(\.kind)) == [.snippet, .file])
        #expect(results.first { $0.kind == .file }?.isMissing == true)
        #expect(results.first { $0.kind == .file }?.detail == "Missing")
        #expect(results.first { $0.kind == .snippet }?.dockName == "Work")
        #expect(SavedCollectionSearch.results(in: docks, query: "work", fileExists: { _ in true }).first?.kind == .link)
        // The middle of a word is not a match.
        #expect(SavedCollectionSearch.results(in: docks, query: "eply", fileExists: { _ in true }).isEmpty)
    }

    @Test func duplicateTitlesOrderByDockThenTitle() {
        let docks = [
            profile("Zeta", snippets: [TextSnippet(title: "Hello", text: "z")]),
            profile("Alpha", snippets: [TextSnippet(title: "Hello again", text: "a1"), TextSnippet(title: "Hello", text: "a2")])
        ]
        let results = SavedCollectionSearch.results(in: docks, query: "hello", fileExists: { _ in true })
        #expect(results.map(\.dockName) == ["Alpha", "Alpha", "Zeta"])
        #expect(results.map(\.title) == ["Hello", "Hello again", "Hello"])
        let again = SavedCollectionSearch.results(in: Array(docks.reversed()), query: "hello", fileExists: { _ in true })
        #expect(results.map(\.id) == again.map(\.id))
    }

    @Test func resultCountIsBounded() {
        let many = (0..<40).map { TextSnippet(title: "Note \($0)", text: "x") }
        let results = SavedCollectionSearch.results(in: [profile("Work", snippets: many)], query: "note", fileExists: { _ in true })
        #expect(results.count == SavedCollectionSearch.maxResults)
    }

    @Test func privateTextPreviewIsOneShortLine() {
        let long = "First line\nsecond line " + String(repeating: "secret ", count: 40)
        let preview = SavedCollectionSearch.oneLinePreview(long)
        #expect(!preview.contains("\n"))
        #expect(preview.count <= SavedCollectionSearch.previewLimit + 1)
        #expect(preview.hasSuffix("…"))
        #expect(SavedCollectionSearch.oneLinePreview("Short  text") == "Short text")
        let results = SavedCollectionSearch.results(in: [profile("Work", snippets: [TextSnippet(title: "Note", text: long)])], query: "note", fileExists: { _ in true })
        #expect(results.first?.detail == preview)
    }
}
