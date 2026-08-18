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

    private func startTimer() {
        stopTimer()

        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        let interval = Double(pollingMode.intervalSeconds)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
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

    private func performSample() {
        let pipe = Pipe()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P: Per-process collapse
        // -L 1: Single instantaneous snapshot (takes ~20ms and exits immediately, avoiding background thread spinning)
        // -J bytes_in,bytes_out: Only extract bytes in and bytes out
        // -n: No reverse DNS lookup (saves CPU and network)
        proc.arguments = [
            "-P",
            "-L", "1",
            "-J", "bytes_in,bytes_out",
            "-n"
        ]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            processSnapshotData(data)
        } catch {
            print("Failed to run nettop snapshot: \(error)")
        }
    }

    private func processSnapshotData(_ data: Data) {
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
