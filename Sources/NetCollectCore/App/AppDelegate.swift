import Cocoa
import SwiftUI

/// AppKit Application Delegate managing window lifecycle and activation policies.
@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public static var shared: AppDelegate?

    public var dashboardWindowController: NSWindowController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // Apply saved activation policy
        let bgOnly = UserDefaults.standard.bool(forKey: "netcollect_bg_only")
        if bgOnly {
            NSApp.setActivationPolicy(.accessory)
        } else {
            NSApp.setActivationPolicy(.regular)
        }

        // Ensure database flushes on shutdown, restart, or sleep
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            DatabaseService.shared.flushSync()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            DatabaseService.shared.flushSync()
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        DatabaseService.shared.flushSync()
        NetworkCollector.shared.stop()
    }

    public func openDashboardWindow() {
        // Bring app to foreground if in background mode
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = dashboardWindowController?.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let contentView = DashboardView(viewModel: .shared)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 680),
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
    }
}
