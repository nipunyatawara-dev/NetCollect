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

    /// Computes the start and end date for this timeframe relative to the calendar.
    public func dateInterval(for referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        switch self {
        case .daily:
            let start = calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? referenceDate
            return DateInterval(start: start, end: end)
        case .weekly:
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .day, value: 7, to: start)?.addingTimeInterval(-1) ?? referenceDate
            return DateInterval(start: start, end: end)
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: referenceDate)
            let start = calendar.date(from: components) ?? calendar.startOfDay(for: referenceDate)
            let end = calendar.date(byAdding: .month, value: 1, to: start)?.addingTimeInterval(-1) ?? referenceDate
            return DateInterval(start: start, end: end)
        }
    }

    public func rangeDescription(for referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        "\(title) (\(formattedDateRange(for: referenceDate, calendar: calendar)))"
    }

    func formattedDateRange(for referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        switch self {
        case .daily:
            formatter.dateStyle = .medium
            return formatter.string(from: referenceDate)
        case .weekly:
            let interval = dateInterval(for: referenceDate, calendar: calendar)
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: interval.end))"
        case .monthly:
            formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return formatter.string(from: referenceDate)
        }
    }
}
