import Foundation

/// RFC 3339 timestamps from provider responses and local logs, with or without fractional seconds.
/// Parsers call this per row, so the formatters are built once; ISO8601DateFormatter is thread-safe
/// once configured and these are never mutated after initialisation.
enum ISO8601Timestamp {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractional.date(from: value) ?? plain.date(from: value)
    }

    /// Internet date-time without fractional seconds, in UTC.
    static func string(_ date: Date) -> String {
        plain.string(from: date)
    }
}

/// `yyyy-MM-dd` in UTC with the POSIX locale, as provider APIs expect for day parameters and rows.
enum UTCDayFormat {
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func date(_ value: String) -> Date? { formatter.date(from: value) }
    static func string(_ date: Date) -> String { formatter.string(from: date) }
}
