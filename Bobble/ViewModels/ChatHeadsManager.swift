import Foundation
import SwiftUI

class ChatHeadsManager: ObservableObject {
    struct HistoryEntry: Identifiable {
        let session: ChatSession
        let isArchived: Bool

        var id: UUID { session.id }
    }

    @Published var sessions: [ChatSession] = []
    @Published var historySessions: [ChatSession] = []
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
    @Published var panelDockSide: PanelDockSide = .trailing
    @Published var availableBackends: Set<CLIBackend> = []
    @Published var morphOriginY: CGFloat = 240
    @Published var isRevealed = false

    var onSessionsChanged: ((Int) -> Void)?
    var onSessionAdded: ((ChatSession) -> Void)?
    var onSelectedProviderChanged: ((CLIBackend) -> Void)?

    private var viewModels: [UUID: ChatSessionViewModel] = [:]
    private let historyStore = ChatHistoryStore()
    private var pendingPersistenceWorkItem: DispatchWorkItem?

    init() {
        restoreSessions()
        detectAvailableBackends()
    }

    deinit {
        flushPersistence()
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

    var historyEntries: [HistoryEntry] {
        let activeEntries = sessions
            .filter(\.qualifiesForHistory)
            .map { HistoryEntry(session: $0, isArchived: false) }
        let archivedEntries = historySessions
            .filter(\.qualifiesForHistory)
            .map { HistoryEntry(session: $0, isArchived: true) }

        return (activeEntries + archivedEntries)
            .sorted { $0.session.updatedAt > $1.session.updatedAt }
    }

    func viewModel(for sessionId: UUID) -> ChatSessionViewModel? {
        viewModels[sessionId]
    }

    func isActiveSession(_ sessionId: UUID) -> Bool {
        sessions.contains { $0.id == sessionId }
    }

    func addSession() {
        let imageName = nextChatHeadImageName(existingSessions: sessions + historySessions)
        let session = ChatSession(
            chatHeadSymbol: imageName,
            hasAssignedChatHeadSymbol: true,
            provider: selectedProvider
        )
        sessions.append(session)
        configureViewModel(for: session)

        schedulePersistence()
        onSessionsChanged?(sessions.count)
        onSessionAdded?(session)
    }

    @discardableResult
    func restoreSessionFromHistory(_ session: ChatSession) -> ChatSession? {
        guard let index = historySessions.firstIndex(where: { $0.id == session.id }) else { return nil }

        var restored = historySessions.remove(at: index).normalizedForRestore()
        restored.isArchived = false
        restored.touchUpdatedAt()
        sessions.append(restored)
        configureViewModel(for: restored)

        schedulePersistence()
        onSessionsChanged?(sessions.count)
        onSessionAdded?(restored)
        return restored
    }

    func archiveSession(_ session: ChatSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }

        viewModels[session.id]?.terminate()
        viewModels.removeValue(forKey: session.id)

        var archived = sessions.remove(at: index)
        archived.isArchived = true
        archived.markAssistantMessagesRead()
        if case .running = archived.state {
            archived.state = .idle
        }
        historySessions.removeAll { $0.id == archived.id }
        historySessions.append(archived)
        historySessions.sort { $0.updatedAt > $1.updatedAt }

        if closingSessionId == session.id {
            closingSessionId = nil
        }
        if deletingSessionId == session.id {
            deletingSessionId = nil
        }
        if expandedSessionId == session.id {
            expandedSessionId = nil
        }

        schedulePersistence()
        onSessionsChanged?(sessions.count)
    }

    func deleteHistorySession(_ session: ChatSession) {
        historySessions.removeAll { $0.id == session.id }
        schedulePersistence()
        deleteWorkspace(for: session)
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
        updatedSession.touchUpdatedAt()
        sessions[index] = updatedSession
        viewModels[sessionId]?.updateProvider(provider)
        schedulePersistence()

        if expandedSessionId == sessionId && selectedProvider != provider {
            selectedProvider = provider
        }
    }

    func removeSession(_ session: ChatSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }

        viewModels[session.id]?.terminate()
        viewModels.removeValue(forKey: session.id)
        sessions.remove(at: index)

        if closingSessionId == session.id {
            closingSessionId = nil
        }
        if deletingSessionId == session.id {
            deletingSessionId = nil
        }
        if expandedSessionId == session.id {
            expandedSessionId = nil
        }

        schedulePersistence()
        onSessionsChanged?(sessions.count)
        deleteWorkspace(for: session)
    }

    func markRead(sessionId: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        var updatedSession = sessions[index]
        updatedSession.markAssistantMessagesRead()
        sessions[index] = updatedSession
        viewModels[sessionId]?.markAssistantMessagesRead(notify: false)
        schedulePersistence()
    }

    func flushPersistence() {
        pendingPersistenceWorkItem?.cancel()
        historyStore.save(activeSessions: sessions, historySessions: historySessions)
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

    private func restoreSessions() {
        var restored = historyStore.load().map { $0.normalizedForRestore() }
        let didAssignMissingChatHeads = assignMissingChatHeadsIfNeeded(in: &restored)

        sessions = restored
            .filter { !$0.isArchived }
            .sorted { $0.updatedAt < $1.updatedAt }
        historySessions = restored
            .filter { $0.isArchived }
            .sorted { $0.updatedAt > $1.updatedAt }

        if didAssignMissingChatHeads {
            historyStore.save(activeSessions: sessions, historySessions: historySessions)
        }

        for session in sessions {
            configureViewModel(for: session)
        }

        if let lastSession = sessions.last {
            selectedProvider = lastSession.provider
        }
    }

    private func configureViewModel(for session: ChatSession) {
        let vm = ChatSessionViewModel(session: session)
        vm.onSessionUpdated = { [weak self] updated in
            guard let self else { return }

            var syncedSession = updated
            if self.expandedSessionId == updated.id {
                syncedSession.markAssistantMessagesRead()
                self.viewModels[updated.id]?.markAssistantMessagesRead(notify: false)
            }

            if let index = self.sessions.firstIndex(where: { $0.id == updated.id }) {
                self.sessions[index] = syncedSession
                self.schedulePersistence()
            }
        }
        viewModels[session.id] = vm
    }

    private func schedulePersistence() {
        pendingPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistSessions()
        }
        pendingPersistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func persistSessions() {
        let activeSessions = sessions
        let archivedSessions = historySessions
        let store = historyStore
        DispatchQueue.global(qos: .utility).async {
            store.save(activeSessions: activeSessions, historySessions: archivedSessions)
        }
    }

    private func assignMissingChatHeadsIfNeeded(in restoredSessions: inout [ChatSession]) -> Bool {
        var didAssign = false
        var usageCounts = emptyChatHeadUsageCounts()

        for session in restoredSessions where session.hasAssignedChatHeadSymbol {
            usageCounts[session.chatHeadImageName, default: 0] += 1
        }

        for index in restoredSessions.indices where !restoredSessions[index].hasAssignedChatHeadSymbol {
            let imageName = nextChatHeadImageName(usageCounts: usageCounts)
            restoredSessions[index].chatHeadSymbol = imageName
            restoredSessions[index].hasAssignedChatHeadSymbol = true
            usageCounts[imageName, default: 0] += 1
            didAssign = true
        }

        return didAssign
    }

    private func nextChatHeadImageName(existingSessions: [ChatSession]) -> String {
        var usageCounts = emptyChatHeadUsageCounts()
        for session in existingSessions {
            usageCounts[session.chatHeadImageName, default: 0] += 1
        }
        return nextChatHeadImageName(usageCounts: usageCounts)
    }

    private func nextChatHeadImageName(usageCounts: [String: Int]) -> String {
        for imageName in ChatSession.availableChatHeadImageNames where usageCounts[imageName, default: 0] == 0 {
            return imageName
        }

        let minimumUsage = usageCounts.values.min() ?? 0
        return ChatSession.availableChatHeadImageNames.first(where: { usageCounts[$0, default: 0] == minimumUsage })
            ?? ChatSession.defaultChatHeadSymbol
    }

    private func emptyChatHeadUsageCounts() -> [String: Int] {
        Dictionary(
            uniqueKeysWithValues: ChatSession.availableChatHeadImageNames.map { ($0, 0) }
        )
    }

    private func deleteWorkspace(for session: ChatSession) {
        let workspaceURL = URL(fileURLWithPath: session.workspaceDirectory, isDirectory: true)
        try? FileManager.default.removeItem(at: workspaceURL)
    }
}

private final class ChatHistoryStore {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func load() -> [ChatSession] {
        guard let data = try? Data(contentsOf: storageURL) else { return [] }
        do {
            return try decoder.decode([ChatSession].self, from: data)
        } catch {
            return []
        }
    }

    func save(activeSessions: [ChatSession], historySessions: [ChatSession]) {
        let payload = activeSessions + historySessions
        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try encoder.encode(payload)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }

    private var storageDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Bobble", isDirectory: true)
    }

    private var storageURL: URL {
        storageDirectory.appendingPathComponent("session-history.json", isDirectory: false)
    }
}
