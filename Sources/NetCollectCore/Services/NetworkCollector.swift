import Foundation
import Darwin
import Combine

/// Polling frequency modes for live bandwidth sampling.
public enum PollingMode: String, CaseIterable, Identifiable, Sendable {
    case oneSecond = "1 second"
    case twoSeconds = "2 seconds"
    case balanced = "3 seconds (Default)"
    case eco = "5 seconds"
    case tenSeconds = "10 seconds"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var intervalSeconds: Int {
        switch self {
        case .oneSecond: return 1
        case .twoSeconds: return 2
        case .balanced: return 3
        case .eco: return 5
        case .tenSeconds: return 10
        }
    }

    public static func from(storedValue: String) -> PollingMode {
        switch storedValue {
        case "High Precision (1s)", "1s", "1 second", "oneSecond":
            return .oneSecond
        case "2s", "2 seconds", "twoSeconds":
            return .twoSeconds
        case "Balanced (3s)", "3s", "3 seconds", "3 seconds (Default)", "balanced", "threeSeconds":
            return .balanced
        case "Battery Saver (5s)", "5s", "5 seconds", "eco", "fiveSeconds":
            return .eco
        case "10s", "10 seconds", "tenSeconds":
            return .tenSeconds
        default:
            return PollingMode(rawValue: storedValue) ?? .balanced
        }
    }
}

/// Real-time event for network usage updates.
public struct NetworkDeltaEvent: Sendable {
    public let pid: pid_t
    public let rawName: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let resolvedApp: ResolvedAppInfo
}

/// A cumulative per-process counter returned by one `nettop` snapshot.
public struct NetworkProcessSnapshot: Sendable {
    public let pid: pid_t
    public let rawName: String
    public let processStartIdentifier: UInt64
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(
        pid: pid_t,
        rawName: String,
        processStartIdentifier: UInt64,
        bytesIn: UInt64,
        bytesOut: UInt64
    ) {
        self.pid = pid
        self.rawName = rawName
        self.processStartIdentifier = processStartIdentifier
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Bytes transferred since the preceding cumulative snapshot for the same process instance.
public struct NetworkProcessDelta: Sendable {
    public let snapshot: NetworkProcessSnapshot
    public let bytesIn: UInt64
    public let bytesOut: UInt64
    public let observationInterval: TimeInterval
}

/// Converts cumulative `nettop` counters into deltas without ever treating a lifetime total as new traffic.
public struct NetworkSnapshotAccumulator: Sendable {
    private struct ProcessIdentity: Hashable, Sendable {
        let pid: pid_t
        let rawName: String
        let processStartIdentifier: UInt64
    }

    private struct StoredCounters: Sendable {
        let identity: ProcessIdentity
        let bytesIn: UInt64
        let bytesOut: UInt64
        let lastSeen: Date
    }

    private var counters: [pid_t: StoredCounters] = [:]
    private let retentionInterval: TimeInterval
    private var previousSnapshotTimestamp: Date?

    public init(retentionInterval: TimeInterval = 60 * 60) {
        self.retentionInterval = retentionInterval
    }

    public mutating func reset() {
        counters.removeAll(keepingCapacity: false)
        previousSnapshotTimestamp = nil
    }

    public mutating func consume(
        _ snapshots: [NetworkProcessSnapshot],
        at timestamp: Date = Date()
    ) -> [NetworkProcessDelta] {
        counters = counters.filter { timestamp.timeIntervalSince($0.value.lastSeen) <= retentionInterval }

        var deltas: [NetworkProcessDelta] = []
        deltas.reserveCapacity(snapshots.count)

        for snapshot in snapshots {
            let identity = ProcessIdentity(
                pid: snapshot.pid,
                rawName: snapshot.rawName,
                processStartIdentifier: snapshot.processStartIdentifier
            )

            let bytesIn: UInt64
            let bytesOut: UInt64
            let observationInterval: TimeInterval
            let previous = counters[snapshot.pid]
            if let previous,
               previous.identity == identity,
               snapshot.bytesIn >= previous.bytesIn,
               snapshot.bytesOut >= previous.bytesOut {
                bytesIn = snapshot.bytesIn - previous.bytesIn
                bytesOut = snapshot.bytesOut - previous.bytesOut
                observationInterval = max(0.1, timestamp.timeIntervalSince(previous.lastSeen))
            } else if (previous == nil || previous?.identity != identity),
                      processStartedSincePreviousSnapshot(snapshot, currentTimestamp: timestamp) {
                // All counters from a process launched after the previous snapshot
                // belong to this interval and are safe to count in full.
                bytesIn = snapshot.bytesIn
                bytesOut = snapshot.bytesOut
                let processStart = Date(
                    timeIntervalSince1970: Double(snapshot.processStartIdentifier) / 1_000_000
                )
                observationInterval = max(0.1, timestamp.timeIntervalSince(processStart))
            } else {
                bytesIn = 0
                bytesOut = 0
                observationInterval = 0.1
            }

            if bytesIn > 0 || bytesOut > 0 {
                deltas.append(NetworkProcessDelta(
                    snapshot: snapshot,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    observationInterval: observationInterval
                ))
            }

            // Store the current cumulative values as the baseline for the next snapshot.
            counters[snapshot.pid] = StoredCounters(
                identity: identity,
                bytesIn: snapshot.bytesIn,
                bytesOut: snapshot.bytesOut,
                lastSeen: timestamp
            )
        }

        previousSnapshotTimestamp = timestamp
        return deltas
    }

    private func processStartedSincePreviousSnapshot(
        _ snapshot: NetworkProcessSnapshot,
        currentTimestamp: Date
    ) -> Bool {
        guard let previousSnapshotTimestamp,
              snapshot.processStartIdentifier > 0 else { return false }

        let processStart = Date(
            timeIntervalSince1970: Double(snapshot.processStartIdentifier) / 1_000_000
        )
        // Allow for the short interval between nettop reading the kernel counters
        // and the snapshot being timestamped in this process.
        return processStart >= previousSnapshotTimestamp.addingTimeInterval(-0.5)
            && processStart <= currentTimestamp
    }
}

public struct NetworkInterfaceSnapshot: Sendable {
    public let name: String
    public let bytesIn: UInt64
    public let bytesOut: UInt64

    public init(name: String, bytesIn: UInt64, bytesOut: UInt64) {
        self.name = name
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

public struct NetworkInterfaceRate: Sendable {
    public let bytesInPerSecond: Double
    public let bytesOutPerSecond: Double
}

/// Produces global live throughput from physical interface counters without VPN duplication.
public struct NetworkInterfaceAccumulator: Sendable {
    private struct StoredCounters: Sendable {
        let bytesIn: UInt64
        let bytesOut: UInt64
        let sampleUptime: TimeInterval
    }

    private var counters: [String: StoredCounters] = [:]

    public init() {}

    public mutating func reset() {
        counters.removeAll(keepingCapacity: false)
    }

    public mutating func consume(
        _ snapshots: [NetworkInterfaceSnapshot],
        atUptime sampleUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> NetworkInterfaceRate? {
        var bytesInPerSecond: Double = 0
        var bytesOutPerSecond: Double = 0
        var comparedAnInterface = false

        for snapshot in snapshots {
            if let previous = counters[snapshot.name],
               snapshot.bytesIn >= previous.bytesIn,
               snapshot.bytesOut >= previous.bytesOut {
                let elapsed = max(0.1, sampleUptime - previous.sampleUptime)
                bytesInPerSecond += Double(snapshot.bytesIn - previous.bytesIn) / elapsed
                bytesOutPerSecond += Double(snapshot.bytesOut - previous.bytesOut) / elapsed
                comparedAnInterface = true
            }

            // New, reset, or wrapped interface counters establish a fresh baseline.
            counters[snapshot.name] = StoredCounters(
                bytesIn: snapshot.bytesIn,
                bytesOut: snapshot.bytesOut,
                sampleUptime: sampleUptime
            )
        }

        guard comparedAnInterface else { return nil }
        return NetworkInterfaceRate(
            bytesInPerSecond: bytesInPerSecond,
            bytesOutPerSecond: bytesOutPerSecond
        )
    }
}

/// Ultra-lightweight background collector that samples process-level network statistics via short-lived nettop snapshots.
public final class NetworkCollector: @unchecked Sendable {
    public static let shared = NetworkCollector()

    private let databaseService: DatabaseService
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.netcollect.networkcollector", qos: .utility)
    private var isRunning = false
    private var isUIVisibleState = false

    private var snapshotAccumulator = NetworkSnapshotAccumulator()
    private var interfaceAccumulator = NetworkInterfaceAccumulator()
    private var isBootstrapped = false
    private var processIdentityTokens: [pid_t: String] = [:]
    private var processLastSeen: [pid_t: Date] = [:]
    private var collectionInterval: Double = 1.0
    private var consecutiveQuietSamples = 0

    private var peakInRate: Double = 0
    private var peakOutRate: Double = 0
    private var lastBandwidthPublishDate: Date?
    private var pendingInRateTotal: Double = 0
    private var pendingOutRateTotal: Double = 0
    private var pendingRateSampleCount = 0

    public var onDeltaReceived: (@Sendable (NetworkDeltaEvent) -> Void)?
    public var onBandwidthUpdated: (@Sendable (LiveBandwidth) -> Void)?

    public var pollingMode: PollingMode = .balanced {
        didSet {
            if isRunning && oldValue != pollingMode {
                restart()
            }
        }
    }

    public init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }

    deinit {
        stop()
    }

    public func setUIVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self, self.isUIVisibleState != visible else { return }
            self.isUIVisibleState = visible

            if self.isRunning {
                if visible {
                    self.performSample()
                }
                self.startTimer()
            }
        }
    }

    public func start() {
        queue.async { [weak self] in
            guard let self, !self.isRunning else { return }
            self.isRunning = true
            self.performSample()
            self.startTimer()
        }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            self.stopTimer()
            self.snapshotAccumulator.reset()
            self.interfaceAccumulator.reset()
            self.isBootstrapped = false
            self.processIdentityTokens.removeAll()
            self.processLastSeen.removeAll()
            self.lastBandwidthPublishDate = nil
            self.pendingInRateTotal = 0
            self.pendingOutRateTotal = 0
            self.pendingRateSampleCount = 0
            self.collectionInterval = 1.0
            self.consecutiveQuietSamples = 0
        }
    }

    public func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            if self.isRunning {
                self.lastBandwidthPublishDate = nil
                self.pendingInRateTotal = 0
                self.pendingOutRateTotal = 0
                self.pendingRateSampleCount = 0
                self.performSample()
                self.startTimer()
            }
        }
    }

    private func startTimer() {
        stopTimer()

        // Accounting is independent of live-meter publication. Sampling speeds
        // up only while traffic is active so short-lived transfers are retained
        // without paying the faster cadence continuously.
        let interval = collectionInterval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(50)
        )
        timer.setEventHandler { [weak self] in
            self?.performSample()
        }
        timer.resume()
        self.timer = timer
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    /// Uses a short-lived snapshot because continuous nettop consumes an entire CPU core on macOS 26.
    private func performSample() {
        var pipeFds: [Int32] = [0, 0]
        guard pipe(&pipeFds) == 0 else { return }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, pipeFds[1], STDOUT_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, pipeFds[0])

        let devNull = open("/dev/null", O_WRONLY)
        if devNull >= 0 {
            posix_spawn_file_actions_adddup2(&fileActions, devNull, STDERR_FILENO)
        }

        let args: [UnsafeMutablePointer<CChar>?] = [
            strdup("nettop"),
            strdup("-P"),
            strdup("-L"),
            strdup("1"),
            strdup("-J"),
            strdup("bytes_in,bytes_out"),
            strdup("-n"),
            strdup("-t"),
            strdup("wifi"),
            strdup("-t"),
            strdup("wired"),
            strdup("-t"),
            strdup("expensive"),
            nil
        ]

        var pid: pid_t = 0
        let spawnStatus = posix_spawnp(&pid, "/usr/bin/nettop", &fileActions, nil, args, nil)
        posix_spawn_file_actions_destroy(&fileActions)
        close(pipeFds[1])
        if devNull >= 0 { close(devNull) }

        for arg in args where arg != nil {
            free(arg)
        }

        guard spawnStatus == 0 else {
            close(pipeFds[0])
            return
        }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let bytesRead = read(pipeFds[0], &buffer, buffer.count)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }
        close(pipeFds[0])

        var exitStatus: Int32 = 0
        waitpid(pid, &exitStatus, 0)

        processSnapshotData(data)
    }

    private func processSnapshotData(_ data: Data) {
        guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else { return }

        let now = Date()
        var processInRate: Double = 0
        var processOutRate: Double = 0
        var activeProcesses = 0
        var snapshots: [NetworkProcessSnapshot] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.contains("bytes_in") else { continue }

            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3,
                  let currentIn = UInt64(columns[1]),
                  let currentOut = UInt64(columns[2]) else { continue }

            let processIdentifier = String(columns[0])
            guard let dotIndex = processIdentifier.lastIndex(of: "."),
                  let pid = pid_t(processIdentifier[processIdentifier.index(after: dotIndex)...]) else { continue }

            let rawName = String(processIdentifier[..<dotIndex])
            let processStartIdentifier = processStartIdentifier(for: pid)
            snapshots.append(NetworkProcessSnapshot(
                pid: pid,
                rawName: rawName,
                processStartIdentifier: processStartIdentifier,
                bytesIn: currentIn,
                bytesOut: currentOut
            ))
            processLastSeen[pid] = now

            let identityToken = "\(processStartIdentifier)|\(rawName)"
            if let previousToken = processIdentityTokens[pid], previousToken != identityToken {
                AppResolver.shared.invalidatePID(pid)
            }
            processIdentityTokens[pid] = identityToken
        }

        let deltas = snapshotAccumulator.consume(snapshots, at: now)

        for delta in deltas {
            let pid = delta.snapshot.pid
            let rawName = delta.snapshot.rawName
            let deltaIn = delta.bytesIn
            let deltaOut = delta.bytesOut

            let resolved = AppResolver.shared.resolve(pid: pid, rawName: rawName)
            if !resolved.isTrafficRelay {
                activeProcesses += 1
                processInRate += Double(deltaIn) / delta.observationInterval
                processOutRate += Double(deltaOut) / delta.observationInterval
            }

            databaseService.recordUsage(
                date: now,
                bundleId: resolved.bundleId,
                appName: resolved.displayName,
                appPath: resolved.appPath,
                bytesIn: deltaIn,
                bytesOut: deltaOut,
                isSystem: resolved.isSystemProcess,
                isTrafficRelay: resolved.isTrafficRelay
            )

            onDeltaReceived?(NetworkDeltaEvent(
                pid: pid,
                rawName: rawName,
                bytesIn: deltaIn,
                bytesOut: deltaOut,
                resolvedApp: resolved
            ))
        }

        let resolverRetention: TimeInterval = 60 * 60
        let expiredPIDs = processLastSeen.compactMap { pid, lastSeen in
            now.timeIntervalSince(lastSeen) > resolverRetention ? pid : nil
        }
        for pid in expiredPIDs {
            processLastSeen.removeValue(forKey: pid)
            processIdentityTokens.removeValue(forKey: pid)
            AppResolver.shared.invalidatePID(pid)
        }

        let interfaceRate = interfaceAccumulator.consume(readExternalInterfaceSnapshots())

        guard isBootstrapped else {
            isBootstrapped = true
            return
        }

        let inRate = interfaceRate?.bytesInPerSecond ?? processInRate
        let outRate = interfaceRate?.bytesOutPerSecond ?? processOutRate
        updateCollectionCadence(isTrafficActive: inRate + outRate >= 128 * 1024)

        peakInRate = max(peakInRate, inRate)
        peakOutRate = max(peakOutRate, outRate)
        pendingInRateTotal += inRate
        pendingOutRateTotal += outRate
        pendingRateSampleCount += 1

        if let lastBandwidthPublishDate,
           now.timeIntervalSince(lastBandwidthPublishDate) < Double(pollingMode.intervalSeconds) {
            return
        }
        lastBandwidthPublishDate = now
        let sampleCount = max(1, pendingRateSampleCount)
        let publishedInRate = pendingInRateTotal / Double(sampleCount)
        let publishedOutRate = pendingOutRateTotal / Double(sampleCount)
        pendingInRateTotal = 0
        pendingOutRateTotal = 0
        pendingRateSampleCount = 0

        onBandwidthUpdated?(LiveBandwidth(
            bytesInPerSecond: publishedInRate,
            bytesOutPerSecond: publishedOutRate,
            peakInPerSecond: peakInRate,
            peakOutPerSecond: peakOutRate,
            activeProcessCount: activeProcesses
        ))
    }

    private func processStartIdentifier(for pid: pid_t) -> UInt64 {
        var info = proc_bsdinfo()
        let expectedSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, pointer, expectedSize)
        }
        guard result == expectedSize else { return 0 }
        return info.pbi_start_tvsec &* 1_000_000 &+ info.pbi_start_tvusec
    }

    private func updateCollectionCadence(isTrafficActive: Bool) {
        let desiredInterval: Double
        if isTrafficActive {
            consecutiveQuietSamples = 0
            desiredInterval = 0.5
        } else {
            consecutiveQuietSamples += 1
            desiredInterval = consecutiveQuietSamples >= 4 ? 1.0 : collectionInterval
        }

        guard desiredInterval != collectionInterval else { return }
        collectionInterval = desiredInterval
        if isRunning {
            startTimer()
        }
    }

    private func readExternalInterfaceSnapshots() -> [NetworkInterfaceSnapshot] {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
        defer { freeifaddrs(firstAddress) }

        var snapshots: [NetworkInterfaceSnapshot] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let interface = current.pointee
            cursor = interface.ifa_next

            guard let address = interface.ifa_addr,
                  Int32(address.pointee.sa_family) == AF_LINK,
                  interface.ifa_flags & UInt32(IFF_UP) != 0,
                  let dataPointer = interface.ifa_data else { continue }

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }

            let statistics = dataPointer.assumingMemoryBound(to: if_data.self).pointee
            snapshots.append(NetworkInterfaceSnapshot(
                name: name,
                bytesIn: UInt64(statistics.ifi_ibytes),
                bytesOut: UInt64(statistics.ifi_obytes)
            ))
        }
        return snapshots
    }
}
