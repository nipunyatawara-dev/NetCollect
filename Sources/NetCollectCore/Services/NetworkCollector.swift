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

/// Ultra-lightweight background collector that streams process-level network statistics via nettop.
public final class NetworkCollector: @unchecked Sendable {
    public static let shared = NetworkCollector()

    private var process: Process?
    private var stdoutPipe: Pipe?
    private let queue = DispatchQueue(label: "com.netcollect.networkcollector", qos: .utility)
    private var isRunning = false

    private var lineBuffer = ""
    private var lastSampleTime: Date = Date()
    private var currentIntervalBytesIn: UInt64 = 0
    private var currentIntervalBytesOut: UInt64 = 0
    private var sampleHeadersSeen = 0

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

    private var peakInRate: Double = 0
    private var peakOutRate: Double = 0

    private init() {}

    deinit {
        stop()
    }

    /// Starts the background network collection stream.
    public func start() {
        queue.async { [weak self] in
            guard let self = self, !self.isRunning else { return }
            self.isRunning = true
            self.launchNettop()
        }
    }

    /// Stops the background collection stream.
    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isRunning = false
            self.terminateProcess()
        }
    }

    /// Restarts collection (e.g. after changing sampling rate).
    public func restart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.terminateProcess()
            if self.isRunning {
                self.launchNettop()
            }
        }
    }

    private func terminateProcess() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
    }

    private func launchNettop() {
        terminateProcess()

        sampleHeadersSeen = 0
        lineBuffer = ""
        currentIntervalBytesIn = 0
        currentIntervalBytesOut = 0

        let pipe = Pipe()
        self.stdoutPipe = pipe

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P: Per-process collapse
        // -L 0: Infinite samples in raw logging mode
        // -J bytes_in,bytes_out: Only extract bytes in and bytes out
        // -d: Delta mode (gives delta counts per interval)
        // -n: No reverse DNS lookup (saves CPU and network)
        // -c: Less intensive CPU usage
        // -s <interval>: Polling interval
        proc.arguments = [
            "-P",
            "-L", "0",
            "-J", "bytes_in,bytes_out",
            "-d",
            "-n",
            "-c",
            "-s", "\(pollingMode.intervalSeconds)"
        ]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self = self else { return }
            self.queue.async {
                self.processIncomingData(data)
            }
        }

        proc.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            self.queue.async { [weak self] in
                guard let strongSelf = self, strongSelf.isRunning else { return }
                // If it died unexpectedly, wait 2s and restart
                strongSelf.queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    if let s = self, s.isRunning {
                        s.launchNettop()
                    }
                }
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.lastSampleTime = Date()
        } catch {
            print("Failed to run nettop: \(error)")
        }
    }

    private func processIncomingData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        lineBuffer += chunk

        guard let lastNewlineIndex = lineBuffer.lastIndex(of: "\n") else { return }
        let completeChunk = lineBuffer[..<lastNewlineIndex]
        lineBuffer = String(lineBuffer[lineBuffer.index(after: lastNewlineIndex)...])

        var activeProcessesInSample = 0

        for rawLine in completeChunk.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            // Header line ",bytes_in,bytes_out," marks sample boundaries
            if line.contains("bytes_in") {
                sampleHeadersSeen += 1

                if sampleHeadersSeen == 1 {
                    // Start of initial bootstrap sample (cumulative totals from nettop)
                    lastSampleTime = Date()
                    currentIntervalBytesIn = 0
                    currentIntervalBytesOut = 0
                    activeProcessesInSample = 0
                    continue
                } else if sampleHeadersSeen == 2 {
                    // End of bootstrap sample. Beginning of real delta streaming.
                    lastSampleTime = Date()
                    currentIntervalBytesIn = 0
                    currentIntervalBytesOut = 0
                    activeProcessesInSample = 0
                    continue
                }

                // Sample boundary finished: calculate instantaneous bandwidth
                let now = Date()
                let elapsed = max(0.1, now.timeIntervalSince(lastSampleTime))
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

                self.currentIntervalBytesIn = 0
                self.currentIntervalBytesOut = 0
                self.lastSampleTime = now
                activeProcessesInSample = 0
                continue
            }

            // If we are still in the initial bootstrap sample (sampleHeadersSeen < 2),
            // nettop outputs cumulative process totals from boot. Do NOT treat as delta.
            guard sampleHeadersSeen >= 2 else { continue }

            // CSV format: <name>.<pid>,<bytes_in>,<bytes_out>,
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }

            let procIdentifier = String(columns[0])
            guard let bytesIn = UInt64(columns[1]),
                  let bytesOut = UInt64(columns[2]) else { continue }

            // Only process rows with non-zero traffic
            if bytesIn > 0 || bytesOut > 0 {
                activeProcessesInSample += 1
                currentIntervalBytesIn += bytesIn
                currentIntervalBytesOut += bytesOut

                // Parse PID: procIdentifier is typically e.g. "Spotify.24404" or "Signal Helper (.24293"
                if let dotIndex = procIdentifier.lastIndex(of: ".") {
                    let pidString = String(procIdentifier[procIdentifier.index(after: dotIndex)...])
                    let rawName = String(procIdentifier[..<dotIndex])

                    if let pid = pid_t(pidString) {
                        let resolved = AppResolver.shared.resolve(pid: pid, rawName: rawName)

                        // Record into SQLite
                        DatabaseService.shared.recordUsage(
                            bundleId: resolved.bundleId,
                            appName: resolved.displayName,
                            appPath: resolved.appPath,
                            bytesIn: bytesIn,
                            bytesOut: bytesOut,
                            isSystem: resolved.isSystemProcess
                        )

                        let event = NetworkDeltaEvent(
                            pid: pid,
                            rawName: rawName,
                            bytesIn: bytesIn,
                            bytesOut: bytesOut,
                            resolvedApp: resolved
                        )
                        self.onDeltaReceived?(event)
                    }
                }
            }
        }
    }
}
