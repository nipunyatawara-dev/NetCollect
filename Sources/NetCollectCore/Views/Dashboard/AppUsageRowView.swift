import SwiftUI
import AppKit

/// A sleek, Apple-designed row displaying network usage for an application.
public struct AppUsageRowView: View {
    public let record: AppUsageRecord
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    public init(record: AppUsageRecord) {
        self.record = record
    }

    private var appIcon: NSImage {
        AppResolver.shared.icon(
            for: record.bundleId,
            appPath: record.appPath,
            isSystem: record.isSystemProcess
        )
    }

    public var body: some View {
        HStack(spacing: 14) {
            // App Icon
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

            // App Name & Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if record.isSystemProcess {
                        Text("System")
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(Color.secondary.opacity(0.15))
                            )
                            .foregroundColor(.secondary)
                    }
                }

                Text(record.bundleId)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.secondary.opacity(0.8))
                    .lineLimit(1)
            }
            .frame(minWidth: 140, alignment: .leading)

            Spacer(minLength: 12)

            // Usage Progress Meter
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    // Meter Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 6)

                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(4, geo.size.width * CGFloat(min(1.0, record.percentage))), height: 6)
                                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 1), value: record.percentage)
                        }
                    }
                    .frame(width: 80, height: 6)

                    // Percentage Text
                    Text(record.percentageString)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                // Download & Upload Breakdown
                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.accentColor)
                        Text(record.formattedIn)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                        Text(record.formattedOut)
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Total Data Badge
            VStack(alignment: .trailing, spacing: 2) {
                Text(record.formattedTotal)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)

                Text("total")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .frame(width: 75, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isHovered ? Color.white.opacity(0.1) : Color.clear, lineWidth: 0.5)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 1)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            if let path = record.appPath, FileManager.default.fileExists(atPath: path) {
                Button {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.bundleId, forType: .string)
            } label: {
                Label("Copy Bundle ID", systemImage: "doc.on.doc")
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.appName, forType: .string)
            } label: {
                Label("Copy Application Name", systemImage: "textformat")
            }
        }
    }
}
