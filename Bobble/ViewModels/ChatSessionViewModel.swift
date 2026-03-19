import Combine
import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

class ChatSessionViewModel: ObservableObject {
    @Published var session: ChatSession
    @Published var inputText: String = ""
    @Published var pendingAttachments: [ChatAttachment] = []
    @Published var isCapturingScreenshot = false

    var onSessionUpdated: ((ChatSession) -> Void)?

    private var processManager: CLIProcessManager?
    private var chatHeadSymbolProcess: CLIProcessManager?
    private var cancellables = Set<AnyCancellable>()
    private var didRequestScreenCaptureAccessThisLaunch = false
    private var didShowScreenCaptureAccessErrorThisLaunch = false

    init(session: ChatSession) {
        self.session = session
    }

    func send() {
        let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !prompt.isEmpty || !attachments.isEmpty else { return }
        let isFirstUserTurn = session.messages.isEmpty

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

        if isFirstUserTurn {
            updateChatHeadSymbolFromFirstMessage(prompt: prompt, attachments: attachments)
        }

        let backend = session.provider
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

        let pm = CLIProcessManager(
            backend: backend,
            executablePath: path,
            model: session.selectedModel.cliValue,
            prompt: buildPrompt(userPrompt: prompt, attachments: attachments),
            imagePaths: attachments.filter(\.isImage).map(\.filePath),
            sessionId: session.cliSessionId,
            isResume: shouldResume,
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
                self.finishAssistantRun()
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

        pm.onTurnCompleted = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.finishAssistantRun()
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
                self.session.cliSessionBackend = nil
                self.processManager = nil
                self.notifyUpdate()
            }
        }

        pm.start()
    }

    func terminate() {
        processManager?.stop()
        processManager = nil
        chatHeadSymbolProcess?.stop()
        chatHeadSymbolProcess = nil
    }

    func selectModel(_ model: CodexModelOption) {
        guard session.provider == .codex else { return }
        guard session.selectedModel != model else { return }
        session.selectedModel = model
        notifyUpdate()
    }

    func updateProvider(_ provider: CLIBackend) {
        guard session.provider != provider else { return }
        session.provider = provider
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

    func attachImageData(_ data: Data, suggestedName: String?) {
        do {
            let attachment = try makeImageAttachment(from: data, suggestedName: suggestedName)
            pendingAttachments.append(attachment)
        } catch {
            appendAttachmentError("Couldn't attach dropped image: \(error.localizedDescription)")
        }
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

    private func finishAssistantRun() {
        if let idx = session.messages.lastIndex(where: { $0.role == .assistant && $0.isStreaming }) {
            session.messages[idx].isStreaming = false
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

    private func updateChatHeadSymbolFromFirstMessage(prompt: String, attachments: [ChatAttachment]) {
        guard chatHeadSymbolProcess == nil else { return }
        let backend = session.provider
        guard let path = backend.resolvedPath() else { return }

        let seed = buildChatHeadSymbolSeed(userPrompt: prompt, attachments: attachments)
        guard !seed.isEmpty else { return }

        var generatedOutput = ""
        let process = CLIProcessManager(
            backend: backend,
            executablePath: path,
            model: session.selectedModel.cliValue,
            prompt: buildChatHeadSymbolPrompt(from: seed),
            imagePaths: attachments.filter(\.isImage).map(\.filePath),
            sessionId: UUID().uuidString,
            isResume: false,
            workingDirectory: session.workspaceDirectory
        )

        process.onTextChunk = { text in
            generatedOutput += text
        }

        process.onResult = { text in
            generatedOutput = text
        }

        process.onComplete = { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.session.updateChatHeadSymbol(from: generatedOutput)
                self.chatHeadSymbolProcess = nil
                self.notifyUpdate()
            }
        }

        process.onError = { [weak self] _ in
            DispatchQueue.main.async {
                self?.chatHeadSymbolProcess = nil
            }
        }

        chatHeadSymbolProcess = process
        process.start()
    }

    private func buildChatHeadSymbolSeed(userPrompt: String, attachments: [ChatAttachment]) -> String {
        let trimmedPrompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty else { return trimmedPrompt }

        guard !attachments.isEmpty else { return "" }
        let attachmentSummary = attachments.map { attachment in
            "\(attachment.isImage ? "image" : "file"): \(attachment.fileName)"
        }.joined(separator: ", ")

        return "Attachment-only first message with: \(attachmentSummary)"
    }

    private func buildChatHeadSymbolPrompt(from seed: String) -> String {
        """
        Choose the single best emoji to represent this chat based on the first user message.

        Rules:
        - Return exactly one emoji and nothing else.
        - Prefer specific emojis over generic ones.
        - Do not return any words, punctuation, Markdown, or explanation.
        - If the request is broad or unclear, return \(ChatSession.defaultChatHeadSymbol).

        First user message:
        \(seed)
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
}
