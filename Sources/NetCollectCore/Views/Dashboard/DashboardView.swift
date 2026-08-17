import SwiftUI

/// Main macOS dashboard window providing comprehensive network usage analytics.
public struct DashboardView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @State private var showingSettings = false

    public init(viewModel: AppUsageViewModel = .shared) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header Bar
            headerBar
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(.ultraThinMaterial)

            Divider()
                .opacity(0.3)

            // MARK: - Main Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 18) {
                    // Hero Metrics Cards
                    heroMetricsGrid

                    // Usage Trend Chart
                    UsageChartView(
                        points: viewModel.chartPoints,
                        timeframe: viewModel.selectedTimeframe
                    )

                    // Applications List Section
                    applicationsSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, idealWidth: 850, minHeight: 560, idealHeight: 680)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.8)
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
            }
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: viewModel)
        }
    }

    // MARK: - Header Bar View
    private var headerBar: some View {
        HStack(spacing: 16) {
            // App Identity (Left)
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)

                Text("NetCollect")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Centered Timeframe Segment Picker
            TimeframeSegmentPicker(selected: $viewModel.selectedTimeframe)

            Spacer()

            // Right: Live Speed Pill & Settings
            HStack(spacing: 10) {
                // Live Speed Pill Badge
                HStack(spacing: 7) {
                    Circle()
                        .fill(viewModel.liveBandwidth.totalBytesPerSecond > 0 ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: 7, height: 7)
                        .shadow(color: viewModel.liveBandwidth.totalBytesPerSecond > 0 ? Color.accentColor.opacity(0.6) : Color.clear, radius: 3)

                    HStack(spacing: 5) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.accentColor)
                            Text(viewModel.liveBandwidth.formattedInRate)
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }

                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.secondary)
                            Text(viewModel.liveBandwidth.formattedOutRate)
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                        }
                    }
                    .foregroundColor(.primary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                )

                // Settings Button
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(7)
                        .background(Circle().fill(Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help("Preferences")
            }
        }
    }

    // MARK: - Hero Metrics Grid
    private var heroMetricsGrid: some View {
        HStack(spacing: 14) {
            HeroMetricsCard(
                title: "Total Data",
                value: viewModel.formattedTotalBytes,
                subtitle: viewModel.selectedTimeframe.rangeDescription(),
                iconName: "network",
                accentColor: .accentColor
            )

            HeroMetricsCard(
                title: "Download",
                value: viewModel.formattedTotalIn,
                subtitle: "\(viewModel.activeAppsCount) active apps",
                iconName: "arrow.down.circle.fill",
                accentColor: .accentColor
            )

            HeroMetricsCard(
                title: "Upload",
                value: viewModel.formattedTotalOut,
                subtitle: "Top: \(viewModel.topAppName)",
                iconName: "arrow.up.circle.fill",
                accentColor: .accentColor.opacity(0.85)
            )
        }
    }

    // MARK: - Applications List Section
    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Controls Bar (Search, Category Filter, Sort)
            HStack(spacing: 12) {
                // Section Title
                VStack(alignment: .leading, spacing: 1) {
                    Text("Applications")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    Text("\(viewModel.filteredApps.count) apps tracked")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    TextField("Search applications...", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 0.5))
                )
                .frame(width: 180)

                // Category Filter
                Picker("Category", selection: $viewModel.categoryFilter) {
                    ForEach(AppCategoryFilter.allCases) { cat in
                        Label(cat.rawValue, systemImage: cat.iconName).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 125)

                // Sort Option Menu
                Picker("Sort", selection: $viewModel.sortOption) {
                    ForEach(SortOption.allCases) { opt in
                        Label(opt.rawValue, systemImage: opt.iconName).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 135)
            }

            // App List Card
            VStack(spacing: 0) {
                if viewModel.filteredApps.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: viewModel.searchQuery.isEmpty ? "tray" : "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text(viewModel.searchQuery.isEmpty ? "No network usage recorded for this period." : "No matching applications found.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.filteredApps) { record in
                            AppUsageRowView(record: record)
                            if record.id != viewModel.filteredApps.last?.id {
                                Divider()
                                    .opacity(0.2)
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }
}

/// Helper NSVisualEffectView wrapper for macOS translucent vibrancy behind windows.
public struct VisualEffectView: NSViewRepresentable {
    public let material: NSVisualEffectView.Material
    public let blendingMode: NSVisualEffectView.BlendingMode

    public init(
        material: NSVisualEffectView.Material = .contentBackground,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
