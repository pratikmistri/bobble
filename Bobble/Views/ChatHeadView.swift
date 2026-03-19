import SwiftUI

struct ChatHeadView: View {
    let session: ChatSession
    let isExpanded: Bool
    let onTap: () -> Void
    var morphNamespace: Namespace.ID

    @State private var isHovering = false
    @State private var isShowingPreview = false
    @State private var statusBlink = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Main circle — participates in matchedGeometryEffect morph
            Circle()
                .fill(DesignTokens.surfaceAccent.opacity(0.95))
                .overlay(
                    Circle()
                        .strokeBorder(DesignTokens.borderColor, lineWidth: 1.2)
                )
                .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
                .matchedGeometryEffect(
                    id: session.id,
                    in: morphNamespace,
                    properties: .frame,
                    anchor: .bottomTrailing
                )
                .shadow(
                    color: .black.opacity(isHovering ? 0.26 : 0.16),
                    radius: isHovering ? 10 : DesignTokens.headShadowRadius,
                    y: isHovering ? 2 : DesignTokens.headShadowY
                )

            Circle()
                .fill(.white.opacity(isHovering ? 0.38 : 0.28))
                .frame(
                    width: DesignTokens.headDiameter * 0.48,
                    height: DesignTokens.headDiameter * 0.36
                )
                .blur(radius: 3)
                .offset(x: -10, y: -11)

            // Model-chosen chat marker
            Text(session.displayChatHeadSymbol)
                .font(DesignTokens.headInitialFont)
                .foregroundColor(DesignTokens.textPrimary)

            // Selection ring — animated stroke
            Circle()
                .stroke(DesignTokens.textSecondary.opacity(isExpanded ? 0.9 : 0), lineWidth: 3)
                .frame(
                    width: DesignTokens.headDiameter + (isExpanded ? 6 : 0),
                    height: DesignTokens.headDiameter + (isExpanded ? 6 : 0)
                )
                .scaleEffect(isExpanded ? 1 : 0.8)

            // Single top-right status indicator.
            if let status = statusIndicator {
                statusIndicatorView(for: status)
                    .offset(x: 18, y: -18)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // Hover: lift + scale
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .zIndex(isHovering || isShowingPreview ? 1000 : 0)
        .animation(DesignTokens.motionHover, value: isHovering)
        .animation(DesignTokens.motionLayout, value: isExpanded)
        .animation(DesignTokens.motionEntrance, value: isShowingPreview)
        .overlay(alignment: .leading) {
            if let preview = previewContent, isShowingPreview {
                ChatHeadPreviewBubble(
                    sessionName: session.name,
                    preview: preview
                )
                .offset(x: -(DesignTokens.headPreviewWidth + DesignTokens.headPreviewGap))
                .transition(
                    .scale(scale: 0.94, anchor: .trailing)
                        .combined(with: .opacity)
                )
                .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                schedulePreview()
            } else {
                dismissPreview()
            }
        }
        .onTapGesture {
            dismissPreview()
            onTap()
        }
        .onDisappear {
            dismissPreview()
        }
        .contextMenu {
            Text(session.name)
        }
    }

    private var statusIndicator: HeadStatus? {
        switch session.state {
        case .running:
            return .working
        case .error:
            return .needsHelp
        case .idle:
            return session.hasUnread ? .completed : nil
        }
    }

    private var previewContent: ChatHeadPreviewContent? {
        if let message = session.messages.reversed().first(where: shouldIncludeInPreview(_:)) {
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)

            if !trimmed.isEmpty {
                return ChatHeadPreviewContent(
                    senderLabel: senderLabel(for: message),
                    message: trimmed.replacingOccurrences(of: "\n", with: " ")
                )
            }

            if !message.attachments.isEmpty {
                return ChatHeadPreviewContent(
                    senderLabel: senderLabel(for: message),
                    message: attachmentSummary(for: message)
                )
            }
        }

        if case .running = session.state {
            return ChatHeadPreviewContent(
                senderLabel: "Live",
                message: "Working on your latest message..."
            )
        }

        return nil
    }

    private func shouldIncludeInPreview(_ message: ChatMessage) -> Bool {
        guard message.role != .system else { return false }
        return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !message.attachments.isEmpty
    }

    private func senderLabel(for message: ChatMessage) -> String {
        switch message.role {
        case .user:
            return "You"
        case .assistant:
            return "Assistant"
        case .error:
            return "Issue"
        case .system:
            return "System"
        }
    }

    private func attachmentSummary(for message: ChatMessage) -> String {
        let imageCount = message.attachments.filter(\.isImage).count
        let fileCount = message.attachments.count - imageCount

        if imageCount > 0 && fileCount > 0 {
            return "Shared \(imageCount) image\(imageCount == 1 ? "" : "s") and \(fileCount) file\(fileCount == 1 ? "" : "s")."
        }

        if imageCount > 0 {
            return "Shared \(imageCount) image\(imageCount == 1 ? "" : "s")."
        }

        return "Shared \(fileCount) file\(fileCount == 1 ? "" : "s")."
    }

    private func schedulePreview() {
        previewTask?.cancel()

        guard previewContent != nil else {
            isShowingPreview = false
            return
        }

        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard isHovering else { return }
                withAnimation(DesignTokens.motionEntrance) {
                    isShowingPreview = true
                }
            }
        }
    }

    private func dismissPreview() {
        previewTask?.cancel()
        previewTask = nil

        guard isShowingPreview else { return }
        withAnimation(DesignTokens.motionFade) {
            isShowingPreview = false
        }
    }

    @ViewBuilder
    private func statusIndicatorView(for status: HeadStatus) -> some View {
        switch status {
        case .working:
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
                .scaleEffect(statusBlink ? (4.0 / 12.0) : 1.0)
                .shadow(color: status.color.opacity(0.7), radius: 7)
                .id("status-working")
                .onAppear { startStatusBlink() }
                .onDisappear { stopStatusBlink() }

        case .needsHelp, .completed:
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
                .shadow(color: status.color.opacity(0.35), radius: 3)
                .id("status-\(String(describing: status))")
                .transaction { transaction in
                    transaction.animation = nil
                }
                .onAppear { stopStatusBlink() }
        }
    }

    private func startStatusBlink() {
        statusBlink = false
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            statusBlink = true
        }
    }

    private func stopStatusBlink() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            statusBlink = false
        }
    }
}

private struct ChatHeadPreviewContent {
    let senderLabel: String
    let message: String
}

private struct ChatHeadPreviewBubble: View {
    let sessionName: String
    let preview: ChatHeadPreviewContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(sessionName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(preview.senderLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
                    .lineLimit(1)
            }

            Text(preview.message)
                .font(.system(size: 12))
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(width: DesignTokens.headPreviewWidth, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignTokens.surfaceColor.opacity(0.98))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DesignTokens.borderColor.opacity(0.9), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}

private enum HeadStatus: Equatable {
    case working
    case needsHelp
    case completed

    var color: Color {
        switch self {
        case .working:
            return .green
        case .needsHelp:
            return .orange
        case .completed:
            return .green
        }
    }
}
