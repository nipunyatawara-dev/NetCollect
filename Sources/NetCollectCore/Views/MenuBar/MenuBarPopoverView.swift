import SwiftUI
import AppKit

/// Compact, quick-glance view displayed in the macOS Menu Bar popover.
public struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    public var onOpenDashboard: () -> Void
    public var onQuit: () -> Void

    public init(
        viewModel: AppUsageViewModel = .shared,
        onOpenDashboard: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onOpenDashboard = onOpenDashboard
        self.onQuit = onQuit
    }

    private var topApps: [AppUsageRecord] {
        Array(viewModel.allRecords.prefix(5))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("NetCollect")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)

                    HStack(spacing: 8) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.accentColor)
                            Text(viewModel.liveBandwidth.formattedInRate)
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }

                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(viewModel.liveBandwidth.formattedOutRate)
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Total Period Usage Pill
                VStack(alignment: .trailing, spacing: 1) {
                    Text(viewModel.formattedTotalBytes)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)

                    Text(viewModel.selectedTimeframe.title.lowercased())
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider().opacity(0.3)

            // MARK: - Timeframe Picker
            HStack(spacing: 4) {
                ForEach([TimeframeFilter.daily, .weekly, .monthly]) { tf in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            viewModel.selectedTimeframe = tf
                        }
                    } label: {
                        Text(tf.title)
                            .font(.system(size: 11, weight: viewModel.selectedTimeframe == tf ? .semibold : .regular))
                            .foregroundColor(viewModel.selectedTimeframe == tf ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background {
                                if viewModel.selectedTimeframe == tf {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.accentColor)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.3)

            // MARK: - Top Apps List
            VStack(spacing: 2) {
                if topApps.isEmpty {
                    Text("No usage recorded")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 16)
                } else {
                    ForEach(topApps) { record in
                        HStack(spacing: 8) {
                            Image(nsImage: AppResolver.shared.icon(for: record.bundleId, appPath: record.appPath, isSystem: record.isSystemProcess))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                            Text(record.appName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            Spacer()

                            Text(record.formattedTotal)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
            }
            .padding(.vertical, 4)

            Divider().opacity(0.3)

            // MARK: - Actions Footer
            HStack {
                Button {
                    onOpenDashboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                        Text("Open Dashboard")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Spacer()

                Button {
                    onQuit()
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .frame(width: 290)
    }
}
