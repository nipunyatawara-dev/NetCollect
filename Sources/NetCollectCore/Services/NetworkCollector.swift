import Foundation
import Darwin
import Combine

/// Polling frequency modes.
public enum PollingMode: String, CaseIterable, Identifiable, Sendable {
    case eco = "Battery Saver (5s)"
    case balanced = "Balanced (3s)"
    case highPrecision = "High Precision (1s)"

    public var id: String { rawValue }

    public var intervalSeconds: Int {
        switch self {
        case .eco: return 5
        case .balanced: return 3
        case .highPrecision: return 1
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

        var activeProcessesInSample = 0

        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            lineBuffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else { continue }

            // Skip header line ",bytes_in,bytes_out,"
            if line.contains("bytes_in") {
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
