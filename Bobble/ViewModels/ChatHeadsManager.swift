import Foundation
import SwiftUI
import Combine

class ChatHeadsManager: ObservableObject {
    @Published var sessions: [ChatSession] = []
    @Published var expandedSessionId: UUID? {
        didSet {
            syncSelectedProviderFromExpandedSession()
        }
    }
    @Published var closingSessionId: UUID?
    @Published var deletingSessionId: UUID?
    @Published var selectedProvider: CLIBackend = .codex {
        didSet {
            onSelectedProviderChanged?(selectedProvider)
        }
    }
    @Published var availableBackends: Set<CLIBackend> = []
    @Published var morphOriginY: CGFloat = 240
    @Published var isRevealed = false

    var onSessionsChanged: ((Int) -> Void)?
    var onSessionAdded: ((ChatSession) -> Void)?
    var onSelectedProviderChanged: ((CLIBackend) -> Void)?

    private var viewModels: [UUID: ChatSessionViewModel] = [:]
    private var cancellables = Set<AnyCancellable>()

    init() {
        detectAvailableBackends()
    }

    private func detectAvailableBackends() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let available = Set(CLIBackend.availableBackends())
            let preferred = CLIBackend.preferredDefault(from: available) ?? .codex
            DispatchQueue.main.async {
                guard let self else { return }
                self.availableBackends = available
                if self.sessions.isEmpty {
                    self.selectedProvider = preferred
                }
            }
        }
    }

    var expandedSession: ChatSession? {
        guard let id = expandedSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    var hasMixedProviders: Bool {
        Set(sessions.map(\.provider)).count > 1
    }

    func viewModel(for sessionId: UUID) -> ChatSessionViewModel? {
        return viewModels[sessionId]
    }

    func addSession() {
        let session = ChatSession(provider: selectedProvider)
        sessions.append(session)

        let vm = ChatSessionViewModel(session: session)
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

    func updateSelectedProvider(_ provider: CLIBackend) {
        if selectedProvider != provider {
            selectedProvider = provider
        }

        guard let sessionId = activeSessionId else { return }
        setProvider(provider, for: sessionId)
    }

    func setProvider(_ provider: CLIBackend, for sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        guard sessions[index].provider != provider else { return }

        var updatedSession = sessions[index]
        updatedSession.provider = provider
        sessions[index] = updatedSession
        viewModels[sessionId]?.updateProvider(provider)

        if expandedSessionId == sessionId && selectedProvider != provider {
            selectedProvider = provider
        }
    }

    func removeSession(_ session: ChatSession) {
        viewModels[session.id]?.terminate()
        viewModels.removeValue(forKey: session.id)
        sessions.removeAll { $0.id == session.id }
        if closingSessionId == session.id {
            closingSessionId = nil
        }
        if deletingSessionId == session.id {
            deletingSessionId = nil
        }
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

    private var activeSessionId: UUID? {
        expandedSessionId ?? sessions.last?.id
    }

    private func syncSelectedProviderFromExpandedSession() {
        guard let expandedSession else { return }
        if selectedProvider != expandedSession.provider {
            selectedProvider = expandedSession.provider
        }
    }
}
