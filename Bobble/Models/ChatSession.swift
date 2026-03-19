import Foundation

struct ChatSession: Identifiable {
    let id: UUID
    var name: String
    var messages: [ChatMessage]
    var state: SessionState
    var cliSessionId: String
    var workspaceDirectory: String

    enum SessionState {
        case idle
        case running
        case error(String)
    }

    var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1)).uppercased()
    }

    var hasUnread: Bool {
        messages.contains { $0.role == .assistant && $0.isNew }
    }

    mutating func markAssistantMessagesRead() {
        for index in messages.indices where messages[index].role == .assistant && messages[index].isNew {
            messages[index].isNew = false
        }
    }

    var attachmentsDirectory: String {
        let directoryURL = URL(fileURLWithPath: workspaceDirectory, isDirectory: true)
            .appendingPathComponent("attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.path
    }

    init(name: String = "New Chat") {
        let newId = UUID()
        self.id = newId
        self.name = name
        self.messages = []
        self.state = .idle
        self.cliSessionId = UUID().uuidString
        self.workspaceDirectory = Self.createWorkspaceDirectory(for: newId)
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
            try fm.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            return sessionDir.path
        } catch {
            let fallback = fm.temporaryDirectory
                .appendingPathComponent("BobbleChatWorkspaces", isDirectory: true)
                .appendingPathComponent(sessionId.uuidString, isDirectory: true)
            try? fm.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback.path
        }
    }
}
