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
    private let maxHorizontalCollapsedVisibleHeads = DesignTokens.maxHorizontalCollapsedVisibleHeads
    private let maxHorizontalExpandedDeckHeadsPerSide = DesignTokens.maxHorizontalExpandedDeckHeadsPerSide

    private var isExpanded: Bool { manager.expandedSessionId != nil }
    private var dockSide: PanelDockSide { manager.panelDockSide }
    private var layoutMode: ChatHeadsLayoutMode { manager.layoutMode }
    private var isHorizontalLayout: Bool { layoutMode == .horizontal }
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
        let allTopSessions = Array(manager.sessions.prefix(expandedSessionIndex))
        guard isHorizontalLayout else { return allTopSessions }
        return Array(allTopSessions.suffix(maxHorizontalExpandedDeckHeadsPerSide))
    }

    private var expandedBottomSessions: [ChatSession] {
        guard let expandedSessionIndex else { return [] }
        let nextIndex = manager.sessions.index(after: expandedSessionIndex)
        guard nextIndex < manager.sessions.endIndex else { return [] }
        let allBottomSessions = Array(manager.sessions[nextIndex...])
        guard isHorizontalLayout else { return allBottomSessions }
        return Array(allBottomSessions.prefix(maxHorizontalExpandedDeckHeadsPerSide))
    }

    private var collapsedVisibleSessions: [ChatSession] {
        guard isHorizontalLayout else { return manager.sessions }
        return Array(manager.sessions.suffix(maxHorizontalCollapsedVisibleHeads))
    }

    private var collapsedHeadsRenderHeight: CGFloat {
        let count = collapsedVisibleSessions.count
        guard count > 0 else { return 0 }
        if isHorizontalLayout {
            return DesignTokens.headControlDiameter
        }
        return CGFloat(count) * DesignTokens.headControlDiameter
            + CGFloat(count - 1) * DesignTokens.headSpacing
    }

    private var collapsedHeadsRenderWidth: CGFloat {
        let count = collapsedVisibleSessions.count
        guard count > 0 else { return 0 }
        if isHorizontalLayout {
            return CGFloat(count) * DesignTokens.headControlDiameter
                + CGFloat(count - 1) * DesignTokens.headSpacing
        }
        return headsRenderWidth
    }

    private var headsRenderWidth: CGFloat {
        DesignTokens.headDiameter + (headVisualPadding * 2)
    }

    private var controlItemWidth: CGFloat {
        isHorizontalLayout ? DesignTokens.headControlDiameter : headsRenderWidth
    }

    private var actionButtonShadowPadding: CGFloat {
        isHorizontalLayout ? 0 : (DesignTokens.headVisualPadding / 2)
    }

    private var actionButtonRenderHeight: CGFloat {
        DesignTokens.headDiameter + (actionButtonShadowPadding * 2)
    }

    private var headColumnAlignment: Alignment {
        dockSide == .trailing ? .topTrailing : .topLeading
    }

    private var headsStackAlignment: Alignment {
        isHorizontalLayout ? .topLeading : headColumnAlignment
    }

    private var headButtonFrameAlignment: Alignment {
        isHorizontalLayout ? .center : (dockSide == .trailing ? .trailing : .leading)
    }

    private var controlsLayout: AnyLayout {
        if isHorizontalLayout {
            return AnyLayout(HStackLayout(alignment: .bottom, spacing: DesignTokens.headSpacing))
        }
        return AnyLayout(
            VStackLayout(
                alignment: dockSide == .trailing ? .trailing : .leading,
                spacing: DesignTokens.headSpacing
            )
        )
    }

    private var headsLayoutAnimation: Animation? {
        let isTransitioning = manager.deletingSessionId != nil
        return isTransitioning ? nil : DesignTokens.motionLayout
    }

    private func collapsedHeadOffset(for index: Int) -> CGSize {
        let step = CGFloat(index) * (DesignTokens.headControlDiameter + DesignTokens.headSpacing)
        if isHorizontalLayout {
            return CGSize(width: step, height: 0)
        }
        return CGSize(width: 0, height: step)
    }

    private func cardStackLength(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return DesignTokens.headDiameter
            + CGFloat(count - 1) * DesignTokens.deckOffset
            + headVisualPadding
    }

    private func cardStackSize(for count: Int) -> CGSize {
        if isHorizontalLayout {
            return CGSize(width: cardStackLength(for: count), height: DesignTokens.headControlDiameter)
        }
        return CGSize(width: headsRenderWidth, height: cardStackLength(for: count))
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

                controlsLayout {
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
                .animation(headsLayoutAnimation, value: layoutMode)

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

        if !collapsedVisibleSessions.isEmpty {
            ZStack(alignment: headsStackAlignment) {
                ForEach(Array(collapsedVisibleSessions.enumerated()), id: \.element.id) { index, session in
                    chatHeadButton(for: session)
                        .offset(collapsedHeadOffset(for: index))
                        .zIndex(Double(collapsedVisibleSessions.count - index))
                }
            }
            .frame(
                width: collapsedHeadsRenderWidth,
                height: collapsedHeadsRenderHeight,
                alignment: headsStackAlignment
            )
            .animation(headsLayoutAnimation, value: collapsedVisibleSessions.count)
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
        ZStack(alignment: headsStackAlignment) {
            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                chatHeadButton(for: session)
                    .offset(
                        x: isHorizontalLayout ? CGFloat(index) * DesignTokens.deckOffset : 0,
                        y: isHorizontalLayout ? 0 : CGFloat(index) * DesignTokens.deckOffset
                    )
                    .zIndex(Double(sessions.count - index))
            }
        }
        .frame(
            width: cardStackSize(for: sessions.count).width,
            height: cardStackSize(for: sessions.count).height,
            alignment: headsStackAlignment
        )
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
        .frame(width: controlItemWidth, alignment: headButtonFrameAlignment)
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
                        .padding(actionButtonShadowPadding)
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
                    .padding(actionButtonShadowPadding)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(
            width: controlItemWidth,
            height: actionButtonRenderHeight,
            alignment: headButtonFrameAlignment
        )
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
            return message.attachments.isEmpty ? "No messages yet." : AttachmentSummaryFormatter.summary(for: message.attachments)
        }

        if case .error(let message) = state {
            return message
        }

        return "No messages yet."
    }
}
