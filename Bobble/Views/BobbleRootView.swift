import SwiftUI

struct BobbleRootView: View {
    @ObservedObject var manager: ChatHeadsManager
    let onHeadTapped: (ChatSession) -> Void
    let onClose: () -> Void
    let onAddSession: () -> Void
    let onHeadsDragChanged: () -> Void
    let onHeadsDragEnded: () -> Void

    @Namespace private var morphNamespace
    @State private var isHoveringAdd = false

    private let chatWidth: CGFloat = 320
    private let chatHeight: CGFloat = 480

    private var isExpanded: Bool { manager.expandedSessionId != nil }
    private var headVisualPadding: CGFloat { DesignTokens.headVisualPadding }

    /// Sessions visible as heads (excludes the one morphed into the window).
    private var visibleSessions: [ChatSession] {
        manager.sessions.filter { $0.id != manager.expandedSessionId }
    }

    private var headsFrameHeight: CGFloat {
        let count = visibleSessions.count
        guard count > 0 else { return 0 }
        if isExpanded {
            return DesignTokens.headDiameter + CGFloat(count - 1) * DesignTokens.deckOffset
        } else {
            return CGFloat(count) * DesignTokens.headDiameter
                + CGFloat(count - 1) * DesignTokens.headSpacing
        }
    }

    private var headsRenderHeight: CGFloat {
        headsFrameHeight + (headVisualPadding * 2)
    }

    private var headsRenderWidth: CGFloat {
        DesignTokens.headDiameter + (headVisualPadding * 2)
    }

    private func headYOffset(for index: Int) -> CGFloat {
        let base = isExpanded
            ? CGFloat(index) * DesignTokens.deckOffset
            : CGFloat(index) * (DesignTokens.headDiameter + DesignTokens.headSpacing)
        return base + headVisualPadding
    }

    private var headsDragGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { _ in
                onHeadsDragChanged()
            }
            .onEnded { _ in
                onHeadsDragEnded()
            }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // MARK: – Chat window (above heads, expands upward into the screen)
            if let sessionId = manager.expandedSessionId,
               let session = manager.sessions.first(where: { $0.id == sessionId }),
               let viewModel = manager.viewModel(for: sessionId) {

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)

                    ZStack {
                        // Background — matchedGeometryEffect morphs the head circle into this rect
                        RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                            .fill(DesignTokens.surfaceColor)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius)
                                    .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
                            )
                            .matchedGeometryEffect(
                                id: session.id,
                                in: morphNamespace,
                                properties: .frame,
                                anchor: .bottomTrailing
                            )

                        // Chat content
                        ChatContentView(
                            session: session,
                            viewModel: viewModel,
                            showProviderBadge: manager.hasMixedProviders,
                            onClose: onClose,
                            onMarkRead: { manager.markRead(sessionId: sessionId) },
                            onRemove: {
                                withAnimation(DesignTokens.motionLayout) {
                                    manager.removeSession(session)
                                }
                            }
                        )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                    .shadow(color: .black.opacity(0.15), radius: DesignTokens.panelShadowRadius)
                    .frame(width: chatWidth, height: chatHeight)
                }
            }

            // MARK: – Heads section (anchored at bottom-right of screen)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)

                VStack(spacing: DesignTokens.headSpacing) {
                    addButton

                    if !visibleSessions.isEmpty {
                        ZStack(alignment: .top) {
                            ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
                                ChatHeadView(
                                    session: session,
                                    showProviderBadge: manager.hasMixedProviders,
                                    isExpanded: false,
                                    onTap: { onHeadTapped(session) },
                                    morphNamespace: morphNamespace
                                )
                                .offset(y: headYOffset(for: index))
                                .zIndex(Double(visibleSessions.count - index))
                            }
                        }
                        // Reserve extra render room so blur/shadows are not clipped at stack edges.
                        .frame(width: headsRenderWidth, height: headsRenderHeight, alignment: .top)
                        .animation(DesignTokens.motionLayout, value: isExpanded)
                        .animation(DesignTokens.motionLayout, value: visibleSessions.count)
                    }
                }
                .padding(DesignTokens.headInset)
                .contentShape(Rectangle())
                .simultaneousGesture(headsDragGesture)
            }
        }
        // Keep heads anchored to the panel corner during expand/collapse so motion stays continuous.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    // MARK: – Add button
    private var addButton: some View {
        ZStack {
            Circle()
                .fill(DesignTokens.addButtonColor.opacity(0.95))
                .overlay(
                    Circle()
                        .strokeBorder(DesignTokens.borderColor, lineWidth: 1.2)
                )
                .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
                .shadow(
                    color: .black.opacity(isHoveringAdd ? 0.24 : 0.14),
                    radius: isHoveringAdd ? 10 : DesignTokens.headShadowRadius,
                    y: isHoveringAdd ? 2 : DesignTokens.headShadowY
                )

            Circle()
                .fill(.white.opacity(isHoveringAdd ? 0.34 : 0.26))
                .frame(
                    width: DesignTokens.headDiameter * 0.48,
                    height: DesignTokens.headDiameter * 0.34
                )
                .blur(radius: 3)
                .offset(x: -9, y: -12)

            Image(systemName: "plus")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .scaleEffect(isHoveringAdd ? 1.08 : 1.0)
        .animation(DesignTokens.motionHover, value: isHoveringAdd)
        .onHover { hovering in
            isHoveringAdd = hovering
        }
        .onTapGesture {
            onAddSession()
        }
    }
}
