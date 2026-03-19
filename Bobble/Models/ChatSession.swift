import Foundation

struct ChatSession: Identifiable, Codable {
    static let defaultChatHeadSymbol = "💬"

    let id: UUID
    var name: String
    var chatHeadSymbol: String
    var provider: CLIBackend
    var selectedModel: CodexModelOption
    var messages: [ChatMessage]
    var state: SessionState
    var cliSessionId: String
    var cliSessionBackend: CLIBackend?
    var workspaceDirectory: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool

    enum SessionState: Codable {
        case idle
        case running
        case error(String)

        private enum CodingKeys: String, CodingKey {
            case kind
            case message
        }

        private enum Kind: String, Codable {
            case idle
            case running
            case error
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .idle:
                self = .idle
            case .running:
                self = .running
            case .error:
                self = .error(try container.decode(String.self, forKey: .message))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .idle:
                try container.encode(Kind.idle, forKey: .kind)
            case .running:
                try container.encode(Kind.running, forKey: .kind)
            case .error(let message):
                try container.encode(Kind.error, forKey: .kind)
                try container.encode(message, forKey: .message)
            }
        }
    }

    var displayChatHeadSymbol: String {
        Self.sanitizedChatHeadSymbol(from: chatHeadSymbol) ?? Self.defaultChatHeadSymbol
    }

    var hasUnread: Bool {
        messages.contains { $0.role == .assistant && $0.isNew }
    }

    var qualifiesForHistory: Bool {
        messages.contains { $0.role == .user }
    }

    mutating func markAssistantMessagesRead() {
        for index in messages.indices where messages[index].role == .assistant && messages[index].isNew {
            messages[index].isNew = false
        }
        touchUpdatedAt()
    }

    var attachmentsDirectory: String {
        let directoryURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return directoryURL.path
    }

    init(
        id: UUID = UUID(),
        name: String = "New Chat",
        chatHeadSymbol: String = Self.defaultChatHeadSymbol,
        provider: CLIBackend = .codex,
        selectedModel: CodexModelOption = .default,
        messages: [ChatMessage] = [],
        state: SessionState = .idle,
        cliSessionId: String = UUID().uuidString,
        cliSessionBackend: CLIBackend? = nil,
        workspaceDirectory: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.chatHeadSymbol = chatHeadSymbol
        self.provider = provider
        self.selectedModel = selectedModel
        self.messages = messages
        self.state = state
        self.cliSessionId = cliSessionId
        self.cliSessionBackend = cliSessionBackend
        self.workspaceDirectory = workspaceDirectory ?? Self.createWorkspaceDirectory(for: id)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    private static func createWorkspaceDirectory(for sessionId: UUID) -> String {
        let fm = FileManager.default

        let appSupportBase = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let sessionDir = appSupportBase
            .appendingPathComponent("Bobble", isDirectory: true)
            .appendingPathComponent("ChatWorkspaces", isDirectory: true)
            .appendingPathComponent(sessionId.uuidString, isDirectory: true)

        do {
            try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true, attributes: nil)
            return sessionDir.path
        } catch {
            let fallback = fm.temporaryDirectory
                .appendingPathComponent("BobbleChatWorkspaces", isDirectory: true)
                .appendingPathComponent(sessionId.uuidString, isDirectory: true)
            try? fm.createDirectory(at: fallback, withIntermediateDirectories: true, attributes: nil)
            return fallback.path
        }
    }

    static func sanitizedChatHeadSymbol(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for character in trimmed where !character.isWhitespaceLike {
            if character.isEmojiBadge {
                return String(character)
            }
        }

        return nil
    }

    mutating func updateChatHeadSymbol(from rawValue: String?) {
        guard let rawValue,
              let symbol = Self.sanitizedChatHeadSymbol(from: rawValue) else {
            return
        }

        chatHeadSymbol = symbol
        touchUpdatedAt()
    }

    mutating func touchUpdatedAt() {
        updatedAt = Date()
    }

    func normalizedForRestore() -> ChatSession {
        var restored = self
        if case .running = restored.state {
            restored.state = .idle
        }
        for index in restored.messages.indices where restored.messages[index].isStreaming {
            restored.messages[index].isStreaming = false
        }
        return restored
    }
}

private extension Character {
    var isEmojiBadge: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        return firstScalar.properties.isEmojiPresentation
            || (firstScalar.properties.isEmoji && unicodeScalars.count > 1)
    }

    var isWhitespaceLike: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
