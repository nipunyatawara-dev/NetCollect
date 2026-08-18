import Foundation

/// Options for sorting the application usage list.
public enum SortOption: String, CaseIterable, Identifiable, Sendable {
    case totalDescending = "Total Usage"
    case downloadDescending = "Download"
    case uploadDescending = "Upload"
    case nameAscending = "Name (A-Z)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .totalDescending:
            return "arrow.up.arrow.down.circle"
        case .downloadDescending:
            return "arrow.down.circle"
        case .uploadDescending:
            return "arrow.up.circle"
        case .nameAscending:
            return "textformat.abc"
        }
    }
}

/// Filter for narrowing down application category.
public enum AppCategoryFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Apps"
    case userOnly = "User Apps"
    case systemOnly = "System"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .userOnly:
            return "person.crop.circle"
        case .systemOnly:
            return "gearshape.2"
        }
    }
}

/// Refresh frequency options for UI data usage aggregation and charts.
public enum DataRefreshInterval: Int, CaseIterable, Identifiable, Sendable {
    case oneSecond = 1
    case twoSeconds = 2
    case threeSeconds = 3
    case fiveSeconds = 5
    case tenSeconds = 10

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .oneSecond: return "1 second"
        case .twoSeconds: return "2 seconds"
        case .threeSeconds: return "3 seconds (Default)"
        case .fiveSeconds: return "5 seconds"
        case .tenSeconds: return "10 seconds"
        }
    }

    public var intervalSeconds: Double {
        Double(rawValue)
    }
}
