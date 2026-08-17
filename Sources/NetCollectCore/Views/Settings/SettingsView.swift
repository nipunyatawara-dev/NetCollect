import SwiftUI

/// Preferences & Configuration View.
public struct SettingsView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirmation = false

    public init(viewModel: AppUsageViewModel = .shared) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Preferences")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)

            Divider().opacity(0.3)

            Form {
                // MARK: - App Mode & Presence
                Section {
                    Toggle("Run in Menu Bar Only (Background Mode)", isOn: $viewModel.isBackgroundOnly)
                        .toggleStyle(.switch)

                    Text("When enabled, NetCollect hides from the macOS Dock and Cmd-Tab switcher, minimizing RAM and running purely in the background via the menu bar icon.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } header: {
                    Label("App Mode", systemImage: "menubar.dock.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                }

                // MARK: - Collection Rate
                Section {
                    Picker("Sampling Frequency", selection: $viewModel.pollingMode) {
                        ForEach(PollingMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Text("Balanced mode provides live updates while keeping CPU usage under 0.1%.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } header: {
                    Label("Data Collection", systemImage: "timer")
                        .font(.system(size: 12, weight: .semibold))
                }

                // MARK: - System
                Section {
                    Toggle("Launch automatically at login", isOn: $viewModel.launchAtLogin)
                        .toggleStyle(.switch)
                } header: {
                    Label("Startup", systemImage: "power")
                        .font(.system(size: 12, weight: .semibold))
                }

                // MARK: - Data Management
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear Network History")
                                .font(.system(size: 12, weight: .medium))
                            Text("Removes all recorded daily, weekly, and monthly data from the SQLite database.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Reset Data", role: .destructive) {
                            showingClearConfirmation = true
                        }
                        .controlSize(.small)
                    }
                } header: {
                    Label("Data Storage", systemImage: "cylinder.split.1x2")
                        .font(.system(size: 12, weight: .semibold))
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 10)
        }
        .frame(width: 480, height: 420)
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
            Text("This action cannot be undone. All daily, weekly, and monthly stats will be permanently erased.")
        }
    }
}
