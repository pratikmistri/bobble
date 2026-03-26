import Combine
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

class ChatSessionViewModel: ObservableObject {
    static let supportedDropTypeIdentifiers: [String] = [
        UTType.fileURL.identifier,
        UTType.png.identifier,
        UTType.jpeg.identifier,
        UTType.tiff.identifier,
        UTType.gif.identifier,
        UTType.image.identifier
    ]

    @Published var session: ChatSession
    @Published var inputText: String = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isCapturingScreenshot = false

    var onSessionUpdated: ((ChatSession) -> Void)?

    private var conversationTransport: ConversationTransport?
    private var conversationTransportBackend: CLIBackend?
    private var cancellables = Set<AnyCancellable>()
    private var didRequestScreenCaptureAccessThisLaunch = false
    private var didShowScreenCaptureAccessErrorThisLaunch = false
    private var shouldRecycleCopilotTransportAfterTurn = false
    private var shouldResetTransportAfterTurn = false
    private var pendingTextReplyInterruptionID: String?

    init(session: ChatSession) {
        self.session = session
        hydrateDerivedAssistantAttachments()
    }

    func send() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !prompt.isEmpty || !attachments.isEmpty else { return }
        let backend = session.provider

        inputText = ""
        pendingAttachments = []

        // Auto-name from first prompt
        if session.messages.isEmpty {
            let seed = prompt.isEmpty ? (attachments.first?.fileName ?? "New Chat") : prompt
            let truncated = String(seed.prefix(30))
            session.name = truncated
        }

        let userMessage = ChatMessage(role: .user, content: prompt, attachments: attachments)
        session.messages.append(userMessage)
        notifyUpdate()

        if let replyInterruptionID = pendingTextReplyInterruptionID,
           let transport = conversationTransport {
            session.state = .running
            self.pendingTextReplyInterruptionID = nil
            transport.resolveInterruption(
                id: replyInterruptionID,
                actionTransportValue: nil,
                textResponse: buildPrompt(userPrompt: prompt, attachments: attachments)
            )
            notifyUpdate()
            return
        }

        guard let path = backend.resolvedPath() else {
            let errorMsg = ChatMessage(
                role: .error,
                content: backend.missingCLIMessage
            )
            session.messages.append(errorMsg)
            session.state = .error("CLI not found")
            notifyUpdate()
            return
        }

        session.state = .running
        notifyUpdate()

        let shouldResume = session.cliSessionBackend == backend
            && session.messages.filter({ $0.role == .user }).count > 1
        if !shouldResume {
            session.cliSessionId = UUID().uuidString
        }
        session.cliSessionBackend = backend

        let transport = transportForCurrentConversation(executablePath: path)
        configureTransportCallbacks(transport)

        let request = ConversationTurnRequest(
            backend: backend,
            prompt: buildPrompt(userPrompt: prompt, attachments: attachments),
            imagePaths: attachments.filter(\.isImage).map(\.filePath),
            sessionId: session.cliSessionId,
            isResume: shouldResume,
            workingDirectory: session.workspaceDirectory,
            model: session.selectedModel.cliValue(for: backend),
            executionMode: session.conversationMode
        )
        transport.sendTurn(request)
    }

    func terminate() {
        resetConversationTransport()
    }

    func selectModel(_ model: ProviderModelOption) {
        let normalized = model.normalized(for: session.provider)
        guard normalized.isAvailable(for: session.provider) else { return }
        guard session.selectedModel != normalized else { return }
        session.selectedModel = normalized
        session.cliSessionId = UUID().uuidString
        session.cliSessionBackend = nil
        if case .running = session.state {
            shouldResetTransportAfterTurn = true
            notifyUpdate()
            return
        }
        resetConversationTransport()
        notifyUpdate()
    }

    func updateProvider(_ provider: CLIBackend) {
        guard session.provider != provider else { return }
        session.provider = provider
        session.selectedModel = session.selectedModel.normalized(for: provider)
        session.cliSessionId = UUID().uuidString
        session.cliSessionBackend = nil
        resetConversationTransport()
        notifyUpdate()
    }

    func updateConversationMode(_ mode: ConversationExecutionMode) {
        guard session.conversationMode != mode else { return }
        session.conversationMode = mode
        if case .running = session.state {
            notifyUpdate()
            return
        }
        session.cliSessionId = UUID().uuidString
        session.cliSessionBackend = nil
        resetConversationTransport()
        notifyUpdate()
    }

    func handleInterruptionAction(_ action: ChatMessage.InterruptionAction) {
        guard let payload = action.payload else { return }
        let components = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard components.count == 3 else { return }

        let interruptionID = components[0]
        let actionID = components[1]
        let transportValue = components[2].isEmpty ? nil : components[2]

        if actionID == "bypass-conversation" {
            shouldRecycleCopilotTransportAfterTurn = true
            session.conversationMode = .bypass
        }

        if pendingTextReplyInterruptionID == interruptionID {
            pendingTextReplyInterruptionID = nil
        }

        conversationTransport?.resolveInterruption(
            id: interruptionID,
            actionTransportValue: transportValue,
            textResponse: nil
        )
        clearInterruptionActions(containing: action.id)
        notifyUpdate()
    }

    func attachFiles(urls: [URL]) {
        for url in urls {
            do {
                let attachment = try makeAttachment(from: url)
                if !pendingAttachments.contains(where: { $0.filePath == attachment.filePath }) {
                    pendingAttachments.append(attachment)
                }
            } catch {
                appendAttachmentError("Couldn't attach \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    private func configureTransportCallbacks(_ transport: ConversationTransport) {
        transport.onTextChunk = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.applyAssistantDelta(text)
                self.notifyUpdate()
            }
        }

        transport.onResult = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.completeAssistantMessage(with: text)
                self.notifyUpdate()
            }
        }

        transport.onEventText = { [weak self] text in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.appendSystemEvent(text)
                self.notifyUpdate()
            }
        }

        transport.onInterruption = { [weak self] interruption in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.appendInterruptionMessage(interruption)
                self.finishAssistantRun()
                if interruption.responseMode == .textReply {
                    self.pendingTextReplyInterruptionID = interruption.id
                }
                self.notifyUpdate()
            }
        }

        transport.onComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.finishAssistantRun()
                self.pendingTextReplyInterruptionID = nil
                self.handleTurnLifecycleCompletion()
                self.notifyUpdate()
            }
        }

        transport.onSessionId = { [weak self] newId in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.session.cliSessionId != newId {
                    self.session.cliSessionId = newId
                    self.notifyUpdate()
                }
            }
        }

        transport.onAssistantMessageStarted = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.startAssistantMessageIfNeeded()
                self.notifyUpdate()
            }
        }

        transport.onTurnCompleted = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.finishAssistantRun()
                self.pendingTextReplyInterruptionID = nil
                self.notifyUpdate()
            }
        }

        transport.onError = { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let idx = self.session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
                    self.session.messages.remove(at: idx)
                }
                let errorMsg = ChatMessage(role: .error, content: error)
                self.session.messages.append(errorMsg)
                self.session.state = .error(error)
                self.session.cliSessionBackend = nil
                self.pendingTextReplyInterruptionID = nil
                self.handleTurnLifecycleCompletion(forceReset: true)
                self.notifyUpdate()
            }
        }
    }

    private func transportForCurrentConversation(executablePath: String) -> ConversationTransport {
        switch session.provider {
        case .copilot:
            if let existing = conversationTransport as? CopilotACPTransport,
               conversationTransportBackend == .copilot {
                return existing
            }

            resetConversationTransport()
            let transport = CopilotACPTransport(
                executablePath: executablePath,
                workingDirectory: session.workspaceDirectory,
                executionMode: session.conversationMode
            )
            conversationTransport = transport
            conversationTransportBackend = .copilot
            return transport

        case .claude:
            if let existing = conversationTransport as? ClaudeInteractiveTransport,
               conversationTransportBackend == .claude {
                return existing
            }

            resetConversationTransport()
            let transport = ClaudeInteractiveTransport(
                executablePath: executablePath,
                workingDirectory: session.workspaceDirectory,
                executionMode: session.conversationMode
            )
            conversationTransport = transport
            conversationTransportBackend = .claude
            return transport

        case .codex:
            if let existing = conversationTransport as? CodexAppServerTransport,
               conversationTransportBackend == .codex {
                return existing
            }

            resetConversationTransport()
            let transport = CodexAppServerTransport(
                executablePath: executablePath,
                workingDirectory: session.workspaceDirectory,
                executionMode: session.conversationMode
            )
            conversationTransport = transport
            conversationTransportBackend = .codex
            return transport
        }
    }

    private func resetConversationTransport() {
        conversationTransport?.stop()
        conversationTransport = nil
        conversationTransportBackend = nil
        shouldRecycleCopilotTransportAfterTurn = false
        shouldResetTransportAfterTurn = false
        pendingTextReplyInterruptionID = nil
    }

    private func handleTurnLifecycleCompletion(forceReset: Bool = false) {
        let shouldReset = forceReset
            || !(conversationTransport?.persistsAcrossTurns ?? false)
            || shouldRecycleCopilotTransportAfterTurn
            || shouldResetTransportAfterTurn

        if shouldReset {
            resetConversationTransport()
        } else {
            shouldRecycleCopilotTransportAfterTurn = false
        }
    }

    private func appendInterruptionMessage(_ interruption: ConversationInterruption) {
        let actions = interruption.actions.map { action in
            ChatMessage.InterruptionAction(
                title: action.label,
                role: interruptionActionRole(for: action.role),
                payload: "\(interruption.id)|\(action.id)|\(action.transportValue ?? "")"
            )
        }

        let kind: ChatMessage.Kind = interruption.kind == .question ? .question : .permission
        session.messages.append(
            ChatMessage(
                role: .system,
                content: interruption.details,
                interruptionTitle: interruption.title,
                interruptionDetails: interruption.details,
                interruptionActions: actions,
                kind: kind
            )
        )
    }

    private func clearInterruptionActions(containing actionID: UUID) {
        guard let messageIndex = session.messages.firstIndex(where: { message in
            message.interruptionActions.contains(where: { $0.id == actionID })
        }) else {
            return
        }

        session.messages[messageIndex].interruptionActions = []
    }

    private func interruptionActionRole(for role: ConversationInterruption.Action.Role) -> ChatMessage.InterruptionAction.Role {
        switch role {
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        case .destructive:
            return .destructive
        }
    }

    func attachImageData(_ data: Data, suggestedName: String?) {
        do {
            let attachment = try makeImageAttachment(from: data, suggestedName: suggestedName)
            pendingAttachments.append(attachment)
        } catch {
            appendAttachmentError("Couldn't attach dropped image: \(error.localizedDescription)")
        }
    }

    func attachDroppedItems(from providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    guard let self, let url = self.extractFileURL(from: item) else {
                        return
                    }
                    DispatchQueue.main.async {
                        self.attachFiles(urls: [url])
                    }
                }
                continue
            }

            guard let imageTypeIdentifier = preferredImageType(for: provider) else {
                continue
            }

            handled = true
            provider.loadDataRepresentation(forTypeIdentifier: imageTypeIdentifier) { [weak self] data, _ in
                guard let self, let data else { return }
                DispatchQueue.main.async {
                    self.attachImageData(data, suggestedName: provider.suggestedName)
                }
            }
        }

        return handled
    }

    func removePendingAttachment(id: UUID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    func markAssistantMessagesRead(notify: Bool = true) {
        let hadUnread = session.hasUnread
        session.markAssistantMessagesRead()

        guard notify, hadUnread else { return }
        notifyUpdate()
    }

    func captureScreenshot() {
        guard !isCapturingScreenshot else { return }
        guard ensureScreenCaptureAccess() else { return }
        isCapturingScreenshot = true

        let fileName = makeUniqueFileName(baseName: "screenshot-\(timestampSlug())", pathExtension: "png")
        let destination = attachmentsDirectoryURL.appendingPathComponent(fileName, isDirectory: false)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", destination.path]

        process.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCapturingScreenshot = false

                guard proc.terminationStatus == 0 else {
                    try? FileManager.default.removeItem(at: destination)
                    return
                }

                guard FileManager.default.fileExists(atPath: destination.path) else {
                    return
                }

                let attachment = self.makeStoredAttachment(
                    kind: .image,
                    fileName: destination.lastPathComponent,
                    storedURL: destination
                )
                self.pendingAttachments.append(attachment)
            }
        }

        do {
            try process.run()
        } catch {
            isCapturingScreenshot = false
            appendAttachmentError("Couldn't start screenshot capture: \(error.localizedDescription)")
        }
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            didShowScreenCaptureAccessErrorThisLaunch = false
            return true
        }

        if !didRequestScreenCaptureAccessThisLaunch {
            didRequestScreenCaptureAccessThisLaunch = true
            _ = CGRequestScreenCaptureAccess()
        }

        guard CGPreflightScreenCaptureAccess() else {
            if !didShowScreenCaptureAccessErrorThisLaunch {
                didShowScreenCaptureAccessErrorThisLaunch = true
                appendAttachmentError(
                    "Screen Recording access is required for screenshots. If you just enabled Bobble in System Settings > Privacy & Security > Screen Recording, quit and reopen Bobble before trying again."
                )
            }
            return false
        }

        return true
    }

    private func notifyUpdate() {
        session.touchUpdatedAt()
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

        syncDerivedAttachments(forMessageAt: idx)
    }

    private func completeAssistantMessage(with text: String) {
        if let idx = session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            if !text.isEmpty {
                session.messages[idx].content = text
            }
            session.messages[idx].isStreaming = false
            syncDerivedAttachments(forMessageAt: idx)
            if session.messages[idx].content.isEmpty {
                session.messages.remove(at: idx)
            }
            return
        }

        guard !text.isEmpty else { return }
        session.messages.append(ChatMessage(role: .assistant, content: text))
        if let idx = session.messages.indices.last {
            syncDerivedAttachments(forMessageAt: idx)
        }
    }

    private func finishAssistantRun() {
        if let idx = session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            session.messages[idx].isStreaming = false
            syncDerivedAttachments(forMessageAt: idx)
            if session.messages[idx].content.isEmpty {
                let hasFollowupEvent = session.messages.indices.contains(where: { messageIndex in
                    messageIndex > idx
                    && session.messages[messageIndex].role == .system
                    && !session.messages[messageIndex].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                })
                if hasFollowupEvent {
                    session.messages.remove(at: idx)
                } else {
                    session.messages[idx].content = "(No response)"
                }
            }
        }

        if case .running = session.state {
            session.state = .idle
        }
    }

    private func classifySystemEventKind(_ text: String) -> ChatMessage.Kind {
        let normalized = text.lowercased()

        let permissionMarkers = [
            "codex approval",
            "codex permission",
            "claude approval",
            "claude permission",
            "approval",
            "permission"
        ]
        if permissionMarkers.contains(where: normalized.contains) {
            return .permission
        }

        let questionMarkers = [
            "request user input",
            "user input",
            "question",
            "sendusermessage"
        ]
        if questionMarkers.contains(where: normalized.contains) {
            return .question
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

    private func appendSystemEvent(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let kind = classifySystemEventKind(trimmed)
        if kind == .agentThought {
            appendOrMergeAgentThought(trimmed)
            return
        }

        session.messages.append(ChatMessage(role: .system, content: trimmed, kind: kind))
    }

    private func appendOrMergeAgentThought(_ incoming: String) {
        guard let lastIndex = session.messages.indices.last,
              session.messages[lastIndex].role == .system,
              session.messages[lastIndex].kind == .agentThought else {
            session.messages.append(ChatMessage(role: .system, content: incoming, kind: .agentThought))
            return
        }

        let existing = session.messages[lastIndex].content
        let merged = mergeThoughtEvent(existing: existing, incoming: incoming)
        session.messages[lastIndex].content = merged
    }

    private func mergeThoughtEvent(existing: String, incoming: String) -> String {
        if incoming == existing {
            return existing
        }
        if incoming.hasPrefix(existing) {
            return incoming
        }
        if existing.hasPrefix(incoming) {
            return existing
        }

        guard let existingBody = thoughtBody(from: existing),
              let incomingBody = thoughtBody(from: incoming) else {
            if existing.contains(incoming) {
                return existing
            }
            return existing + "\n" + incoming
        }

        let mergedBody = mergeThoughtBody(current: existingBody, incoming: incomingBody)
        return mergedBody.isEmpty ? "Agent thought" : "Agent thought\n\(mergedBody)"
    }

    private func thoughtBody(from eventText: String) -> String? {
        let title = "Agent thought"
        guard eventText.lowercased().hasPrefix(title.lowercased()) else { return nil }

        let components = eventText.components(separatedBy: "\n")
        guard components.count > 1 else { return "" }
        return components.dropFirst().joined(separator: "\n")
    }

    private func mergeThoughtBody(current: String, incoming: String) -> String {
        if incoming == current {
            return current
        }
        if incoming.hasPrefix(current) {
            return incoming
        }
        if current.hasPrefix(incoming) {
            return current
        }
        if current.contains(incoming) {
            return current
        }
        if incoming.contains(current) {
            return incoming
        }

        guard !current.isEmpty else { return incoming }
        guard !incoming.isEmpty else { return current }

        let needsSpacer = !endsWithWhitespace(current)
            && !startsWithWhitespace(incoming)
            && !startsWithPunctuation(incoming)
        return current + (needsSpacer ? " " : "") + incoming
    }

    private func startsWithWhitespace(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private func endsWithWhitespace(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.last else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }

    private func startsWithPunctuation(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return CharacterSet.punctuationCharacters.contains(scalar)
    }

    private func hydrateDerivedAssistantAttachments() {
        for index in session.messages.indices where session.messages[index].role == .assistant {
            syncDerivedAttachments(forMessageAt: index)
        }
    }

    private func syncDerivedAttachments(forMessageAt index: Int) {
        guard session.messages.indices.contains(index) else { return }
        guard session.messages[index].role == .assistant else { return }
        session.messages[index].attachments = extractAttachments(fromAssistantMessage: session.messages[index].content)
    }

    private func extractAttachments(fromAssistantMessage content: String) -> [ChatAttachment] {
        let destinations = extractMarkdownLinkDestinations(from: content)
        guard !destinations.isEmpty else { return [] }

        var attachments: [ChatAttachment] = []
        var seenPaths = Set<String>()

        for destination in destinations {
            guard let fileURL = resolveLinkedFileURL(from: destination) else { continue }
            guard seenPaths.insert(fileURL.path).inserted else { continue }
            attachments.append(makeDerivedAttachment(for: fileURL))
        }

        return attachments
    }

    private func extractMarkdownLinkDestinations(from content: String) -> [String] {
        let pattern = #"!?\[[^\]]*\]\((.+?)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let nsRange = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: nsRange).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: content) else {
                return nil
            }
            return String(content[range])
        }
    }

    private func resolveLinkedFileURL(from rawDestination: String) -> URL? {
        var candidate = rawDestination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        if candidate.first == "<", candidate.last == ">" {
            candidate.removeFirst()
            candidate.removeLast()
        }

        if let hashIndex = candidate.firstIndex(of: "#") {
            candidate = String(candidate[..<hashIndex])
        }

        candidate = candidate.removingPercentEncoding ?? candidate

        if candidate.hasPrefix("file://"), let url = URL(string: candidate) {
            return regularReadableFileURL(for: url)
        }

        guard candidate.hasPrefix("/") else { return nil }

        if let exactURL = regularReadableFileURL(for: URL(fileURLWithPath: candidate)) {
            return exactURL
        }

        let lineSuffixPattern = #":\d+(?::\d+)?$"#
        if let regex = try? NSRegularExpression(pattern: lineSuffixPattern) {
            let nsRange = NSRange(candidate.startIndex..., in: candidate)
            let stripped = regex.stringByReplacingMatches(in: candidate, range: nsRange, withTemplate: "")
            if stripped != candidate {
                return regularReadableFileURL(for: URL(fileURLWithPath: stripped))
            }
        }

        return nil
    }

    private func regularReadableFileURL(for url: URL) -> URL? {
        guard url.isFileURL else { return nil }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path) else {
            return nil
        }

        return url
    }

    private func makeDerivedAttachment(for fileURL: URL) -> ChatAttachment {
        let kind: ChatAttachment.Kind = isImageFile(url: fileURL) ? .image : .file
        return ChatAttachment(
            kind: kind,
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            relativePath: relativePathForPreviewAttachment(fileURL)
        )
    }

    private func relativePathForPreviewAttachment(_ fileURL: URL) -> String {
        let workspaceURL = URL(fileURLWithPath: session.workspaceDirectory, isDirectory: true)
        let workspacePath = workspaceURL.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(workspacePath) else { return filePath }

        let relative = String(filePath.dropFirst(workspacePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? fileURL.lastPathComponent : relative
    }

    private func buildPrompt(userPrompt: String, attachments: [ChatAttachment]) -> String {
        guard !attachments.isEmpty else { return userPrompt }

        let attachmentLines = attachments.map { attachment in
            "- \(attachment.isImage ? "image" : "file"): \(attachment.relativePath)"
        }.joined(separator: "\n")

        let effectivePrompt = userPrompt.isEmpty
            ? "Inspect the attachments and respond appropriately. If the intended task is unclear, summarize what was attached and ask one focused clarifying question."
            : userPrompt

        return """
        The user attached the following workspace files for this message:
        \(attachmentLines)

        Use those paths when you need to inspect the attachments.

        User request:
        \(effectivePrompt)
        """
    }

    private func appendAttachmentError(_ message: String) {
        session.messages.append(ChatMessage(role: .error, content: message))
        notifyUpdate()
    }

    private func makeAttachment(from sourceURL: URL) throws -> ChatAttachment {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw NSError(domain: "BobbleAttachment", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Only files can be attached."
            ])
        }

        let sourceExtension = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let storedFileName = makeUniqueFileName(baseName: baseName, pathExtension: sourceExtension)
        let destinationURL = attachmentsDirectoryURL.appendingPathComponent(storedFileName, isDirectory: false)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let kind: ChatAttachment.Kind = isImageFile(url: sourceURL) ? .image : .file
        return makeStoredAttachment(kind: kind, fileName: sourceURL.lastPathComponent, storedURL: destinationURL)
    }

    private func makeImageAttachment(from data: Data, suggestedName: String?) throws -> ChatAttachment {
        let normalizedData = normalizedPNGData(from: data) ?? data
        let requestedBaseName = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = (requestedBaseName?.isEmpty == false ? requestedBaseName! : "dropped-image")
            .replacingOccurrences(of: ".png", with: "")
        let storedFileName = makeUniqueFileName(baseName: baseName, pathExtension: "png")
        let destinationURL = attachmentsDirectoryURL.appendingPathComponent(storedFileName, isDirectory: false)
        try normalizedData.write(to: destinationURL, options: .atomic)
        return makeStoredAttachment(kind: .image, fileName: storedFileName, storedURL: destinationURL)
    }

    private func makeStoredAttachment(kind: ChatAttachment.Kind, fileName: String, storedURL: URL) -> ChatAttachment {
        ChatAttachment(
            kind: kind,
            fileName: fileName,
            filePath: storedURL.path,
            relativePath: "attachments/\(storedURL.lastPathComponent)"
        )
    }

    private func isImageFile(url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }
        return type.conforms(to: .image)
    }

    private func makeUniqueFileName(baseName: String, pathExtension: String) -> String {
        let sanitizedBaseName = sanitizeFileComponent(baseName)
        let sanitizedExtension = sanitizeFileComponent(pathExtension)
        let uniqueSuffix = UUID().uuidString.prefix(8)
        if sanitizedExtension.isEmpty {
            return "\(sanitizedBaseName)-\(uniqueSuffix)"
        }
        return "\(sanitizedBaseName)-\(uniqueSuffix).\(sanitizedExtension)"
    }

    private func sanitizeFileComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }
        let sanitized = scalars.joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "attachment" : sanitized
    }

    private func timestampSlug() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private var attachmentsDirectoryURL: URL {
        URL(fileURLWithPath: session.attachmentsDirectory, isDirectory: true)
    }

    private func normalizedPNGData(from data: Data) -> Data? {
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func preferredImageType(for provider: NSItemProvider) -> String? {
        let candidates = [
            UTType.png.identifier,
            UTType.jpeg.identifier,
            UTType.tiff.identifier,
            UTType.gif.identifier,
            UTType.image.identifier
        ]
        return candidates.first(where: provider.hasItemConformingToTypeIdentifier)
    }

    private func extractFileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url
        }

        if let url = item as? NSURL, let bridgedURL = url as URL?, bridgedURL.isFileURL {
            return bridgedURL
        }

        if let data = item as? Data {
            return decodeFileURL(from: data)
        }

        if let string = item as? String, let url = URL(string: string), url.isFileURL {
            return url
        }

        return nil
    }

    private func decodeFileURL(from data: Data) -> URL? {
        if let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
            return url
        }

        let candidateStrings = [
            String(data: data, encoding: .utf8),
            String(data: data, encoding: .utf16LittleEndian),
            String(data: data, encoding: .utf16BigEndian)
        ]

        for candidate in candidateStrings.compactMap({ $0 }) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.isFileURL {
                return url
            }
        }

        return nil
    }
}
