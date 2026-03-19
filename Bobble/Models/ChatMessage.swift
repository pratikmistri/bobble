import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var isNew: Bool
    var kind: Kind

    enum Role {
        case user
        case assistant
        case system
        case error
    }

    enum Kind {
        case regular
        case permission
        case agentThought
        case toolUse
    }

    init(role: Role, content: String, isStreaming: Bool = false, kind: Kind = .regular) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
        self.isNew = role == .assistant
        self.kind = kind
    }
}
