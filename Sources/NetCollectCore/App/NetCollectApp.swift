import SwiftUI

public struct NetCollectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("netcollect_show_menu_bar") private var showMenuBarExtra = true
    @AppStorage("netcollect_silent_bg_mode") private var silentMode = false

    public init() {}

    public var body: some Scene {
        Window("NetCollect", id: "dashboard") {
            DashboardView()
                .background(DashboardWindowBridge())
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 910, height: 680)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Show NetCollect") {
                    appDelegate.openDashboardWindow()
                }
            }
        }

        MenuBarExtra(isInserted: Binding(
            get: { showMenuBarExtra && !silentMode },
            set: { if !silentMode { showMenuBarExtra = $0 } }
        )) {
            MenuBarContent(appDelegate: appDelegate)
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .accessibilityLabel("NetCollect network activity")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Binds Finder/Spotlight reopen and visibility tracking to the actual SwiftUI window.
private struct DashboardWindowBridge: NSViewRepresentable {
    @Environment(\.openWindow) private var openWindow

    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: WindowObserver, context: Context) {
        let action = openWindow
        view.openDashboard = { action(id: "dashboard") }
    }

    final class WindowObserver: NSView {
        var openDashboard: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let openDashboard else { return }
            AppDelegate.shared?.attachDashboard(window, open: openDashboard)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    let appDelegate: AppDelegate

    var body: some View {
        MenuBarPopoverView(
            onOpenDashboard: {
                appDelegate.openDashboardWindow { openWindow(id: "dashboard") }
            },
            onOpenSettings: {
                appDelegate.activate()
                openSettings()
            },
            onQuit: appDelegate.quitApp
        )
    }
}
