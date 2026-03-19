import Foundation

struct ChatMessage: Identifiable {
    let id: UUID
    let role: Role
    var content: String
    var attachments: [ChatAttachment]
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

    init(
        role: Role,
        content: String,
        attachments: [ChatAttachment] = [],
        isStreaming: Bool = false,
        kind: Kind = .regular
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = Date()
        self.isStreaming = isStreaming
        self.isNew = role == .assistant
        self.kind = kind
    }
}

struct ChatAttachment: Identifiable, Hashable {
    let id: UUID
    let kind: Kind
    let fileName: String
    let filePath: String
    let relativePath: String

    enum Kind: String {
        case file
        case image
    }

    init(kind: Kind, fileName: String, filePath: String, relativePath: String) {
        self.id = UUID()
        self.kind = kind
        self.fileName = fileName
        self.filePath = filePath
        self.relativePath = relativePath
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var isImage: Bool {
        kind == .image
    }

    var systemImageName: String {
        isImage ? "photo" : "doc"
    }
}
