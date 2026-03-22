import SwiftUI

struct ChatContentView: View {
    let session: ChatSession
    @ObservedObject var viewModel: ChatSessionViewModel
    let showProviderBadge: Bool
    let onClose: () -> Void
    let onMarkRead: () -> Void
    let onArchive: () -> Void

    private let typingIndicatorID = "typing-indicator"

    @State private var headerAppeared = false
    @State private var contentAppeared = false

    private var chronologicalMessages: [ChatMessage] {
        viewModel.session.messages.sorted { lhs, rhs in
            if lhs.timestamp != rhs.timestamp {
                return lhs.timestamp < rhs.timestamp
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var activeStreamingAssistantMessage: ChatMessage? {
        chronologicalMessages.last(where: { $0.role == .assistant && $0.isStreaming })
    }

    private var shouldShowTypingIndicatorPlaceholder: Bool {
        guard case .running = viewModel.session.state else { return false }
        return activeStreamingAssistantMessage == nil
    }

    private var bottomScrollTarget: AnyHashable? {
        if shouldShowTypingIndicatorPlaceholder {
            return AnyHashable(typingIndicatorID)
        }

        return chronologicalMessages.last.map { AnyHashable($0.id) }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        guard let target = bottomScrollTarget else { return }

        DispatchQueue.main.async {
            if animated {
                withAnimation(DesignTokens.motionScroll) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(DesignTokens.surfaceAccent)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Text(viewModel.session.displayChatHeadSymbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.textPrimary)
                    )

                Text(viewModel.session.name)
                    .font(DesignTokens.headerFont)
                    .foregroundColor(DesignTokens.textPrimary)
                    .lineLimit(1)

                if showProviderBadge {
                    ProviderBadgeView(provider: viewModel.session.provider)
                }

                Spacer()

                Button(action: onArchive) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.textSecondary)
                }
                .buttonStyle(HoverScaleButtonStyle())

                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(DesignTokens.textSecondary)
                }
                .buttonStyle(HoverScaleButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .offset(y: headerAppeared ? 0 : -8)
            .opacity(headerAppeared ? 1 : 0)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(chronologicalMessages.enumerated()), id: \.element.id) { index, message in
                            MessageBubbleView(
                                message: message,
                                index: index,
                                onInterruptionAction: { action in
                                    viewModel.handleInterruptionAction(action)
                                }
                            )
                                .id(message.id)
                        }

                        if shouldShowTypingIndicatorPlaceholder {
                            TypingIndicatorBubbleView()
                                .id(typingIndicatorID)
                        }
                    }
                    .padding(12)
                }
                .onAppear {
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: session.id) {
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: viewModel.session.messages.count) {
                    scrollToBottom(using: proxy, animated: true)
                }
                .onChange(of: shouldShowTypingIndicatorPlaceholder) {
                    guard shouldShowTypingIndicatorPlaceholder else { return }
                    scrollToBottom(using: proxy, animated: true)
                }
            }
            .opacity(contentAppeared ? 1 : 0)
            .offset(y: contentAppeared ? 0 : 12)

            Divider()

            // Input bar
            InputBarView(viewModel: viewModel, showProviderBadge: showProviderBadge)
                .offset(y: contentAppeared ? 0 : 8)
                .opacity(contentAppeared ? 1 : 0)
        }
        .foregroundColor(DesignTokens.textPrimary)
        .onAppear {
            onMarkRead()
            withAnimation(DesignTokens.motionFade.delay(0.06)) {
                headerAppeared = true
            }
            withAnimation(DesignTokens.motionEntrance.delay(0.1)) {
                contentAppeared = true
            }
        }
    }
}

// Reusable micro-interaction for buttons
struct HoverScaleButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : (isHovering ? 1.06 : 1.0))
            .animation(DesignTokens.motionPress, value: configuration.isPressed)
            .animation(DesignTokens.motionHover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}
