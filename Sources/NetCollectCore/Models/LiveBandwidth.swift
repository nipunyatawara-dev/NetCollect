import Foundation

/// Real-time network throughput information.
public struct LiveBandwidth: Sendable {
    public var bytesInPerSecond: Double
    public var bytesOutPerSecond: Double
    public var totalBytesPerSecond: Double { bytesInPerSecond + bytesOutPerSecond }
    public var peakInPerSecond: Double
    public var peakOutPerSecond: Double
    public var activeProcessCount: Int

    public init(
        bytesInPerSecond: Double = 0,
        bytesOutPerSecond: Double = 0,
        peakInPerSecond: Double = 0,
        peakOutPerSecond: Double = 0,
        activeProcessCount: Int = 0
    ) {
        self.bytesInPerSecond = bytesInPerSecond
        self.bytesOutPerSecond = bytesOutPerSecond
        self.peakInPerSecond = peakInPerSecond
        self.peakOutPerSecond = peakOutPerSecond
        self.activeProcessCount = activeProcessCount
    }

    public var formattedInRate: String {
        ByteCountFormatter.formatRate(bytesPerSec: bytesInPerSecond)
    }

    public var formattedOutRate: String {
        ByteCountFormatter.formatRate(bytesPerSec: bytesOutPerSecond)
    }

    public var formattedTotalRate: String {
        ByteCountFormatter.formatRate(bytesPerSec: totalBytesPerSecond)
    }
}
