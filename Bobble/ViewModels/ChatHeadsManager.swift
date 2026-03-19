import Foundation
import SwiftUI
import Combine

class ChatHeadsManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var expandedSessionId: UUID?
    @Published var detectedBackend: CLIBackend?
    @Published var morphOriginY: CGFloat = 240
    @Published var isRevealed = false

    var onSessionsChanged: ((Int) -> Void)?
    var onSessionAdded: ((ChatSession) -> Void)?

    private var viewModels: [UUID: ChatSessionViewModel] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        detectBackend()
    }

    private func detectBackend() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let backend = CLIBackend.detect()
            DispatchQueue.main.async {
                self?.detectedBackend = backend
            }
        }
    }

    var expandedSession: ChatSession? {
        guard let id = expandedSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    func viewModel(for sessionId: UUID) -> ChatSessionViewModel? {
        return viewModels[sessionId]
    }

    func addSession() {
        let session = ChatSession()
        sessions.append(session)

        let vm = ChatSessionViewModel(session: session, backend: detectedBackend)
        vm.onSessionUpdated = { [weak self] updated in
            guard let self = self else { return }
            var syncedSession = updated
            if self.expandedSessionId == updated.id {
                syncedSession.markAssistantMessagesRead()
                self.viewModels[updated.id]?.markAssistantMessagesRead(notify: false)
            }
            if let idx = self.sessions.firstIndex(where: { $0.id == updated.id }) {
                self.sessions[idx] = syncedSession
            }
        }
        viewModels[session.id] = vm

        onSessionsChanged?(sessions.count)
        onSessionAdded?(session)
    }

    func removeSession(_ session: ChatSession) {
        viewModels[session.id]?.terminate()
        viewModels.removeValue(forKey: session.id)
        sessions.removeAll { $0.id == session.id }
        if expandedSessionId == session.id {
            expandedSessionId = nil
        }
        onSessionsChanged?(sessions.count)
    }

    func markRead(sessionId: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var updatedSession = sessions[idx]
        updatedSession.markAssistantMessagesRead()
        sessions[idx] = updatedSession
        viewModels[sessionId]?.markAssistantMessagesRead(notify: false)
    }

    func terminateAll() {
        for vm in viewModels.values {
            vm.terminate()
        }
    }
}
