import Foundation

/// Calendar-aligned periods available when removing stored network history.
public enum HistoryDeletionPeriod: String, CaseIterable, Identifiable, Sendable {
    case today
    case last3Days
    case last7Days
    case last14Days
    case last30Days
    case last90Days
    case allHistory

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: return "Today"
        case .last3Days: return "Last 3 Days"
        case .last7Days: return "Last 7 Days"
        case .last14Days: return "Last 14 Days"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .allHistory: return "All History"
        }
    }

    public var deletionDescription: String {
        switch self {
        case .today:
            return "Permanently remove all usage recorded today."
        case .allHistory:
            return "Permanently remove every stored usage record."
        default:
            return "Permanently remove usage recorded during the \(displayName.lowercased())."
        }
    }

    public var confirmationTitle: String {
        switch self {
        case .today:
            return "Delete Today's Network History?"
        case .allHistory:
            return "Delete All Network History?"
        default:
            return "Delete Network History for the \(displayName)?"
        }
    }

    public var destructiveButtonTitle: String {
        switch self {
        case .today: return "Delete Today's Data"
        case .allHistory: return "Delete All History"
        default: return "Delete \(displayName)"
        }
    }

    /// Returns a half-open interval covering whole local calendar days.
    /// `nil` represents all stored history.
    public func dateInterval(
        containing date: Date = Date(),
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard self != .allHistory else { return nil }

        let dayCount: Int
        switch self {
        case .today: dayCount = 1
        case .last3Days: dayCount = 3
        case .last7Days: dayCount = 7
        case .last14Days: dayCount = 14
        case .last30Days: dayCount = 30
        case .last90Days: dayCount = 90
        case .allHistory: return nil
        }

        let startOfToday = calendar.startOfDay(for: date)
        guard
            let start = calendar.date(byAdding: .day, value: -(dayCount - 1), to: startOfToday),
            let end = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }
}
