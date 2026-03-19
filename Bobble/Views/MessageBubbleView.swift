import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let index: Int

    @State private var appeared = false
    @State private var cursorVisible = true

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text(message.content)
                        .font(DesignTokens.messageFont)
                        .foregroundColor(foregroundColor)
                        .textSelection(.enabled)

                    // Animated streaming cursor
                    if message.isStreaming {
                        Text(" |")
                            .font(DesignTokens.messageFont)
                            .foregroundColor(foregroundColor.opacity(cursorVisible ? 1 : 0.2))
                            .onAppear {
                                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                                    cursorVisible.toggle()
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.messageBubbleRadius))
            }

            if message.role != .user {
                Spacer(minLength: 40)
            }
        }
        // Entrance animation — slide up from role direction
        .offset(
            x: appeared ? 0 : (message.role == .user ? 12 : -12),
            y: appeared ? 0 : 8
        )
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
        .onAppear {
            let delay = message.isStreaming ? 0.0 : min(Double(index) * 0.04, 0.2)
            withAnimation(DesignTokens.motionEntrance.delay(delay)) {
                appeared = true
            }
        }
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return DesignTokens.userBubbleColor
        case .assistant:
            return DesignTokens.assistantBubbleColor
        case .system:
            return DesignTokens.surfaceAccent.opacity(0.5)
        case .error:
            return Color.red.opacity(0.15)
        }
    }

    private var foregroundColor: Color {
        switch message.role {
        case .user:
            return DesignTokens.textPrimary
        case .assistant:
            return DesignTokens.textPrimary
        case .system:
            return DesignTokens.textSecondary
        case .error:
            return .red
        }
    }
}
