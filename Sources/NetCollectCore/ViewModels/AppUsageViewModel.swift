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

    public func setHoverPrecision(active: Bool) {
        guard isHoverPrecisionActive != active else { return }
        isHoverPrecisionActive = active
        if active {
            NetworkCollector.shared.pollingMode = .highPrecision
        } else {
            NetworkCollector.shared.pollingMode = pollingMode
        }
    }

    private var refreshTimer: Timer?

    private init() {
        // Load preferences
        if let savedMode = UserDefaults.standard.string(forKey: "netcollect_polling_mode"),
           let mode = PollingMode(rawValue: savedMode) {
            self.pollingMode = mode
        }
        self.isBackgroundOnly = UserDefaults.standard.bool(forKey: "netcollect_bg_only")
        self.isSilentBackgroundMode = UserDefaults.standard.bool(forKey: "netcollect_silent_bg_mode")
        if UserDefaults.standard.object(forKey: "netcollect_show_menu_bar") != nil {
            self.showMenuBarExtra = UserDefaults.standard.bool(forKey: "netcollect_show_menu_bar") && !self.isSilentBackgroundMode
        } else {
            self.showMenuBarExtra = !self.isSilentBackgroundMode
        }
        self.launchAtLogin = LaunchAtLoginService.shared.isEnabled

        setupCollector()
        loadUsageData()
        loadChartData()

        // Set up periodic UI refresh (every 3 seconds) to pull batched changes smoothly
        self.refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadUsageData()
                self?.loadChartData()
            }
        }
    }

    private func setupCollector() {
        NetworkCollector.shared.onBandwidthUpdated = { [weak self] bandwidth in
            Task { @MainActor [weak self] in
                self?.liveBandwidth = bandwidth
            }
        }

        NetworkCollector.shared.onDeltaReceived = { _ in
            // Delta received in background
        }

        NetworkCollector.shared.pollingMode = pollingMode
        NetworkCollector.shared.start()
    }

    // MARK: - Data Loading
    public func loadUsageData() {
        let interval = selectedTimeframe.dateInterval()
        let records = DatabaseService.shared.fetchUsage(from: interval.start, to: interval.end)
        self.allRecords = records

        var sumIn: UInt64 = 0
        var sumOut: UInt64 = 0
        for r in records {
            sumIn += r.bytesIn
            sumOut += r.bytesOut
        }
        self.totalBytesIn = sumIn
        self.totalBytesOut = sumOut
        self.totalBytes = sumIn + sumOut
        self.topAppName = records.first?.appName ?? "None"
        self.activeAppsCount = records.count
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
