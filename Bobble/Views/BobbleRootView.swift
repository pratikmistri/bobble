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

    private let chatWidth: CGFloat = 320
    private let chatHeight: CGFloat = 480
    private let previewOverflow: CGFloat = DesignTokens.headPreviewOverflow

    private var isExpanded: Bool { manager.expandedSessionId != nil }
    private var isHeadsDeckMode: Bool { isExpanded }
    private var headVisualPadding: CGFloat { DesignTokens.headVisualPadding }
    private var dockSide: PanelDockSide { manager.panelDockSide }

    private var visibleSessions: [ChatSession] {
        manager.sessions.filter { $0.id != manager.expandedSessionId }
    }

    private var headsSlotCount: Int {
        let virtualExpandedSlot = isHeadsDeckMode && !manager.sessions.isEmpty ? 1 : 0
        return visibleSessions.count + virtualExpandedSlot
    }

    private var headsFrameHeight: CGFloat {
        let count = headsSlotCount
        guard count > 0 else { return 0 }
        if isHeadsDeckMode {
            return DesignTokens.headDiameter + CGFloat(count - 1) * DesignTokens.deckOffset
        } else {
            return CGFloat(count) * DesignTokens.headDiameter
                + CGFloat(count - 1) * DesignTokens.headSpacing
        }
    }

    private var collapsedHeadsRenderHeight: CGFloat {
        let count = manager.sessions.count
        guard count > 0 else { return 0 }
        let collapsedFrameHeight = CGFloat(count) * DesignTokens.headDiameter
            + CGFloat(count - 1) * DesignTokens.headSpacing
        return collapsedFrameHeight + headVisualPadding
    }

    private var headsRenderHeight: CGFloat {
        let currentRenderHeight = headsFrameHeight + headVisualPadding
        if isHeadsDeckMode {
            return max(currentRenderHeight, collapsedHeadsRenderHeight)
        }
        return currentRenderHeight
    }

    private var headsRenderWidth: CGFloat {
        DesignTokens.headDiameter + (headVisualPadding * 2)
    }

    private var controlsSectionHeight: CGFloat {
        let controlsHeight = (DesignTokens.headDiameter * 2) + DesignTokens.headSpacing
        let headsHeight = headsSlotCount == 0 ? 0 : (DesignTokens.headSpacing + headsRenderHeight)
        return controlsHeight + headsHeight + (DesignTokens.headInset * 2)
    }

    private var headsLayoutAnimation: Animation? {
        let isTransitioning = manager.deletingSessionId != nil
        return isTransitioning ? nil : DesignTokens.motionLayout
    }

    private func headYOffset(for index: Int) -> CGFloat {
        let base = isHeadsDeckMode
            ? CGFloat(index) * DesignTokens.deckOffset
            : CGFloat(index) * (DesignTokens.headDiameter + DesignTokens.headSpacing)
        return base
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
            if let sessionId = manager.expandedSessionId,
               let session = manager.sessions.first(where: { $0.id == sessionId }),
               let viewModel = manager.viewModel(for: sessionId) {
                let isDeletingExpandedSession = manager.deletingSessionId == sessionId

                HStack(spacing: 0) {
                    if dockSide == .trailing {
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    }

                    ZStack {
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
                                anchor: dockSide == .trailing ? .bottomTrailing : .bottomLeading
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
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius))
                    .shadow(color: .black.opacity(0.15), radius: DesignTokens.panelShadowRadius)
                    .frame(width: chatWidth, height: chatHeight)

                    if dockSide == .leading {
                        Spacer(minLength: 0)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: isDeletingExpandedSession ? 0 : chatHeight, alignment: .top)
                .clipped()
                .opacity(isDeletingExpandedSession ? 0 : 1)
                .animation(DesignTokens.motionLayout, value: isDeletingExpandedSession)
                .animation(DesignTokens.motionFade, value: isDeletingExpandedSession)
                .padding(.bottom, controlsSectionHeight + 8)
            }

            HStack(spacing: 0) {
                if dockSide == .trailing {
                    Spacer(minLength: 0)
                        .allowsHitTesting(false)
                }

                VStack(spacing: DesignTokens.headSpacing) {
                    addButton
                    historyButton

                    if headsSlotCount > 0 {
                        ZStack(alignment: .top) {
                            ForEach(Array(visibleSessions.enumerated()), id: \.element.id) { index, session in
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
                                .offset(y: headYOffset(for: index))
                                .zIndex(Double(visibleSessions.count - index))
                            }

                            if isHeadsDeckMode {
                                Color.clear
                                    .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
                                    .allowsHitTesting(false)
                                    .offset(y: headYOffset(for: visibleSessions.count))
                                    .zIndex(0)
                            }
                        }
                        .frame(width: headsRenderWidth, height: headsRenderHeight, alignment: .top)
                        .animation(headsLayoutAnimation, value: isExpanded)
                        .animation(headsLayoutAnimation, value: headsSlotCount)
                    }
                }
                .padding(DesignTokens.headInset)
                .contentShape(Rectangle())
                .simultaneousGesture(headsDragGesture)

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
        .popover(isPresented: $isShowingHistory, arrowEdge: dockSide == .trailing ? .trailing : .leading) {
            HistoryPopoverView(
                entries: manager.historyEntries,
                onOpen: { entry in
                    isShowingHistory = false
                    onOpenHistorySession(entry.session)
                },
                onDelete: { entry in
                    guard entry.isArchived else { return }
                    onDeleteHistorySession(entry.session)
                }
            )
        }
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
                    ZStack {
                        Circle()
                            .fill(DesignTokens.addButtonColor.opacity(0.95))
                            .overlay(
                                Circle()
                                    .strokeBorder(DesignTokens.borderColor, lineWidth: 1.2)
                            )
                            .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)

                        Image(systemName: symbolName)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(DesignTokens.textPrimary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HistoryPopoverView: View {
    let entries: [ChatHeadsManager.HistoryEntry]
    let onOpen: (ChatHeadsManager.HistoryEntry) -> Void
    let onDelete: (ChatHeadsManager.HistoryEntry) -> Void

    var body: some View {
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
        .padding(12)
        .frame(width: 328, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(DesignTokens.surfaceColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(DesignTokens.borderColor.opacity(0.75), lineWidth: 1)
                )
        )
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
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(DesignTokens.surfaceAccent.opacity(0.82))
                        .frame(width: 30, height: 30)
                        .overlay(
                            Text(session.displayChatHeadSymbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(session.name)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .lineLimit(1)

                            Spacer(minLength: 0)

                            Text(session.updatedAt, style: .relative)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }

                        Text(session.historyPreview)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignTokens.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
                .background(DesignTokens.surfaceElevated.opacity(isHovering ? 0.42 : 0))
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
