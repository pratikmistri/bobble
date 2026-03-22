import AppKit
import QuickLookThumbnailing
import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let index: Int
    let onInterruptionAction: ((ChatMessage.InterruptionAction) -> Void)?

    @State private var appeared = false
    @State private var cursorVisible = true
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
                        messageContent
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
            if message.isStreaming {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    cursorVisible.toggle()
                }
            }
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

    @ViewBuilder
    private var messageContent: some View {
        if message.isInterruptionCard {
            interruptionCardContent
        } else if shouldShowTypingIndicator {
            TypingIndicatorDotsView(dotColor: foregroundColor)
        } else if shouldUsePlainText {
            bubbleText
                .font(DesignTokens.messageFont)
                .lineLimit(isCollapsed ? 2 : nil)
                .multilineTextAlignment(message.role == .user ? .trailing : .leading)
        } else {
            MarkdownMessageView(markdown: message.content)
        }
    }

    private var interruptionCardTitle: String {
        message.interruptionCardTitle ?? "Update"
    }

    private var interruptionCardIconName: String {
        switch message.kind {
        case .permission:
            return "shield.lefthalf.filled"
        case .question:
            return "questionmark.circle.fill"
        case .regular, .agentThought, .toolUse:
            return "exclamationmark.bubble.fill"
        }
    }

    private var interruptionCardAccentColor: Color {
        switch message.kind {
        case .permission:
            return DesignTokens.surfaceAccent
        case .question:
            return DesignTokens.textSecondary
        case .regular, .agentThought, .toolUse:
            return DesignTokens.surfaceAccent
        }
    }

    @ViewBuilder
    private var interruptionCardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: interruptionCardIconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(interruptionCardAccentColor)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 4) {
                    Text(interruptionCardTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.textPrimary)

                    Text(message.interruptionCardBody)
                        .font(DesignTokens.messageFont)
                        .foregroundColor(DesignTokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                Spacer(minLength: 0)
            }

            if !message.interruptionActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(message.interruptionActions) { action in
                        Button(action: {
                            onInterruptionAction?(action)
                        }) {
                            Text(action.title)
                                .font(.system(size: 11, weight: .semibold))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .foregroundColor(actionForegroundColor(for: action))
                                .background(actionBackground(for: action))
                                .overlay(actionBorder(for: action))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(onInterruptionAction == nil)
                        .opacity(onInterruptionAction == nil ? 0.55 : 1)
                    }
                }
                .padding(.leading, 28)
            }
        }
    }

    private func actionForegroundColor(for action: ChatMessage.InterruptionAction) -> Color {
        switch action.role {
        case .primary:
            return DesignTokens.textPrimary
        case .secondary:
            return DesignTokens.textSecondary
        case .destructive:
            return .red
        }
    }

    @ViewBuilder
    private func actionBackground(for action: ChatMessage.InterruptionAction) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                action.role == .primary
                    ? DesignTokens.surfaceAccent.opacity(0.55)
                    : Color.clear
            )
    }

    @ViewBuilder
    private func actionBorder(for action: ChatMessage.InterruptionAction) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .stroke(
                action.role == .primary ? Color.clear : DesignTokens.borderColor.opacity(0.85),
                lineWidth: 1
            )
    }

    private var bubbleText: Text {
        let base = Text(message.content)
        if message.isStreaming {
            return base + Text(" |").foregroundColor(foregroundColor.opacity(cursorVisible ? 1 : 0.2))
        }
        return base
    }

    private var shouldUsePlainText: Bool {
        message.isStreaming || isCollapsed
    }

    private var shouldShowTypingIndicator: Bool {
        message.role == .assistant
            && message.isStreaming
            && message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

struct TypingIndicatorBubbleView: View {
    @State private var appeared = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                TypingIndicatorDotsView(dotColor: DesignTokens.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(DesignTokens.assistantBubbleColor)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.messageBubbleRadius))
            }

            Spacer(minLength: 40)
        }
        .offset(x: appeared ? 0 : -12, y: appeared ? 0 : 8)
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97, anchor: .bottomLeading)
        .onAppear {
            withAnimation(DesignTokens.motionEntrance) {
                appeared = true
            }
        }
    }
}

struct TypingIndicatorDotsView: View {
    let dotColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let cycleDuration = 2.1

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = (time / cycleDuration) * (.pi * 2) - (Double(index) * 0.55)
                    let wave = (sin(phase) + 1) / 2

                    Circle()
                        .fill(dotColor.opacity(0.32 + (wave * 0.6)))
                        .frame(width: 6, height: 6)
                        .scaleEffect(0.82 + (wave * 0.28))
                        .offset(y: -1.5 * wave)
                        .blur(radius: 0.15 + ((1 - wave) * 0.35))
                }
            }
            .frame(height: 14)
        }
    }
}

struct AttachmentChipView: View {
    let attachment: ChatAttachment
    var removable: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        if removable, attachment.isImage {
            RemovableImageAttachmentChipView(attachment: attachment, onRemove: onRemove)
        } else {
            standardChip
        }
    }

    @ViewBuilder
    private var standardChip: some View {
        let chip = HStack(spacing: 6) {
            Image(systemName: attachment.systemImageName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(DesignTokens.textSecondary)

            Text(attachment.fileName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DesignTokens.textPrimary)
                .lineLimit(1)

            if removable, let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.textSecondary.opacity(0.9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DesignTokens.surfaceColor.opacity(0.8))
        )
        .overlay(
            Capsule()
                .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
        )

        if removable {
            chip
        } else {
            Button(action: openAttachment) {
                chip
            }
            .buttonStyle(.plain)
            .help("Open \(attachment.fileName)")
        }
    }

    private func openAttachment() {
        NSWorkspace.shared.open(attachment.fileURL)
    }
}

private struct RemovableImageAttachmentChipView: View {
    let attachment: ChatAttachment
    let onRemove: (() -> Void)?

    private let thumbnailSize: CGFloat = 60

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image = NSImage(contentsOf: attachment.fileURL) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(DesignTokens.surfaceColor.opacity(0.9))

                        Image(systemName: attachment.systemImageName)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(DesignTokens.textSecondary)
                    }
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
            )

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .frame(width: thumbnailSize, height: thumbnailSize)
        .help(attachment.fileName)
    }
}

private struct ImageAttachmentPreviewView: View {
    let attachment: ChatAttachment

    @State private var isExpanded = false

    private let collapsedHeight: CGFloat = 128
    private let expandedHeight: CGFloat = 196

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = NSImage(contentsOf: attachment.fileURL) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 220)
                        .frame(height: isExpanded ? expandedHeight : collapsedHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DesignTokens.borderColor.opacity(0.7), lineWidth: 1)
                        )

                    Button(action: openAttachment) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DesignTokens.textPrimary)
                            .padding(6)
                            .background(.thinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    withAnimation(DesignTokens.motionPress) {
                        isExpanded.toggle()
                    }
                }

                Text(attachment.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DesignTokens.textSecondary)
                    .lineLimit(1)
            } else {
                AttachmentChipView(attachment: attachment)
            }
        }
        .frame(maxWidth: 220, alignment: .leading)
        .help("Click to resize. Use the arrow button to open the image.")
    }

    private func openAttachment() {
        NSWorkspace.shared.open(attachment.fileURL)
    }
}

private struct DocumentAttachmentPreviewView: View {
    let attachment: ChatAttachment

    @State private var textPreview = ""
    @State private var quickLookThumbnail: NSImage?
    @State private var didRequestPreview = false

    private let previewSize = CGSize(width: 440, height: 240)
    private let cardWidth: CGFloat = 220
    private let previewHeight: CGFloat = 110

    var body: some View {
        Button(action: openAttachment) {
            VStack(alignment: .leading, spacing: 10) {
                previewSurface
                    .frame(maxWidth: .infinity)
                    .frame(height: previewHeight)
                    .background(previewBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(DesignTokens.borderColor.opacity(0.75), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 6) {
                            Text(attachment.previewBadgeLabel)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())

                            Image(systemName: "arrow.up.forward.app")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DesignTokens.textPrimary)
                                .padding(7)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .padding(8)
                    }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: attachment.systemImageName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DesignTokens.textSecondary)
                        .frame(width: 18, height: 18)

                    Text(attachment.fileName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(DesignTokens.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Spacer(minLength: 0)
                }
            }
            .padding(10)
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DesignTokens.surfaceColor.opacity(0.9))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(DesignTokens.borderColor.opacity(0.8), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: cardWidth, alignment: .leading)
        .help("Open \(attachment.fileName)")
        .onAppear(perform: loadPreviewIfNeeded)
    }

    @ViewBuilder
    private var previewSurface: some View {
        switch attachment.preferredPreviewKind {
        case .textDocument:
            textDocumentSurface
        case .image:
            thumbnailSurface(image: NSImage(contentsOf: attachment.fileURL))
        case .document:
            thumbnailSurface(image: quickLookThumbnail)
        }
    }

    private var textDocumentSurface: some View {
        VStack(alignment: .leading, spacing: 6) {
            if textPreview.isEmpty {
                Text("Loading preview...")
                    .foregroundStyle(DesignTokens.textSecondary)
            } else {
                Text(textPreview)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
        }
        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
        .lineSpacing(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
    }

    @ViewBuilder
    private func thumbnailSurface(image: NSImage?) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            VStack(spacing: 8) {
                Image(systemName: attachment.systemImageName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DesignTokens.textSecondary)

                Text("Preview unavailable")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var previewBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                DesignTokens.surfaceAccent.opacity(0.2),
                DesignTokens.surfaceColor.opacity(0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func loadPreviewIfNeeded() {
        guard !didRequestPreview else { return }
        didRequestPreview = true

        switch attachment.preferredPreviewKind {
        case .textDocument:
            loadTextPreview()
        case .image:
            break
        case .document:
            loadQuickLookThumbnail()
        }
    }

    private func loadTextPreview() {
        let fileURL = attachment.fileURL

        Task.detached(priority: .utility) {
            let preview = readTextPreview(from: fileURL)
            await MainActor.run {
                textPreview = preview
            }
        }
    }

    private func loadQuickLookThumbnail() {
        let request = QLThumbnailGenerator.Request(
            fileAt: attachment.fileURL,
            size: previewSize,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let representation else { return }
            let image = NSImage(cgImage: representation.cgImage, size: previewSize)
            DispatchQueue.main.async {
                quickLookThumbnail = image
            }
        }
    }

    private func openAttachment() {
        NSWorkspace.shared.open(attachment.fileURL)
    }
}

private func readTextPreview(from fileURL: URL) -> String {
    guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]) else {
        return "Preview unavailable"
    }

    let previewData = data.prefix(2_400)
    let rawPreview = String(decoding: previewData, as: UTF8.self)
        .replacingOccurrences(of: "\r\n", with: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard !rawPreview.isEmpty else {
        return "Preview unavailable"
    }

    let collapsedLines = rawPreview
        .components(separatedBy: "\n")
        .prefix(6)
        .map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? " " : String(trimmed.prefix(62))
        }

    let preview = collapsedLines.joined(separator: "\n")
    return preview.count > 360 ? String(preview.prefix(360)) + "..." : preview
}

private struct MarkdownMessageView: View {
    let markdown: String

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case let .heading(level, text):
            MarkdownInlineText(markdown: text)
                .font(headingFont(level: level))
                .fontWeight(.semibold)
        case let .paragraph(text):
            MarkdownInlineText(markdown: text)
                .font(DesignTokens.messageFont)
        case let .unorderedList(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    MarkdownListItemView(marker: "•", text: item)
                }
            }
        case let .orderedList(items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    MarkdownListItemView(marker: "\(index + 1).", text: item)
                }
            }
        case let .quote(lines):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DesignTokens.borderColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        MarkdownInlineText(markdown: line)
                            .font(DesignTokens.messageFont)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        case let .code(language, code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(DesignTokens.textSecondary)
                }

                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignTokens.surfaceColor.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DesignTokens.borderColor.opacity(0.7), lineWidth: 1)
                )
            }
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .system(size: 17, weight: .semibold)
        case 2:
            return .system(size: 15, weight: .semibold)
        default:
            return .system(size: 14, weight: .semibold)
        }
    }
}

private struct MarkdownListItemView: View {
    let marker: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignTokens.textSecondary)
                .frame(width: 18, alignment: .trailing)

            MarkdownInlineText(markdown: text)
                .font(DesignTokens.messageFont)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MarkdownInlineText: View {
    let markdown: String

    var body: some View {
        Text(attributedText)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attributedText: AttributedString {
        do {
            return try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(
                    interpretedSyntax: .inlineOnlyPreservingWhitespace
                )
            )
        } catch {
            return AttributedString(markdown)
        }
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote([String])
    case code(language: String?, code: String)
}

private enum MarkdownBlockParser {
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let language = codeFenceLanguage(for: line) {
                index += 1
                var codeLines: [String] = []

                while index < lines.count, codeFenceLanguage(for: lines[index]) == nil {
                    codeLines.append(lines[index])
                    index += 1
                }

                if index < lines.count {
                    index += 1
                }

                blocks.append(.code(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            if let heading = heading(for: line) {
                blocks.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }

            if quoteContent(for: line) != nil {
                var quoteLines: [String] = []
                while index < lines.count {
                    let candidate = lines[index]
                    if candidate.trimmingCharacters(in: .whitespaces).isEmpty {
                        quoteLines.append("")
                        index += 1
                        continue
                    }

                    guard let content = quoteContent(for: candidate) else {
                        break
                    }
                    quoteLines.append(content)
                    index += 1
                }
                blocks.append(.quote(quoteLines))
                continue
            }

            if let item = unorderedListItem(for: line) {
                var items: [String] = [item]
                index += 1
                while index < lines.count, let nextItem = unorderedListItem(for: lines[index]) {
                    items.append(nextItem)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if let item = orderedListItem(for: line) {
                var items: [String] = [item]
                index += 1
                while index < lines.count, let nextItem = orderedListItem(for: lines[index]) {
                    items.append(nextItem)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            var paragraphLines: [String] = [line]
            index += 1
            while index < lines.count {
                let candidate = lines[index]
                if candidate.trimmingCharacters(in: .whitespaces).isEmpty || startsNewBlock(candidate) {
                    break
                }
                paragraphLines.append(candidate)
                index += 1
            }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
        }

        return blocks.isEmpty ? [.paragraph(markdown)] : blocks
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        codeFenceLanguage(for: line) != nil
            || heading(for: line) != nil
            || quoteContent(for: line) != nil
            || unorderedListItem(for: line) != nil
            || orderedListItem(for: line) != nil
    }

    private static func codeFenceLanguage(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("```") else {
            return nil
        }

        let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return language.isEmpty ? "" : language
    }

    private static func heading(for line: String) -> (level: Int, text: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else {
            return nil
        }

        let remainder = trimmed.dropFirst(hashes.count)
        guard remainder.first == " " else {
            return nil
        }

        return (hashes.count, remainder.trimmingCharacters(in: .whitespaces))
    }

    private static func quoteContent(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix(">") else {
            return nil
        }

        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func unorderedListItem(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            return nil
        }

        let marker = trimmed.prefix(2)
        guard marker == "- " || marker == "* " || marker == "+ " else {
            return nil
        }

        return String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func orderedListItem(for line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else {
            return nil
        }

        let numberPart = trimmed[..<dotIndex]
        guard !numberPart.isEmpty, numberPart.allSatisfy(\.isNumber) else {
            return nil
        }

        let afterDot = trimmed[trimmed.index(after: dotIndex)...]
        guard afterDot.first == " " else {
            return nil
        }

        return afterDot.trimmingCharacters(in: .whitespaces)
    }
}
