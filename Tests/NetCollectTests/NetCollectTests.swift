import Foundation
import NetCollectCore

@main
@MainActor
struct NetCollectTestsRunner {
    static var passedCount = 0
    static var failedCount = 0

    static func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        if condition {
            passedCount += 1
            print("  ✅ PASS: \(message)")
        } else {
            failedCount += 1
            print("  ❌ FAIL: \(message) (Line \(line))")
        }
    }

    static func main() {
        print("🧪 Running NetCollect Test Suite...")

        testByteCountFormatter()
        testTimeframeFilterIntervals()
        testChartDataPointIdentity()
        testDatabaseServiceOperations()
        testAppResolverCleaning()

        print("\n==================================")
        print("Results: \(passedCount) Passed, \(failedCount) Failed")
        print("==================================")

        if failedCount > 0 {
            exit(1)
        }
    }

    static func testByteCountFormatter() {
        print("\n--- Testing ByteCountFormatter ---")
        assert(ByteCountFormatter.format(bytes: 0) == "0 B", "Format 0 bytes")
        assert(ByteCountFormatter.format(bytes: 512) == "512 B", "Format 512 B")
        assert(ByteCountFormatter.format(bytes: 1024) == "1.00 KB", "Format 1024 B")
        assert(ByteCountFormatter.format(bytes: 1024 * 1024 * 5) == "5.00 MB", "Format 5 MB")
        assert(ByteCountFormatter.format(bytes: 1024 * 1024 * 1024 * 2) == "2.00 GB", "Format 2 GB")

        assert(ByteCountFormatter.formatRate(bytesPerSec: 0) == "0 B/s", "Format rate 0 B/s")
        assert(ByteCountFormatter.formatRate(bytesPerSec: 2048) == "2.00 KB/s", "Format rate 2 KB/s")
        assert(ByteCountFormatter.formatRate(bytesPerSec: 1024 * 1024 * 15) == "15.0 MB/s", "Format rate 15 MB/s")
    }

    static func testTimeframeFilterIntervals() {
        print("\n--- Testing TimeframeFilter ---")
        let calendar = Calendar.current
        let now = Date()

        let dailyInterval = TimeframeFilter.daily.dateInterval(for: now, calendar: calendar)
        assert(dailyInterval.start == calendar.startOfDay(for: now), "Daily interval starts at start of day")
        assert(dailyInterval.end == now, "Daily interval ends at now")

        let weeklyInterval = TimeframeFilter.weekly.dateInterval(for: now, calendar: calendar)
        assert(weeklyInterval.start <= now, "Weekly interval starts before or at now")
        assert(weeklyInterval.end == now, "Weekly interval ends at now")

        let monthlyInterval = TimeframeFilter.monthly.dateInterval(for: now, calendar: calendar)
        assert(monthlyInterval.start <= now, "Monthly interval starts before or at now")
        assert(monthlyInterval.end == now, "Monthly interval ends at now")
    }

    static func testChartDataPointIdentity() {
        print("\n--- Testing Chart Data Points ---")
        let bucketDate = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ChartDataPoint(date: bucketDate, label: "10AM", bytesIn: 512, bytesOut: 128)
        let refreshed = ChartDataPoint(date: bucketDate, label: "10AM", bytesIn: 1_024, bytesOut: 256)

        assert(original.id == refreshed.id, "Refetched chart buckets retain stable identity")
        assert(original != refreshed, "Changed bucket values are detected during refresh")
    }

    static func testDatabaseServiceOperations() {
        print("\n--- Testing DatabaseService ---")
        let tempDir = FileManager.default.temporaryDirectory
        let dbURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: dbURL)
        }

        let db = DatabaseService(databaseURL: dbURL)
        let testDate = Date()

        // Record usage for App A
        db.recordUsage(
            date: testDate,
            bundleId: "com.spotify.client",
            appName: "Spotify",
            appPath: "/Applications/Spotify.app",
            bytesIn: 10_000_000,
            bytesOut: 500_000,
            isSystem: false
        )

        // Record usage for App B
        db.recordUsage(
            date: testDate,
            bundleId: "com.google.Chrome",
            appName: "Google Chrome",
            appPath: "/Applications/Google Chrome.app",
            bytesIn: 30_000_000,
            bytesOut: 2_000_000,
            isSystem: false
        )

        db.flushSync()

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: testDate)
        let records = db.fetchUsage(from: startOfDay, to: testDate.addingTimeInterval(3600))

        assert(records.count == 2, "Fetched exactly 2 aggregated records")
        assert(records[0].bundleId == "com.google.Chrome", "Chrome is ranked #1 by total usage")
        assert(records[0].bytesIn == 30_000_000, "Chrome bytesIn is 30 MB")
        assert(records[0].bytesOut == 2_000_000, "Chrome bytesOut is 2 MB")
        assert(records[0].totalBytes == 32_000_000, "Chrome total is 32 MB")

        assert(records[1].bundleId == "com.spotify.client", "Spotify is ranked #2")
        assert(records[1].bytesIn == 10_000_000, "Spotify bytesIn is 10 MB")
        assert(records[1].bytesOut == 500_000, "Spotify bytesOut is 500 KB")
        assert(records[1].totalBytes == 10_500_000, "Spotify total is 10.5 MB")

        assert(records[0].percentage > 0.70 && records[0].percentage < 0.80, "Chrome percentage calculation is ~75.3%")

        // Test Time Series
        let hourlyPoints = db.fetchTimeSeries(from: startOfDay, to: testDate.addingTimeInterval(3600), grouping: .hourly)
        assert(!hourlyPoints.isEmpty, "Time series generated non-empty hourly points")
        let totalTimeSeriesBytes = hourlyPoints.reduce(0) { $0 + $1.totalBytes }
        assert(totalTimeSeriesBytes == 42_500_000, "Time series aggregated total matches sum of apps (42.5 MB)")

        let quietDay = calendar.startOfDay(for: Date(timeIntervalSince1970: 978_307_200))
        let firstHalfHour = calendar.date(byAdding: .minute, value: 30, to: quietDay)!
        let firstHourPoints = db.fetchTimeSeries(from: quietDay, to: firstHalfHour, grouping: .hourly)
        assert(firstHourPoints.count == 1, "First hour contains no fabricated previous-day chart point")
        assert(firstHourPoints.first?.date == quietDay, "First hourly bucket starts at the requested day")

        // Test Clear
        db.clearAllData()
        let clearedRecords = db.fetchUsage(from: startOfDay, to: testDate.addingTimeInterval(3600))
        assert(clearedRecords.isEmpty, "Database successfully cleared")
    }

    static func testAppResolverCleaning() {
        print("\n--- Testing AppResolver ---")
        let resolver = AppResolver.shared
        let info1 = resolver.resolve(pid: 99999, rawName: "Signal Helper (")
        assert(info1.displayName == "Signal Helper", "Cleaned trailing parenthesis from process name")

        let info2 = resolver.resolve(pid: 99998, rawName: "mDNSResponder")
        assert(info2.isSystemProcess == true, "Identified mDNSResponder as system daemon")
    }
}
