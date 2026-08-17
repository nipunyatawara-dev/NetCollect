import SwiftUI

enum NetCollectDesign {
    static let accent = Color.accentColor
    static let positive = Color(red: 0.20, green: 0.72, blue: 0.43)
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 9
    static let contentPadding: CGFloat = 24
}

struct NetCollectBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
            .ignoresSafeArea()
    }
}

struct NetCollectSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    } else {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.62), lineWidth: 0.75)
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.055), radius: 16, x: 0, y: 7)
            }
    }
}

extension View {
    func netCollectSurface(radius: CGFloat = NetCollectDesign.cardRadius) -> some View {
        modifier(NetCollectSurface(radius: radius))
    }
}

struct NetCollectPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? .linear(duration: 0.08) : .spring(response: 0.22, dampingFraction: 1),
                value: configuration.isPressed
            )
    }
}

struct LiveStatusDot: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? NetCollectDesign.positive : Color.secondary.opacity(0.45))
            .frame(width: 7, height: 7)
            .overlay {
                Circle()
                    .stroke((isActive ? NetCollectDesign.positive : Color.clear).opacity(0.28), lineWidth: 4)
            }
            .accessibilityHidden(true)
    }
}
