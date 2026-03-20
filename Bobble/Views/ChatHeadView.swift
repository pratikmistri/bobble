import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ChatHeadView: View {
    let session: ChatSession
    let showProviderBadge: Bool
    let isExpanded: Bool
    let dockSide: PanelDockSide
    let onTap: () -> Void
    let onDropAttachments: ([NSItemProvider]) -> Bool
    var morphNamespace: Namespace.ID

    @State private var isHovering = false
    @State private var isDropTargeted = false
    @State private var isShowingPreview = false
    @State private var statusBlink = false
    @State private var previewTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Main circle — participates in matchedGeometryEffect morph
            if #available(macOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .matchedGeometryEffect(
                        id: session.id,
                        in: morphNamespace,
                        properties: .frame,
                        anchor: dockSide == .trailing ? .bottomTrailing : .bottomLeading
                    )
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity((isHovering || isDropTargeted) ? 0.58 : 0.44), lineWidth: 1)
                    )
                    .frame(width: DesignTokens.headDiameter, height: DesignTokens.headDiameter)
                    .matchedGeometryEffect(
                        id: session.id,
                        in: morphNamespace,
                        properties: .frame,
                        anchor: dockSide == .trailing ? .bottomTrailing : .bottomLeading
                    )
                    .shadow(
                        color: .black.opacity((isHovering || isDropTargeted) ? 0.22 : 0.12),
                        radius: (isHovering || isDropTargeted) ? 9 : DesignTokens.headShadowRadius,
                        y: (isHovering || isDropTargeted) ? 2 : DesignTokens.headShadowY
                    )
            }

            // Model-chosen chat marker
            Text(session.displayChatHeadSymbol)
                .font(DesignTokens.headInitialFont)
                .foregroundColor(DesignTokens.textPrimary)

            if showProviderBadge {
                ProviderBadgeView(provider: session.provider, compact: true)
                    .offset(y: 21)
            }

            // Selection ring — animated stroke
            Circle()
                .stroke(DesignTokens.textSecondary.opacity(isExpanded ? 0.9 : 0), lineWidth: 3)
                .frame(
                    width: DesignTokens.headDiameter + (isExpanded ? 6 : 0),
                    height: DesignTokens.headDiameter + (isExpanded ? 6 : 0)
                )
                .scaleEffect(isExpanded ? 1 : 0.8)

            Circle()
                .stroke(DesignTokens.surfaceAccent.opacity(isDropTargeted ? 0.95 : 0), lineWidth: 2)
                .frame(
                    width: DesignTokens.headDiameter + 10,
                    height: DesignTokens.headDiameter + 10
                )
                .scaleEffect(isDropTargeted ? 1 : 0.92)

            // Single top-right status indicator.
            if let status = statusIndicator {
                statusIndicatorView(for: status)
                    .offset(x: 18, y: -18)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        // Hover: lift + scale
        .scaleEffect((isHovering || isDropTargeted) ? 1.04 : 1.0)
        .zIndex(isHovering || isDropTargeted || isShowingPreview ? 1000 : 0)
        .animation(DesignTokens.motionHover, value: isHovering)
        .animation(DesignTokens.motionHover, value: isDropTargeted)
        .animation(DesignTokens.motionLayout, value: isExpanded)
        .animation(DesignTokens.motionEntrance, value: isShowingPreview)
        .overlay(alignment: dockSide == .trailing ? .leading : .trailing) {
            if let preview = previewContent, isShowingPreview {
                ChatHeadPreviewBubble(
                    sessionName: session.name,
                    preview: preview
                )
                .offset(
                    x: dockSide == .trailing
                        ? -(DesignTokens.headPreviewWidth + DesignTokens.headPreviewGap)
                        : (DesignTokens.headPreviewWidth + DesignTokens.headPreviewGap)
                )
                .transition(
                    .scale(scale: 0.94, anchor: dockSide == .trailing ? .trailing : .leading)
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
        .background {
            ChatHeadDropDestinationView(
                onHoverChanged: { hovering in
                    isDropTargeted = hovering
                },
                onPerformDrop: handleDrop
            )
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let handled = onDropAttachments(providers)
        guard handled else { return false }

        dismissPreview()
        onTap()
        return true
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

private struct ChatHeadDropDestinationView: NSViewRepresentable {
    let onHoverChanged: (Bool) -> Void
    let onPerformDrop: ([NSItemProvider]) -> Bool

    func makeNSView(context: Context) -> ChatHeadDropNSView {
        let view = ChatHeadDropNSView()
        view.onHoverChanged = onHoverChanged
        view.onPerformDrop = onPerformDrop
        return view
    }

    func updateNSView(_ nsView: ChatHeadDropNSView, context: Context) {
        nsView.onHoverChanged = onHoverChanged
        nsView.onPerformDrop = onPerformDrop
    }
}

private final class ChatHeadDropNSView: NSView {
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onPerformDrop: ([NSItemProvider]) -> Bool = { _ in false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(Self.supportedPasteboardTypes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes(Self.supportedPasteboardTypes)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let providers = Self.providers(from: sender.draggingPasteboard)
        guard !providers.isEmpty else { return [] }
        onHoverChanged(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let providers = Self.providers(from: sender.draggingPasteboard)
        guard !providers.isEmpty else {
            onHoverChanged(false)
            return []
        }
        onHoverChanged(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverChanged(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        !Self.providers(from: sender.draggingPasteboard).isEmpty
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let providers = Self.providers(from: sender.draggingPasteboard)
        onHoverChanged(false)
        guard !providers.isEmpty else { return false }
        return onPerformDrop(providers)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onHoverChanged(false)
    }

    private static var supportedPasteboardTypes: [NSPasteboard.PasteboardType] {
        [
            .fileURL,
            NSPasteboard.PasteboardType(UTType.png.identifier),
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            NSPasteboard.PasteboardType(UTType.tiff.identifier),
            NSPasteboard.PasteboardType(UTType.gif.identifier)
        ]
    }

    private static func providers(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        var providers: [NSItemProvider] = []

        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            providers.append(contentsOf: urls.map { url in
                let provider = NSItemProvider(object: url as NSURL)
                provider.suggestedName = url.deletingPathExtension().lastPathComponent
                return provider
            })
        }

        guard let items = pasteboard.pasteboardItems else {
            return providers
        }

        for item in items {
            for type in supportedPasteboardTypes where type != .fileURL {
                guard let data = item.data(forType: type) else { continue }
                let provider = NSItemProvider()
                provider.registerDataRepresentation(forTypeIdentifier: type.rawValue, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
                providers.append(provider)
                break
            }
        }

        return providers
    }
}

private struct ChatHeadPreviewContent {
    let senderLabel: String
    let message: String
}

struct ProviderBadgeView: View {
    let provider: CLIBackend
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            Image(systemName: provider.badgeSymbolName)
                .font(.system(size: compact ? 7 : 9, weight: .bold))

            Text(compact ? provider.compactBadgeText : provider.shortLabel)
                .font(.system(size: compact ? 8 : 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundColor(provider.badgeForegroundColor)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(
            Capsule()
                .fill(provider.badgeFillColor)
        )
        .overlay(
            Capsule()
                .stroke(provider.badgeStrokeColor, lineWidth: 1)
        )
        .shadow(color: .black.opacity(compact ? 0.1 : 0.08), radius: compact ? 2 : 3, y: 1)
    }
}

private extension CLIBackend {
    var compactBadgeText: String {
        switch self {
        case .codex:
            return "CX"
        case .copilot:
            return "GH"
        case .claude:
            return "CL"
        }
    }

    var badgeSymbolName: String {
        switch self {
        case .codex:
            return "cpu"
        case .copilot:
            return "chevron.left.forwardslash.chevron.right"
        case .claude:
            return "text.bubble"
        }
    }

    var badgeFillColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.86, green: 0.92, blue: 0.98)
        case .copilot:
            return Color(red: 0.89, green: 0.95, blue: 0.90)
        case .claude:
            return Color(red: 0.98, green: 0.91, blue: 0.84)
        }
    }

    var badgeStrokeColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.53, green: 0.68, blue: 0.83).opacity(0.8)
        case .copilot:
            return Color(red: 0.46, green: 0.66, blue: 0.48).opacity(0.8)
        case .claude:
            return Color(red: 0.78, green: 0.56, blue: 0.33).opacity(0.8)
        }
    }

    var badgeForegroundColor: Color {
        switch self {
        case .codex:
            return Color(red: 0.16, green: 0.29, blue: 0.44)
        case .copilot:
            return Color(red: 0.12, green: 0.31, blue: 0.18)
        case .claude:
            return Color(red: 0.45, green: 0.24, blue: 0.08)
        }
    }
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
