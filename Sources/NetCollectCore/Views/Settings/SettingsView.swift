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
                            title: "Sampling frequency",
                            description: pollingDescription,
                            symbol: "timer"
                        ) {
                            Picker("Sampling frequency", selection: $viewModel.pollingMode) {
                                ForEach(PollingMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 118)
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
        .frame(width: 500, height: 460)
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
        case .eco:
            return "Uses fewer updates to minimize background work."
        case .balanced:
            return "Recommended for responsive updates with low CPU use."
        case .highPrecision:
            return "Updates most frequently for the freshest live readings."
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
