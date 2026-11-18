import SwiftUI

/// The primary macOS workspace for network usage and per-application activity.
public struct DashboardView: View {
    @ObservedObject var viewModel: AppUsageViewModel
    @State private var showingLiveBandwidth = false

    public init(viewModel: AppUsageViewModel = .shared) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let storageIssue = viewModel.storageIssue {
                    Label(storageIssue, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }

                heroMetricsGrid
                UsageChartView(
                    points: viewModel.chartPoints,
                    timeframe: viewModel.selectedTimeframe,
                    dateRange: viewModel.displayedDateRange,
                    hasHistory: viewModel.hasHistory
                )
                applicationsSection
            }
            .padding(NetCollectDesign.contentPadding)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Usage period", selection: $viewModel.selectedTimeframe) {
                        ForEach(TimeframeFilter.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(viewModel.selectedTimeframe.title, systemImage: "calendar")
                }
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Usage period")
                .accessibilityValue(viewModel.selectedTimeframe.title)
                .help("Change the usage period for the dashboard")
            }

            if #available(macOS 26, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingLiveBandwidth.toggle()
                } label: {
                    Label(viewModel.liveBandwidth.formattedTotalRate, systemImage: "gauge.with.needle")
                        .monospacedDigit()
                }
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Live bandwidth")
                .accessibilityValue(viewModel.liveBandwidth.formattedTotalRate)
                .help("Show live download and upload speeds")
                .popover(isPresented: $showingLiveBandwidth, arrowEdge: .bottom) {
                    LabeledContent {
                        Text(viewModel.liveBandwidth.formattedInRate)
                            .monospacedDigit()
                    } label: {
                        Label("Download", systemImage: "arrow.down")
                    }
                    .padding(.horizontal)
                    .padding(.top)
                    LabeledContent {
                        Text(viewModel.liveBandwidth.formattedOutRate)
                            .monospacedDigit()
                    } label: {
                        Label("Upload", systemImage: "arrow.up")
                    }
                    .padding([.horizontal, .bottom])
                }

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open settings")
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .onChange(of: showingLiveBandwidth) { _, visible in
            viewModel.setHoverPrecision(active: visible)
        }
        .onDisappear {
            viewModel.setHoverPrecision(active: false)
        }
    }

    private var heroMetricsGrid: some View {
        HStack(spacing: 12) {
            HeroMetricsCard(
                title: "Total usage",
                value: viewModel.hasHistory ? viewModel.formattedTotalBytes : "—",
                subtitle: viewModel.hasHistory ? "\(viewModel.activeAppsCount) applications" : "",
                iconName: "arrow.up.arrow.down",
                accentColor: NetCollectDesign.accent,
                isProminent: true,
                bytes: viewModel.totalBytes,
                timeframe: viewModel.selectedTimeframe
            )
            HeroMetricsCard(
                title: "Downloaded",
                value: viewModel.hasHistory ? viewModel.formattedTotalIn : "—",
                subtitle: "",
                iconName: "arrow.down",
                accentColor: NetCollectDesign.accent,
                bytes: viewModel.totalBytesIn,
                timeframe: viewModel.selectedTimeframe
            )
            HeroMetricsCard(
                title: "Uploaded",
                value: viewModel.hasHistory ? viewModel.formattedTotalOut : "—",
                subtitle: "",
                iconName: "arrow.up",
                accentColor: .secondary,
                bytes: viewModel.totalBytesOut,
                timeframe: viewModel.selectedTimeframe
            )
        }
    }

    private var applicationsSection: some View {
        let records = viewModel.filteredApps
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Applications")
                    .font(.headline)
                Spacer()
                if viewModel.hasHistory {
                    Text("\(records.count) of \(viewModel.allRecords.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            applicationListControls

            if !viewModel.hasHistory {
                Color.clear.frame(height: 150)
                    .accessibilityHidden(true)
            } else if records.isEmpty {
                if viewModel.allRecords.isEmpty {
                    ContentUnavailableView(
                        "No Network Activity",
                        systemImage: "network",
                        description: Text("Usage appears here as applications connect.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ContentUnavailableView(
                        "No Matching Applications",
                        systemImage: "magnifyingglass",
                        description: Text("Change your search or category filter.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        AppUsageRowView(record: record)
                        if record.id != records.last?.id {
                            Divider().padding(.leading, 60)
                        }
                    }
                }
                .padding(.vertical, 4)
                .netCollectSurface()
            }
        }
    }

    private var applicationListControls: some View {
        HStack(spacing: 16) {
            ApplicationSearchField(query: $viewModel.searchQuery)
                .frame(maxWidth: 260)
            Spacer(minLength: 0)

            Picker("Show", selection: $viewModel.categoryFilter) {
                ForEach(AppCategoryFilter.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()

            Picker("Sort by", selection: $viewModel.sortOption) {
                ForEach(SortOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

private struct ApplicationSearchField: NSViewRepresentable {
    @Binding var query: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search applications"
        field.setAccessibilityLabel("Search applications")
        field.sendsSearchStringImmediately = true
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.query = $query
        if field.stringValue != query {
            field.stringValue = query
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(query: $query)
    }

    @MainActor
    final class Coordinator: NSObject {
        var query: Binding<String>

        init(query: Binding<String>) {
            self.query = query
        }

        @objc func searchChanged(_ field: NSSearchField) {
            if query.wrappedValue != field.stringValue {
                query.wrappedValue = field.stringValue
            }
        }
    }
}
