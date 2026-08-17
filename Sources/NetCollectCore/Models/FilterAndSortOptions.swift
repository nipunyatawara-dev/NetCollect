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
