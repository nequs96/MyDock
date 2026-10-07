import Foundation

/// Clock faces call this every tick, so formatters are cached instead of built per call. `DateFormatter` keeps
/// honouring the system 12/24-hour setting; the cache is cleared when the locale, its settings or the time zone change.
enum LocalClockFormatter {
    static func time(for date: Date,
                     locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        LocalClockFormatterCache.shared.string(from: date, locale: locale, timeZone: timeZone, dateStyle: .none, timeStyle: .short)
    }

    static func date(for date: Date,
                     locale: Locale = .autoupdatingCurrent,
                     timeZone: TimeZone = .autoupdatingCurrent) -> String {
        LocalClockFormatterCache.shared.string(from: date, locale: locale, timeZone: timeZone, dateStyle: .full, timeStyle: .none)
    }
}

/// Lock-protected; formatting happens inside the lock, so no formatter is used from two threads at once.
private final class LocalClockFormatterCache: @unchecked Sendable {
    static let shared = LocalClockFormatterCache()

    private struct Key: Hashable {
        var locale: Locale
        var timeZone: TimeZone
        var dateStyle: UInt
        var timeStyle: UInt
    }

    private let lock = NSLock()
    private var formatters: [Key: DateFormatter] = [:]
    private var observers: [NSObjectProtocol] = []

    private init() {
        let names = [NSLocale.currentLocaleDidChangeNotification, Notification.Name.NSSystemTimeZoneDidChange]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in self?.removeAll() }
        }
    }

    func string(from date: Date, locale: Locale, timeZone: TimeZone,
                dateStyle: DateFormatter.Style, timeStyle: DateFormatter.Style) -> String {
        let key = Key(locale: locale, timeZone: timeZone, dateStyle: dateStyle.rawValue, timeStyle: timeStyle.rawValue)
        lock.lock(); defer { lock.unlock() }
        if let formatter = formatters[key] { return formatter.string(from: date) }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        if formatters.count >= 32 { formatters.removeAll() }
        formatters[key] = formatter
        return formatter.string(from: date)
    }

    private func removeAll() {
        lock.lock(); formatters.removeAll(); lock.unlock()
    }
}
