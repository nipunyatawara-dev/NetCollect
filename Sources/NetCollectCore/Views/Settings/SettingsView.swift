import SwiftUI

/// Native macOS Settings panes for app behavior, monitoring, and history.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @State private var selectedDeletionPeriod: HistoryDeletionPeriod = .today
    @State private var showingDeleteConfirmation = false

    public init(viewModel: AppUsageViewModel = .shared) {
        self.viewModel = viewModel
    }

    public var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            monitoring.tabItem { Label("Monitoring", systemImage: "waveform.path.ecg") }
            history.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 510, height: 310)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshLaunchAtLoginStatus()
        }
        .alert("Settings Couldn’t Be Updated", isPresented: Binding(
            get: { viewModel.settingsIssue != nil },
            set: { if !$0 { viewModel.settingsIssue = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.settingsIssue ?? "")
        }
    }

    private var general: some View {
        Form {
            Section("Background") {
                Toggle("Silent background mode", isOn: $viewModel.isSilentBackgroundMode)
                Text("Hides the menu bar icon and removes NetCollect from the Dock when its windows close. Reopen it from Spotlight.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Toggle("Menu bar only", isOn: $viewModel.isBackgroundOnly)
                    .disabled(viewModel.isSilentBackgroundMode)
                Toggle("Launch at login", isOn: Binding(
                    get: { viewModel.launchAtLogin },
                    set: viewModel.setLaunchAtLogin
                ))
            }

            Section {
                Button("Quit NetCollect", role: .destructive) {
                    AppDelegate.shared?.quitApp()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var monitoring: some View {
        Form {
            Section("Refresh intervals") {
                Picker("Live speed updates", selection: $viewModel.pollingMode) {
                    ForEach(PollingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Picker("Usage totals and chart", selection: $viewModel.dataRefreshInterval) {
                    ForEach(DataRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                Text("Usage totals and the chart refresh while the dashboard or menu bar panel is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var history: some View {
        Form {
            Section("Network history") {
                Picker("Period to delete", selection: $selectedDeletionPeriod) {
                    ForEach(HistoryDeletionPeriod.allCases) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                Button("Delete History…", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(viewModel.isDeletingHistory)
                .confirmationDialog(
                    selectedDeletionPeriod.confirmationTitle,
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible,
                    presenting: selectedDeletionPeriod
                ) { period in
                    Button(period.destructiveButtonTitle, role: .destructive) {
                        viewModel.deleteHistory(for: period)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { period in
                    Text(period.deletionDescription)
                }
            }
        }
        .formStyle(.grouped)
    }
}
