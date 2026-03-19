import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var isNew: Bool

    enum Role {
        case user
        case assistant
        case system
        case error
    }

    init(role: Role, content: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.isStreaming = isStreaming
        self.isNew = role == .assistant
    }
}
