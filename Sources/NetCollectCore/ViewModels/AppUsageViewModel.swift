import Foundation
import SwiftUI
import Combine

@MainActor
public final class AppUsageViewModel: ObservableObject {
    public static let shared = AppUsageViewModel()

    private struct UsageHistory: Equatable {
        let timeframe: TimeframeFilter
        let dateRange: String
        let records: [AppUsageRecord]
        let chartPoints: [ChartDataPoint]
        let bytesIn: UInt64
        let bytesOut: UInt64

        init(snapshot: DatabaseService.Snapshot, timeframe: TimeframeFilter, referenceDate: Date) {
            self.timeframe = timeframe
            dateRange = timeframe.formattedDateRange(for: referenceDate)
            records = snapshot.records
            chartPoints = snapshot.points

            var download: UInt64 = 0
            var upload: UInt64 = 0
            for record in records {
                download += min(record.bytesIn, UInt64.max - download)
                upload += min(record.bytesOut, UInt64.max - upload)
            }
            bytesIn = download
            bytesOut = upload
        }
    }

    // Publish the period, totals, chart, and rows as one update. The request
    // stays separate so changing it never blanks or relabels the visible data.
    @Published private var history: UsageHistory?
    private var requestedTimeframe: TimeframeFilter = .daily

    public var selectedTimeframe: TimeframeFilter {
        get { history?.timeframe ?? .daily }
        set {
            guard requestedTimeframe != newValue else { return }
            requestedTimeframe = newValue
            refreshData(replacingPending: true)
        }
    }

    var displayedDateRange: String {
        history?.dateRange ?? selectedTimeframe.formattedDateRange()
    }

    var hasHistory: Bool { history != nil }

    @Published public var searchQuery: String = ""
    @Published public var categoryFilter: AppCategoryFilter = .all
    @Published public var sortOption: SortOption = .totalDescending

    @Published public var liveBandwidth: LiveBandwidth = LiveBandwidth()
    public var allRecords: [AppUsageRecord] { history?.records ?? [] }
    public var chartPoints: [ChartDataPoint] { history?.chartPoints ?? [] }

    public var totalBytesIn: UInt64 { history?.bytesIn ?? 0 }
    public var totalBytesOut: UInt64 { history?.bytesOut ?? 0 }
    public var totalBytes: UInt64 { totalBytesIn + min(totalBytesOut, UInt64.max - totalBytesIn) }
    public var topAppName: String { allRecords.first?.appName ?? "None" }
    public var activeAppsCount: Int { allRecords.count }

    @Published public var pollingMode: PollingMode = .balanced {
        didSet {
            updatePollingMode()
            UserDefaults.standard.set(pollingMode.rawValue, forKey: "netcollect_polling_mode")
        }
    }

    @Published public var dataRefreshInterval: DataRefreshInterval = .threeSeconds {
        didSet {
            UserDefaults.standard.set(dataRefreshInterval.rawValue, forKey: "netcollect_data_refresh_interval")
            restartRefreshTimer()
        }
    }

    @Published private(set) var storageIssue: String?
    @Published var settingsIssue: String?
    @Published private(set) var isDeletingHistory = false

    @Published public var isBackgroundOnly: Bool = false {
        didSet {
            UserDefaults.standard.set(isBackgroundOnly, forKey: "netcollect_bg_only")
            AppDelegate.shared?.updateActivationPolicy()
        }
    }

    @Published public var isSilentBackgroundMode: Bool = false {
        didSet {
            UserDefaults.standard.set(isSilentBackgroundMode, forKey: "netcollect_silent_bg_mode")
            showMenuBarExtra = !isSilentBackgroundMode
            AppDelegate.shared?.updateActivationPolicy()
        }
    }

    @Published public var showMenuBarExtra: Bool = true {
        didSet {
            UserDefaults.standard.set(showMenuBarExtra, forKey: "netcollect_show_menu_bar")
        }
    }

    @Published private(set) var launchAtLogin = false

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginService.setEnabled(enabled)
            if enabled && !LaunchAtLoginService.isEnabled {
                settingsIssue = "Allow NetCollect under Login Items in System Settings to finish enabling launch at login."
            }
        } catch {
            settingsIssue = error.localizedDescription
        }
        refreshLaunchAtLoginStatus()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = LaunchAtLoginService.isEnabled
    }

    private var isHoverPrecisionActive: Bool = false
    private var activeUIRefCount: Int = 0
    public var isUIVisible: Bool { activeUIRefCount > 0 }

    public func setHoverPrecision(active: Bool) {
        guard isHoverPrecisionActive != active else { return }
        isHoverPrecisionActive = active
        updatePollingMode()
    }

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?

    private var sharedCollectionEnabled: Bool {
        ProcessInfo.processInfo.environment["NETCOLLECT_DISABLE_SHARED_COLLECTION"] != "1"
    }

    private func updatePollingMode() {
        guard sharedCollectionEnabled else { return }
        NetworkCollector.shared.setPollingMode(isHoverPrecisionActive && !isLowPowerModeEnabled ? .oneSecond : effectivePollingMode)
    }

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
        let defaults = UserDefaults.standard
        let silentMode = defaults.bool(forKey: "netcollect_silent_bg_mode")
        let menuBarPreference = defaults.object(forKey: "netcollect_show_menu_bar") as? Bool ?? true
        let savedPollingMode = defaults.string(forKey: "netcollect_polling_mode")
        let savedRefreshInterval = defaults.integer(forKey: "netcollect_data_refresh_interval")

        // Seed property wrappers directly so initialization does not invoke
        // preference setters or re-enter the shared view model via the delegate.
        _isSilentBackgroundMode = Published(initialValue: silentMode)
        _isBackgroundOnly = Published(initialValue: defaults.bool(forKey: "netcollect_bg_only"))
        _showMenuBarExtra = Published(initialValue: menuBarPreference && !silentMode)
        _pollingMode = Published(initialValue: savedPollingMode.map(PollingMode.from(storedValue:)) ?? .balanced)
        _dataRefreshInterval = Published(initialValue: DataRefreshInterval(rawValue: savedRefreshInterval) ?? .threeSeconds)
        _launchAtLogin = Published(initialValue: LaunchAtLoginService.isEnabled)

        setupPowerStateObserver()
        setupCollector()
    }

    private func setupPowerStateObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updatePollingMode()
            }
        }
    }

    /// Called when a view (Dashboard or MenuBar popover) appears on screen.
    public func registerUIVisible() {
        activeUIRefCount += 1
        if activeUIRefCount == 1 {
            if sharedCollectionEnabled { NetworkCollector.shared.setUIVisible(true) }
            refreshData()
            restartRefreshTimer()
        }
    }

    /// Called when a view disappears from screen.
    public func unregisterUIVisible() {
        activeUIRefCount = max(0, activeUIRefCount - 1)
        if activeUIRefCount == 0 {
            if sharedCollectionEnabled { NetworkCollector.shared.setUIVisible(false) }
            stopRefreshTimer()
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    public func restartRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard isUIVisible else { return }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: dataRefreshInterval.intervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isUIVisible else { return }
                self.refreshData()
            }
        }
    }

    public func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func setupCollector() {
        guard sharedCollectionEnabled else { return }

        NetworkCollector.shared.setBandwidthHandler { [weak self] bandwidth in
            Task { @MainActor [weak self] in
                guard let self, isUIVisible, liveBandwidth != bandwidth else { return }
                liveBandwidth = bandwidth
            }
        }

        updatePollingMode()
        NetworkCollector.shared.setUIVisible(isUIVisible)
        startCollection()
    }

    func startCollection() {
        if sharedCollectionEnabled { NetworkCollector.shared.start() }
    }

    private func refreshData(replacingPending: Bool = false) {
        guard isUIVisible, sharedCollectionEnabled else { return }
        if replacingPending {
            refreshTask?.cancel()
        } else {
            guard refreshTask == nil else { return }
        }

        let timeframe = requestedTimeframe
        let referenceDate = Date()
        let interval = timeframe.dateInterval(for: referenceDate)
        let grouping: TimeGrouping = timeframe == .daily ? .hourly : .daily

        refreshTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            let snapshot = await DatabaseService.shared.fetchSnapshot(for: interval, grouping: grouping)
            guard let self, !Task.isCancelled else { return }
            refreshTask = nil
            if let snapshot {
                let updatedHistory = UsageHistory(snapshot: snapshot, timeframe: timeframe, referenceDate: referenceDate)
                if history != updatedHistory { history = updatedHistory }
                if storageIssue != nil { storageIssue = nil }
            } else if storageIssue == nil {
                storageIssue = "Network history is temporarily unavailable. NetCollect will retry."
            }
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

    public func deleteHistory(for period: HistoryDeletionPeriod, now: Date = Date()) {
        guard !isDeletingHistory else { return }
        isDeletingHistory = true
        let interval = period.dateInterval(containing: now)
        Task {
            let deleted = await DatabaseService.shared.deleteHistory(in: interval)
            if !deleted {
                settingsIssue = "Network history couldn’t be deleted. Try again."
            }
            isDeletingHistory = false
            refreshData(replacingPending: true)
        }
    }
}
