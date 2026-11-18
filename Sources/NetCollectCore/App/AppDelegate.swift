import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public private(set) static weak var shared: AppDelegate?
    private weak var dashboard: NSWindow?
    private var presentDashboard: (() -> Void)?
    private var reopenRequested = false
    private var dashboardIsVisible = false
    private var isExplicitQuit = false
    private var isTerminating = false
    private var isPoweringOff = false

    public override init() {
        super.init()
        Self.shared = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        _ = AppUsageViewModel.shared
        refreshWindowState()

        let center = NotificationCenter.default
        for name in [
            NSWindow.willCloseNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didChangeOcclusionStateNotification
        ] {
            center.addObserver(self, selector: #selector(windowStateChanged), name: name, object: nil)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(willPowerOff), name: NSWorkspace.willPowerOffNotification, object: nil)
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboardWindow()
        return false
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !isExplicitQuit && AppUsageViewModel.shared.isSilentBackgroundMode {
            for window in NSApp.windows where window.canBecomeMain && !window.isSheet {
                window.orderOut(nil)
            }
            refreshWindowState()
            return .terminateCancel
        }

        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        NetworkCollector.shared.stopAndFlush { [weak self] saved in
            Task { @MainActor [weak self] in
                guard let self, !saved, !isPoweringOff else {
                    sender.reply(toApplicationShouldTerminate: true)
                    return
                }
                activate()
                let alert = NSAlert()
                alert.messageText = "Network History Couldn’t Be Saved"
                alert.informativeText = "Keep NetCollect running to retry saving recent network activity. Quitting now will discard those samples."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Keep Running")
                alert.addButton(withTitle: "Quit Without Saving")
                if alert.runModal() == .alertSecondButtonReturn {
                    sender.reply(toApplicationShouldTerminate: true)
                } else {
                    isExplicitQuit = false
                    isTerminating = false
                    AppUsageViewModel.shared.startCollection()
                    sender.reply(toApplicationShouldTerminate: false)
                }
            }
        }
        return .terminateLater
    }

    @objc private func willSleep(_ notification: Notification) {
        NetworkCollector.shared.stopAndFlush()
    }

    @objc private func didWake(_ notification: Notification) {
        guard !isExplicitQuit, !isTerminating else { return }
        AppUsageViewModel.shared.startCollection()
    }

    @objc private func willPowerOff(_ notification: Notification) {
        isPoweringOff = true
        isExplicitQuit = true
        NetworkCollector.shared.stopAndFlush()
    }

    @objc private func windowStateChanged(_ notification: Notification) {
        // willClose arrives before the window leaves the screen.
        Task { @MainActor [weak self] in
            self?.refreshWindowState()
        }
    }

    private func refreshWindowState() {
        let visible = dashboard.map { $0.isVisible && !$0.isMiniaturized } ?? false
        if dashboardIsVisible != visible {
            dashboardIsVisible = visible
            if visible {
                AppUsageViewModel.shared.registerUIVisible()
            } else {
                AppUsageViewModel.shared.setHoverPrecision(active: false)
                AppUsageViewModel.shared.unregisterUIVisible()
            }
        }
        updateActivationPolicy()
    }

    func updateActivationPolicy() {
        let viewModel = AppUsageViewModel.shared
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain && !$0.isSheet }
        let policy: NSApplication.ActivationPolicy =
            !hasWindow && (viewModel.isSilentBackgroundMode || viewModel.isBackgroundOnly) ? .accessory : .regular
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }

    func attachDashboard(_ window: NSWindow, open: @escaping () -> Void) {
        dashboard = window
        presentDashboard = open
        Task { @MainActor [weak self] in
            guard let self else { return }
            if reopenRequested {
                openDashboardWindow()
            }
            refreshWindowState()
        }
    }

    func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    public func openDashboardWindow(open: (() -> Void)? = nil) {
        activate()
        if let dashboard {
            reopenRequested = false
            if dashboard.isMiniaturized {
                dashboard.deminiaturize(nil)
            }
            dashboard.makeKeyAndOrderFront(nil)
            refreshWindowState()
        } else if let present = open ?? presentDashboard {
            reopenRequested = false
            present()
        } else {
            reopenRequested = true
        }
    }

    public func quitApp() {
        isExplicitQuit = true
        NSApp.terminate(nil)
    }
}
