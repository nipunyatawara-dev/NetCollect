import SwiftUI

public struct NetCollectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppUsageViewModel.shared

    public init() {}

    public var body: some Scene {
        // Main Dashboard Window
        WindowGroup("NetCollect", id: "dashboard") {
            DashboardView(viewModel: viewModel)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 720)

        // Menu Bar Extra Status Item
        MenuBarExtra(isInserted: $viewModel.showMenuBarExtra) {
            MenuBarPopoverView(
                viewModel: viewModel,
                onOpenDashboard: {
                    AppDelegate.shared?.openDashboardWindow()
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
            SettingsView(viewModel: viewModel)
        }
    }
}
