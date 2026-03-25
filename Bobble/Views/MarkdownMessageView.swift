import SwiftUI

struct MarkdownMessageView: View {
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
