import Foundation
import NetCollectCore

final class BandwidthRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [LiveBandwidth] = []

    func record(_ sample: LiveBandwidth) {
        lock.lock()
        samples.append(sample)
        lock.unlock()
    }

    func reset() {
        lock.lock()
        samples.removeAll()
        lock.unlock()
    }

    func downloadRates() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return samples.map(\.bytesInPerSecond)
    }
}

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
        setenv("NETCOLLECT_DISABLE_SHARED_COLLECTION", "1", 1)
        print("🧪 Running NetCollect Test Suite...")

        testByteCountFormatter()
        testTimeframeFilterIntervals()
        testChartDataPointIdentity()
        testDatabaseServiceOperations()
        testAppResolverCleaning()
        testSilentBackgroundModeSettings()
        testRefreshAndSamplingSettings()
        testUIVisibilityAndPowerEfficiency()
        testSnapshotDeltaAccounting()
        testInterfaceSpeedAccounting()
        testSingleInstanceGuard()
        testLiveNetworkCollectorTracking()

        print("\n==================================")
        print("Results: \(passedCount) Passed, \(failedCount) Failed")
        print("==================================")

        if failedCount > 0 {
            exit(1)
        }
    }

    static func testLiveNetworkCollectorTracking() {
        print("\n--- Testing Live NetworkCollector Tracking ---")
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("live_collector_\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: dbURL)
            try? FileManager.default.removeItem(atPath: dbURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: dbURL.path + "-shm")
        }
        let database = DatabaseService(databaseURL: dbURL)
        let collector = NetworkCollector(databaseService: database)
        let bandwidthRecorder = BandwidthRecorder()
        collector.onBandwidthUpdated = { bandwidthRecorder.record($0) }
        collector.pollingMode = .oneSecond
        collector.setUIVisible(true)
        collector.start()

        // Wait for nettop to launch and complete baseline (blocks 0 & 1)
        Thread.sleep(forTimeInterval: 3.5)
        bandwidthRecorder.reset()

        // Perform curl
        let curl = Process()
        curl.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        // Keep the transfer alive across at least one one-second nettop boundary;
        // very small downloads can open and close entirely between samples.
        curl.arguments = [
            "-s",
            "--limit-rate", "512K",
            "-o", "/dev/null",
            "https://speed.cloudflare.com/__down?bytes=1048576"
        ]
        try? curl.run()
        curl.waitUntilExit()

        // Wait for sample interval to process deltas (block 2+)
        Thread.sleep(forTimeInterval: 4.0)

        database.flushSync()
        let records = database.fetchUsage(from: Date().addingTimeInterval(-3600), to: Date().addingTimeInterval(3600))
        print("  Fetched \(records.count) active apps from live tracking:")
        for r in records {
            print("    -> \(r.appName) (\(r.bundleId)): \(ByteCountFormatter.format(bytes: r.bytesIn)) in, \(ByteCountFormatter.format(bytes: r.bytesOut)) out")
        }

        assert(!records.isEmpty, "Live network tracking captured real process deltas")
        let total = records.reduce(0) { $0 + $1.totalBytes }
        assert(total > 0, "Total recorded delta bytes is greater than 0")
        let curlDownload = records.first(where: { $0.bundleId == "system.curl" })?.bytesIn ?? 0
        assert(curlDownload >= 800_000, "Collector captures most of a known 1 MB short-lived download")
        assert(curlDownload <= 1_500_000, "Known 1 MB download cannot become a lifetime-counter spike")
        let downloadRates = bandwidthRecorder.downloadRates()
        print("  Observed interface download rates: \(downloadRates.map { ByteCountFormatter.formatRate(bytesPerSec: $0) })")
        assert(downloadRates.contains(where: { $0 >= 100_000 }), "Physical-interface speed reacts to the known download")
        assert(downloadRates.allSatisfy { $0 < 100_000_000 }, "Physical-interface speed cannot become a lifetime-counter spike")

        collector.onBandwidthUpdated = nil
        collector.stop()
    }

    static func testSnapshotDeltaAccounting() {
        print("\n--- Testing Snapshot Delta Accounting ---")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var accumulator = NetworkSnapshotAccumulator(retentionInterval: 60)

        let lifetimeBaseline = NetworkProcessSnapshot(
            pid: 42,
            rawName: "Browser Helper",
            processStartIdentifier: 100,
            bytesIn: 8_000_000_000,
            bytesOut: 2_000_000_000
        )
        let initialDeltas = accumulator.consume([lifetimeBaseline], at: start)
        assert(initialDeltas.isEmpty, "Initial lifetime counters establish a zero-usage baseline")

        let nextSample = NetworkProcessSnapshot(
            pid: 42,
            rawName: "Browser Helper",
            processStartIdentifier: 100,
            bytesIn: 8_000_004_096,
            bytesOut: 2_000_001_024
        )
        let nextDeltas = accumulator.consume([nextSample], at: start.addingTimeInterval(3))
        assert(nextDeltas.count == 1, "A repeated process snapshot produces one delta")
        assert(nextDeltas.first?.bytesIn == 4_096, "Download delta excludes the lifetime baseline")
        assert(nextDeltas.first?.bytesOut == 1_024, "Upload delta excludes the lifetime baseline")
        assert(nextDeltas.first?.observationInterval == 3, "Repeated-process speed uses its exact observation interval")

        _ = accumulator.consume([], at: start.addingTimeInterval(6))
        let reappearedSample = NetworkProcessSnapshot(
            pid: 42,
            rawName: "Browser Helper",
            processStartIdentifier: 100,
            bytesIn: 8_000_006_144,
            bytesOut: 2_000_001_536
        )
        let reappearedDeltas = accumulator.consume([reappearedSample], at: start.addingTimeInterval(9))
        assert(reappearedDeltas.first?.bytesIn == 2_048, "A temporarily missing process retains its download baseline")
        assert(reappearedDeltas.first?.bytesOut == 512, "A temporarily missing process retains its upload baseline")
        assert(reappearedDeltas.first?.observationInterval == 6, "Reappearing-process speed spans the full missing interval")

        let newlyObserved = NetworkProcessSnapshot(
            pid: 99,
            rawName: "Uploader",
            processStartIdentifier: 200,
            bytesIn: 100_000,
            bytesOut: 3_000_000_000
        )
        let newProcessDeltas = accumulator.consume([newlyObserved], at: start.addingTimeInterval(12))
        assert(newProcessDeltas.isEmpty, "A newly observed process cannot inject lifetime counters")

        let justLaunched = NetworkProcessSnapshot(
            pid: 100,
            rawName: "New Downloader",
            processStartIdentifier: UInt64(start.addingTimeInterval(13).timeIntervalSince1970 * 1_000_000),
            bytesIn: 750_000,
            bytesOut: 25_000
        )
        let justLaunchedDeltas = accumulator.consume([justLaunched], at: start.addingTimeInterval(15))
        assert(justLaunchedDeltas.first?.bytesIn == 750_000, "A process launched after the prior snapshot counts its initial download")
        assert(justLaunchedDeltas.first?.bytesOut == 25_000, "A process launched after the prior snapshot counts its initial upload")

        let reusedPID = NetworkProcessSnapshot(
            pid: 99,
            rawName: "Uploader",
            processStartIdentifier: 201,
            bytesIn: 7_000_000_000,
            bytesOut: 4_000_000_000
        )
        let reusedPIDDeltas = accumulator.consume([reusedPID], at: start.addingTimeInterval(15))
        assert(reusedPIDDeltas.isEmpty, "PID reuse establishes a new process baseline")

        let rolledBack = NetworkProcessSnapshot(
            pid: 99,
            rawName: "Uploader",
            processStartIdentifier: 201,
            bytesIn: 10,
            bytesOut: 20
        )
        let rollbackDeltas = accumulator.consume([rolledBack], at: start.addingTimeInterval(18))
        assert(rollbackDeltas.isEmpty, "Counter rollback establishes a new zero-usage baseline")

        let afterRollback = NetworkProcessSnapshot(
            pid: 99,
            rawName: "Uploader",
            processStartIdentifier: 201,
            bytesIn: 110,
            bytesOut: 220
        )
        let afterRollbackDeltas = accumulator.consume([afterRollback], at: start.addingTimeInterval(21))
        assert(afterRollbackDeltas.first?.bytesIn == 100, "Download resumes accurately after a counter reset")
        assert(afterRollbackDeltas.first?.bytesOut == 200, "Upload resumes accurately after a counter reset")

        var expiringAccumulator = NetworkSnapshotAccumulator(retentionInterval: 5)
        _ = expiringAccumulator.consume([lifetimeBaseline], at: start)
        let expiredDeltas = expiringAccumulator.consume([nextSample], at: start.addingTimeInterval(10))
        assert(expiredDeltas.isEmpty, "An expired process baseline cannot create a delayed lifetime spike")
    }

    static func testSingleInstanceGuard() {
        print("\n--- Testing Single Instance Guard ---")
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("netcollect-instance-\(UUID().uuidString).lock")
        defer { try? FileManager.default.removeItem(at: lockURL) }

        let first = SingleInstanceGuard(lockURL: lockURL)
        let second = SingleInstanceGuard(lockURL: lockURL)
        assert(first.acquire(), "First application instance acquires the collector lock")
        assert(!second.acquire(), "Second application instance is prevented from collecting")
        first.release()
        assert(second.acquire(), "Collector lock becomes available after the first instance exits")
        second.release()
    }

    static func testInterfaceSpeedAccounting() {
        print("\n--- Testing Interface Speed Accounting ---")
        var accumulator = NetworkInterfaceAccumulator()
        let baseline = [NetworkInterfaceSnapshot(name: "en0", bytesIn: 9_000_000_000, bytesOut: 4_000_000_000)]
        assert(accumulator.consume(baseline, atUptime: 100) == nil, "Interface lifetime totals establish a speed baseline")

        let next = [NetworkInterfaceSnapshot(name: "en0", bytesIn: 9_002_000_000, bytesOut: 4_000_500_000)]
        let rate = accumulator.consume(next, atUptime: 102)
        assert(rate?.bytesInPerSecond == 1_000_000, "Interface download speed uses counter delta over elapsed time")
        assert(rate?.bytesOutPerSecond == 250_000, "Interface upload speed uses counter delta over elapsed time")

        let reset = [NetworkInterfaceSnapshot(name: "en0", bytesIn: 10, bytesOut: 20)]
        assert(accumulator.consume(reset, atUptime: 103) == nil, "Interface counter reset cannot create a speed spike")
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
        assert(dailyInterval.end >= now, "Daily interval spans to end of day")

        let weeklyInterval = TimeframeFilter.weekly.dateInterval(for: now, calendar: calendar)
        assert(weeklyInterval.start <= now, "Weekly interval starts before or at now")
        assert(weeklyInterval.end >= now, "Weekly interval spans to end of week")

        let monthlyInterval = TimeframeFilter.monthly.dateInterval(for: now, calendar: calendar)
        assert(monthlyInterval.start <= now, "Monthly interval starts before or at now")
        assert(monthlyInterval.end >= now, "Monthly interval spans to end of month")

        let dailyDesc = TimeframeFilter.daily.rangeDescription(for: now, calendar: calendar)
        assert(dailyDesc.starts(with: "Today ("), "Daily description starts with 'Today ('")

        let weeklyDesc = TimeframeFilter.weekly.rangeDescription(for: now, calendar: calendar)
        assert(weeklyDesc.starts(with: "This Week ("), "Weekly description starts with 'This Week ('")

        let monthlyDesc = TimeframeFilter.monthly.rangeDescription(for: now, calendar: calendar)
        assert(monthlyDesc.starts(with: "This Month ("), "Monthly description starts with 'This Month ('")
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

        // A packet tunnel sees App A and App B's payload again. It is retained in
        // storage for diagnostics but must not inflate aggregate usage.
        db.recordUsage(
            date: testDate,
            bundleId: "com.example.vpn.PacketTunnel",
            appName: "PacketTunnel",
            appPath: "/Applications/ExampleVPN.app/Contents/PlugIns/PacketTunnel.appex",
            bytesIn: 40_000_000,
            bytesOut: 2_500_000,
            isSystem: true,
            isTrafficRelay: true
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

        let fullDayEnd = calendar.date(byAdding: .day, value: 1, to: quietDay)!.addingTimeInterval(-1)
        let fullDayPoints = db.fetchTimeSeries(from: quietDay, to: fullDayEnd, grouping: .hourly)
        assert(fullDayPoints.count == 24, "Full day generates 24 hourly buckets")

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

        assert(AppResolver.isTrafficRelayExtensionPoint("com.apple.networkextension.packet-tunnel"), "Identified packet tunnel as a traffic relay")
        assert(AppResolver.isTrafficRelayExtensionPoint("com.apple.networkextension.app-proxy"), "Identified app proxy as a traffic relay")
        assert(!AppResolver.isTrafficRelayExtensionPoint("com.apple.Safari.content-blocker"), "Did not classify unrelated extensions as traffic relays")
    }

    static func testSilentBackgroundModeSettings() {
        print("\n--- Testing Silent Background Mode Settings ---")
        let vm = AppUsageViewModel.shared
        let initialSilent = vm.isSilentBackgroundMode
        let initialMenu = vm.showMenuBarExtra

        // Enable silent background mode
        vm.isSilentBackgroundMode = true
        assert(UserDefaults.standard.bool(forKey: "netcollect_silent_bg_mode") == true, "Silent background mode persisted to UserDefaults")
        assert(vm.showMenuBarExtra == false, "Menu bar extra is hidden when silent background mode is enabled")

        // Disable silent background mode
        vm.isSilentBackgroundMode = false
        assert(UserDefaults.standard.bool(forKey: "netcollect_silent_bg_mode") == false, "Silent background mode disabled in UserDefaults")
        assert(vm.showMenuBarExtra == true, "Menu bar extra is restored when silent background mode is disabled")

        // Restore initial state
        vm.isSilentBackgroundMode = initialSilent
        vm.showMenuBarExtra = initialMenu
    }

    static func testRefreshAndSamplingSettings() {
        print("\n--- Testing Refresh and Sampling Settings ---")
        // Test DataRefreshInterval
        assert(DataRefreshInterval.oneSecond.intervalSeconds == 1.0, "DataRefreshInterval 1s has 1.0s interval")
        assert(DataRefreshInterval.twoSeconds.intervalSeconds == 2.0, "DataRefreshInterval 2s has 2.0s interval")
        assert(DataRefreshInterval.threeSeconds.intervalSeconds == 3.0, "DataRefreshInterval 3s has 3.0s interval")
        assert(DataRefreshInterval.fiveSeconds.intervalSeconds == 5.0, "DataRefreshInterval 5s has 5.0s interval")
        assert(DataRefreshInterval.tenSeconds.intervalSeconds == 10.0, "DataRefreshInterval 10s has 10.0s interval")

        // Test PollingMode
        assert(PollingMode.oneSecond.intervalSeconds == 1, "PollingMode 1s has 1s interval")
        assert(PollingMode.twoSeconds.intervalSeconds == 2, "PollingMode 2s has 2s interval")
        assert(PollingMode.balanced.intervalSeconds == 3, "PollingMode 3s has 3s interval")
        assert(PollingMode.eco.intervalSeconds == 5, "PollingMode 5s has 5s interval")
        assert(PollingMode.tenSeconds.intervalSeconds == 10, "PollingMode 10s has 10s interval")

        // Test PollingMode backwards compatibility / migration
        assert(PollingMode.from(storedValue: "High Precision (1s)") == .oneSecond, "Migrated High Precision (1s) to oneSecond")
        assert(PollingMode.from(storedValue: "Battery Saver (5s)") == .eco, "Migrated Battery Saver (5s) to eco")
        assert(PollingMode.from(storedValue: "Balanced (3s)") == .balanced, "Migrated Balanced (3s) to balanced")
        assert(PollingMode.from(storedValue: "2 seconds") == .twoSeconds, "Parsed 2 seconds correctly")
        assert(PollingMode.from(storedValue: "10 seconds") == .tenSeconds, "Parsed 10 seconds correctly")

        // Test AppUsageViewModel dataRefreshInterval update & persistence
        let vm = AppUsageViewModel.shared
        let initialRefresh = vm.dataRefreshInterval
        let initialPolling = vm.pollingMode

        vm.dataRefreshInterval = .oneSecond
        assert(UserDefaults.standard.integer(forKey: "netcollect_data_refresh_interval") == 1, "dataRefreshInterval persisted to UserDefaults")

        vm.dataRefreshInterval = .fiveSeconds
        assert(UserDefaults.standard.integer(forKey: "netcollect_data_refresh_interval") == 5, "dataRefreshInterval update persisted to UserDefaults")

        vm.pollingMode = .tenSeconds
        assert(UserDefaults.standard.string(forKey: "netcollect_polling_mode") == PollingMode.tenSeconds.rawValue, "pollingMode persisted to UserDefaults")

        // Test isShowingSettings
        let appDelegate = AppDelegate()
        assert(vm.isShowingSettings == false, "Initial isShowingSettings is false")
        appDelegate.openSettingsWindow()
        assert(vm.isShowingSettings == true, "openSettingsWindow sets isShowingSettings to true")
        vm.isShowingSettings = false

        // Restore initial settings
        vm.dataRefreshInterval = initialRefresh
        vm.pollingMode = initialPolling
    }

    static func testUIVisibilityAndPowerEfficiency() {
        print("\n--- Testing UI Visibility & Power Efficiency ---")
        let vm = AppUsageViewModel.shared

        assert(vm.isUIVisible == false, "Initial state has no active UI windows")

        // Simulate Dashboard opening
        vm.registerUIVisible()
        assert(vm.isUIVisible == true, "isUIVisible is true after first UI surface appears")

        // Simulate MenuBar opening concurrently
        vm.registerUIVisible()
        assert(vm.isUIVisible == true, "isUIVisible remains true when multiple UI surfaces appear")

        // MenuBar closes
        vm.unregisterUIVisible()
        assert(vm.isUIVisible == true, "isUIVisible is still true because Dashboard is still open")

        // Dashboard closes
        vm.unregisterUIVisible()
        assert(vm.isUIVisible == false, "isUIVisible is false when all UI surfaces close, suspending background UI timer")
    }
}
