import SwiftUI
#if os(macOS)
import AppKit
#endif

enum DesignTokens {
    // Sizes
    static let headDiameter: CGFloat = 50
    static let headSpacing: CGFloat = 8
    static let headInset: CGFloat = 14 // extra space around heads for hover scale, shadows, indicators
    static let headVisualPadding: CGFloat = 8 // extra per-head render room for blur/shadow
    static let headPreviewWidth: CGFloat = 220
    static let headPreviewGap: CGFloat = 14
    static let headPreviewOverflow: CGFloat = 250
    static let deckOffset: CGFloat = 14
    static let screenMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 16
    static let messageBubbleRadius: CGFloat = 14
    static let inputBarHeight: CGFloat = 44

    // Colors — theme-aware:
    // light: cream/off-white, dark: warm black/gray.
    #if os(macOS)
    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let best = appearance.bestMatch(from: [.aqua, .darkAqua])
                return best == .darkAqua ? dark : light
            }
        )
    }
    #endif

    static let surfaceColor = dynamicColor(
        light: NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1),
        dark: NSColor(calibratedRed: 0.13, green: 0.11, blue: 0.10, alpha: 1)
    )
    static let surfaceElevated = dynamicColor(
        light: NSColor(calibratedRed: 0.94, green: 0.90, blue: 0.85, alpha: 1),
        dark: NSColor(calibratedRed: 0.17, green: 0.15, blue: 0.13, alpha: 1)
    )
    static let surfaceAccent = dynamicColor(
        light: NSColor(calibratedRed: 0.90, green: 0.85, blue: 0.78, alpha: 1),
        dark: NSColor(calibratedRed: 0.21, green: 0.18, blue: 0.16, alpha: 1)
    )
    static let borderColor = dynamicColor(
        light: NSColor(calibratedRed: 0.85, green: 0.80, blue: 0.74, alpha: 1),
        dark: NSColor(calibratedRed: 0.24, green: 0.21, blue: 0.18, alpha: 1)
    )
    static let textPrimary = dynamicColor(
        light: NSColor(calibratedRed: 0.19, green: 0.16, blue: 0.14, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.91, blue: 0.87, alpha: 1)
    )
    static let textSecondary = dynamicColor(
        light: NSColor(calibratedRed: 0.43, green: 0.39, blue: 0.35, alpha: 1),
        dark: NSColor(calibratedRed: 0.76, green: 0.71, blue: 0.65, alpha: 1)
    )
    static let liquidGlassTint = dynamicColor(
        light: NSColor(calibratedRed: 0.96, green: 0.98, blue: 1.00, alpha: 0.22),
        dark: NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.00, alpha: 0.16)
    )
    static let liquidGlassGlow = dynamicColor(
        light: NSColor(calibratedRed: 0.90, green: 0.95, blue: 1.00, alpha: 0.16),
        dark: NSColor(calibratedRed: 0.78, green: 0.88, blue: 1.00, alpha: 0.12)
    )
    static let liquidGlassBorder = dynamicColor(
        light: NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 0.78),
        dark: NSColor(calibratedRed: 0.88, green: 0.93, blue: 1.00, alpha: 0.58)
    )
    static let liquidGlassShadow = dynamicColor(
        light: NSColor(calibratedRed: 0.73, green: 0.82, blue: 0.93, alpha: 0.18),
        dark: NSColor(calibratedRed: 0.82, green: 0.90, blue: 1.00, alpha: 0.10)
    )

    static let userBubbleColor = surfaceAccent
    static let assistantBubbleColor = surfaceElevated
    static let addButtonColor = surfaceElevated

    // Shadows
    static let headShadowRadius: CGFloat = 4
    static let headShadowY: CGFloat = 2
    static let panelShadowRadius: CGFloat = 12

    // Motion — intent-based system:
    // smooth defaults for layout/content, playful spring only on selected accents.
    static let motionLayout = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.34)
    static let motionEntrance = Animation.timingCurve(0.2, 0.9, 0.2, 1.0, duration: 0.3)
    static let motionFade = Animation.easeOut(duration: 0.22)
    static let motionHover = Animation.easeOut(duration: 0.18)
    static let motionPress = Animation.spring(response: 0.2, dampingFraction: 0.82)
    static let motionPlayful = Animation.spring(response: 0.38, dampingFraction: 0.72)
    static let motionScroll = Animation.easeOut(duration: 0.24)

    // Legacy aliases
    static let springSnappy = motionEntrance
    static let springBouncy = motionPlayful
    static let springGentle = motionLayout
    static let springMicro = motionPress
    static let springAnimation = motionEntrance

    // Fonts
    static let headInitialFont = Font.system(size: 20, weight: .semibold)
    static let messageFont = Font.system(size: 13)
    static let inputFont = Font.system(size: 13)
    static let headerFont = Font.system(size: 14, weight: .semibold)
}

struct ThinLiquidGlassBackground<S: InsettableShape>: View {
    let shape: S
    var emphasized: Bool = false
    var isActive: Bool = false

    private var fillOpacity: Double {
        switch (emphasized, isActive) {
        case (true, true): return 0.28
        case (true, false): return 0.22
        case (false, true): return 0.22
        case (false, false): return 0.16
        }
    }

    private var glowOpacity: Double {
        switch (emphasized, isActive) {
        case (true, true): return 0.22
        case (true, false): return 0.16
        case (false, true): return 0.16
        case (false, false): return 0.1
        }
    }

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.24 : 0.18),
                            DesignTokens.liquidGlassTint.opacity(fillOpacity),
                            DesignTokens.liquidGlassGlow.opacity(glowOpacity)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isActive ? 0.92 : 0.72),
                            DesignTokens.liquidGlassBorder.opacity(emphasized ? 0.92 : 0.76)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: emphasized ? 1.2 : 1
                )
            }
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(Color.white.opacity(isActive ? 0.34 : 0.24))
                    .scaleEffect(x: 0.72, y: 0.34, anchor: .center)
                    .blur(radius: 7)
                    .offset(x: -10, y: -8)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: DesignTokens.liquidGlassShadow.opacity(isActive ? 0.28 : 0.18),
                radius: isActive ? 10 : 6,
                y: isActive ? 2 : 1
            )
    }
}

struct ThinLiquidGlassButtonStyle<S: InsettableShape>: ButtonStyle {
    let shape: S
    var emphasized: Bool = false
    var hoverScale: CGFloat = 1.04
    var pressedScale: CGFloat = 0.96

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        let isActive = isHovering || configuration.isPressed

        return configuration.label
            .contentShape(shape)
            .background(
                ThinLiquidGlassBackground(
                    shape: shape,
                    emphasized: emphasized,
                    isActive: isActive
                )
            )
            .scaleEffect(configuration.isPressed ? pressedScale : (isHovering ? hoverScale : 1.0))
            .animation(DesignTokens.motionPress, value: configuration.isPressed)
            .animation(DesignTokens.motionHover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}
