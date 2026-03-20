import SwiftUI

struct FloatingControlCircle<Content: View>: View {
    let isHighlighted: Bool
    let content: Content

    init(
        isHighlighted: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isHighlighted = isHighlighted
        self.content = content()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.addButtonColor.opacity(0.95))
                .overlay(
                    Circle()
                        .strokeBorder(
                            DesignTokens.borderColor.opacity(isHighlighted ? 0.95 : 0.85),
                            lineWidth: 1.2
                        )
                )

            content
        }
        .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
        .shadow(
            color: .black.opacity(isHighlighted ? 0.18 : 0.12),
            radius: isHighlighted ? 8 : DesignTokens.headShadowRadius,
            y: isHighlighted ? 3 : DesignTokens.headShadowY
        )
    }
}
