import Foundation

struct ConversationTurnRequest {
    let backend: CLIBackend
    let prompt: String
    let imagePaths: [String]
    let sessionId: String
    let isResume: Bool
    let workingDirectory: String
    let model: String?
    let executionMode: ConversationExecutionMode
}

struct ConversationInterruption {
    enum Kind {
        case permission
        case question
    }

    enum ResponseMode {
        case informational
        case actionButtons
        case textReply
    }

    struct Action {
        enum Role {
            case primary
            case secondary
            case destructive
        }

        let id: String
        let label: String
        let role: Role
        let transportValue: String?
    }

    let id: String
    let kind: Kind
    let provider: CLIBackend
    let title: String
    let details: String
    let actions: [Action]
    let responseMode: ResponseMode
}

protocol ConversationTransport: AnyObject {
    var persistsAcrossTurns: Bool { get }
    var onTextChunk: ((String) -> Void)? { get set }
    var onResult: ((String) -> Void)? { get set }
    var onEventText: ((String) -> Void)? { get set }
    var onInterruption: ((ConversationInterruption) -> Void)? { get set }
    var onComplete: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onSessionId: ((String) -> Void)? { get set }
    var onAssistantMessageStarted: (() -> Void)? { get set }
    var onTurnCompleted: (() -> Void)? { get set }

    func sendTurn(_ request: ConversationTurnRequest)
    func stop()
    func resolveInterruption(id: String, actionTransportValue: String?, textResponse: String?)
}

final class CLIConversationTransport: ConversationTransport {
    let persistsAcrossTurns = false
    var onTextChunk: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onEventText: ((String) -> Void)?
    var onInterruption: ((ConversationInterruption) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSessionId: ((String) -> Void)?
    var onAssistantMessageStarted: (() -> Void)?
    var onTurnCompleted: (() -> Void)?

    private var processManager: CLIProcessManager?
    private var didStopForBlockingInterruption = false

    func sendTurn(_ request: ConversationTurnRequest) {
        stop()
        didStopForBlockingInterruption = false

        guard let executablePath = request.backend.resolvedPath() else {
            onError?(request.backend.missingCLIMessage)
            return
        }

        let processManager = CLIProcessManager(
            backend: request.backend,
            executablePath: executablePath,
            model: request.model,
            prompt: request.prompt,
            imagePaths: request.imagePaths,
            sessionId: request.sessionId,
            isResume: request.isResume,
            workingDirectory: request.workingDirectory,
            launchPurpose: .conversation(request.executionMode)
        )
        self.processManager = processManager

        processManager.onTextChunk = { [weak self] text in
            self?.onTextChunk?(text)
        }

        processManager.onResult = { [weak self] text in
            self?.onResult?(text)
        }

        processManager.onEventText = { [weak self] text in
            guard let self else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if request.executionMode == .ask,
               let interruption = self.makeBlockingInterruption(for: request.backend, text: trimmed) {
                self.didStopForBlockingInterruption = true
                self.onInterruption?(interruption)
                self.stop()
                return
            }

            self.onEventText?(trimmed)
        }

        processManager.onComplete = { [weak self] in
            guard let self else { return }
            self.processManager = nil
            self.onComplete?()
        }

        processManager.onSessionId = { [weak self] id in
            self?.onSessionId?(id)
        }

        processManager.onAssistantMessageStarted = { [weak self] in
            self?.onAssistantMessageStarted?()
        }

        processManager.onTurnCompleted = { [weak self] in
            self?.onTurnCompleted?()
        }

        processManager.onError = { [weak self] error in
            guard let self else { return }
            if self.didStopForBlockingInterruption {
                self.didStopForBlockingInterruption = false
                return
            }
            self.processManager = nil
            self.onError?(error)
        }

        processManager.start()
    }

    func stop() {
        processManager?.stop()
        processManager = nil
    }

    func resolveInterruption(id: String, actionTransportValue: String?, textResponse: String?) {
        // One-shot CLI transports render interruptions as informative cards only.
    }

    private func makeBlockingInterruption(for backend: CLIBackend, text: String) -> ConversationInterruption? {
        let normalized = text.lowercased()
        let isPermissionLike = normalized.contains("approval")
            || normalized.contains("permission")
            || normalized.contains("request user input")
            || normalized.contains("user input")
            || normalized.contains("question")

        guard isPermissionLike else { return nil }

        let title: String
        switch backend {
        case .codex:
            title = "Codex needs approval"
        case .claude:
            title = "Claude needs input"
        case .copilot:
            title = "Copilot needs input"
        }

        return ConversationInterruption(
            id: UUID().uuidString,
            kind: normalized.contains("question") ? .question : .permission,
            provider: backend,
            title: title,
            details: text,
            actions: [],
            responseMode: .informational
        )
    }
}
