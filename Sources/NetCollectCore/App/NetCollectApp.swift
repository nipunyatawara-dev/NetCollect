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
        .defaultSize(width: 850, height: 680)

        // Menu Bar Extra Status Item
        MenuBarExtra {
            MenuBarPopoverView(
                viewModel: viewModel,
                onOpenDashboard: {
                    AppDelegate.shared?.openDashboardWindow()
                },
                onQuit: {
                    DatabaseService.shared.flushSync()
                    NSApp.terminate(nil)
                }
            )
        } label: {
            Image(systemName: "antenna.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.window)

        // Preferences Window
        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
