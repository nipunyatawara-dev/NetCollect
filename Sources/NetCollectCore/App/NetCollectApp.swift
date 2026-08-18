import SwiftUI

public struct NetCollectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("netcollect_show_menu_bar") private var showMenuBarExtra: Bool = true

    public init() {}

    public var body: some Scene {
        // Main Dashboard Window
        WindowGroup("NetCollect", id: "dashboard") {
            DashboardView(viewModel: .shared)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 720)

        // Menu Bar Extra Status Item
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            MenuBarPopoverView(
                viewModel: .shared,
                onOpenDashboard: {
                    AppDelegate.shared?.openDashboardWindow()
                },
                onOpenSettings: {
                    AppDelegate.shared?.openSettingsWindow()
                },
                onQuit: {
                    AppDelegate.shared?.quitApp()
                }
            )
        } label: {
            Image(systemName: "chart.bar.xaxis")
                .accessibilityLabel("NetCollect network activity")
        }
        .menuBarExtraStyle(.window)

        // Preferences Window
        Settings {
            SettingsView(viewModel: .shared)
        }
    }
}
