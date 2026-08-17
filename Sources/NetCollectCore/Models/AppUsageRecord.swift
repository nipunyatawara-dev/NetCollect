import Foundation
import AppKit

/// Represents an aggregated network usage record for a specific application or process.
public struct AppUsageRecord: Identifiable, Sendable, Hashable {
    public let id: String
    public let bundleId: String
    public let appName: String
    public let appPath: String?
    public var bytesIn: UInt64
    public var bytesOut: UInt64
    public var totalBytes: UInt64 { bytesIn + bytesOut }
    public var percentage: Double
    public let isSystemProcess: Bool
    public var lastActiveDate: Date?

    public init(
        id: String,
        bundleId: String,
        appName: String,
        appPath: String? = nil,
        bytesIn: UInt64 = 0,
        bytesOut: UInt64 = 0,
        percentage: Double = 0.0,
        isSystemProcess: Bool = false,
        lastActiveDate: Date? = nil
    ) {
        self.id = id
        self.bundleId = bundleId
        self.appName = appName
        self.appPath = appPath
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
        self.percentage = percentage
        self.isSystemProcess = isSystemProcess
        self.lastActiveDate = lastActiveDate
    }

    public var formattedIn: String {
        ByteCountFormatter.format(bytes: bytesIn)
    }

    public var formattedOut: String {
        ByteCountFormatter.format(bytes: bytesOut)
    }

    public var formattedTotal: String {
        ByteCountFormatter.format(bytes: totalBytes)
    }

    public var percentageString: String {
        String(format: "%.1f%%", percentage * 100)
    }
}

/// High-performance utility to format byte counts into human-readable strings.
public enum ByteCountFormatter {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB"]

    public static func format(bytes: UInt64) -> String {
        if bytes == 0 { return "0 B" }
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        } else if value >= 100 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else if value >= 10 {
            return String(format: "%.1f %@", value, units[unitIndex])
        } else {
            return String(format: "%.2f %@", value, units[unitIndex])
        }
    }

    public static func formatRate(bytesPerSec: Double) -> String {
        if bytesPerSec <= 0 { return "0 B/s" }
        var value = bytesPerSec
        var unitIndex = 0

        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }

        let unitStr = units[unitIndex] + "/s"
        if unitIndex == 0 {
            return String(format: "%.0f %@", value, unitStr)
        } else if value >= 100 {
            return String(format: "%.0f %@", value, unitStr)
        } else if value >= 10 {
            return String(format: "%.1f %@", value, unitStr)
        } else {
            return String(format: "%.2f %@", value, unitStr)
        }
    }
}
