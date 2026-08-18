import Cocoa
import SwiftUI

/// AppKit Application Delegate managing window lifecycle and activation policies.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static var shared: AppDelegate?

    public var dashboardWindowController: NSWindowController?
    public var isExplicitQuit: Bool = false

    override public init() {
        super.init()
        AppDelegate.shared = self
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        _ = AppUsageViewModel.shared

        // Observe window close notifications to update Dock / background presence
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Apply saved activation policy
        let silentBg = UserDefaults.standard.bool(forKey: "netcollect_silent_bg_mode")
        let bgOnly = UserDefaults.standard.bool(forKey: "netcollect_bg_only")
        if silentBg {
            // Keep regular on launch so the initial window can be shown if opened by user
            NSApp.setActivationPolicy(.regular)
        } else if bgOnly {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }

        // Ensure database flushes on shutdown, restart, or sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isExplicitQuit = true
                DatabaseService.shared.flushSync()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                DatabaseService.shared.flushSync()
                NetworkCollector.shared.stop()
            }
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                NetworkCollector.shared.start()
            }
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openDashboardWindow()
        return true
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isExplicitQuit {
            return .terminateNow
        }

        if AppUsageViewModel.shared.isSilentBackgroundMode {
            // In silent background mode, closing or Cmd+Q hides windows and enters stealth background
            for window in NSApp.windows where !window.isSheet && !(String(describing: type(of: window)).contains("StatusBar")) {
                window.orderOut(nil)
            }
            NSApp.setActivationPolicy(.accessory)
            return .terminateCancel
        }

        return .terminateNow
    }

    public func applicationWillTerminate(_ notification: Notification) {
        DatabaseService.shared.flushSync()
        NetworkCollector.shared.stop()
    }

    @objc private func handleWindowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.evaluateActivationPolicyAfterWindowClosed()
        }
    }

    public func evaluateActivationPolicyAfterWindowClosed() {
        let visibleWindows = NSApp?.windows.filter { window in
            window.isVisible && window.canBecomeMain && !window.isSheet && !(String(describing: type(of: window)).contains("StatusBar"))
        } ?? []

        guard visibleWindows.isEmpty else { return }

        let silentBg = AppUsageViewModel.shared.isSilentBackgroundMode
        let bgOnly = AppUsageViewModel.shared.isBackgroundOnly

        if silentBg || bgOnly {
            // Hide from Dock and App Switcher when no windows are open
            NSApp?.setActivationPolicy(.accessory)
        } else {
            NSApp?.setActivationPolicy(.regular)
        }
    }

    public func quitApp() {
        isExplicitQuit = true
        DatabaseService.shared.flushSync()
        NetworkCollector.shared.stop()
        NSApp?.terminate(nil)
    }

    public func openSettingsWindow() {
        AppUsageViewModel.shared.isShowingSettings = true
        openDashboardWindow()
    }

    public func openDashboardWindow() {
        // Bring app to foreground and make Dock icon visible
        NSApp?.setActivationPolicy(.regular)
        NSApp?.activate(ignoringOtherApps: true)

        if let existing = dashboardWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            return
        }

        // WindowGroup owns the first dashboard window. Reuse it before creating an
        // AppKit-managed replacement so the menu bar action never duplicates it.
        if let existing = NSApp?.windows.first(where: { window in
            window.title == "NetCollect" &&
            window.canBecomeMain &&
            !window.isSheet &&
            !(String(describing: type(of: window)).contains("StatusBar"))
        }) {
            existing.makeKeyAndOrderFront(nil)
            existing.orderFrontRegardless()
            if existing.isVisible {
                return
            }
        }

        let contentView = DashboardView(viewModel: .shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "NetCollect"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: contentView)

        let controller = NSWindowController(window: window)
        self.dashboardWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
