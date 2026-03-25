import SwiftUI

struct MessageBubbleContentView: View {
    let message: ChatMessage
    let foregroundColor: Color
    let isCollapsed: Bool
    let cursorVisible: Bool
    let onInterruptionAction: ((ChatMessage.InterruptionAction) -> Void)?

    var body: some View {
        if message.isInterruptionCard {
            interruptionCardContent
        } else if shouldShowTypingIndicator {
            TypingIndicatorDotsView(dotColor: foregroundColor)
        } else if shouldUsePlainText {
            bubbleText
                .font(DesignTokens.messageFont)
                .lineLimit(isCollapsed ? 2 : nil)
                .multilineTextAlignment(message.role == .user ? .trailing : .leading)
        } else {
            MarkdownMessageView(markdown: message.content)
        }
    }

    private var interruptionCardTitle: String {
        message.interruptionCardTitle ?? "Update"
    }

    private var interruptionCardIconName: String {
        switch message.kind {
        case .permission:
            return "shield.lefthalf.filled"
        case .question:
            return "questionmark.circle.fill"
        case .regular, .agentThought, .toolUse:
            return "exclamationmark.bubble.fill"
        }
    }

    private var interruptionCardAccentColor: Color {
        switch message.kind {
        case .permission:
            return DesignTokens.surfaceAccent
        case .question:
            return DesignTokens.textSecondary
        case .regular, .agentThought, .toolUse:
            return DesignTokens.surfaceAccent
        }
    }

    private var interruptionCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: interruptionCardIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(interruptionCardAccentColor)
                    .frame(width: 18, height: 18, alignment: .leading)

                Text(interruptionCardTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignTokens.textPrimary)

                Text(message.interruptionCardBody)
                    .font(DesignTokens.messageFont)
                    .foregroundColor(DesignTokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            if !message.interruptionActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.interruptionActions) { action in
                        Button(action: {
                            onInterruptionAction?(action)
                        }) {
                            Text(action.title)
                                .font(.system(size: 11, weight: .semibold))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .foregroundColor(actionForegroundColor(for: action))
                                .background(actionBackground(for: action))
                                .overlay(actionBorder(for: action))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(onInterruptionAction == nil)
                        .opacity(onInterruptionAction == nil ? 0.55 : 1)
                    }
                }
            }
        }
    }

    private func actionForegroundColor(for action: ChatMessage.InterruptionAction) -> Color {
        switch action.role {
        case .primary:
            return DesignTokens.textPrimary
        case .secondary:
            return DesignTokens.textSecondary
        case .destructive:
            return .red
        }
    }

    private func actionBackground(for action: ChatMessage.InterruptionAction) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                action.role == .primary
                    ? DesignTokens.surfaceAccent.opacity(0.55)
                    : Color.clear
            )
    }

    private func actionBorder(for action: ChatMessage.InterruptionAction) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .stroke(
                action.role == .primary ? Color.clear : DesignTokens.borderColor.opacity(0.85),
                lineWidth: 1
            )
    }

    private var bubbleText: Text {
        let base = Text(message.content)
        if message.isStreaming {
            return base + Text(" |").foregroundColor(foregroundColor.opacity(cursorVisible ? 1 : 0.2))
        }
        return base
    }

    private var shouldUsePlainText: Bool {
        message.isStreaming || isCollapsed
    }

    private var shouldShowTypingIndicator: Bool {
        message.role == .assistant
            && message.isStreaming
            && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
