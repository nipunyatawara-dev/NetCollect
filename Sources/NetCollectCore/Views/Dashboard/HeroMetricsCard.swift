import SwiftUI

/// A usage summary with a numeric transition when the displayed period changes.
public struct HeroMetricsCard: View {
    public let title: String
    public let value: String
    public let subtitle: String
    public let iconName: String
    public let accentColor: Color
    public let isProminent: Bool
    private let bytes: UInt64
    private let timeframe: TimeframeFilter?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        value: String,
        subtitle: String,
        iconName: String,
        accentColor: Color,
        isProminent: Bool = false,
        bytes: UInt64 = 0,
        timeframe: TimeframeFilter? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.iconName = iconName
        self.accentColor = accentColor
        self.isProminent = isProminent
        self.bytes = bytes
        self.timeframe = timeframe
    }

    public var body: some View {
        let unit = value.split(separator: " ").last
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 27, height: 27)
                    .background(accentColor.opacity(isProminent ? 0.16 : 0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: isProminent ? 25 : 22, weight: .bold, design: .rounded))
                    .tracking(-0.45)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(bytes)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: timeframe)
                    // Replacing the text on a unit change prevents the old unit
                    // and new digits from ever appearing together.
                    .id(unit)
                    .keyframeAnimator(initialValue: 1.0, trigger: unit) { text, opacity in
                        text.opacity(opacity)
                    } keyframes: { _ in
                        MoveKeyframe(reduceMotion ? 1 : 0.7)
                        LinearKeyframe(1, duration: 0.18)
                    }

                Text(subtitle.isEmpty ? " " : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(subtitle.isEmpty)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .netCollectSurface()
    }
}
