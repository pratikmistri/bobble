import Foundation
import Combine

class ChatSessionViewModel: ObservableObject {
    @Published var session: ChatSession
    @Published var inputText: String = ""

    var onSessionUpdated: ((ChatSession) -> Void)?

    private let backend: CLIBackend?
    private var processManager: CLIProcessManager?
    private var cancellables = Set<AnyCancellable>()

    init(session: ChatSession, backend: CLIBackend?) {
        self.session = session
        self.backend = backend
    }

    func send() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        inputText = ""

        // Auto-name from first prompt
        if session.messages.isEmpty {
            let truncated = String(prompt.prefix(30))
            session.name = truncated
        }

        let userMessage = ChatMessage(role: .user, content: prompt)
        session.messages.append(userMessage)
        notifyUpdate()

        guard let backend = backend, let path = backend.resolvedPath() else {
            let errorMsg = ChatMessage(
                role: .error,
                content: "Codex CLI not found. Install with `npm install -g @openai/codex`."
            )
            session.messages.append(errorMsg)
            session.state = .error("CLI not found")
            notifyUpdate()
            return
        }

        session.state = .running
        notifyUpdate()

        let pm = CLIProcessManager(
            backend: backend,
            executablePath: path,
            prompt: prompt,
            sessionId: session.cliSessionId,
            isResume: session.messages.filter({ $0.role == .user }).count > 1,
            workingDirectory: session.workspaceDirectory
        )
        self.processManager = pm

        pm.onTextChunk = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.applyAssistantDelta(text)
                self.notifyUpdate()
            }
        }

        pm.onResult = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.completeAssistantMessage(with: text)
                self.notifyUpdate()
            }
        }

        pm.onEventText = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let kind = self.classifySystemEventKind(trimmed)
                self.session.messages.append(ChatMessage(role: .system, content: trimmed, kind: kind))
                self.notifyUpdate()
            }
        }

        pm.onComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let idx = self.session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    self.session.messages[idx].isStreaming = false
                    // If empty response, add a note
                    if self.session.messages[idx].content.isEmpty {
                        let hasFollowupEvent = self.session.messages.indices.contains(where: { messageIndex in
                            messageIndex > idx
                            && self.session.messages[messageIndex].role == .system
                            && !self.session.messages[messageIndex].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        })
                        if hasFollowupEvent {
                            self.session.messages.remove(at: idx)
                        } else {
                            self.session.messages[idx].content = "(No response)"
                        }
                    }
                }
                self.session.state = .idle
                self.processManager = nil
                self.notifyUpdate()
            }
        }

        pm.onSessionId = { [weak self] newId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.session.cliSessionId != newId {
                    self.session.cliSessionId = newId
                    self.notifyUpdate()
                }
            }
        }

        pm.onAssistantMessageStarted = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.startAssistantMessageIfNeeded()
                self.notifyUpdate()
            }
        }

        pm.onError = { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Remove the empty streaming message
                if let idx = self.session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    self.session.messages.remove(at: idx)
                }
                let errorMsg = ChatMessage(role: .error, content: error)
                self.session.messages.append(errorMsg)
                self.session.state = .error(error)
                self.processManager = nil
                self.notifyUpdate()
            }
        }

        pm.start()
    }

    func terminate() {
        processManager?.stop()
        processManager = nil
    }

    private func notifyUpdate() {
        objectWillChange.send()
        onSessionUpdated?(session)
    }

    private func startAssistantMessageIfNeeded() {
        if session.messages.contains(where: { $0.role == .assistant && $0.isStreaming }) {
            return
        }
        session.messages.append(ChatMessage(role: .assistant, content: "", isStreaming: true))
    }

    private func applyAssistantDelta(_ text: String) {
        guard !text.isEmpty else { return }
        startAssistantMessageIfNeeded()

        guard let idx = session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) else {
            return
        }

        let current = session.messages[idx].content
        // Some backends may emit both deltas and full snapshots. If we get a full
        // snapshot, replace instead of append to prevent duplicated text.
        if text == current {
            return
        } else if text.hasPrefix(current) {
            session.messages[idx].content = text
        } else {
            session.messages[idx].content += text
        }
    }

    private func completeAssistantMessage(with text: String) {
        if let idx = session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            if !text.isEmpty {
                session.messages[idx].content = text
            }
            session.messages[idx].isStreaming = false
            if session.messages[idx].content.isEmpty {
                session.messages.remove(at: idx)
            }
            return
        }

        guard !text.isEmpty else { return }
        session.messages.append(ChatMessage(role: .assistant, content: text))
    }

    private func classifySystemEventKind(_ text: String) -> ChatMessage.Kind {
        let normalized = text.lowercased()

        let permissionMarkers = [
            "codex approval",
            "codex permission",
            "approval",
            "permission",
            "request user input",
            "user input"
        ]
        if permissionMarkers.contains(where: normalized.contains) {
            return .permission
        }

        let thoughtMarkers = [
            "agent thought",
            "codex reasoning",
            "reasoning"
        ]
        if thoughtMarkers.contains(where: normalized.contains) {
            return .agentThought
        }

        let isToolOrCommandEvent = normalized.hasPrefix("running command:")
            || normalized.hasPrefix("command ")
            || normalized.hasPrefix("running tool:")
            || normalized.contains("tool call")
            || normalized.contains("tool use")
        if isToolOrCommandEvent {
            return .toolUse
        }

        return .regular
    }
}
