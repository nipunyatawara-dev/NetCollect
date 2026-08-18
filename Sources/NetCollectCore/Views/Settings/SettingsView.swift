import SwiftUI

/// Preferences presented as a single, calm macOS settings pane.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

    public init(viewModel: AppUsageViewModel = .shared) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    preferenceSection(title: "General", symbol: "slider.horizontal.3") {
                        settingRow(
                            title: "Silent background mode",
                            description: "Run NetCollect invisibly in the background without showing in the menu bar or Dock when closed. Reopen anytime via Spotlight.",
                            symbol: "eye.slash"
                        ) {
                            Toggle("Silent background mode", isOn: $viewModel.isSilentBackgroundMode)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }

                        sectionDivider

                        settingRow(
                            title: "Menu bar only",
                            description: "Hide NetCollect from the Dock and app switcher while keeping the menu bar icon.",
                            symbol: "menubar.dock.rectangle"
                        ) {
                            Toggle("Menu bar only", isOn: $viewModel.isBackgroundOnly)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .disabled(viewModel.isSilentBackgroundMode)
                        }

                        sectionDivider

                        settingRow(
                            title: "Launch at login",
                            description: "Start monitoring automatically after you sign in to this Mac.",
                            symbol: "power"
                        ) {
                            Toggle("Launch at login", isOn: $viewModel.launchAtLogin)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }

                    preferenceSection(title: "Collection", symbol: "waveform.path.ecg") {
                        settingRow(
                            title: "Speed sampling frequency",
                            description: pollingDescription,
                            symbol: "gauge.with.needle"
                        ) {
                            Picker("Speed sampling frequency", selection: $viewModel.pollingMode) {
                                ForEach(PollingMode.allCases) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 140)
                        }

                        sectionDivider

                        settingRow(
                            title: "Data usage refresh",
                            description: refreshIntervalDescription,
                            symbol: "arrow.clockwise"
                        ) {
                            Picker("Data usage refresh", selection: $viewModel.dataRefreshInterval) {
                                ForEach(DataRefreshInterval.allCases) { interval in
                                    Text(interval.displayName).tag(interval)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 140)
                        }
                    }

                    preferenceSection(title: "Data", symbol: "internaldrive") {
                        settingRow(
                            title: "Network history",
                            description: "Permanently remove all daily, weekly, and monthly usage records.",
                            symbol: "trash"
                        ) {
                            Button("Clear…", role: .destructive) {
                                showingClearConfirmation = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    preferenceSection(title: "Application", symbol: "power.circle") {
                        settingRow(
                            title: "Quit NetCollect",
                            description: "Stop background monitoring and completely exit the application.",
                            symbol: "xmark.circle"
                        ) {
                            Button("Quit", role: .destructive) {
                                AppDelegate.shared?.quitApp()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(22)
                .padding(.top, 10)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
            .help("Close")
        }
        .frame(width: 520, height: 500)
        .background(NetCollectBackground())
        .confirmationDialog(
            "Clear Network Usage History?",
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete All History", role: .destructive) {
                viewModel.clearAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. All recorded network usage will be permanently removed.")
        }
    }

    private var pollingDescription: String {
        switch viewModel.pollingMode {
        case .oneSecond:
            return "Fastest live bandwidth sampling (1 second interval)."
        case .twoSeconds:
            return "Responsive bandwidth sampling (2 seconds interval)."
        case .balanced:
            return "Balanced sampling frequency for bandwidth meters (3 seconds)."
        case .eco:
            return "Reduced sampling frequency to minimize background work (5 seconds)."
        case .tenSeconds:
            return "Lowest CPU usage for live bandwidth sampling (10 seconds)."
        }
    }

    private var refreshIntervalDescription: String {
        switch viewModel.dataRefreshInterval {
        case .oneSecond:
            return "Re-queries and updates total usage metrics and charts every second."
        case .twoSeconds:
            return "Re-queries and updates total usage metrics and charts every 2 seconds."
        case .threeSeconds:
            return "Recommended default. Refreshes data usage totals every 3 seconds."
        case .fiveSeconds:
            return "Updates usage totals and charts every 5 seconds to reduce UI re-renders."
        case .tenSeconds:
            return "Minimal UI database queries for maximum efficiency (10 seconds)."
        }
    }

    @ViewBuilder
    private func preferenceSection<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title.uppercased(), systemImage: symbol)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.55)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content()
            }
            .netCollectSurface(radius: 14)
        }
    }

    private func settingRow<Trailing: View>(
        title: String,
        description: String,
        symbol: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NetCollectDesign.accent)
                .frame(width: 30, height: 30)
                .background(NetCollectDesign.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(description)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }

    private var sectionDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 1)
            .padding(.leading, 57)
    }
}
