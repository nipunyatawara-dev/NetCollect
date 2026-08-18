import Foundation
import SQLite3

public enum TimeGrouping: Sendable {
    case hourly
    case daily
}

/// Persistent, high-performance embedded SQLite database for network usage history.
public final class DatabaseService: @unchecked Sendable {
    public static let shared = DatabaseService()

    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.netcollect.databaseservice", qos: .utility)
    private let lock = NSLock()

    // In-memory buffer to batch writes and avoid disk thrashing
    private struct PendingUsage {
        var appName: String
        var appPath: String?
        var bytesIn: UInt64
        var bytesOut: UInt64
        var isSystem: Bool
    }
    private var writeBuffer: [String: PendingUsage] = [:] // key: "\(timestamp_hour)_\(bundleId)"
    private var lastFlushTime: Date = Date()

    public init(databaseURL: URL? = nil) {
        let url = databaseURL ?? defaultDatabaseURL()
        openDatabase(at: url)
        createTables()
    }

    deinit {
        flushSync()
        if let db = db {
            sqlite3_close(db)
        }
    }

    private func defaultDatabaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("NetCollect", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("netcollect.sqlite")
    }

    private func openDatabase(at url: URL) {
        if sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("Error opening database at \(url.path): \(errmsg)")
        } else {
            // Enable WAL mode for high concurrency and performance
            execute(sql: "PRAGMA journal_mode=WAL;")
            execute(sql: "PRAGMA synchronous=NORMAL;")
            execute(sql: "PRAGMA cache_size = -2000;")
            execute(sql: "PRAGMA temp_store = MEMORY;")
        }
    }

    private func createTables() {
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS hourly_usage (
            timestamp_hour INTEGER NOT NULL,
            bundle_id TEXT NOT NULL,
            app_name TEXT NOT NULL,
            app_path TEXT,
            bytes_in INTEGER NOT NULL DEFAULT 0,
            bytes_out INTEGER NOT NULL DEFAULT 0,
            is_system INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (timestamp_hour, bundle_id)
        );
        CREATE INDEX IF NOT EXISTS idx_hourly_ts ON hourly_usage(timestamp_hour);
        CREATE INDEX IF NOT EXISTS idx_hourly_bundle ON hourly_usage(bundle_id);
        """
        execute(sql: createTableSQL)
    }

    private func execute(sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            if let err = err {
                let msg = String(cString: err)
                print("SQLite exec error: \(msg)")
                sqlite3_free(err)
            }
        }
    }

    /// Records delta bytes in the in-memory buffer.
    public func recordUsage(
        date: Date = Date(),
        bundleId: String,
        appName: String,
        appPath: String?,
        bytesIn: UInt64,
        bytesOut: UInt64,
        isSystem: Bool
    ) {
        guard bytesIn > 0 || bytesOut > 0 else { return }

        let calendar = Calendar.current
        let hourComponents = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let hourDate = calendar.date(from: hourComponents) ?? date
        let timestampHour = Int64(hourDate.timeIntervalSince1970)

        let bufferKey = "\(timestampHour)|\(bundleId)"

        lock.lock()
        if var existing = writeBuffer[bufferKey] {
            existing.bytesIn += bytesIn
            existing.bytesOut += bytesOut
            writeBuffer[bufferKey] = existing
        } else {
            writeBuffer[bufferKey] = PendingUsage(
                appName: appName,
                appPath: appPath,
                bytesIn: bytesIn,
                bytesOut: bytesOut,
                isSystem: isSystem
            )
        }

        let count = writeBuffer.count
        let elapsed = Date().timeIntervalSince(lastFlushTime)
        lock.unlock()

        // Flush every 15 seconds or if buffer exceeds 50 items to minimize disk wakeups
        if elapsed > 15.0 || count > 50 {
            flushAsync()
        }
    }

    /// Asynchronously flushes the in-memory write buffer to SQLite.
    public func flushAsync() {
        dbQueue.async { [weak self] in
            self?.flushSyncInternal()
        }
    }

    /// Synchronously writes pending usage to disk in a single transaction.
    public func flushSync() {
        dbQueue.sync {
            self.flushSyncInternal()
        }
    }

    private func flushSyncInternal() {
        lock.lock()
        guard !writeBuffer.isEmpty else {
            lastFlushTime = Date()
            lock.unlock()
            return
        }
        let pending = writeBuffer
        writeBuffer.removeAll(keepingCapacity: true)
        lastFlushTime = Date()
        lock.unlock()

        guard let db = self.db else { return }

        execute(sql: "BEGIN TRANSACTION;")

        let upsertSQL = """
        INSERT INTO hourly_usage (timestamp_hour, bundle_id, app_name, app_path, bytes_in, bytes_out, is_system)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(timestamp_hour, bundle_id) DO UPDATE SET
            bytes_in = bytes_in + excluded.bytes_in,
            bytes_out = bytes_out + excluded.bytes_out,
            app_name = CASE WHEN excluded.app_name != '' THEN excluded.app_name ELSE hourly_usage.app_name END,
            app_path = CASE WHEN excluded.app_path IS NOT NULL THEN excluded.app_path ELSE hourly_usage.app_path END,
            is_system = MAX(hourly_usage.is_system, excluded.is_system);
        """

        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, upsertSQL, -1, &statement, nil) == SQLITE_OK {
            for (key, usage) in pending {
                let parts = key.split(separator: "|")
                guard parts.count == 2, let ts = Int64(parts[0]) else { continue }
                let bundleId = String(parts[1])

                sqlite3_bind_int64(statement, 1, ts)
                sqlite3_bind_text(statement, 2, (bundleId as NSString).utf8String, -1, nil)
                sqlite3_bind_text(statement, 3, (usage.appName as NSString).utf8String, -1, nil)
                if let path = usage.appPath {
                    sqlite3_bind_text(statement, 4, (path as NSString).utf8String, -1, nil)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                sqlite3_bind_int64(statement, 5, Int64(usage.bytesIn))
                sqlite3_bind_int64(statement, 6, Int64(usage.bytesOut))
                sqlite3_bind_int(statement, 7, usage.isSystem ? 1 : 0)

                sqlite3_step(statement)
                sqlite3_reset(statement)
            }
            sqlite3_finalize(statement)
        }

        execute(sql: "COMMIT;")
    }

    /// Fetches aggregated application usage for a given date range.
    public func fetchUsage(from startDate: Date, to endDate: Date = Date()) -> [AppUsageRecord] {
        dbQueue.sync {
            self.flushSyncInternal()
            guard let db = self.db else { return [] }

            let startTs = Int64(startDate.timeIntervalSince1970)
            let endTs = Int64(endDate.timeIntervalSince1970)

            let querySQL = """
            SELECT
                bundle_id,
                app_name,
                app_path,
                SUM(bytes_in) as total_in,
                SUM(bytes_out) as total_out,
                MAX(is_system) as is_system
            FROM hourly_usage
            WHERE timestamp_hour >= ? AND timestamp_hour <= ?
            GROUP BY bundle_id
            ORDER BY (total_in + total_out) DESC;
            """

            var statement: OpaquePointer?
            var records: [AppUsageRecord] = []
            var totalAllBytes: UInt64 = 0

            if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, startTs)
                sqlite3_bind_int64(statement, 2, endTs)

                while sqlite3_step(statement) == SQLITE_ROW {
                    let bundleId = String(cString: sqlite3_column_text(statement, 0))
                    let appName = String(cString: sqlite3_column_text(statement, 1))
                    var appPath: String? = nil
                    if let pathText = sqlite3_column_text(statement, 2) {
                        appPath = String(cString: pathText)
                    }
                    let bytesIn = UInt64(max(0, sqlite3_column_int64(statement, 3)))
                    let bytesOut = UInt64(max(0, sqlite3_column_int64(statement, 4)))
                    let isSystem = sqlite3_column_int(statement, 5) != 0

                    let total = bytesIn + bytesOut
                    totalAllBytes += total

                    let record = AppUsageRecord(
                        id: bundleId,
                        bundleId: bundleId,
                        appName: appName,
                        appPath: appPath,
                        bytesIn: bytesIn,
                        bytesOut: bytesOut,
                        percentage: 0.0,
                        isSystemProcess: isSystem
                    )
                    records.append(record)
                }
                sqlite3_finalize(statement)
            }

            // Calculate usage percentages
            if totalAllBytes > 0 {
                for i in 0..<records.count {
                    records[i].percentage = Double(records[i].totalBytes) / Double(totalAllBytes)
                }
            }

            return records
        }
    }

    /// Fetches time-series data points for charts.
    public func fetchTimeSeries(from startDate: Date, to endDate: Date = Date(), grouping: TimeGrouping) -> [ChartDataPoint] {
        dbQueue.sync {
            self.flushSyncInternal()
            guard let db = self.db else { return [] }

            let startTs = Int64(startDate.timeIntervalSince1970)
            let endTs = Int64(endDate.timeIntervalSince1970)

            let querySQL = """
            SELECT
                timestamp_hour,
                SUM(bytes_in) as total_in,
                SUM(bytes_out) as total_out
            FROM hourly_usage
            WHERE timestamp_hour >= ? AND timestamp_hour <= ?
            GROUP BY timestamp_hour
            ORDER BY timestamp_hour ASC;
            """

            var statement: OpaquePointer?
            var rawPoints: [(date: Date, bytesIn: UInt64, bytesOut: UInt64)] = []

            if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_int64(statement, 1, startTs)
                sqlite3_bind_int64(statement, 2, endTs)

                while sqlite3_step(statement) == SQLITE_ROW {
                    let ts = sqlite3_column_int64(statement, 0)
                    let bytesIn = UInt64(max(0, sqlite3_column_int64(statement, 1)))
                    let bytesOut = UInt64(max(0, sqlite3_column_int64(statement, 2)))
                    let date = Date(timeIntervalSince1970: TimeInterval(ts))
                    rawPoints.append((date, bytesIn, bytesOut))
                }
                sqlite3_finalize(statement)
            }

            let calendar = Calendar.current
            var results: [ChartDataPoint] = []

            switch grouping {
            case .hourly:
                let hourFormatter = DateFormatter()
                hourFormatter.dateFormat = "ha" // e.g. 2PM
                let startOfTargetDay = calendar.startOfDay(for: startDate)
                var current = startOfTargetDay
                let endHourComponents = calendar.dateComponents([.year, .month, .day, .hour], from: endDate)
                let endHourDate = calendar.date(from: endHourComponents) ?? endDate

                var map: [Date: (in: UInt64, out: UInt64)] = [:]
                for p in rawPoints {
                    let comps = calendar.dateComponents([.year, .month, .day, .hour], from: p.date)
                    if let bucketDate = calendar.date(from: comps) {
                        map[bucketDate] = (p.bytesIn, p.bytesOut)
                    }
                }

                while current <= endHourDate {
                    let comps = calendar.dateComponents([.year, .month, .day, .hour], from: current)
                    let bucketDate = calendar.date(from: comps) ?? current
                    let data = map[bucketDate] ?? (0, 0)
                    results.append(ChartDataPoint(
                        date: bucketDate,
                        label: hourFormatter.string(from: bucketDate),
                        bytesIn: data.in,
                        bytesOut: data.out
                    ))
                    current = calendar.date(byAdding: .hour, value: 1, to: current) ?? current.addingTimeInterval(3600)
                }

            case .daily:
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "MMM d" // e.g. Aug 17

                var map: [Date: (in: UInt64, out: UInt64)] = [:]
                for p in rawPoints {
                    let dayStart = calendar.startOfDay(for: p.date)
                    let existing = map[dayStart] ?? (0, 0)
                    map[dayStart] = (existing.in + p.bytesIn, existing.out + p.bytesOut)
                }

                var current = calendar.startOfDay(for: startDate)
                let endDay = calendar.startOfDay(for: endDate)

                while current <= endDay {
                    let data = map[current] ?? (0, 0)
                    results.append(ChartDataPoint(
                        date: current,
                        label: dayFormatter.string(from: current),
                        bytesIn: data.in,
                        bytesOut: data.out
                    ))
                    current = calendar.date(byAdding: .day, value: 1, to: current) ?? current.addingTimeInterval(86400)
                }
            }

            return results
        }
    }

    /// Clears all historical data.
    public func clearAllData() {
        dbQueue.sync {
            lock.lock()
            writeBuffer.removeAll()
            lock.unlock()
            execute(sql: "DELETE FROM hourly_usage; VACUUM;")
        }
    }
}
