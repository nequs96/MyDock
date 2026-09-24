import Foundation

enum TimeProgressCalculator {
    static func fraction(for period: TimeProgressPeriod, at date: Date, calendar: Calendar = .current) -> Double {
        let component: Calendar.Component
        switch period {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        case .year: component = .year
        }
        guard let interval = calendar.dateInterval(of: component, for: date), interval.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }
}
