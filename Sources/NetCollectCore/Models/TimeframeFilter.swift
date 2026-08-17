import Foundation

/// Defines the timeframe over which network usage is aggregated.
public enum TimeframeFilter: String, CaseIterable, Identifiable, Sendable {
    case daily = "Today"
    case weekly = "This Week"
    case monthly = "This Month"

    public var id: String { rawValue }

    public var title: String { rawValue }

    public var iconName: String {
        switch self {
        case .daily:
            return "sun.max.fill"
        case .weekly:
            return "calendar"
        case .monthly:
            return "calendar.badge.clock"
        }
    }

    /// Computes the start date for this timeframe relative to the current calendar.
    public func dateInterval(for referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .daily:
            let start = calendar.startOfDay(for: referenceDate)
            return DateInterval(start: start, end: referenceDate)
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: referenceDate)
            return DateInterval(start: start, end: referenceDate)
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: referenceDate)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: referenceDate)
            return DateInterval(start: start, end: referenceDate)
        }
    }

    /// Subtitle describing the date range.
    public func rangeDescription(for referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let interval = dateInterval(for: referenceDate, calendar: calendar)
        let formatter = DateFormatter()

        switch self {
        case .daily:
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Today (\(formatter.string(from: referenceDate)))"
        case .weekly:
            formatter.dateFormat = "MMM d"
            let startStr = formatter.string(from: interval.start)
            let endStr = formatter.string(from: interval.end)
            return "\(startStr) – \(endStr)"
        case .monthly:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: referenceDate)
        }
    }
}
