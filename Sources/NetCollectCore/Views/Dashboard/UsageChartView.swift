import SwiftUI
import Charts

/// Network activity with pointer inspection and accessible series controls.
public struct UsageChartView: View {
    public let points: [ChartDataPoint]
    public let timeframe: TimeframeFilter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDate: Date?
    @State private var showDownload: Bool = true
    @State private var showUpload: Bool = true

    public init(points: [ChartDataPoint], timeframe: TimeframeFilter) {
        self.points = points
        self.timeframe = timeframe
    }

    private var hoveredPoint: ChartDataPoint? {
        guard let hoveredDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate))
        }
    }

    private var maxBytes: Double {
        let peak = points.reduce(0.0) { currentPeak, point in
            let download = showDownload ? Double(point.bytesIn) : 0
            let upload = showUpload ? Double(point.bytesOut) : 0
            return max(currentPeak, download, upload)
        }

        // A 1 MB floor flattened ordinary KB-level traffic into a seemingly dead graph.
        return peak > 0 ? peak * 1.15 : 1
    }

    private var hasAnyTraffic: Bool {
        points.contains { $0.totalBytes > 0 }
    }

    private var xAxisStride: Int {
        // Aim for roughly six labels while keeping every tick on a real hour/day boundary.
        max(1, Int(ceil(Double(max(points.count - 1, 1)) / 5.0)))
    }

    private var xAxisComponent: Calendar.Component {
        timeframe == .daily ? .hour : .day
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header Bar & Live Tooltip
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.accentColor)

                        Text("Activity")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                    }

                    if let selected = hoveredPoint {
                        HStack(spacing: 10) {
                            Text(selected.label)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.primary)

                            if showDownload {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                    Text("↓ \(ByteCountFormatter.format(bytes: selected.bytesIn))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor(.accentColor)
                                }
                            }

                            if showUpload {
                                HStack(spacing: 3) {
                                    Circle().fill(Color.secondary).frame(width: 6, height: 6)
                                    Text("↑ \(ByteCountFormatter.format(bytes: selected.bytesOut))")
                                        .font(.system(size: 11, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text("Total: \(ByteCountFormatter.format(bytes: selected.totalBytes))")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        .transition(.opacity)
                    } else {
                        Text(timeframe == .daily ? "Hourly network usage" : "Daily network usage")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Series Filter Toggles
                HStack(spacing: 6) {
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0)) {
                            showDownload.toggle()
                            if !showDownload && !showUpload { showUpload = true }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(showDownload ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text("Download")
                                .font(.system(size: 11, weight: showDownload ? .semibold : .regular))
                                .foregroundColor(showDownload ? .primary : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(showDownload ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0)) {
                            showUpload.toggle()
                            if !showDownload && !showUpload { showDownload = true }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(showUpload ? Color.secondary : Color.secondary.opacity(0.3))
                                .frame(width: 6, height: 6)
                            Text("Upload")
                                .font(.system(size: 11, weight: showUpload ? .semibold : .regular))
                                .foregroundColor(showUpload ? .primary : .secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(showUpload ? Color.secondary.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            // MARK: - Swift Charts Canvas
            ZStack {
                // Line & Area Marks
                Chart {
                    ForEach(points) { point in
                        if showDownload {
                            let bytesIn = Double(point.bytesIn)
                            AreaMark(
                                x: .value("Time", point.date),
                                yStart: .value("Base", 0.0),
                                yEnd: .value("Download", bytesIn),
                                series: .value("Series", "Download")
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)

                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("Download", bytesIn),
                                series: .value("Series", "Download")
                            )
                            .foregroundStyle(Color.accentColor)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)

                            if points.count == 1 {
                                PointMark(
                                    x: .value("Time", point.date),
                                    y: .value("Download", bytesIn)
                                )
                                .symbolSize(24)
                                .foregroundStyle(Color.accentColor)
                            }
                        }

                        if showUpload {
                            let bytesOut = Double(point.bytesOut)
                            AreaMark(
                                x: .value("Time", point.date),
                                yStart: .value("Base", 0.0),
                                yEnd: .value("Upload", bytesOut),
                                series: .value("Series", "Upload")
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.secondary.opacity(0.14), Color.secondary.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)

                            LineMark(
                                x: .value("Time", point.date),
                                y: .value("Upload", bytesOut),
                                series: .value("Series", "Upload")
                            )
                            .foregroundStyle(Color.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)

                            if points.count == 1 {
                                PointMark(
                                    x: .value("Time", point.date),
                                    y: .value("Upload", bytesOut)
                                )
                                .symbolSize(20)
                                .foregroundStyle(Color.secondary)
                            }
                        }

                        // Hover Highlight Indicators
                        if let hovered = hoveredPoint, hovered.id == point.id {
                            RuleMark(x: .value("Hovered", hovered.date))
                                .foregroundStyle(Color.primary.opacity(0.20))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                            if showDownload {
                                PointMark(
                                    x: .value("Time", hovered.date),
                                    y: .value("Download", Double(hovered.bytesIn))
                                )
                                .symbolSize(40)
                                .foregroundStyle(Color.accentColor)
                            }

                            if showUpload {
                                PointMark(
                                    x: .value("Time", hovered.date),
                                    y: .value("Upload", Double(hovered.bytesOut))
                                )
                                .symbolSize(32)
                                .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartYScale(domain: 0 ... maxBytes)
                .chartXAxis {
                    AxisMarks(values: .stride(by: xAxisComponent, count: xAxisStride)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel(format: timeframe == .daily ? .dateTime.hour() : .dateTime.month().day())
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                            .foregroundStyle(Color.primary.opacity(0.06))
                        AxisValueLabel {
                            if let byteValue = value.as(Double.self) {
                                Text(formatBytes(byteValue))
                                    .font(.system(size: 9))
                                    .monospacedDigit()
                                    .foregroundStyle(Color.secondary)
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let plotRect = geo[plotFrame]
                                    guard plotRect.contains(location) else {
                                        hoveredDate = nil
                                        return
                                    }

                                    // ChartProxy positions are relative to the plot area, while hover
                                    // locations are relative to the full chart including its axes.
                                    let plotX = location.x - plotRect.minX
                                    guard let date: Date = proxy.value(atX: plotX),
                                          let nearestPoint = points.min(by: {
                                              abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                          }) else { return }

                                    // Snap to a real bucket so the rule is exact and pointer motion
                                    // doesn't trigger a state update for every pixel.
                                    if hoveredDate != nearestPoint.date {
                                        hoveredDate = nearestPoint.date
                                    }
                                case .ended:
                                    hoveredDate = nil
                                }
                            }
                    }
                }
                .animation(.none, value: timeframe)

                if !hasAnyTraffic {
                    VStack(spacing: 5) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 15, weight: .medium))
                        Text("No activity recorded in this period")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 188)
        }
        .padding(16)
        .netCollectSurface()
        .onChange(of: timeframe) { _, _ in
            hoveredDate = nil
        }
    }

    private func formatBytes(_ bytes: Double) -> String {
        guard bytes.isFinite, bytes > 0 else { return "0 B" }
        return ByteCountFormatter.format(bytes: UInt64(bytes.rounded()))
    }
}
