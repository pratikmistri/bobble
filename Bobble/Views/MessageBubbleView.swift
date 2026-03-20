import AppKit
import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage
    let index: Int

    @State private var appeared = false
    @State private var cursorVisible = true
    @State private var isExpanded = false

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
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(fileAttachments) { attachment in
                                            AttachmentChipView(attachment: attachment)
                                        }
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
            return DesignTokens.surfaceAccent.opacity(0.5)
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
            return DesignTokens.textSecondary
        case .error:
            return .red
        }
    }

    @ViewBuilder
    private var messageContent: some View {
        if shouldShowTypingIndicator {
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
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(DesignTokens.textPrimary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(ThinLiquidGlassButtonStyle(shape: Circle(), pressedScale: 0.9))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            ThinLiquidGlassBackground(shape: Capsule())
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
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(ThinLiquidGlassButtonStyle(shape: Circle(), emphasized: true, pressedScale: 0.9))
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
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(ThinLiquidGlassButtonStyle(shape: Circle(), emphasized: true, pressedScale: 0.9))
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
