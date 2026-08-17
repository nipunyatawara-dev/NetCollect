import SwiftUI

/// Custom Apple-style segmented picker with smooth spring animation, high contrast, and reliable hit testing.
public struct TimeframeSegmentPicker: View {
    @Binding var selected: TimeframeFilter
    @Namespace private var animationNamespace

    public init(selected: Binding<TimeframeFilter>) {
        self._selected = selected
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(TimeframeFilter.allCases) { timeframe in
                let isSelected = selected == timeframe
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        selected = timeframe
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: timeframe.iconName)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        Text(timeframe.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundColor(isSelected ? .white : .primary.opacity(0.75))
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.accentColor)
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 1)
                                .matchedGeometryEffect(id: "ActiveTimeframeTab", in: animationNamespace)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}
