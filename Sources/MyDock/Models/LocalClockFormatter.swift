import Foundation

/// Clock text. Format styles are values that reuse the system's cached formatters, so a clock that
/// redraws allocates no `DateFormatter`.
enum LocalClockFormatter {
    static func time(for date: Date,
                     locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: locale.calendar, timeZone: timeZone).format(date)
    }

    static func date(for date: Date,
                     locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        Date.FormatStyle(date: .complete, time: .omitted, locale: locale, calendar: locale.calendar, timeZone: timeZone).format(date)
    }
}
