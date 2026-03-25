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
    @State private var isHeadBobbling = false
    @State private var previewTask: Task<Void, Never>?
    private let controlShellDiameter: CGFloat = DesignTokens.headControlDiameter

    var body: some View {
        let isHighlighted = isHovering || isDropTargeted

        ZStack {
            ChatHeadAvatarView(imageName: session.chatHeadImageName, size: controlShellDiameter)
                .matchedGeometryEffect(
                    id: session.id,
                    in: morphNamespace,
                    properties: [.frame, .position],
                    anchor: dockSide == .trailing ? .bottomTrailing : .bottomLeading,
                    isSource: true
                )
                .scaleEffect(isWorking ? (isHeadBobbling ? 1.08 : 0.95) : 1.0)
                .rotationEffect(.degrees(isWorking ? (isHeadBobbling ? 6 : -5) : 0))
                .offset(y: isWorking ? (isHeadBobbling ? -2 : 2) : 0)
                .shadow(
                    color: .black.opacity(isHighlighted ? 0.22 : 0.14),
                    radius: isHighlighted ? 10 : 5,
                    y: isHighlighted ? 4 : 2
                )
                .shadow(
                    color: HeadStatus.working.color.opacity(isWorking ? (isHeadBobbling ? 0.42 : 0.18) : 0),
                    radius: isWorking ? (isHeadBobbling ? 10 : 4) : 0,
                    y: isWorking ? (isHeadBobbling ? 4 : 1) : 0
                )

            // Selection ring — animated stroke
            Circle()
                .stroke(DesignTokens.textSecondary.opacity(isExpanded ? 0.9 : 0), lineWidth: 3)
                .frame(
                    width: controlShellDiameter + (isExpanded ? 6 : 0),
                    height: controlShellDiameter + (isExpanded ? 6 : 0)
                )
                .scaleEffect(isExpanded ? 1 : 0.8)

            Circle()
                .stroke(DesignTokens.surfaceAccent.opacity(isDropTargeted ? 0.95 : 0), lineWidth: 2)
                .frame(
                    width: controlShellDiameter + 10,
                    height: controlShellDiameter + 10
                )
                .scaleEffect(isDropTargeted ? 1 : 0.92)
        }
        .frame(width: controlShellDiameter, height: controlShellDiameter)
        .contentShape(Circle())
        // Hover: lift + scale
        .scaleEffect(isHighlighted ? 1.04 : 1.0)
        .zIndex(isHovering || isDropTargeted || isShowingPreview ? 1000 : 0)
        .animation(DesignTokens.motionHover, value: isHovering)
        .animation(DesignTokens.motionHover, value: isDropTargeted)
        .animation(DesignTokens.motionLayout, value: isExpanded)
        .animation(DesignTokens.motionEntrance, value: isShowingPreview)
        .overlay(alignment: .bottom) {
            if showProviderBadge {
                ProviderBadgeView(provider: session.provider, compact: true)
                    .offset(y: 3)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if let status = badgeStatus {
                statusIndicatorView(for: status)
                    .offset(x: 1, y: -1)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
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
        .onAppear {
            updateWorkingAnimation()
        }
        .onChange(of: headStatus) { _, _ in
            updateWorkingAnimation()
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
            stopWorkingAnimation()
        }
        .contextMenu {
            Text(session.name)
        }
    }

    private var isWorking: Bool {
        headStatus == .working
    }

    private var headStatus: HeadStatus? {
        switch session.state {
        case .running:
            return .working
        case .error:
            return .needsHelp
        case .idle:
            return session.hasUnread ? .completed : nil
        }
    }

    private var badgeStatus: HeadStatus? {
        switch headStatus {
        case .working, nil:
            return nil
        case .needsHelp:
            return .needsHelp
        case .completed:
            return .completed
        }
    }

    private var previewContent: ChatHeadPreviewContent? {
        ChatHeadPreviewFormatter.preview(for: session).map {
            ChatHeadPreviewContent(senderLabel: $0.senderLabel, message: $0.message)
        }
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
        case .working, .needsHelp, .completed:
            Circle()
                .fill(status.color)
                .frame(width: 12, height: 12)
                .shadow(color: status.color.opacity(0.35), radius: 3)
                .id("status-\(String(describing: status))")
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
    }

    private func updateWorkingAnimation() {
        if isWorking {
            startWorkingAnimation()
        } else {
            stopWorkingAnimation()
        }
    }

    private func startWorkingAnimation() {
        guard !isHeadBobbling else { return }
        isHeadBobbling = false
        withAnimation(DesignTokens.motionPlayful.speed(1.05).repeatForever(autoreverses: true)) {
            isHeadBobbling = true
        }
    }

    private func stopWorkingAnimation() {
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            isHeadBobbling = false
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
        SessionFlyoutSurface(contentPadding: 2) {
            SessionFlyoutRowContent(
                chatHeadImageName: ChatSession.defaultChatHeadSymbol,
                title: sessionName,
                subtitle: preview.message,
                trailingLabel: preview.senderLabel,
                subtitleLineLimit: 3,
                showsLeadingAvatar: false
            )
            .padding(.horizontal, 10)
        }
        .frame(width: DesignTokens.headPreviewWidth, alignment: .leading)
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
