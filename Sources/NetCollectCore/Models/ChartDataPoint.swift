import Foundation

/// Represents a single time slice data point for Swift Charts visualization.
///
/// A bucket's date is also its stable identity. Time-series data is refreshed often,
/// and using a new UUID for every fetch makes Swift Charts discard and recreate every
/// mark even when only the current bucket changed.
public struct ChartDataPoint: Identifiable, Sendable, Equatable {
    public var id: Date { date }
    public let date: Date
    public let label: String
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var totalBytes: UInt64 { bytesIn + bytesOut }

    public init(
        date: Date,
        label: String,
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0
    ) {
        self.date = date
        self.label = label
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}
