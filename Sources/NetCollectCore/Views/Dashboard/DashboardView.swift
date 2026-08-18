import SwiftUI

/// The primary macOS workspace for network usage and per-application activity.
public struct DashboardView: View {
    @ObservedObject var viewModel: AppUsageViewModel

    public init(viewModel: AppUsageViewModel = .shared) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            topBar

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    heroMetricsGrid
                    UsageChartView(points: viewModel.chartPoints, timeframe: viewModel.selectedTimeframe)
                    applicationsSection
                }
                .padding(NetCollectDesign.contentPadding)
            }
        }
        .frame(minWidth: 760, idealWidth: 900, minHeight: 600, idealHeight: 720)
        .background(NetCollectBackground())
        .sheet(isPresented: $viewModel.isShowingSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear {
            viewModel.registerUIVisible()
        }
        .onDisappear {
            viewModel.unregisterUIVisible()
        }
    }

    private var topBar: some View {
        ZStack {
            // Centered Timeframe Toggle
            TimeframeSegmentPicker(selected: $viewModel.selectedTimeframe)
                .frame(width: 290)

            HStack(spacing: 0) {
                // Leading Brand & Date Range (left-aligned with content below)
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(NetCollectDesign.accent.gradient)
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("NetCollect")
                            .font(.system(size: 13, weight: .semibold))
                        Text(viewModel.selectedTimeframe.rangeDescription())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.leading, NetCollectDesign.contentPadding)

                Spacer(minLength: 12)

                // Trailing Live Bandwidth & Settings
                HStack(spacing: 8) {
                    LiveSpeedBadgeView(viewModel: viewModel)

                    Button {
                        viewModel.isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color.primary.opacity(0.055), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(NetCollectPressStyle())
                    .keyboardShortcut(",", modifiers: .command)
                    .help("Settings")
                }
                .padding(.trailing, NetCollectDesign.contentPadding)
            }
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [Color.primary.opacity(0.08), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 1)
        }
    }

    private var heroMetricsGrid: some View {
        HStack(spacing: 14) {
            HeroMetricsCard(
                title: "Total usage",
                value: viewModel.formattedTotalBytes,
                subtitle: viewModel.selectedTimeframe.rangeDescription(),
                iconName: "arrow.up.arrow.down",
                accentColor: NetCollectDesign.accent,
                isProminent: true
            )
            HeroMetricsCard(
                title: "Downloaded",
                value: viewModel.formattedTotalIn,
                subtitle: "Across \(viewModel.activeAppsCount) applications",
                iconName: "arrow.down",
                accentColor: NetCollectDesign.accent
            )
            HeroMetricsCard(
                title: "Uploaded",
                value: viewModel.formattedTotalOut,
                subtitle: "Highest: \(viewModel.topAppName)",
                iconName: "arrow.up",
                accentColor: .secondary
            )
        }
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Applications")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(viewModel.filteredApps.count) of \(viewModel.allRecords.count) shown")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)
                searchField

                Picker("Category", selection: $viewModel.categoryFilter) {
                    ForEach(AppCategoryFilter.allCases) { category in
                        Label(category.rawValue, systemImage: category.iconName).tag(category)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 116)

                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(SortOption.allCases) { option in
                        Label(option.rawValue, systemImage: option.iconName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 126)
            }

            VStack(spacing: 0) {
                if viewModel.filteredApps.isEmpty {
                    emptyApplicationsView
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.filteredApps) { record in
                            AppUsageRowView(record: record)
                            if record.id != viewModel.filteredApps.last?.id {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.065))
                                    .frame(height: 1)
                                    .padding(.leading, 66)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .netCollectSurface()
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(NetCollectPressStyle())
                .help("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 166, height: 28)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
        }
    }

    private var emptyApplicationsView: some View {
        VStack(spacing: 9) {
            Image(systemName: viewModel.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.searchQuery.isEmpty ? "No network activity yet" : "No matching applications")
                .font(.system(size: 13, weight: .semibold))
            Text(viewModel.searchQuery.isEmpty ? "Usage will appear here as applications connect." : "Try a different name or filter.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
    }
}

/// Interactive live speed tile in the top right corner.
/// On hover, splits into separate Download and Upload pills and triggers 1-second high-precision refresh.
struct LiveSpeedBadgeView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if isHovered {
                // Download Speed Pill
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(NetCollectDesign.accent)
                    Text(viewModel.liveBandwidth.formattedInRate)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(NetCollectDesign.accent.opacity(0.12), in: Capsule())
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                    removal: .scale(scale: 0.88).combined(with: .opacity)
                ))

                // Upload Speed Pill
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.liveBandwidth.formattedOutRate)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(Color.primary.opacity(0.06), in: Capsule())
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                    removal: .scale(scale: 0.88).combined(with: .opacity)
                ))
            } else {
                // Combined Total Speed Pill
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(viewModel.liveBandwidth.formattedTotalRate)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.primary.opacity(0.055), in: Capsule())
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                    removal: .scale(scale: 0.88).combined(with: .opacity)
                ))
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            viewModel.setHoverPrecision(active: hovering)
        }
        .help("Live throughput: hover to view 1s live download and upload breakdown")
    }
}
