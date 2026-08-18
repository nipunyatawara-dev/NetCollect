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

/// Ultra-lightweight background collector that samples process-level network statistics via short-lived nettop snapshots.
public final class NetworkCollector: @unchecked Sendable {
    public static let shared = NetworkCollector()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.netcollect.networkcollector", qos: .utility)
    private var isRunning = false
    private var isUIVisibleState = false

    private var previousTotals: [pid_t: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var isBootstrapped = false
    private var lastSampleTime = Date()

    private var peakInRate: Double = 0
    private var peakOutRate: Double = 0

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
            self.previousTotals.removeAll()
            self.isBootstrapped = false
        }
    }

    public func restart() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            if self.isRunning {
                self.performSample()
                self.startTimer()
            }
        }
    }

    private var effectiveInterval: Double {
        isUIVisibleState ? Double(pollingMode.intervalSeconds) : 10.0
    }

    private func startTimer() {
        stopTimer()

        let interval = effectiveInterval
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + interval,
            repeating: interval,
            leeway: .milliseconds(interval >= 10 ? 500 : 200)
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
        let elapsed = max(0.1, now.timeIntervalSince(lastSampleTime))
        lastSampleTime = now

        var intervalBytesIn: UInt64 = 0
        var intervalBytesOut: UInt64 = 0
        var activeProcesses = 0
        var currentPids = Set<pid_t>()

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
            currentPids.insert(pid)

            if !isBootstrapped {
                previousTotals[pid] = (currentIn, currentOut)
                continue
            }

            let deltaIn: UInt64
            let deltaOut: UInt64
            if let previous = previousTotals[pid] {
                deltaIn = currentIn >= previous.bytesIn ? currentIn - previous.bytesIn : currentIn
                deltaOut = currentOut >= previous.bytesOut ? currentOut - previous.bytesOut : currentOut
            } else {
                deltaIn = currentIn
                deltaOut = currentOut
            }
            previousTotals[pid] = (currentIn, currentOut)

            guard deltaIn > 0 || deltaOut > 0 else { continue }

            let resolved = AppResolver.shared.resolve(pid: pid, rawName: rawName)
            if !resolved.isTrafficRelay {
                activeProcesses += 1
                intervalBytesIn += deltaIn
                intervalBytesOut += deltaOut
            }

            DatabaseService.shared.recordUsage(
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

        let deadPids = Set(previousTotals.keys).subtracting(currentPids)
        for deadPid in deadPids {
            previousTotals.removeValue(forKey: deadPid)
            AppResolver.shared.invalidatePID(deadPid)
        }

        guard isBootstrapped else {
            isBootstrapped = true
            return
        }

        let inRate = Double(intervalBytesIn) / elapsed
        let outRate = Double(intervalBytesOut) / elapsed
        peakInRate = max(peakInRate, inRate)
        peakOutRate = max(peakOutRate, outRate)

        onBandwidthUpdated?(LiveBandwidth(
            bytesInPerSecond: inRate,
            bytesOutPerSecond: outRate,
            peakInPerSecond: peakInRate,
            peakOutPerSecond: peakOutRate,
            activeProcessCount: activeProcesses
        ))
    }
}
