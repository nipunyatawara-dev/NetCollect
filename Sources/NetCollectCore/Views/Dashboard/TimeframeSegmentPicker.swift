import SwiftUI

/// Compact period selector used where a sidebar is not available.
public struct TimeframeSegmentPicker: View {
    @Binding var selected: TimeframeFilter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var animationNamespace

    public init(selected: Binding<TimeframeFilter>) {
        self._selected = selected
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(TimeframeFilter.allCases) { timeframe in
                let isSelected = selected == timeframe

                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.9)) {
                        selected = timeframe
                    }
                } label: {
                    Text(timeframe.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 9)
                        .frame(height: 27)
                        .background(
                            isSelected ?
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1) :
                            nil
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(NetCollectPressStyle())
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Usage period")
    }
}
