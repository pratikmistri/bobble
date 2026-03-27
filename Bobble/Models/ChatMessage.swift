import Foundation
import UniformTypeIdentifiers

struct ChatMessage: Identifiable, Codable {
    struct InterruptionAction: Identifiable, Hashable, Codable {
        enum Role: String, Codable {
            case primary
            case secondary
            case destructive
        }

        let id: UUID
        var title: String
        var role: Role
        var payload: String?

        init(
            id: UUID = UUID(),
            title: String,
            role: Role = .primary,
            payload: String? = nil
        ) {
            self.id = id
            self.title = title
            self.role = role
            self.payload = payload
        }
    }

    let id: UUID
    let role: Role
    var content: String
    var attachments: [ChatAttachment]
    var interruptionTitle: String?
    var interruptionDetails: String?
    var interruptionActions: [InterruptionAction]
    let timestamp: Date
    var isStreaming: Bool
    var isNew: Bool
    var kind: Kind

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachments
        case interruptionTitle
        case interruptionDetails
        case interruptionActions
        case timestamp
        case isStreaming
        case isNew
        case kind
    }

    enum Role: String, Codable {
        case user
        case assistant
        case system
        case error
    }

    enum Kind: String, Codable {
        case regular
        case permission
        case question
        case agentThought
        case toolUse
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachments: [ChatAttachment] = [],
        interruptionTitle: String? = nil,
        interruptionDetails: String? = nil,
        interruptionActions: [InterruptionAction] = [],
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        isNew: Bool? = nil,
        kind: Kind = .regular
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.interruptionTitle = interruptionTitle
        self.interruptionDetails = interruptionDetails
        self.interruptionActions = interruptionActions
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.isNew = isNew ?? (role == .assistant)
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: .id)
        self.role = try container.decode(Role.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.attachments = try container.decodeIfPresent([ChatAttachment].self, forKey: .attachments) ?? []
        self.interruptionTitle = try container.decodeIfPresent(String.self, forKey: .interruptionTitle)
        self.interruptionDetails = try container.decodeIfPresent(String.self, forKey: .interruptionDetails)
        self.interruptionActions = try container.decodeIfPresent([InterruptionAction].self, forKey: .interruptionActions) ?? []
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.isStreaming = try container.decodeIfPresent(Bool.self, forKey: .isStreaming) ?? false
        self.isNew = try container.decodeIfPresent(Bool.self, forKey: .isNew) ?? (role == .assistant)
        self.kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .regular
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(attachments, forKey: .attachments)
        try container.encodeIfPresent(interruptionTitle, forKey: .interruptionTitle)
        try container.encodeIfPresent(interruptionDetails, forKey: .interruptionDetails)
        try container.encode(interruptionActions, forKey: .interruptionActions)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(isStreaming, forKey: .isStreaming)
        try container.encode(isNew, forKey: .isNew)
        try container.encode(kind, forKey: .kind)
    }

    var isInterruptionCard: Bool {
        kind == .permission || kind == .question
    }

    var isVisibleInPrimaryTimeline: Bool {
        switch role {
        case .user, .assistant, .error:
            return true
        case .system:
            return kind == .agentThought || isInterruptionCard
        }
    }

    var interruptionCardTitle: String? {
        interruptionTitle ?? defaultInterruptionCardTitle
    }

    var interruptionCardBody: String {
        interruptionDetails ?? content
    }

    private var defaultInterruptionCardTitle: String? {
        switch kind {
        case .permission:
            return "Permission required"
        case .question:
            return "Question"
        case .regular, .agentThought, .toolUse:
            return nil
        }
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

    var uniformType: UTType? {
        let pathExtension = fileURL.pathExtension.isEmpty
            ? (fileName as NSString).pathExtension
            : fileURL.pathExtension
        guard !pathExtension.isEmpty else { return nil }
        return UTType(filenameExtension: pathExtension)
    }

    var isImage: Bool {
        kind == .image
    }

    var isTextPreviewable: Bool {
        guard let uniformType else {
            return fallbackTextExtensions.contains((fileName as NSString).pathExtension.lowercased())
        }

        return uniformType.conforms(to: .text)
            || uniformType.conforms(to: .sourceCode)
            || uniformType.conforms(to: .json)
            || uniformType.conforms(to: .xml)
    }

    var preferredPreviewKind: PreviewKind {
        if isImage {
            return .image
        }

        if isTextPreviewable {
            return .textDocument
        }

        return .document
    }

    var previewBadgeLabel: String {
        let pathExtension = (fileName as NSString).pathExtension
        guard !pathExtension.isEmpty else { return "FILE" }
        return pathExtension.uppercased()
    }

    var systemImageName: String {
        if isImage {
            return "photo"
        }

        guard let uniformType else { return "doc" }

        if uniformType.conforms(to: .pdf) {
            return "doc.richtext"
        }
        if uniformType.conforms(to: .movie) {
            return "film"
        }
        if uniformType.conforms(to: .audio) {
            return "waveform"
        }
        if uniformType.conforms(to: .archive) {
            return "archivebox"
        }
        if uniformType.conforms(to: .json) || uniformType.conforms(to: .sourceCode) {
            return "curlybraces"
        }
        if uniformType.conforms(to: .text) {
            return "doc.text"
        }

        return "doc"
    }

    enum PreviewKind {
        case image
        case textDocument
        case document
    }

    private var fallbackTextExtensions: Set<String> {
        [
            "txt", "md", "markdown", "json", "jsonl", "yaml", "yml", "xml",
            "swift", "m", "mm", "h", "c", "cc", "cpp", "js", "ts", "tsx", "jsx",
            "html", "css", "scss", "sql", "sh", "zsh", "py", "rb", "go", "rs"
        ]
    }
}
