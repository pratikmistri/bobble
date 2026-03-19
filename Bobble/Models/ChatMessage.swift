import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var attachments: [ChatAttachment]
    let timestamp: Date
    var isStreaming: Bool
    var isNew: Bool
    var kind: Kind

    enum Role: String, Codable {
        case user
        case assistant
        case system
        case error
    }

    enum Kind: String, Codable {
        case regular
        case permission
        case agentThought
        case toolUse
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [ChatAttachment] = [],
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        isNew: Bool? = nil,
        kind: Kind = .regular
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.isNew = isNew ?? (role == .assistant)
        self.kind = kind
    }
}

struct ChatAttachment: Identifiable, Hashable, Codable {
    let id: UUID
    let kind: Kind
    let fileName: String
    let filePath: String
    let relativePath: String

    enum Kind: String, Codable {
        case file
        case image
    }

    init(id: UUID = UUID(), kind: Kind, fileName: String, filePath: String, relativePath: String) {
        self.id = id
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
