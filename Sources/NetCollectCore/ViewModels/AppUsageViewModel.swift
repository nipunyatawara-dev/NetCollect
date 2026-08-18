import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppUsageViewModel: ObservableObject {
    public static let shared = AppUsageViewModel()

    // MARK: - Published State
    @Published public var selectedTimeframe: TimeframeFilter = .daily {
        didSet {
            loadUsageData()
            loadChartData()
        }
    }

    @Published public var searchQuery: String = ""
    @Published public var categoryFilter: AppCategoryFilter = .all
    @Published public var sortOption: SortOption = .totalDescending

    @Published public var liveBandwidth: LiveBandwidth = LiveBandwidth()
    @Published public var allRecords: [AppUsageRecord] = []
    @Published public var chartPoints: [ChartDataPoint] = []

    @Published public var totalBytesIn: UInt64 = 0
    @Published public var totalBytesOut: UInt64 = 0
    @Published public var totalBytes: UInt64 = 0
    @Published public var topAppName: String = "None"
    @Published public var activeAppsCount: Int = 0

    @Published public var pollingMode: PollingMode = .balanced {
        didSet {
            NetworkCollector.shared.pollingMode = pollingMode
            UserDefaults.standard.set(pollingMode.rawValue, forKey: "netcollect_polling_mode")
        }
    }

    @Published public var dataRefreshInterval: DataRefreshInterval = .threeSeconds {
        didSet {
            UserDefaults.standard.set(dataRefreshInterval.rawValue, forKey: "netcollect_data_refresh_interval")
            restartRefreshTimer()
        }
    }

    @Published public var isShowingSettings: Bool = false

    @Published public var isBackgroundOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(isBackgroundOnly, forKey: "netcollect_bg_only")
            updateActivationPolicy()
        }
    }

    @Published public var isSilentBackgroundMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isSilentBackgroundMode, forKey: "netcollect_silent_bg_mode")
            showMenuBarExtra = !isSilentBackgroundMode
            updateActivationPolicy()
        }
    }

    @Published public var showMenuBarExtra: Bool = true {
        didSet {
            UserDefaults.standard.set(showMenuBarExtra, forKey: "netcollect_show_menu_bar")
        }
    }

    @Published public var launchAtLogin: Bool = false {
        didSet {
            LaunchAtLoginService.shared.isEnabled = launchAtLogin
        }
    }

    private var isHoverPrecisionActive: Bool = false
    private var activeUIRefCount: Int = 0
    public var isUIVisible: Bool { activeUIRefCount > 0 }

    public func setHoverPrecision(active: Bool) {
        guard isHoverPrecisionActive != active else { return }
        isHoverPrecisionActive = active
        if active {
            NetworkCollector.shared.pollingMode = .oneSecond
        } else {
            NetworkCollector.shared.pollingMode = effectivePollingMode
        }
    }

    private var refreshTimer: Timer?

    private var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var effectivePollingMode: PollingMode {
        if isLowPowerModeEnabled && (pollingMode == .oneSecond || pollingMode == .twoSeconds) {
            return .eco
        }
        return pollingMode
    }

    private init() {
        // Load preferences
        if let savedMode = UserDefaults.standard.string(forKey: "netcollect_polling_mode") {
            self.pollingMode = PollingMode.from(storedValue: savedMode)
        }
        if let savedRefreshRaw = UserDefaults.standard.object(forKey: "netcollect_data_refresh_interval") as? Int,
           let interval = DataRefreshInterval(rawValue: savedRefreshRaw) {
            self.dataRefreshInterval = interval
        }
        self.isBackgroundOnly = UserDefaults.standard.bool(forKey: "netcollect_bg_only")
        self.isSilentBackgroundMode = UserDefaults.standard.bool(forKey: "netcollect_silent_bg_mode")
        if UserDefaults.standard.object(forKey: "netcollect_show_menu_bar") != nil {
            self.showMenuBarExtra = UserDefaults.standard.bool(forKey: "netcollect_show_menu_bar") && !self.isSilentBackgroundMode
        } else {
            self.showMenuBarExtra = !self.isSilentBackgroundMode
        }
        self.launchAtLogin = LaunchAtLoginService.shared.isEnabled

        setupPowerStateObserver()
        setupCollector()
        loadUsageData()
        loadChartData()
    }

    private func setupPowerStateObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                NetworkCollector.shared.pollingMode = self.effectivePollingMode
            }
        }
    }

    /// Called when a view (Dashboard or MenuBar popover) appears on screen.
    public func registerUIVisible() {
        activeUIRefCount += 1
        if activeUIRefCount == 1 {
            NetworkCollector.shared.setUIVisible(true)
            loadUsageData()
            loadChartData()
            restartRefreshTimer()
        }
    }

    /// Called when a view disappears from screen.
    public func unregisterUIVisible() {
        activeUIRefCount = max(0, activeUIRefCount - 1)
        if activeUIRefCount == 0 {
            NetworkCollector.shared.setUIVisible(false)
            stopRefreshTimer()
        }
    }

    public func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard isUIVisible else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: dataRefreshInterval.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isUIVisible else { return }
                self.loadUsageData()
                self.loadChartData()
            }
        }
    }

    public func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func setupCollector() {
        guard ProcessInfo.processInfo.environment["NETCOLLECT_DISABLE_SHARED_COLLECTION"] != "1" else {
            return
        }

        NetworkCollector.shared.onBandwidthUpdated = { [weak self] bandwidth in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Only trigger SwiftUI object changes when UI is actively open/rendered and value changed
                if self.isUIVisible && self.liveBandwidth != bandwidth {
                    self.liveBandwidth = bandwidth
                }
            }
        }

        NetworkCollector.shared.onDeltaReceived = { _ in
            // Delta logged directly to SQLite memory buffer in background
        }

        NetworkCollector.shared.pollingMode = effectivePollingMode
        NetworkCollector.shared.setUIVisible(isUIVisible)
        NetworkCollector.shared.start()
    }

    // MARK: - Data Loading
    public func loadUsageData() {
        let interval = selectedTimeframe.dateInterval()
        let records = DatabaseService.shared.fetchUsage(from: interval.start, to: interval.end)

        var sumIn: UInt64 = 0
        var sumOut: UInt64 = 0
        for r in records {
            sumIn += r.bytesIn
            sumOut += r.bytesOut
        }
        let total = sumIn + sumOut
        let topApp = records.first?.appName ?? "None"
        let count = records.count

        // Guard assignments to prevent spurious SwiftUI re-render passes when values haven't changed
        if self.totalBytesIn != sumIn { self.totalBytesIn = sumIn }
        if self.totalBytesOut != sumOut { self.totalBytesOut = sumOut }
        if self.totalBytes != total { self.totalBytes = total }
        if self.topAppName != topApp { self.topAppName = topApp }
        if self.activeAppsCount != count { self.activeAppsCount = count }
        if self.allRecords != records { self.allRecords = records }
    }

    public func loadChartData() {
        let interval = selectedTimeframe.dateInterval()
        let grouping: TimeGrouping = (selectedTimeframe == .daily) ? .hourly : .daily
        let points = DatabaseService.shared.fetchTimeSeries(from: interval.start, to: interval.end, grouping: grouping)
        // Avoid invalidating the entire chart on every polling tick when no bucket changed.
        if chartPoints != points {
            chartPoints = points
        }
    }

    // MARK: - Filtered & Sorted Apps
    public var filteredApps: [AppUsageRecord] {
        var list = allRecords

        // Filter by category
        switch categoryFilter {
        case .all:
            break
        case .userOnly:
            list = list.filter { !$0.isSystemProcess }
        case .systemOnly:
            list = list.filter { $0.isSystemProcess }
        }

        // Filter by search text
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter {
                $0.appName.lowercased().contains(query) ||
                $0.bundleId.lowercased().contains(query)
            }
        }

        // Sort
        switch sortOption {
        case .totalDescending:
            list.sort { $0.totalBytes > $1.totalBytes }
        case .downloadDescending:
            list.sort { $0.bytesIn > $1.bytesIn }
        case .uploadDescending:
            list.sort { $0.bytesOut > $1.bytesOut }
        case .nameAscending:
            list.sort { $0.appName.localizedCaseInsensitiveCompare($1.appName) == .orderedAscending }
        }

        return list
    }

    public var formattedTotalBytes: String {
        ByteCountFormatter.format(bytes: totalBytes)
    }

    public var formattedTotalIn: String {
        ByteCountFormatter.format(bytes: totalBytesIn)
    }

    public var formattedTotalOut: String {
        ByteCountFormatter.format(bytes: totalBytesOut)
    }

    public func clearAllData() {
        DatabaseService.shared.clearAllData()
        loadUsageData()
        loadChartData()
    }

    public func updateActivationPolicy() {
        if isSilentBackgroundMode {
            let hasVisibleWindow = NSApp?.windows.contains(where: {
                $0.isVisible && $0.canBecomeMain && !$0.isSheet && !(String(describing: type(of: $0)).contains("StatusBar"))
            }) ?? false

            if hasVisibleWindow {
                NSApp?.setActivationPolicy(.regular)
            } else {
                NSApp?.setActivationPolicy(.accessory)
            }
        } else if isBackgroundOnly {
            NSApp?.setActivationPolicy(.accessory)
        } else {
            NSApp?.setActivationPolicy(.regular)
        }
    }

    public func quitApp() {
        DatabaseService.shared.flushSync()
        NetworkCollector.shared.stop()
        NSApp?.terminate(nil)
    }
}
