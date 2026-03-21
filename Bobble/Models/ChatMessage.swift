import Foundation
import UniformTypeIdentifiers

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
