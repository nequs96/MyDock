import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MyDock

/// RD-09 faces and popouts A: pure presentation helpers, and a non-empty face for every family × layout.
struct RedesignFacesATests {
    static let families = ["Calendar", "Reminders", "Alarm", "Disk Space", "Calculator", "Quick Checklist", "File Shelf", "Text Snippets",
                           "Quick Links", "Unit Converter", "Color Picker", "Now Playing", "Weather", "AirDrop", "Trash"]

    private func event(start: TimeInterval, end: TimeInterval, now: Date, allDay: Bool = false) -> CalendarEventSnapshot {
        CalendarEventSnapshot(id: "e", title: "Review", startDate: now.addingTimeInterval(start), endDate: now.addingTimeInterval(end),
                              isAllDay: allDay, calendarID: "c", calendarTitle: "Work", meetingURL: nil)
    }

    @Test func calendarCompactStatusIsShortAndTruthful() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 9))!
        #expect(CalendarFacePresentation.compactStatus(event(start: -7200, end: -3600, now: now), now: now, calendar: calendar) == "Ended")
        #expect(CalendarFacePresentation.compactStatus(event(start: 0, end: 86_400, now: now, allDay: true), now: now, calendar: calendar) == "All day")
        #expect(CalendarFacePresentation.compactStatus(event(start: -600, end: 1800, now: now), now: now, calendar: calendar).hasPrefix("Now · until "))
        #expect(CalendarFacePresentation.compactStatus(event(start: 45 * 60, end: 75 * 60, now: now), now: now, calendar: calendar) == "In 45 min")
        #expect(CalendarFacePresentation.compactStatus(event(start: 20, end: 600, now: now), now: now, calendar: calendar) == "In 1 min")
        #expect(CalendarFacePresentation.compactStatus(event(start: 26 * 3600, end: 27 * 3600, now: now), now: now, calendar: calendar).hasPrefix("Tomorrow "))
        let later = CalendarFacePresentation.compactStatus(event(start: 4 * 3600, end: 5 * 3600, now: now), now: now, calendar: calendar)
        #expect(!later.hasPrefix("In ") && !later.hasPrefix("Tomorrow"))
    }

    @Test func calendarPartsFollowBothLayouts() {
        func parts(_ calendarLayout: CalendarWidgetLayout, _ dockLayout: WidgetLayout) -> [Bool] {
            let value = CalendarFacePresentation.parts(calendarLayout: calendarLayout, dockLayout: dockLayout)
            return [value.date, value.event]
        }
        #expect(parts(.dateAndNextEvent, .compact) == [true, false])
        #expect(parts(.dateAndNextEvent, .wide) == [true, true])
        #expect(parts(.nextEvent, .wide) == [false, true])
        #expect(parts(.nextEvent, .compact) == [true, false])
        #expect(parts(.date, .wide) == [true, false])
    }

    @Test func calendarEmptyStateNeverHidesMissingAccess() {
        #expect(CalendarFacePresentation.emptyState(errorMessage: "denied", accessAvailable: false).title == "Unavailable")
        #expect(CalendarFacePresentation.emptyState(errorMessage: "denied", accessAvailable: true).title == "Unavailable")
        #expect(CalendarFacePresentation.emptyState(errorMessage: nil, accessAvailable: true).title == "No events")
        #expect(CalendarFacePresentation.emptyState(errorMessage: nil, accessAvailable: false).title == "Calendar")
    }

    @Test func remindersOverdueStateUsesDueDates() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reminders = [ReminderSnapshot(id: "1", title: "Late", dueDate: now.addingTimeInterval(-60), calendarID: "l", calendarTitle: "L"),
                         ReminderSnapshot(id: "2", title: "Soon", dueDate: now.addingTimeInterval(60), calendarID: "l", calendarTitle: "L"),
                         ReminderSnapshot(id: "3", title: "Someday", dueDate: nil, calendarID: "l", calendarTitle: "L")]
        #expect(RemindersFacePresentation.overdueCount(reminders, now: now) == 1)
        #expect(RemindersFacePresentation.isOverdue(reminders[0], now: now))
        #expect(!RemindersFacePresentation.isOverdue(reminders[1], now: now))
        #expect(!RemindersFacePresentation.isOverdue(reminders[2], now: now))
    }

    @Test func alarmNextIgnoresDisabledAlarmsAndSummarisesRepeats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 8))!
        let alarms = [DockAlarm(title: "Off", hour: 8, minute: 30, repeatWeekdays: [], isEnabled: false),
                      DockAlarm(title: "Noon", hour: 12, minute: 0, repeatWeekdays: [], isEnabled: true),
                      DockAlarm(title: "Evening", hour: 18, minute: 0, repeatWeekdays: [], isEnabled: true)]
        #expect(AlarmFacePresentation.next(alarms, now: now)?.alarm.title == "Noon")
        #expect(AlarmFacePresentation.next(alarms.filter { !$0.isEnabled }, now: now) == nil)
        #expect(AlarmFacePresentation.day(now.addingTimeInterval(3600), now: now, calendar: calendar) == "Today")
        #expect(AlarmFacePresentation.day(now.addingTimeInterval(86_400), now: now, calendar: calendar) == "Tomorrow")
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        #expect(AlarmFacePresentation.repeatSummary([], symbols: symbols) == "Once")
        #expect(AlarmFacePresentation.repeatSummary(Array(1...7), symbols: symbols) == "Every day")
        #expect(AlarmFacePresentation.repeatSummary([4, 2], symbols: symbols) == "Mon Wed")
    }

    @Test func trashStateColoursOnlyFullAndNamesEveryState() {
        let empty = TrashFacePresentation(count: 0, errorMessage: nil)
        #expect(!empty.isFull && !empty.isUnavailable && empty.label == "Empty" && empty.symbol == "trash")
        let one = TrashFacePresentation(count: 1, errorMessage: nil)
        #expect(one.isFull && one.label == "1 item" && one.symbol == "trash.fill")
        #expect(TrashFacePresentation(count: 12, errorMessage: nil).label == "12 items")
        let unavailable = TrashFacePresentation(count: 5, errorMessage: "No access")
        #expect(!unavailable.isFull && unavailable.isUnavailable && unavailable.label == "Unavailable")
    }

    @Test func savedCollectionsNeverShowABareNumber() {
        #expect(SavedCollectionFacePresentation.valueText(kind: "Text Snippets", count: 2) == "2 snippets")
        #expect(SavedCollectionFacePresentation.valueText(kind: "Text Snippets", count: 1) == "1 snippet")
        #expect(SavedCollectionFacePresentation.valueText(kind: "File Shelf", count: 0) == "0 files")
        #expect(SavedCollectionFacePresentation.valueText(kind: "Quick Links", count: 3) == "3 links")
        #expect(SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: "Reply", layout: .compact, narrow: false) == "Saved")
        #expect(SavedCollectionFacePresentation.label(kind: "File Shelf", latest: nil, layout: .compact, narrow: false) == "Shelf")
        #expect(SavedCollectionFacePresentation.label(kind: "Quick Links", latest: "Docs", layout: .wide, narrow: false) == "Docs")
        #expect(SavedCollectionFacePresentation.label(kind: "Quick Links", latest: nil, layout: .wide, narrow: false) == "Add a website")
        #expect(SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: "", layout: .wide, narrow: false) == "Save a snippet")
        #expect(SavedCollectionFacePresentation.label(kind: "Text Snippets", latest: "Reply", layout: .wide, narrow: true) == "Snippets")
    }

    @Test func diskLowStateAndPlaybackFormatting() {
        #expect(DiskSpaceSnapshot(name: "D", totalBytes: 100, availableBytes: 5).isLow)
        #expect(!DiskSpaceSnapshot(name: "D", totalBytes: 100, availableBytes: 50).isLow)
        #expect(!DiskSpaceSnapshot(name: "D", totalBytes: 0, availableBytes: 0).isLow)
        #expect(NowPlayingPresentation.timeString(74) == "1:14")
        #expect(NowPlayingPresentation.timeString(.nan) == "0:00")
        #expect(NowPlayingPresentation.timeString(-5) == "0:00")
        #expect(NowPlayingPresentation.progress(position: 50, duration: 100) == 0.5)
        #expect(NowPlayingPresentation.progress(position: 50, duration: 0) == 0)
        #expect(NowPlayingPresentation.progress(position: 500, duration: 100) == 1)
        #expect(NowPlayingPresentation.progress(position: .infinity, duration: 100) == 0)
    }

    @Test func calculatorKeyRolesCoverEveryKey() {
        #expect(CalculatorKeyStyle.Role("=") == .equals)
        for key in ["÷", "×", "−", "+"] { #expect(CalculatorKeyStyle.Role(key) == .operation) }
        for key in ["C", "(", ")", "%"] { #expect(CalculatorKeyStyle.Role(key) == .function) }
        for key in ["0", "7", "."] { #expect(CalculatorKeyStyle.Role(key) == .digit) }
    }

    @Test func ownedFamiliesAreRegisteredWithLayouts() {
        for kind in Self.families {
            #expect(WidgetRegistry.definition(named: kind) != nil, "\(kind)")
            #expect(!WidgetPresentationCatalog.options(for: kind).isEmpty, "\(kind)")
        }
    }

    /// Every owned family draws visible content for every advertised layout and on the 54 pt side Dock,
    /// on the plain surface (no background), so an empty face would render no pixels.
    @MainActor @Test func everyFamilyRendersANonEmptyFaceForEveryLayout() throws {
        var matrix = WidgetQAMatrix()
        for kind in Self.families {
            var cases = WidgetPresentationCatalog.options(for: kind).map { ($0.layout, CGFloat($0.width)) }
            cases.append((WidgetPresentationCatalog.options(for: kind).first?.layout == .icon ? .icon : .compact, 54))
            for (layout, width) in cases {
                let face = WidgetCardPreview(kind: kind, width: width, layout: layout)
                    .environment(\.dockWidgetSurface, .plain)
                    .environment(\.colorScheme, .light)
                let pixels = try Self.visiblePixels(face, size: CGSize(width: width, height: 54))
                #expect(pixels > 40, "\(kind) \(layout.rawValue) at \(width) pt drew \(pixels) pixels")
                matrix.record(kind, .layout(layout))
            }
        }
        let missing = matrix.missing(in: WidgetRegistry.all.filter { Self.families.contains($0.name) }).filter { !$0.hasSuffix(WidgetQAState.setup.description) }
        #expect(missing.isEmpty, "\(missing)")
    }

    /// Empty, setup and permission states also draw something truthful.
    @MainActor @Test func emptyAndPermissionFacesAreNotBlank() throws {
        let faces: [(String, AnyView, CGFloat, WidgetLayout)] = [
            ("calendar denied", AnyView(CalendarDockFace(date: .now, showsEvent: true, emptyTitle: "Unavailable", emptyDetail: "Allow access")), 154, .wide),
            ("reminders setup", AnyView(RemindersModuleFace(count: nil, context: "Choose a list")), 88, .compact),
            ("reminders overdue", AnyView(RemindersModuleFace(count: 3, overdue: 1, context: "Errands")), 88, .compact),
            ("alarm off", AnyView(AlarmDockFace(time: nil, title: nil)), 88, .compact),
            ("alarm narrow", AnyView(AlarmDockFace(time: "7:30 AM", title: "Morning")), 54, .compact),
            ("trash empty", AnyView(TrashDockFace(count: 0)), 54, .icon),
            ("trash unavailable", AnyView(TrashDockFace(count: 0, errorMessage: "No")), 88, .compact),
            ("airdrop targeted", AnyView(AirDropDockFace(targeted: true)), 88, .compact),
            ("collection empty", AnyView(SavedCollectionDockFace(item: .widget("Text Snippets"))), 96, .compact)
        ]
        for (name, view, width, layout) in faces {
            let face = WidgetContainer(width: width, kind: "Calendar") { view }
                .environment(\.dockWidgetContentWidth, width)
                .environment(\.widgetLayout, layout)
                .environment(\.dockWidgetSurface, .plain)
            #expect(try Self.visiblePixels(face, size: CGSize(width: width, height: 54)) > 40, "\(name)")
        }
    }

    @MainActor static func visiblePixels<V: View>(_ view: V, size: CGSize) throws -> Int {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw CocoaError(.fileWriteUnknown)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: data.count, by: 4).filter { data[$0] > 24 }.count
    }
}
