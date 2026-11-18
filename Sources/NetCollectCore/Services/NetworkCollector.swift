import Foundation
import Darwin
import os

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

        var current: [String: StoredCounters] = [:]
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
            current[snapshot.name] = StoredCounters(
                bytesIn: snapshot.bytesIn,
                bytesOut: snapshot.bytesOut,
                sampleUptime: sampleUptime
            )
        }

        counters = current
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
    private var lastBandwidthPublishUptime: TimeInterval?
    private var pendingInRateTotal: Double = 0
    private var pendingOutRateTotal: Double = 0
    private var pendingRateSampleCount = 0

    private static let logger = Logger(subsystem: "com.netcollect.app", category: "collector")
    private var sampleFailed = false
    private var onBandwidthUpdated: (@Sendable (LiveBandwidth) -> Void)?
    private var pollingMode: PollingMode = .balanced

    public func setBandwidthHandler(_ handler: (@Sendable (LiveBandwidth) -> Void)?) {
        queue.async { [self] in onBandwidthUpdated = handler }
    }

    public func setPollingMode(_ mode: PollingMode) {
        queue.async { [self] in
            guard pollingMode != mode else { return }
            pollingMode = mode
            lastBandwidthPublishUptime = nil
        }
    }

    public init(databaseService: DatabaseService = .shared) {
        self.databaseService = databaseService
    }

    deinit {
        timer?.cancel()
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

    /// Stops scheduling samples, drains the active sample, then persists its writes.
    public func stopAndFlush(completion: (@Sendable (Bool) -> Void)? = nil) {
        queue.async { [self] in
            isRunning = false
            stopTimer()
            snapshotAccumulator.reset()
            interfaceAccumulator.reset()
            isBootstrapped = false
            for pid in processIdentityTokens.keys {
                AppResolver.shared.invalidatePID(pid)
            }
            processIdentityTokens.removeAll()
            processLastSeen.removeAll()
            lastBandwidthPublishUptime = nil
            pendingInRateTotal = 0
            pendingOutRateTotal = 0
            pendingRateSampleCount = 0
            collectionInterval = 1
            consecutiveQuietSamples = 0
            let saved = databaseService.flushSync()
            completion?(saved)
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

    /// Uses short-lived snapshots with a deadline so a stalled child cannot stop
    /// future sampling or hold up sleep and termination indefinitely.
    private func performSample() {
        guard let data = readNettop(), processSnapshotData(data) else {
            if !sampleFailed {
                Self.logger.error("Unable to read network usage from nettop.")
                sampleFailed = true
            }
            return
        }
        sampleFailed = false
    }

    private func readNettop() -> Data? {
        var pipeFds: [Int32] = [0, 0]
        guard pipe(&pipeFds) == 0 else { return nil }
        let input = pipeFds[0]
        let output = pipeFds[1]
        defer { close(input) }

        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else {
            close(output)
            return nil
        }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawnattr_init(&attributes) == 0 else {
            close(output)
            return nil
        }
        defer { posix_spawnattr_destroy(&attributes) }

        let executable = "/usr/bin/nettop"
        let arguments = [executable, "-P", "-L", "1", "-J", "bytes_in,bytes_out", "-n",
                         "-t", "wifi", "-t", "wired", "-t", "expensive"]
        var argv = arguments.map { strdup($0) }
        defer { for argument in argv { free(argument) } }
        guard !argv.contains(nil),
              fcntl(input, F_SETFD, FD_CLOEXEC) == 0,
              fcntl(output, F_SETFD, FD_CLOEXEC) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawn_file_actions_adddup2(&fileActions, output, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0) == 0 else {
            close(output)
            return nil
        }

        argv.append(nil)
        var environment: [UnsafeMutablePointer<CChar>?] = [nil]
        var pid: pid_t = 0
        let status = posix_spawn(&pid, executable, &fileActions, &attributes, &argv, &environment)
        close(output)
        guard status == 0 else { return nil }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        var descriptor = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
        while ProcessInfo.processInfo.systemUptime < deadline {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            let ready = poll(&descriptor, 1, Int32(max(0, remaining * 1000).rounded(.up)))
            if ready < 0 && errno == EINTR { continue }
            guard ready > 0 else { break }
            let count = read(input, &buffer, buffer.count)
            if count < 0 && errno == EINTR { continue }
            if count == 0 {
                var status: Int32 = 0
                while ProcessInfo.processInfo.systemUptime < deadline {
                    let reaped = waitpid(pid, &status, WNOHANG)
                    if reaped == pid { return status == 0 ? data : nil }
                    if reaped < 0 && errno != EINTR { return nil }
                    usleep(5_000)
                }
                break
            }
            guard count > 0, data.count + count <= 4 * 1024 * 1024 else { break }
            data.append(buffer, count: count)
        }

        kill(pid, SIGKILL)
        while waitpid(pid, nil, 0) < 0 && errno == EINTR {}
        return nil
    }

    private func processSnapshotData(_ data: Data) -> Bool {
        guard let output = String(data: data, encoding: .utf8),
              let header = output.split(whereSeparator: \.isNewline).first,
              header == ",bytes_in,bytes_out," else { return false }

        let now = Date()
        let uptime = ProcessInfo.processInfo.systemUptime
        var processInRate: Double = 0
        var processOutRate: Double = 0
        var activeProcesses = 0
        var snapshots: [NetworkProcessSnapshot] = []

        for rawLine in output.split(whereSeparator: \.isNewline).dropFirst() {
            let line = rawLine.hasSuffix(",") ? rawLine.dropLast() : rawLine
            // Process names can contain commas. The numeric columns are at the end.
            guard let outSeparator = line.lastIndex(of: ","),
                  let inSeparator = line[..<outSeparator].lastIndex(of: ","),
                  let currentIn = UInt64(line[line.index(after: inSeparator)..<outSeparator]),
                  let currentOut = UInt64(line[line.index(after: outSeparator)...]) else { continue }

            let processIdentifier = line[..<inSeparator]
            guard let dotIndex = processIdentifier.lastIndex(of: "."),
                  let pid = pid_t(processIdentifier[processIdentifier.index(after: dotIndex)...]),
                  pid >= 0 else { continue }

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
            return true
        }

        let inRate = interfaceRate?.bytesInPerSecond ?? processInRate
        let outRate = interfaceRate?.bytesOutPerSecond ?? processOutRate
        updateCollectionCadence(isTrafficActive: inRate + outRate >= 128 * 1024)

        peakInRate = max(peakInRate, inRate)
        peakOutRate = max(peakOutRate, outRate)
        pendingInRateTotal += inRate
        pendingOutRateTotal += outRate
        pendingRateSampleCount += 1

        if let lastBandwidthPublishUptime,
           uptime - lastBandwidthPublishUptime < Double(pollingMode.intervalSeconds) {
            return true
        }
        lastBandwidthPublishUptime = uptime
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
        return true
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
        // getifaddrs exposes 32-bit byte counters on macOS. NET_RT_IFLIST2
        // supplies 64-bit counters, so fast transfers do not wrap at 4 GiB.
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var size = 0
        guard sysctl(&mib, 6, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        var buffer = Data(count: size)
        let result = buffer.withUnsafeMutableBytes { bytes in
            sysctl(&mib, 6, bytes.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { return [] }

        return buffer.withUnsafeBytes { bytes in
            var snapshots: [NetworkInterfaceSnapshot] = []
            var offset = 0
            while size - offset >= 4 {
                let length = Int(bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self))
                guard length >= 4, length <= size - offset else { break }
                defer { offset += length }
                guard bytes[offset + 2] == UInt8(RTM_VERSION),
                      bytes[offset + 3] == UInt8(RTM_IFINFO2),
                      length >= MemoryLayout<if_msghdr2>.size else { continue }
                let interface = bytes.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                guard interface.ifm_flags & IFF_UP != 0 else { continue }
                var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                guard if_indextoname(UInt32(interface.ifm_index), &nameBuffer) != nil else { continue }
                let name = nameBuffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                guard name.hasPrefix("en") || name.hasPrefix("pdp_ip") else { continue }
                snapshots.append(NetworkInterfaceSnapshot(
                    name: name,
                    bytesIn: interface.ifm_data.ifi_ibytes,
                    bytesOut: interface.ifm_data.ifi_obytes
                ))
            }
            return snapshots
        }
    }
}
