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

/// Ultra-lightweight background collector that samples process-level network statistics via single-shot nettop snapshots.
public final class NetworkCollector: @unchecked Sendable {
    public static let shared = NetworkCollector()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.netcollect.networkcollector", qos: .utility)
    private var isRunning = false
    private var isUIVisibleState = false

    private var previousTotals: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var isBootstrapped = false
    private var lastSampleTime: Date = Date()

    private var peakInRate: Double = 0
    private var peakOutRate: Double = 0

    // Callback on data collection
    public var onDeltaReceived: (@Sendable (NetworkDeltaEvent) -> Void)?
    public var onBandwidthUpdated: (@Sendable (LiveBandwidth) -> Void)?

    public var pollingMode: PollingMode = .balanced {
        didSet {
            if isRunning && oldValue != pollingMode {
                restart()
            }
        }
    }

    private init() {}

    deinit {
        stop()
    }

    /// Adapts the collection frequency based on whether UI is actively visible or in background.
    public func setUIVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.isUIVisibleState != visible else { return }
            self.isUIVisibleState = visible

            if self.isRunning {
                if visible {
                    // Trigger immediate sample on UI open and switch to high-frequency timer
                    self.performSample()
                }
                self.startTimer()
            }
        }
    }

    /// Starts the background network collection timer.
    public func start() {
        queue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true
            self.startTimer()
        }
    }

    /// Stops the background collection.
    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            self.stopTimer()
            self.previousTotals.removeAll()
            self.isBootstrapped = false
        }
    }

    /// Restarts collection (e.g. after changing sampling rate).
    public func restart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.stopTimer()
            if self.isRunning {
                self.startTimer()
            }
        }
    }

    private var effectiveInterval: Double {
        if isUIVisibleState {
            return Double(pollingMode.intervalSeconds)
        } else {
            // When in background with no UI open, sample every 10 seconds to minimize CPU/battery wakeups
            return 10.0
        }
    }

    private func startTimer() {
        stopTimer()

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = effectiveInterval
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(200))
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

    /// Executes nettop snapshot using lightweight C posix_spawnp avoiding Foundation Process overhead.
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
        guard !data.isEmpty else { return }
        guard let output = String(data: data, encoding: .utf8) else { return }

        let now = Date()
        let elapsed = max(0.1, now.timeIntervalSince(lastSampleTime))
        self.lastSampleTime = now

        var currentIntervalBytesIn: UInt64 = 0
        var currentIntervalBytesOut: UInt64 = 0
        var activeProcessesInSample = 0
        var currentPidsInSample = Set<pid_t>()

        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.contains("bytes_in") else { continue }

            // CSV format: <name>.<pid>,<bytes_in>,<bytes_out>,
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }

            let procIdentifier = String(columns[0])
            guard let currentIn = UInt64(columns[1]),
                  let currentOut = UInt64(columns[2]) else { continue }

            guard let dotIndex = procIdentifier.lastIndex(of: ".") else { continue }
            let pidString = String(procIdentifier[procIdentifier.index(after: dotIndex)...])
            let rawName = String(procIdentifier[..<dotIndex])

            guard let pid = pid_t(pidString) else { continue }
            currentPidsInSample.insert(pid)

            if !isBootstrapped {
                // Initial bootstrap snapshot: record baseline cumulative totals from boot without recording deltas
                previousTotals[pid] = (currentIn, currentOut)
                continue
            }

            var deltaIn: UInt64 = 0
            var deltaOut: UInt64 = 0

            if let prev = previousTotals[pid] {
                // If process restarted or counter wrapped, delta is currentIn
                deltaIn = (currentIn >= prev.bytesIn) ? (currentIn - prev.bytesIn) : currentIn
                deltaOut = (currentOut >= prev.bytesOut) ? (currentOut - prev.bytesOut) : currentOut
            } else {
                // New process discovered since last snapshot: initialize baseline
                deltaIn = 0
                deltaOut = 0
            }

            previousTotals[pid] = (currentIn, currentOut)

            if deltaIn > 0 || deltaOut > 0 {
                activeProcessesInSample += 1
                currentIntervalBytesIn += deltaIn
                currentIntervalBytesOut += deltaOut

                let resolved = AppResolver.shared.resolve(pid: pid, rawName: rawName)

                // Record into SQLite
                DatabaseService.shared.recordUsage(
                    date: now,
                    bundleId: resolved.bundleId,
                    appName: resolved.displayName,
                    appPath: resolved.appPath,
                    bytesIn: deltaIn,
                    bytesOut: deltaOut,
                    isSystem: resolved.isSystemProcess
                )

                let event = NetworkDeltaEvent(
                    pid: pid,
                    rawName: rawName,
                    bytesIn: deltaIn,
                    bytesOut: deltaOut,
                    resolvedApp: resolved
                )
                self.onDeltaReceived?(event)
            }
        }

        // Clean up terminated PIDs from previous snapshot
        let knownPids = Set(previousTotals.keys)
        let deadPids = knownPids.subtracting(currentPidsInSample)
        for deadPid in deadPids {
            previousTotals.removeValue(forKey: deadPid)
            AppResolver.shared.invalidatePID(deadPid)
        }

        if !isBootstrapped {
            isBootstrapped = true
            return
        }

        // Calculate instantaneous bandwidth
        let inRate = Double(currentIntervalBytesIn) / elapsed
        let outRate = Double(currentIntervalBytesOut) / elapsed

        if inRate > peakInRate { peakInRate = inRate }
        if outRate > peakOutRate { peakOutRate = outRate }

        let bandwidth = LiveBandwidth(
            bytesInPerSecond: inRate,
            bytesOutPerSecond: outRate,
            peakInPerSecond: peakInRate,
            peakOutPerSecond: peakOutRate,
            activeProcessCount: activeProcessesInSample
        )

        self.onBandwidthUpdated?(bandwidth)
    }
}
