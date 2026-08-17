import Foundation
import AppKit
import Darwin

/// Resolved metadata about a running process or application.
public struct ResolvedAppInfo: Sendable, Hashable {
    public let bundleId: String
    public let displayName: String
    public let appPath: String?
    public let isSystemProcess: Bool

    public init(
        bundleId: String,
        displayName: String,
        appPath: String? = nil,
        isSystemProcess: Bool = false
    ) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.appPath = appPath
        self.isSystemProcess = isSystemProcess
    }
}

/// Thread-safe service for resolving process IDs and names to macOS applications and caching icons.
public final class AppResolver: @unchecked Sendable {
    public static let shared = AppResolver()

    private let lock = NSLock()
    private var pidCache: [pid_t: ResolvedAppInfo] = [:]
    private var nameCache: [String: ResolvedAppInfo] = [:]
    private var iconCache: [String: NSImage] = [:]

    private init() {}

    /// Resolves a process ID and process name to a consolidated Application Info.
    public func resolve(pid: pid_t, rawName: String) -> ResolvedAppInfo {
        lock.lock()
        if let cached = pidCache[pid] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = performResolution(pid: pid, rawName: rawName)

        lock.lock()
        pidCache[pid] = resolved
        lock.unlock()

        return resolved
    }

    private func performResolution(pid: pid_t, rawName: String) -> ResolvedAppInfo {
        // 1. Try NSRunningApplication
        if let runningApp = NSRunningApplication(processIdentifier: pid) {
            let bundleId = runningApp.bundleIdentifier ?? "app.\(rawName)"
            let name = runningApp.localizedName ?? cleanProcessName(rawName)
            let path = runningApp.bundleURL?.path
            let isSystem = isSystemPath(path) || bundleId.starts(with: "com.apple.")
            return ResolvedAppInfo(
                bundleId: bundleId,
                displayName: name,
                appPath: path,
                isSystemProcess: isSystem
            )
        }

        // 2. Try proc_pidpath to get executable path
        var pathBuffer = [CChar](repeating: 0, count: Int(4 * MAXPATHLEN))
        let pathLength = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        if pathLength > 0 {
            let execPath = pathBuffer.withUnsafeBufferPointer { ptr in
                String(cString: ptr.baseAddress!)
            }
            if !execPath.isEmpty {
                if let appBundlePath = findAppBundle(in: execPath) {
                    let bundle = Bundle(path: appBundlePath)
                    let bundleId = bundle?.bundleIdentifier ?? "app.\(rawName)"
                    let name = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                        ?? bundle?.infoDictionary?["CFBundleName"] as? String
                        ?? URL(fileURLWithPath: appBundlePath).deletingPathExtension().lastPathComponent
                    let isSystem = isSystemPath(appBundlePath) || bundleId.starts(with: "com.apple.")

                    return ResolvedAppInfo(
                        bundleId: bundleId,
                        displayName: name,
                        appPath: appBundlePath,
                        isSystemProcess: isSystem
                    )
                }

                // It's a non-bundle executable / daemon / CLI tool
                let isSystem = isSystemPath(execPath)
                let name = cleanProcessName(URL(fileURLWithPath: execPath).lastPathComponent)
                let bundleId = isSystem ? "system.\(name)" : "cli.\(name)"

                return ResolvedAppInfo(
                    bundleId: bundleId,
                    displayName: name,
                    appPath: execPath,
                    isSystemProcess: isSystem
                )
            }
        }

        // 3. Fallback based on raw name
        let cleaned = cleanProcessName(rawName)
        let isSystem = isKnownSystemDaemon(cleaned)
        let bundleId = isSystem ? "system.\(cleaned)" : "process.\(cleaned)"

        return ResolvedAppInfo(
            bundleId: bundleId,
            displayName: cleaned,
            appPath: nil,
            isSystemProcess: isSystem
        )
    }

    /// Finds if an executable path resides inside an `.app` bundle.
    private func findAppBundle(in path: String) -> String? {
        var currentURL = URL(fileURLWithPath: path)
        var bestAppBundle: String? = nil

        while currentURL.pathComponents.count > 1 {
            if currentURL.pathExtension == "app" {
                bestAppBundle = currentURL.path
            }
            currentURL.deleteLastPathComponent()
        }

        return bestAppBundle
    }

    private func isSystemPath(_ path: String?) -> Bool {
        guard let path = path else { return false }
        return path.hasPrefix("/System/") ||
               path.hasPrefix("/usr/libexec/") ||
               path.hasPrefix("/usr/sbin/") ||
               path.hasPrefix("/usr/bin/") ||
               path.hasPrefix("/System/Library/") ||
               path.hasPrefix("/Library/Apple/")
    }

    private func isKnownSystemDaemon(_ name: String) -> Bool {
        let systemDaemons: Set<String> = [
            "mDNSResponder", "apsd", "airportd", "rapportd", "sharingd",
            "identityservice", "launchd", "syslogd", "kernel_task", "cloudd",
            "nsurlsessiond", "trustd", "securityd", "wifip2pd", "netbiosd",
            "ControlCenter", "boringNotch", "bluetoothd", "configd", "locationd"
        ]
        return systemDaemons.contains(name)
    }

    private func cleanProcessName(_ name: String) -> String {
        // Strip trailing parentheses e.g. "Signal Helper (" -> "Signal Helper"
        var clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("(") {
            clean = String(clean.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean.isEmpty ? name : clean
    }

    /// Retrieves or generates an icon for the given bundle ID / app path.
    public func icon(for bundleId: String, appPath: String?, isSystem: Bool) -> NSImage {
        lock.lock()
        if let cached = iconCache[bundleId] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        var image: NSImage? = nil

        if let path = appPath, FileManager.default.fileExists(atPath: path) {
            image = NSWorkspace.shared.icon(forFile: path)
        } else if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            image = NSWorkspace.shared.icon(forFile: appUrl.path)
        }

        if image == nil {
            if isSystem {
                image = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "System")
            } else if bundleId.starts(with: "cli.") {
                image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Terminal Tool")
            } else {
                image = NSImage(systemSymbolName: "app.fill", accessibilityDescription: "Application")
            }
        }

        let finalImage = image ?? NSImage()
        lock.lock()
        iconCache[bundleId] = finalImage
        lock.unlock()

        return finalImage
    }

    /// Clears cached PID mappings when processes terminate.
    public func invalidatePID(_ pid: pid_t) {
        lock.lock()
        pidCache.removeValue(forKey: pid)
        lock.unlock()
    }
}
