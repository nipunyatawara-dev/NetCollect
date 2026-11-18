import Darwin
import Foundation
import SQLite3
import os

public enum TimeGrouping: Sendable {
    case hourly
    case daily
}

/// The connection, pending writes, and flush deadline are owned by dbQueue.
public final class DatabaseService: @unchecked Sendable {
    public static let shared = DatabaseService()

    struct Snapshot: Sendable {
        let records: [AppUsageRecord]
        let points: [ChartDataPoint]
    }

    private struct SQLiteError: Error {
        let code: Int32
        let message: String
    }

    private struct UsageKey: Hashable {
        let hour: Int64
        let bundleID: String
    }

    private struct PendingUsage {
        var appName: String
        var appPath: String?
        var bytesIn: Int64
        var bytesOut: Int64
        var isSystem: Bool
        var isTrafficRelay: Bool
    }

    private static let logger = Logger(subsystem: "com.netcollect.app", category: "storage")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let url: URL
    private let usesDefaultDirectory: Bool
    private let dbQueue = DispatchQueue(label: "com.netcollect.databaseservice", qos: .utility)
    private let queueKey = DispatchSpecificKey<Void>()
    private var db: OpaquePointer?
    private var writeBuffer: [UsageKey: PendingUsage] = [:]
    private var flushDeadline: DispatchWorkItem?
    private var lastFlushFailed = false

    public init(databaseURL: URL? = nil) {
        url = databaseURL ?? LocalStorage.directory.appending(path: "netcollect.sqlite")
        usesDefaultDirectory = databaseURL == nil
        dbQueue.setSpecific(key: queueKey, value: ())
        dbQueue.sync { _ = attempt { try openDatabaseIfNeeded() } }
    }

    deinit {
        // The last queued record can release the final reference on dbQueue.
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            closeDatabase()
        } else {
            dbQueue.sync { closeDatabase() }
        }
    }

    private func closeDatabase() {
        _ = flushPending()
        flushDeadline?.cancel()
        if let db { sqlite3_close(db) }
    }

    private func openDatabaseIfNeeded() throws {
        guard db == nil else { return }

        if usesDefaultDirectory { try LocalStorage.prepareDirectory() }
        // macOS temporary URLs can start with /var, a system symlink. Resolve
        // the parent while retaining no-follow checks on the database and sidecars.
        guard let parent = realpath(url.deletingLastPathComponent().path, nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { free(parent) }
        let path = URL(fileURLWithPath: String(cString: parent), isDirectory: true)
            .appending(path: url.lastPathComponent).path
        let descriptor = try LocalStorage.openPrivateFile(at: path, create: true)
        close(descriptor)
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = try LocalStorage.openPrivateFile(at: path + suffix, create: false)
            if sidecar >= 0 { close(sidecar) }
        }

        do {
            try check(sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW, nil))
            try check(sqlite3_busy_timeout(db, 250))
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=NORMAL;")
            try execute("PRAGMA secure_delete=ON;")
            try execute("""
                CREATE TABLE IF NOT EXISTS hourly_usage (
                    timestamp_hour INTEGER NOT NULL,
                    bundle_id TEXT NOT NULL,
                    app_name TEXT NOT NULL,
                    app_path TEXT,
                    bytes_in INTEGER NOT NULL DEFAULT 0,
                    bytes_out INTEGER NOT NULL DEFAULT 0,
                    is_system INTEGER NOT NULL DEFAULT 0,
                    is_traffic_relay INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (timestamp_hour, bundle_id)
                );
                """)
            // Databases created before relay classification can be opened in place.
            let hasRelayColumn = try withStatement("PRAGMA table_info(hourly_usage);") { statement in
                while try readRow(statement) {
                    if string(statement, at: 1) == "is_traffic_relay" { return true }
                }
                return false
            }
            if !hasRelayColumn {
                try execute("ALTER TABLE hourly_usage ADD COLUMN is_traffic_relay INTEGER NOT NULL DEFAULT 0;")
            }
        } catch {
            if let db { sqlite3_close(db) }
            db = nil
            throw error
        }
    }

    private func attempt<T>(_ operation: () throws -> T) -> T? {
        do {
            return try operation()
        } catch let error as SQLiteError {
            Self.logger.error("SQLite error \(error.code): \(error.message, privacy: .private)")
        } catch {
            Self.logger.error("History storage error: \(error.localizedDescription, privacy: .private)")
        }
        return nil
    }

    private func check(_ code: Int32, expecting expected: Int32 = SQLITE_OK) throws {
        guard code == expected else {
            throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(db, sql, nil, nil, nil))
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var prepared: OpaquePointer?
        try check(sqlite3_prepare_v2(db, sql, -1, &prepared, nil))
        guard let prepared else { throw SQLiteError(code: SQLITE_ERROR, message: "Missing statement") }
        defer { sqlite3_finalize(prepared) }
        return try body(prepared)
    }

    private func readRow(_ statement: OpaquePointer) throws -> Bool {
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return false }
        try check(result, expecting: SQLITE_ROW)
        return true
    }

    private func string(_ statement: OpaquePointer, at index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    public func recordUsage(
        date: Date = Date(),
        bundleId: String,
        appName: String,
        appPath: String?,
        bytesIn: UInt64,
        bytesOut: UInt64,
        isSystem: Bool,
        isTrafficRelay: Bool = false
    ) {
        guard bytesIn > 0 || bytesOut > 0 else { return }
        let start = Calendar.current.dateInterval(of: .hour, for: date)?.start ?? date
        let key = UsageKey(hour: Int64(start.timeIntervalSince1970), bundleID: bundleId)

        dbQueue.async { [self] in
            var pending = writeBuffer[key] ?? PendingUsage(
                appName: appName, appPath: appPath, bytesIn: 0, bytesOut: 0,
                isSystem: false, isTrafficRelay: false
            )
            if !appName.isEmpty { pending.appName = appName }
            pending.appPath = appPath ?? pending.appPath
            pending.bytesIn += min(Int64(clamping: bytesIn), Int64.max - pending.bytesIn)
            pending.bytesOut += min(Int64(clamping: bytesOut), Int64.max - pending.bytesOut)
            pending.isSystem = pending.isSystem || isSystem
            pending.isTrafficRelay = pending.isTrafficRelay || isTrafficRelay
            writeBuffer[key] = pending
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        guard flushDeadline == nil, !writeBuffer.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in
            _ = self?.flushPending()
        }
        flushDeadline = work
        dbQueue.asyncAfter(deadline: .now() + .seconds(5), execute: work)
    }

    @discardableResult
    public func flushSync() -> Bool {
        dbQueue.sync { flushPending() }
    }

    private func flushPending() -> Bool {
        flushDeadline?.cancel()
        flushDeadline = nil
        guard !writeBuffer.isEmpty else { return true }

        let succeeded = attempt {
            try openDatabaseIfNeeded()
            try execute("BEGIN IMMEDIATE;")
            do {
                try upsertPendingUsage()
                try execute("COMMIT;")
            } catch {
                // SQLite can roll back automatically for certain errors.
                if sqlite3_get_autocommit(db) == 0 {
                    try? execute("ROLLBACK;")
                }
                throw error
            }
            writeBuffer.removeAll(keepingCapacity: true)
            return true
        } ?? false

        lastFlushFailed = !succeeded
        if !succeeded { scheduleFlush() }
        return succeeded
    }

    private func upsertPendingUsage() throws {
        try withStatement("""
            INSERT INTO hourly_usage (timestamp_hour, bundle_id, app_name, app_path, bytes_in, bytes_out, is_system, is_traffic_relay)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(timestamp_hour, bundle_id) DO UPDATE SET
                bytes_in = bytes_in + MIN(excluded.bytes_in, 9223372036854775807 - bytes_in),
                bytes_out = bytes_out + MIN(excluded.bytes_out, 9223372036854775807 - bytes_out),
                app_name = CASE WHEN excluded.app_name != '' THEN excluded.app_name ELSE hourly_usage.app_name END,
                app_path = COALESCE(excluded.app_path, hourly_usage.app_path),
                is_system = MAX(hourly_usage.is_system, excluded.is_system),
                is_traffic_relay = MAX(hourly_usage.is_traffic_relay, excluded.is_traffic_relay);
            """) { statement in
            for (key, usage) in writeBuffer {
                try check(sqlite3_bind_int64(statement, 1, key.hour))
                try check(sqlite3_bind_text(statement, 2, key.bundleID, -1, Self.transient))
                try check(sqlite3_bind_text(statement, 3, usage.appName, -1, Self.transient))
                if let path = usage.appPath {
                    try check(sqlite3_bind_text(statement, 4, path, -1, Self.transient))
                } else {
                    try check(sqlite3_bind_null(statement, 4))
                }
                try check(sqlite3_bind_int64(statement, 5, usage.bytesIn))
                try check(sqlite3_bind_int64(statement, 6, usage.bytesOut))
                try check(sqlite3_bind_int(statement, 7, usage.isSystem ? 1 : 0))
                try check(sqlite3_bind_int(statement, 8, usage.isTrafficRelay ? 1 : 0))
                try check(sqlite3_step(statement), expecting: SQLITE_DONE)
                try check(sqlite3_reset(statement))
            }
        }
    }

    /// The dashboard reads both views of the same committed history in one queue operation.
    func fetchSnapshot(for interval: DateInterval, grouping: TimeGrouping) async -> Snapshot? {
        await withCheckedContinuation { continuation in
            dbQueue.async { [self] in
                // Let the scheduled retry handle a previous write failure.
                if !lastFlushFailed { _ = flushPending() }
                guard !lastFlushFailed else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: attempt {
                    try openDatabaseIfNeeded()
                    return Snapshot(
                        records: try queryUsage(from: interval.start, to: interval.end),
                        points: try queryTimeSeries(from: interval.start, to: interval.end, grouping: grouping)
                    )
                })
            }
        }
    }

    public func fetchUsage(from startDate: Date, to endDate: Date = Date()) -> [AppUsageRecord] {
        dbQueue.sync {
            guard flushPending() else { return [] }
            return attempt {
                try openDatabaseIfNeeded()
                return try queryUsage(from: startDate, to: endDate)
            } ?? []
        }
    }

    private func queryUsage(from startDate: Date, to endDate: Date) throws -> [AppUsageRecord] {
        var records = [AppUsageRecord]()
        var totalAllBytes = 0.0

        try withStatement("""
            SELECT bundle_id, app_name, app_path, SUM(bytes_in) AS total_in,
                SUM(bytes_out) AS total_out, MAX(is_system)
            FROM hourly_usage
            WHERE timestamp_hour >= ? AND timestamp_hour <= ? AND is_traffic_relay = 0
            GROUP BY bundle_id
            ORDER BY (total_in + total_out) DESC, bundle_id;
            """) { statement in
            try bindRange(statement, from: startDate, to: endDate)
            while try readRow(statement) {
                guard let bundleID = string(statement, at: 0),
                      let appName = string(statement, at: 1) else { continue }
                let bytesIn = UInt64(clamping: sqlite3_column_int64(statement, 3))
                let bytesOut = UInt64(clamping: sqlite3_column_int64(statement, 4))
                totalAllBytes += Double(bytesIn) + Double(bytesOut)
                records.append(AppUsageRecord(
                    id: bundleID,
                    bundleId: bundleID,
                    appName: appName,
                    appPath: string(statement, at: 2),
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    isSystemProcess: sqlite3_column_int(statement, 5) != 0
                ))
            }
        }
        if totalAllBytes > 0 {
            for index in records.indices {
                records[index].percentage = Double(records[index].totalBytes) / totalAllBytes
            }
        }
        return records
    }

    private func bindRange(_ statement: OpaquePointer, from startDate: Date, to endDate: Date) throws {
        try check(sqlite3_bind_int64(statement, 1, Int64(startDate.timeIntervalSince1970)))
        try check(sqlite3_bind_int64(statement, 2, Int64(endDate.timeIntervalSince1970)))
    }

    public func fetchTimeSeries(from startDate: Date, to endDate: Date = Date(), grouping: TimeGrouping) -> [ChartDataPoint] {
        dbQueue.sync {
            guard flushPending() else { return [] }
            return attempt {
                try openDatabaseIfNeeded()
                return try queryTimeSeries(from: startDate, to: endDate, grouping: grouping)
            } ?? []
        }
    }

    private func queryTimeSeries(from startDate: Date, to endDate: Date, grouping: TimeGrouping) throws -> [ChartDataPoint] {
        guard startDate <= endDate else { return [] }
        let calendar = Calendar.current
        let component: Calendar.Component = grouping == .hourly ? .hour : .day
        var buckets: [Date: (download: UInt64, upload: UInt64)] = [:]

        try withStatement("""
            SELECT timestamp_hour, SUM(bytes_in), SUM(bytes_out)
            FROM hourly_usage
            WHERE timestamp_hour >= ? AND timestamp_hour <= ? AND is_traffic_relay = 0
            GROUP BY timestamp_hour
            ORDER BY timestamp_hour;
            """) { statement in
            try bindRange(statement, from: startDate, to: endDate)
            while try readRow(statement) {
                let date = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0)))
                let bucket = calendar.dateInterval(of: component, for: date)?.start ?? date
                let download = UInt64(clamping: sqlite3_column_int64(statement, 1))
                let upload = UInt64(clamping: sqlite3_column_int64(statement, 2))
                let previous = buckets[bucket] ?? (0, 0)
                buckets[bucket] = (
                    previous.download + min(UInt64.max - previous.download, download),
                    previous.upload + min(UInt64.max - previous.upload, upload)
                )
            }
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(grouping == .hourly ? "j" : "MMMd")
        var date = calendar.dateInterval(of: component, for: startDate)?.start ?? startDate
        var results: [ChartDataPoint] = []
        while date <= endDate {
            let usage = buckets[date] ?? (0, 0)
            results.append(ChartDataPoint(
                date: date, label: formatter.string(from: date), bytesIn: usage.download, bytesOut: usage.upload
            ))
            guard let next = calendar.date(byAdding: component, value: 1, to: date), next > date else { break }
            date = next
        }
        return results
    }

    @discardableResult
    public func clearAllData() -> Bool {
        dbQueue.sync { deleteHistory(in: nil) }
    }

    @discardableResult
    public func deleteData(from startDate: Date, to endDate: Date) -> Bool {
        guard startDate < endDate else { return true }
        return dbQueue.sync { deleteHistory(in: DateInterval(start: startDate, end: endDate)) }
    }

    func deleteHistory(in interval: DateInterval?) async -> Bool {
        await withCheckedContinuation { continuation in
            dbQueue.async { [self] in
                let deleted: Bool = deleteHistory(in: interval)
                continuation.resume(returning: deleted)
            }
        }
    }

    private func deleteHistory(in interval: DateInterval?) -> Bool {
        attempt {
            try openDatabaseIfNeeded()
            if let interval {
                try withStatement("DELETE FROM hourly_usage WHERE timestamp_hour >= ? AND timestamp_hour < ?;") { statement in
                    try bindRange(statement, from: interval.start, to: interval.end)
                    try check(sqlite3_step(statement), expecting: SQLITE_DONE)
                }
                let start = Int64(interval.start.timeIntervalSince1970)
                let end = Int64(interval.end.timeIntervalSince1970)
                writeBuffer = writeBuffer.filter { key, _ in key.hour < start || key.hour >= end }
            } else {
                try execute("DELETE FROM hourly_usage;")
                writeBuffer.removeAll()
            }
            if writeBuffer.isEmpty {
                flushDeadline?.cancel()
                flushDeadline = nil
                lastFlushFailed = false
            }
            // Remove old WAL frames when other readers allow it.
            let checkpoint = sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
            if checkpoint != SQLITE_OK {
                Self.logger.notice("History deleted. WAL truncation returned \(checkpoint).")
            }
            return true
        } ?? false
    }
}
