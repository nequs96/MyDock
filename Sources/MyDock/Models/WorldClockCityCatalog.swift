import Foundation

struct WorldClockCityOption: Identifiable, Hashable {
    let id: String
    let name: String

    var timeZone: TimeZone { TimeZone(identifier: id) ?? .current }
}

enum WorldClockCityCatalog {
    static let all: [WorldClockCityOption] = TimeZone.knownTimeZoneIdentifiers
        .filter { identifier in
            let parts = identifier.split(separator: "/")
            return parts.count > 1 && parts[0] != "Etc" && parts[0] != "SystemV"
        }
        .map { identifier in
            let city = identifier.split(separator: "/").last.map(String.init) ?? identifier
            return WorldClockCityOption(id: identifier, name: city.replacingOccurrences(of: "_", with: " "))
        }
        .sorted {
            let nameOrder = $0.name.localizedStandardCompare($1.name)
            return nameOrder == .orderedSame ? $0.id < $1.id : nameOrder == .orderedAscending
        }

    /// A new World Clock starts on a major city whose current offset differs from this Mac's,
    /// so it shows another place instead of a fixed developer default.
    static func initialZoneID(current: TimeZone = .current, at date: Date = .now) -> String {
        let candidates = ["America/New_York", "Europe/London", "Asia/Tokyo"]
        let offset = current.secondsFromGMT(for: date)
        return candidates.first { TimeZone(identifier: $0).map { $0.secondsFromGMT(for: date) != offset } ?? false }
            ?? candidates[0]
    }

    static func matches(_ query: String, limit: Int = 10) -> [WorldClockCityOption] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, limit > 0 else { return [] }
        return all.lazy.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }.prefix(limit).map { $0 }
    }

    /// Returns the destination's local calendar date relative to the source: yesterday = -1, tomorrow = +1.
    static func dayOffset(from source: TimeZone, to destination: TimeZone, at date: Date) -> Int {
        func utcStartOfLocalDay(in timeZone: TimeZone) -> Date? {
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = timeZone
            let components = localCalendar.dateComponents([.era, .year, .month, .day], from: date)

            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = .gmt
            return utcCalendar.date(from: components)
        }

        guard let sourceDay = utcStartOfLocalDay(in: source),
              let destinationDay = utcStartOfLocalDay(in: destination) else { return 0 }
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = .gmt
        return utcCalendar.dateComponents([.day], from: sourceDay, to: destinationDay).day ?? 0
    }
}
