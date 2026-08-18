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
    private let queue = DispatchQueue(label: "com.netcollect.networkcollector", qos: .utility)
    private var isRunning = false
    private var isUIVisibleState = false

    private var lineBuffer = ""
    private var lastSampleTime: Date = Date()
    private var currentIntervalBytesIn: UInt64 = 0
    private var currentIntervalBytesOut: UInt64 = 0
    private var activeProcessesInSample = 0

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

    /// Adapts collection frequency based on whether UI is visible or in background.
    public func setUIVisible(_ visible: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard self.isUIVisibleState != visible else { return }
            self.isUIVisibleState = visible

            if self.isRunning {
                self.launchNettop()
            }
        }
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

    /// Restarts collection.
    public func restart() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.terminateProcess()
            if self.isRunning {
                self.launchNettop()
            }
        }
    }

    private var effectiveInterval: Int {
        if isUIVisibleState {
            return pollingMode.intervalSeconds
        } else {
            // When running in background with no UI open, sample every 10 seconds to save power
            return 10
        }
    }

    private var sampleBlockCount = 0

    private var readSource: DispatchSourceRead?
    private var masterFd: Int32 = -1
    private var slaveFd: Int32 = -1
    private var launchGeneration: UInt64 = 0

    private func terminateProcess() {
        // Invalidate termination handlers from every older nettop instance. A
        // deliberate restart must not let the old process restart us again later.
        launchGeneration &+= 1
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        if let src = readSource {
            src.cancel()
            readSource = nil
        }
        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        if slaveFd >= 0 {
            close(slaveFd)
            slaveFd = -1
        }
        lineBuffer = ""
        sampleBlockCount = 0
        currentIntervalBytesIn = 0
        currentIntervalBytesOut = 0
        activeProcessesInSample = 0
    }

    private func launchNettop() {
        terminateProcess()

        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            print("Failed to open PTY for nettop")
            return
        }
        self.masterFd = master
        self.slaveFd = slave

        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        // -P: Per-process collapse
        // -L 0: Continuous delta streaming
        // -J bytes_in,bytes_out: Only extract bytes in and bytes out
        // -d: Exact kernel delta mode (accurately captures closed and open sockets)
        // -n: No reverse DNS lookup (saves CPU and bandwidth)
        // -c: Low CPU usage
        // -t wifi -t wired -t expensive: ONLY monitor real network interfaces (excludes high-traffic local 127.0.0.1 IPC)
        // -s <interval>: Polling interval
        proc.arguments = [
            "-P",
            "-L", "0",
            "-J", "bytes_in,bytes_out",
            "-d",
            "-n",
            "-c",
            "-t", "wifi",
            "-t", "wired",
            "-t", "expensive",
            "-s", "\(effectiveInterval)"
        ]
        proc.standardOutput = slaveHandle
        proc.standardError = FileHandle.nullDevice

        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: self.queue)
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let bytesRead = read(master, &buffer, buffer.count)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                self.processIncomingData(data)
            }
        }
        source.resume()
        self.readSource = source

        let generation = launchGeneration
        let processIdentifier = ObjectIdentifier(proc)
        proc.terminationHandler = { [weak self] _ in
            guard let self = self else { return }
            self.queue.async { [weak self] in
                guard let strongSelf = self,
                      strongSelf.isRunning,
                      strongSelf.launchGeneration == generation,
                      strongSelf.process.map(ObjectIdentifier.init) == processIdentifier else { return }
                strongSelf.queue.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    guard let s = self,
                          s.isRunning,
                          s.launchGeneration == generation,
                          s.process.map(ObjectIdentifier.init) == processIdentifier else { return }
                    s.launchNettop()
                }
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.lastSampleTime = Date()
            self.sampleBlockCount = 0
        } catch {
            print("Failed to run nettop: \(error)")
        }
    }

    private func processIncomingData(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        // A PTY emits CRLF. Swift treats CRLF as a single grapheme, so looking
        // for a standalone "\n" in the unnormalized String never finds a line.
        lineBuffer += chunk
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        while let newlineIndex = lineBuffer.firstIndex(of: "\n") {
            let line = String(lineBuffer[..<newlineIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            lineBuffer.removeSubrange(...newlineIndex)

            guard !line.isEmpty else { continue }

            // Sample boundary indicator ",bytes_in,bytes_out,"
            if line.contains("bytes_in") {
                sampleBlockCount += 1

                if sampleBlockCount == 1 {
                    // First header: preceding block is empty, next block contains cumulative lifetime counts (baseline)
                    currentIntervalBytesIn = 0
                    currentIntervalBytesOut = 0
                    activeProcessesInSample = 0
                    continue
                }

                if sampleBlockCount == 2 {
                    // Second header: baseline cumulative block finished. Real deltas begin now!
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
                self.activeProcessesInSample = 0
                continue
            }

            // Only process lines after the baseline block has finished (sampleBlockCount >= 2)
            guard sampleBlockCount >= 2 else { continue }

            // CSV format: <name>.<pid>,<bytes_in>,<bytes_out>,
            let columns = line.split(separator: ",", omittingEmptySubsequences: false)
            guard columns.count >= 3 else { continue }

            let procIdentifier = String(columns[0])
            guard let bytesIn = UInt64(columns[1]),
                  let bytesOut = UInt64(columns[2]) else { continue }

            if bytesIn > 0 || bytesOut > 0 {
                guard let dotIndex = procIdentifier.lastIndex(of: ".") else { continue }
                let pidString = String(procIdentifier[procIdentifier.index(after: dotIndex)...])
                let rawName = String(procIdentifier[..<dotIndex])

                guard let pid = pid_t(pidString) else { continue }
                let resolved = AppResolver.shared.resolve(pid: pid, rawName: rawName)

                // VPN packet tunnels and proxy extensions relay the originating
                // app's payload. Including both processes doubles aggregate usage.
                if !resolved.isTrafficRelay {
                    activeProcessesInSample += 1
                    currentIntervalBytesIn += bytesIn
                    currentIntervalBytesOut += bytesOut
                }

                // Record into SQLite
                DatabaseService.shared.recordUsage(
                    date: Date(),
                    bundleId: resolved.bundleId,
                    appName: resolved.displayName,
                    appPath: resolved.appPath,
                    bytesIn: bytesIn,
                    bytesOut: bytesOut,
                    isSystem: resolved.isSystemProcess,
                    isTrafficRelay: resolved.isTrafficRelay
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
