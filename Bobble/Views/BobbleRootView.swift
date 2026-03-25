import SwiftUI

struct BobbleRootView: View {
    @ObservedObject var manager: ChatHeadsManager
    let onHeadTapped: (ChatSession) -> Void
    let onClose: () -> Void
    let onArchiveSession: (ChatSession) -> Void
    let onOpenHistorySession: (ChatSession) -> Void
    let onDeleteHistorySession: (ChatSession) -> Void
    let onAddSession: () -> Void
    let onHeadsDragChanged: () -> Void
    let onHeadsDragEnded: () -> Void

    @Namespace private var morphNamespace
    @State private var isShowingHistory = false
    @State private var pendingHistorySessionToOpen: ChatSession?

    private let chatWidth: CGFloat = 320
    private let chatHeight: CGFloat = 480
    private let previewOverflow: CGFloat = DesignTokens.headPreviewOverflow

    private var isExpanded: Bool { manager.expandedSessionId != nil }
    private var dockSide: PanelDockSide { manager.panelDockSide }
    private var headVisualPadding: CGFloat { DesignTokens.headVisualPadding }

    private var expandedSession: ChatSession? {
        guard let id = manager.expandedSessionId else { return nil }
        return manager.sessions.first(where: { $0.id == id })
    }

    private var expandedSessionIndex: Int? {
        guard let id = manager.expandedSessionId else { return nil }
        return manager.sessions.firstIndex(where: { $0.id == id })
    }

    private var expandedTopSessions: [ChatSession] {
        guard let expandedSessionIndex else { return [] }
        return Array(manager.sessions.prefix(expandedSessionIndex))
    }

    private var expandedBottomSessions: [ChatSession] {
        guard let expandedSessionIndex else { return [] }
        let nextIndex = manager.sessions.index(after: expandedSessionIndex)
        guard nextIndex < manager.sessions.endIndex else { return [] }
        return Array(manager.sessions[nextIndex...])
    }

    private var collapsedHeadsRenderHeight: CGFloat {
        let count = manager.sessions.count
        guard count > 0 else { return 0 }
        let collapsedFrameHeight = CGFloat(count) * DesignTokens.headControlDiameter
            + CGFloat(count - 1) * DesignTokens.headSpacing
        return collapsedFrameHeight
    }

    private var headsRenderWidth: CGFloat {
        DesignTokens.headDiameter + (headVisualPadding * 2)
    }

    private var headColumnAlignment: Alignment {
        dockSide == .trailing ? .topTrailing : .topLeading
    }

    private var headButtonFrameAlignment: Alignment {
        dockSide == .trailing ? .trailing : .leading
    }

    private var headsLayoutAnimation: Animation? {
        let isTransitioning = manager.deletingSessionId != nil
        return isTransitioning ? nil : DesignTokens.motionLayout
    }

    private func collapsedHeadYOffset(for index: Int) -> CGFloat {
        CGFloat(index) * (DesignTokens.headControlDiameter + DesignTokens.headSpacing)
    }

    private func cardStackHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return DesignTokens.headDiameter
            + CGFloat(count - 1) * DesignTokens.deckOffset
            + headVisualPadding
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
        ZStack(alignment: dockSide == .trailing ? .bottomTrailing : .bottomLeading) {
            HStack(spacing: 0) {
                if dockSide == .trailing {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }

                VStack(
                    alignment: dockSide == .trailing ? .trailing : .leading,
                    spacing: DesignTokens.headSpacing
                ) {
                    addButton
                        .contentShape(Rectangle())
                        .simultaneousGesture(headsDragGesture)

                    if let session = expandedSession,
                       let sessionId = manager.expandedSessionId,
                       let viewModel = manager.viewModel(for: sessionId) {
                        expandedContent(
                            session: session,
                            sessionId: sessionId,
                            viewModel: viewModel
                        )
                    } else {
                        collapsedContent
                            .contentShape(Rectangle())
                            .simultaneousGesture(headsDragGesture)
                    }
                }
                .padding(DesignTokens.headInset)

                if dockSide == .leading {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(.leading, dockSide == .trailing ? previewOverflow : 0)
        .padding(.trailing, dockSide == .leading ? previewOverflow : 0)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: dockSide == .trailing ? .bottomTrailing : .bottomLeading
        )
    }

    private var addButton: some View {
        floatingActionButton(
            symbolName: "plus",
            accessibilityLabel: "New chat",
            action: onAddSession
        )
    }

    private var historyButton: some View {
        floatingActionButton(
            symbolName: "clock.arrow.circlepath",
            accessibilityLabel: "Chat history"
        ) {
            isShowingHistory.toggle()
        }
        .popover(
            isPresented: $isShowingHistory,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: dockSide == .trailing ? .trailing : .leading
        ) {
            HistoryPopoverView(
                entries: manager.historyEntries,
                onOpen: { entry in
                    pendingHistorySessionToOpen = entry.session
                    isShowingHistory = false
                },
                onDelete: { entry in
                    guard entry.isArchived else { return }
                    onDeleteHistorySession(entry.session)
                }
            )
        }
        .onChange(of: isShowingHistory) { _, isPresented in
            guard !isPresented, let session = pendingHistorySessionToOpen else { return }
            pendingHistorySessionToOpen = nil
            onOpenHistorySession(session)
        }
    }

    @ViewBuilder
    private var collapsedContent: some View {
        historyButton

        if !manager.sessions.isEmpty {
            ZStack(alignment: headColumnAlignment) {
                ForEach(Array(manager.sessions.enumerated()), id: \.element.id) { index, session in
                    chatHeadButton(for: session)
                        .offset(y: collapsedHeadYOffset(for: index))
                        .zIndex(Double(manager.sessions.count - index))
                }
            }
            .frame(width: headsRenderWidth, height: collapsedHeadsRenderHeight, alignment: headColumnAlignment)
            .animation(headsLayoutAnimation, value: manager.sessions.count)
            .animation(headsLayoutAnimation, value: isExpanded)
        }
    }

    @ViewBuilder
    private func expandedContent(
        session: ChatSession,
        sessionId: UUID,
        viewModel: ChatSessionViewModel
    ) -> some View {
        historyButton
            .contentShape(Rectangle())
            .simultaneousGesture(headsDragGesture)

        if !expandedTopSessions.isEmpty {
            stackedHeadButtonsView(sessions: expandedTopSessions)
                .contentShape(Rectangle())
                .simultaneousGesture(headsDragGesture)
                .animation(headsLayoutAnimation, value: expandedTopSessions.count)
        }

        expandedChatCard(session: session, sessionId: sessionId, viewModel: viewModel)

        if !expandedBottomSessions.isEmpty {
            stackedHeadButtonsView(sessions: expandedBottomSessions)
                .contentShape(Rectangle())
                .simultaneousGesture(headsDragGesture)
                .animation(headsLayoutAnimation, value: expandedBottomSessions.count)
        }
    }

    @ViewBuilder
    private func stackedHeadButtonsView(sessions: [ChatSession]) -> some View {
        ZStack(alignment: headColumnAlignment) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                chatHeadButton(for: session)
                    .offset(y: CGFloat(index) * DesignTokens.deckOffset)
                    .zIndex(Double(sessions.count - index))
            }
        }
        .frame(width: headsRenderWidth, height: cardStackHeight(for: sessions.count), alignment: headColumnAlignment)
    }

    private func chatHeadButton(for session: ChatSession) -> some View {
        ChatHeadView(
            session: session,
            showProviderBadge: manager.hasMixedProviders,
            isExpanded: false,
            dockSide: dockSide,
            onTap: { onHeadTapped(session) },
            onDropAttachments: { providers in
                guard let viewModel = manager.viewModel(for: session.id) else {
                    return false
                }
                return viewModel.attachDroppedItems(from: providers)
            },
            morphNamespace: morphNamespace
        )
        .frame(width: headsRenderWidth, alignment: headButtonFrameAlignment)
    }

    @ViewBuilder
    private func expandedChatCard(
        session: ChatSession,
        sessionId: UUID,
        viewModel: ChatSessionViewModel
    ) -> some View {
        let isDeletingExpandedSession = manager.deletingSessionId == sessionId
        let shellCornerRadius = DesignTokens.headDiameter / 2

        ZStack {
            RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous)
                .fill(DesignTokens.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous)
                        .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
                )
                .matchedGeometryEffect(
                    id: session.id,
                    in: morphNamespace,
                    properties: [.frame, .position],
                    anchor: dockSide == .trailing ? .bottomTrailing : .bottomLeading,
                    isSource: false
                )

            ChatContentView(
                session: session,
                viewModel: viewModel,
                showProviderBadge: manager.hasMixedProviders,
                onClose: onClose,
                onMarkRead: { manager.markRead(sessionId: sessionId) },
                onArchive: {
                    onArchiveSession(session)
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: DesignTokens.panelShadowRadius)
        .frame(width: chatWidth, height: chatHeight)
        .frame(height: isDeletingExpandedSession ? 0 : chatHeight, alignment: .top)
        .clipped()
        .opacity(isDeletingExpandedSession ? 0 : 1)
        .animation(DesignTokens.motionLayout, value: isDeletingExpandedSession)
        .animation(DesignTokens.motionFade, value: isDeletingExpandedSession)
    }

    private func floatingActionButton(
        symbolName: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                Button(action: action) {
                    Image(systemName: symbolName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
                }
                .buttonStyle(.glass(.regular.interactive()))
                .buttonBorderShape(.circle)
            } else {
                Button(action: action) {
                    FloatingControlCircle {
                        Image(systemName: symbolName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: headsRenderWidth, alignment: headButtonFrameAlignment)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HistoryPopoverView: View {
    let entries: [ChatHeadsManager.HistoryEntry]
    let onOpen: (ChatHeadsManager.HistoryEntry) -> Void
    let onDelete: (ChatHeadsManager.HistoryEntry) -> Void

    var body: some View {
        SessionFlyoutSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("History")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignTokens.textPrimary)

                    Spacer(minLength: 0)

                    Text("\(entries.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                if entries.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No conversation history yet.")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.textPrimary)

                        Text("A chat appears here automatically after your first message, and the preview keeps updating as the conversation progresses.")
                            .font(.system(size: 12))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                VStack(spacing: 0) {
                                    HistorySessionRow(
                                        entry: entry,
                                        onOpen: { onOpen(entry) },
                                        onDelete: { onDelete(entry) }
                                    )

                                    if index < entries.count - 1 {
                                        Divider()
                                            .overlay(DesignTokens.borderColor.opacity(0.45))
                                            .padding(.leading, 46)
                                    }
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
        }
        .frame(width: 328, alignment: .topLeading)
    }
}

private struct HistorySessionRow: View {
    let entry: ChatHeadsManager.HistoryEntry
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    private var session: ChatSession { entry.session }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onOpen) {
                SessionFlyoutRowContent(
                    chatHeadImageName: session.chatHeadImageName,
                    title: session.name,
                    subtitle: session.historyPreview,
                    trailingLabel: session.updatedRelativeDescription,
                    subtitleLineLimit: 2,
                    isHighlighted: isHovering
                )
            }
            .buttonStyle(.plain)

            if entry.isArchived {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(DesignTokens.surfaceElevated.opacity(isHovering ? 0.82 : 0.58)))
                        .opacity(isHovering ? 1 : 0.72)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 2)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

private extension ChatSession {
    private static let flyoutRelativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var updatedRelativeDescription: String {
        Self.flyoutRelativeDateFormatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    var historyPreview: String {
        if let message = messages.reversed().first(where: { $0.role != .system && (!$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.attachments.isEmpty) }) {
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed.replacingOccurrences(of: "\n", with: " ")
            }
            return message.attachments.isEmpty ? "No messages yet." : attachmentPreview(for: message.attachments)
        }

        if case .error(let message) = state {
            return message
        }

        return "No messages yet."
    }

    private func attachmentPreview(for attachments: [ChatAttachment]) -> String {
        let imageCount = attachments.filter(\.isImage).count
        let fileCount = attachments.count - imageCount

        if imageCount > 0 && fileCount > 0 {
            return "Shared \(imageCount) image\(imageCount == 1 ? "" : "s") and \(fileCount) file\(fileCount == 1 ? "" : "s")."
        }

        if imageCount > 0 {
            return "Shared \(imageCount) image\(imageCount == 1 ? "" : "s")."
        }

        return "Shared \(fileCount) file\(fileCount == 1 ? "" : "s")."
    }
}
