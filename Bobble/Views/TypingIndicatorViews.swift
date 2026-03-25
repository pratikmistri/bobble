import SwiftUI

struct TypingIndicatorBubbleView: View {
    @State private var appeared = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                TypingIndicatorDotsView(dotColor: DesignTokens.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(DesignTokens.assistantBubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.messageBubbleRadius))
            }

            Spacer(minLength: 40)
        }
        .offset(x: appeared ? 0 : -12, y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: .bottomLeading)
        .onAppear {
            withAnimation(DesignTokens.motionEntrance) {
                appeared = true
            }
        }
    }
}

struct TypingIndicatorDotsView: View {
    let dotColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycleDuration = 2.1

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (time / cycleDuration) * (.pi * 2) - (Double(index) * 0.55)
                    let wave = (sin(phase) + 1) / 2

                    Circle()
                        .fill(dotColor.opacity(0.32 + (wave * 0.6)))
                        .frame(width: 6, height: 6)
                        .scaleEffect(0.82 + (wave * 0.28))
                        .offset(y: -1.5 * wave)
                        .blur(radius: 0.15 + ((1 - wave) * 0.35))
                }
            }
            .frame(height: 14)
        }
    }
}
