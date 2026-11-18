import SwiftUI

enum NetCollectDesign {
    static let accent = Color.accentColor
    static let cardRadius: CGFloat = 14
    static let contentPadding: CGFloat = 22
}

extension View {
    func netCollectSurface() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: NetCollectDesign.cardRadius))
            .overlay {
                RoundedRectangle(cornerRadius: NetCollectDesign.cardRadius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }

    @ViewBuilder
    func netCollectProminentButton() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}
