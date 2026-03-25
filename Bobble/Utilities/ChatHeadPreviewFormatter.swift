import Foundation

struct ChatHeadPreviewSnapshot: Equatable {
    let senderLabel: String
    let message: String
}

enum ChatHeadPreviewFormatter {
    static func preview(for session: ChatSession) -> ChatHeadPreviewSnapshot? {
        if case .running = session.state {
            return ChatHeadPreviewSnapshot(
                senderLabel: "Live",
                message: "Working on your latest message..."
            )
        }

        guard let message = session.messages.reversed().first(where: shouldIncludeInPreview(_:)) else {
            return nil
        }

        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return ChatHeadPreviewSnapshot(
                senderLabel: senderLabel(for: message),
                message: trimmed.replacingOccurrences(of: "\n", with: " ")
            )
        }

        guard !message.attachments.isEmpty else {
            return nil
        }

        return ChatHeadPreviewSnapshot(
            senderLabel: senderLabel(for: message),
            message: AttachmentSummaryFormatter.summary(for: message.attachments)
        )
    }

    private static func shouldIncludeInPreview(_ message: ChatMessage) -> Bool {
        guard message.role != .system else { return false }
        return !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !message.attachments.isEmpty
    }

    private static func senderLabel(for message: ChatMessage) -> String {
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
}
