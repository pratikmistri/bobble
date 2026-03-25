import Foundation

enum ConversationExecutionMode: String, CaseIterable, Identifiable, Codable {
    case ask
    case bypass

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask:
            return "Ask"
        case .bypass:
            return "Bypass"
        }
    }

    var helpText: String {
        switch self {
        case .ask:
            return "Ask before actions that need permission."
        case .bypass:
            return "Bypass approvals for this conversation."
        }
    }

    static func defaultMode(for provider: CLIBackend) -> ConversationExecutionMode {
        switch provider {
        case .codex:
            return .bypass
        case .copilot, .claude:
            return .ask
        }
    }
}

struct ChatSession: Identifiable, Codable {
    static let defaultChatHeadSymbol = "Bobble1"
    static let availableChatHeadImageNames: [String] = (1...9).map { "Bobble\($0)" }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case chatHeadSymbol
        case hasAssignedChatHeadSymbol
        case provider
        case selectedModel
        case conversationMode
        case messages
        case state
        case cliSessionId
        case cliSessionBackend
        case workspaceDirectory
        case createdAt
        case updatedAt
        case isArchived
    }

    let id: UUID
    var name: String
    var chatHeadSymbol: String
    var hasAssignedChatHeadSymbol: Bool
    var provider: CLIBackend
    var conversationMode: ConversationExecutionMode
    var selectedModel: ProviderModelOption
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

    var chatHeadImageName: String {
        guard hasAssignedChatHeadSymbol,
              let imageName = Self.sanitizedChatHeadImageName(from: chatHeadSymbol) else {
            return Self.chatHeadImageName(for: id)
        }
        return imageName
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
        hasAssignedChatHeadSymbol: Bool = false,
        provider: CLIBackend = .codex,
        conversationMode: ConversationExecutionMode? = nil,
        selectedModel: ProviderModelOption = .automatic,
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
        let sanitizedChatHeadSymbol = Self.sanitizedChatHeadImageName(from: chatHeadSymbol)
        self.chatHeadSymbol = sanitizedChatHeadSymbol ?? Self.defaultChatHeadSymbol
        self.hasAssignedChatHeadSymbol = hasAssignedChatHeadSymbol && sanitizedChatHeadSymbol != nil
        self.provider = provider
        self.conversationMode = conversationMode ?? ConversationExecutionMode.defaultMode(for: provider)
        self.selectedModel = selectedModel.normalized(for: provider)
        self.messages = messages
        self.state = state
        self.cliSessionId = cliSessionId
        self.cliSessionBackend = cliSessionBackend
        self.workspaceDirectory = workspaceDirectory ?? Self.createWorkspaceDirectory(for: id)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let id = try container.decode(UUID.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let chatHeadSymbol = try container.decodeIfPresent(String.self, forKey: .chatHeadSymbol) ?? Self.defaultChatHeadSymbol
        let hasAssignedChatHeadSymbol = try container.decodeIfPresent(Bool.self, forKey: .hasAssignedChatHeadSymbol)
            ?? (chatHeadSymbol != Self.defaultChatHeadSymbol
                && Self.sanitizedChatHeadImageName(from: chatHeadSymbol) != nil)
        let provider = try container.decode(CLIBackend.self, forKey: .provider)
        let conversationMode = try container.decodeIfPresent(ConversationExecutionMode.self, forKey: .conversationMode)
            ?? ConversationExecutionMode.defaultMode(for: provider)
        let selectedModel = try container.decodeIfPresent(ProviderModelOption.self, forKey: .selectedModel) ?? .automatic
        let messages = try container.decode([ChatMessage].self, forKey: .messages)
        let state = try container.decode(SessionState.self, forKey: .state)
        let cliSessionId = try container.decode(String.self, forKey: .cliSessionId)
        let cliSessionBackend = try container.decodeIfPresent(CLIBackend.self, forKey: .cliSessionBackend)
        let workspaceDirectory = try container.decodeIfPresent(String.self, forKey: .workspaceDirectory)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        let isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false

        self.init(
            id: id,
            name: name,
            chatHeadSymbol: chatHeadSymbol,
            hasAssignedChatHeadSymbol: hasAssignedChatHeadSymbol,
            provider: provider,
            conversationMode: conversationMode,
            selectedModel: selectedModel,
            messages: messages,
            state: state,
            cliSessionId: cliSessionId,
            cliSessionBackend: cliSessionBackend,
            workspaceDirectory: workspaceDirectory,
            createdAt: createdAt,
            updatedAt: updatedAt,
            isArchived: isArchived
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(chatHeadSymbol, forKey: .chatHeadSymbol)
        try container.encode(hasAssignedChatHeadSymbol, forKey: .hasAssignedChatHeadSymbol)
        try container.encode(provider, forKey: .provider)
        try container.encode(conversationMode, forKey: .conversationMode)
        try container.encode(selectedModel, forKey: .selectedModel)
        try container.encode(messages, forKey: .messages)
        try container.encode(state, forKey: .state)
        try container.encode(cliSessionId, forKey: .cliSessionId)
        try container.encodeIfPresent(cliSessionBackend, forKey: .cliSessionBackend)
        try container.encode(workspaceDirectory, forKey: .workspaceDirectory)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(isArchived, forKey: .isArchived)
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

    static func sanitizedChatHeadImageName(from rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        guard lowercased.hasPrefix("bobble") else { return nil }
        let suffix = lowercased.dropFirst("bobble".count)
        guard let number = Int(suffix), (1...availableChatHeadImageNames.count).contains(number) else { return nil }
        return "Bobble\(number)"
    }

    static func mappedChatHeadImageName(from rawValue: String) -> String? {
        if let sanitized = sanitizedChatHeadImageName(from: rawValue) {
            return sanitized
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let hash = abs(trimmed.hashValue)
        return availableChatHeadImageNames[hash % availableChatHeadImageNames.count]
    }

    private static func chatHeadImageName(for id: UUID) -> String {
        let hash = abs(id.uuidString.hashValue)
        return availableChatHeadImageNames[hash % availableChatHeadImageNames.count]
    }

    mutating func updateChatHeadSymbol(from rawValue: String?) {
        guard let rawValue,
              let imageName = Self.mappedChatHeadImageName(from: rawValue) else {
            return
        }

        chatHeadSymbol = imageName
        hasAssignedChatHeadSymbol = true
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
        for index in restored.messages.indices {
            if restored.messages[index].isStreaming {
                restored.messages[index].isStreaming = false
            }
            if !restored.messages[index].interruptionActions.isEmpty {
                restored.messages[index].interruptionActions = []
            }
        }
        return restored
    }
}
