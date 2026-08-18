import SwiftUI
import AppKit

/// A compact, source-anchored control surface for quick network checks.
public struct MenuBarPopoverView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public var onOpenDashboard: () -> Void
    public var onOpenSettings: () -> Void
    public var onQuit: () -> Void

    public init(
        viewModel: AppUsageViewModel = .shared,
        onOpenDashboard: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.onOpenDashboard = onOpenDashboard
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    private var topApps: [AppUsageRecord] {
        Array(viewModel.allRecords.prefix(5))
    }

    private var isActive: Bool {
        viewModel.liveBandwidth.totalBytesPerSecond > 0
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 14) {
                liveSummary
                TimeframeSegmentPicker(selected: $viewModel.selectedTimeframe)
                topApplications
            }
            .padding(14)

            footer
        }
        .frame(width: 340)
        .background(.ultraThinMaterial)
        .onAppear {
            viewModel.registerUIVisible()
        }
        .onDisappear {
            viewModel.unregisterUIVisible()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(NetCollectDesign.accent.gradient)
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("NetCollect")
                    .font(.system(size: 13, weight: .semibold))
                Text(isActive ? "Monitoring \(viewModel.liveBandwidth.activeProcessCount) active processes" : "Monitoring network activity")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Menu {
                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings…", systemImage: "gearshape")
                }
                Divider()
                Button("Quit NetCollect", role: .destructive) {
                    onQuit()
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 24)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More options")
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 11)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
    }

    private var liveSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TOTAL USAGE")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.65)
                        .foregroundStyle(.secondary)
                    Text(viewModel.formattedTotalBytes)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .tracking(-0.5)
                        .monospacedDigit()
                }

                Spacer()

                Text(viewModel.selectedTimeframe.rangeDescription())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                throughputCell(
                    title: "Download",
                    value: viewModel.liveBandwidth.formattedInRate,
                    symbol: "arrow.down",
                    tint: NetCollectDesign.accent
                )
                throughputCell(
                    title: "Upload",
                    value: viewModel.liveBandwidth.formattedOutRate,
                    symbol: "arrow.up",
                    tint: .secondary
                )
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
    }

    private func throughputCell(title: String, value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var topApplications: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top applications")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(viewModel.activeAppsCount) active")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if topApps.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Waiting for network activity")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            } else {
                VStack(spacing: 2) {
                    ForEach(topApps) { record in
                        compactAppRow(record)
                    }
                }
            }
        }
    }

    private func compactAppRow(_ record: AppUsageRecord) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: AppResolver.shared.icon(for: record.bundleId, appPath: record.appPath, isSystem: record.isSystemProcess))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.appName)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Text(record.formattedTotal)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Capsule()
                    .fill(Color.primary.opacity(0.055))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule()
                                .fill(NetCollectDesign.accent.opacity(0.72))
                                .frame(width: max(3, geometry.size.width * CGFloat(min(1, record.percentage))))
                        }
                    }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.001), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                onOpenDashboard()
            } label: {
                HStack {
                    Image(systemName: "macwindow")
                    Text("Open NetCollect")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .semibold))
                        .opacity(0.8)
                }
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 11)
                .frame(height: 31)
                .contentShape(Rectangle())
                .foregroundStyle(.white)
                .background(NetCollectDesign.accent.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(NetCollectPressStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.075))
                .frame(height: 1)
        }
    }
}
