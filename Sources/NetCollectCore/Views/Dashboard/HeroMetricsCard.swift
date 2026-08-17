import SwiftUI

/// A restrained summary card with stable numeric typography and immediate pointer feedback.
public struct HeroMetricsCard: View {
    public let title: String
    public let value: String
    public let subtitle: String
    public let iconName: String
    public let accentColor: Color
    public let isProminent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    public init(
        title: String,
        value: String,
        subtitle: String,
        iconName: String,
        accentColor: Color,
        isProminent: Bool = false
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.iconName = iconName
        self.accentColor = accentColor
        self.isProminent = isProminent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.65)
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
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            if isProminent {
                RoundedRectangle(cornerRadius: NetCollectDesign.cardRadius, style: .continuous)
                    .fill(accentColor.opacity(0.055))
            }
        }
        .netCollectSurface()
        .offset(y: isHovered && !reduceMotion ? -2 : 0)
        .animation(.spring(response: 0.32, dampingFraction: 1), value: isHovered)
        .onHover { isHovered = $0 }
    }
}
