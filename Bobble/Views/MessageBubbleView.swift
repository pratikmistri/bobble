import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let index: Int
    let onInterruptionAction: ((ChatMessage.InterruptionAction) -> Void)?

    @State private var appeared = false
    @State private var isExpanded = false

    init(
        message: ChatMessage,
        index: Int,
        onInterruptionAction: ((ChatMessage.InterruptionAction) -> Void)? = nil
    ) {
        self.message = message
        self.index = index
        self.onInterruptionAction = onInterruptionAction
    }

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                    if !message.attachments.isEmpty {
                        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                            if !imageAttachments.isEmpty {
                                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                                    ForEach(imageAttachments) { attachment in
                                        ImageAttachmentPreviewView(attachment: attachment)
                                    }
                                }
                            }

                            if !fileAttachments.isEmpty {
                                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                                    ForEach(fileAttachments) { attachment in
                                        DocumentAttachmentPreviewView(attachment: attachment)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 220, alignment: bubbleAlignment)
                    }

                    if !message.content.isEmpty || message.isStreaming {
                        MessageBubbleContentView(
                            message: message,
                            foregroundColor: foregroundColor,
                            isCollapsed: isCollapsed,
                            onInterruptionAction: onInterruptionAction
                        )
                            .foregroundColor(foregroundColor)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.messageBubbleRadius))
                .onTapGesture {
                    guard canToggle else { return }
                    withAnimation(DesignTokens.motionPress) {
                        isExpanded.toggle()
                    }
                }

                if canToggle {
                    Button(action: {
                        withAnimation(DesignTokens.motionPress) {
                            isExpanded.toggle()
                        }
                    }) {
                        Text(isExpanded ? "Show less" : "Show more")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
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

    private var imageAttachments: [ChatAttachment] {
        message.attachments.filter(\.isImage)
    }

    private var fileAttachments: [ChatAttachment] {
        message.attachments.filter { !$0.isImage }
    }

    private var bubbleAlignment: Alignment {
        message.role == .user ? .trailing : .leading
    }

    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return DesignTokens.userBubbleColor
        case .assistant:
            return DesignTokens.assistantBubbleColor
        case .system:
            return message.isInterruptionCard
                ? DesignTokens.surfaceAccent.opacity(0.28)
                : DesignTokens.surfaceAccent.opacity(0.5)
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
            return message.isInterruptionCard ? DesignTokens.textPrimary : DesignTokens.textSecondary
        case .error:
            return .red
        }
    }

    private var canToggle: Bool {
        shouldCollapseByDefault && isLikelyToWrap
    }

    private var isCollapsed: Bool {
        shouldCollapseByDefault && !isExpanded
    }

    private var shouldCollapseByDefault: Bool {
        message.kind == .toolUse
    }

    private var isLikelyToWrap: Bool {
        let newlineCount = message.content.filter { $0 == "\n" }.count
        return newlineCount >= 2 || message.content.count > 120
    }
}
