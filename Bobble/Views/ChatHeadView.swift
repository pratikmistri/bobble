import SwiftUI

struct ChatHeadView: View {
    let session: ChatSession
    let isExpanded: Bool
    let onTap: () -> Void
    var morphNamespace: Namespace.ID

    @State private var isHovering = false
    @State private var statusBlink = false

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

            // Initial letter
            Text(session.initial)
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
                Circle()
                    .fill(status.color)
                    .frame(width: 12, height: 12)
                    .scaleEffect(status == .working ? (statusBlink ? (4.0 / 12.0) : 1.0) : 1.0)
                    .shadow(color: status.color.opacity(status == .working ? 0.7 : 0.35), radius: status == .working ? 7 : 3)
                    .offset(x: 18, y: -18)
                    .transition(.scale.combined(with: .opacity))
                    .onAppear { updateStatusBlink(for: status) }
                    .onDisappear { statusBlink = false }
            }
        }
        // Hover: lift + scale
        .scaleEffect(isHovering ? 1.04 : 1.0)
        .animation(DesignTokens.motionHover, value: isHovering)
        .animation(DesignTokens.motionLayout, value: isExpanded)
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            onTap()
        }
        .onChange(of: statusIndicator) { _, newStatus in
            updateStatusBlink(for: newStatus)
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
            let hasCompletedReply = session.messages.contains {
                $0.role == .assistant && !$0.isStreaming && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return hasCompletedReply ? .completed : nil
        }
    }

    private func updateStatusBlink(for status: HeadStatus?) {
        guard status == .working else {
            statusBlink = false
            return
        }
        statusBlink = false
        withAnimation(.easeInOut(duration: 0.65).repeatForever(autoreverses: true)) {
            statusBlink = true
        }
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
