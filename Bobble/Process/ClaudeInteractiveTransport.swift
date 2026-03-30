import Foundation

final class ClaudeInteractiveTransport: ConversationTransport {
    let persistsAcrossTurns = true

    var onTextChunk: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onEventText: ((String) -> Void)?
    var onInterruption: ((ConversationInterruption) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSessionId: ((String) -> Void)?
    var onAssistantMessageStarted: (() -> Void)?
    var onTurnCompleted: (() -> Void)?

    private let executablePath: String
    private let workingDirectory: String
    private let executionMode: ConversationExecutionMode
    private let queue = DispatchQueue(label: "Bobble.ClaudeInteractiveTransport")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var pendingTurnRequest: ConversationTurnRequest?
    private var turnInFlight = false
    private var emittedAssistantMessageStart = false
    private var didStreamAssistantDelta = false
    private var didEmitAssistantResult = false
    private var pendingInterruptionID: String?
    private var isStopping = false
    private var shouldIgnoreOutputUntilTurnEnds = false

    init(executablePath: String, workingDirectory: String, executionMode: ConversationExecutionMode) {
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.executionMode = executionMode
    }

    func sendTurn(_ request: ConversationTurnRequest) {
        queue.async {
            self.pendingTurnRequest = request

            if self.process == nil {
                self.startProcess(using: request)
                return
            }

            self.startPendingTurnIfPossible()
        }
    }

    func stop() {
        queue.async {
            self.isStopping = true
            self.pendingTurnRequest = nil
            self.turnInFlight = false
            self.pendingInterruptionID = nil
            self.process?.terminate()
            self.cleanUpProcess()
        }
    }

    func resolveInterruption(id: String, actionTransportValue: String?, textResponse: String?) {
        queue.async {
            guard self.pendingInterruptionID == id else { return }
            guard let textResponse, !textResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            self.pendingInterruptionID = nil
            self.emittedAssistantMessageStart = false
            self.didStreamAssistantDelta = false
            self.didEmitAssistantResult = false
            self.shouldIgnoreOutputUntilTurnEnds = false
            self.writeUserMessage(text: textResponse)
        }
    }

    private func startProcess(using request: ConversationTurnRequest) {
        let process = Process()
        self.process = process
        isStopping = false

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: workingDirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            dispatchError("Failed to create workspace directory: \(error.localizedDescription)")
            return
        }

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        process.arguments = makeArguments(for: request)
        process.environment = makeEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.stdinPipe = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.queue.async {
                self?.consume(data: data)
            }
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.queue.async {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                defer { self.cleanUpProcess() }

                if self.isStopping {
                    return
                }

                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrText = String(data: stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if proc.terminationStatus != 0 {
                    self.dispatchError(stderrText?.isEmpty == false ? stderrText! : "Claude interactive transport terminated unexpectedly.")
                    return
                }

                if self.turnInFlight {
                    self.turnInFlight = false
                    self.onComplete?()
                }
            }
        }

        do {
            try process.run()
            startPendingTurnIfPossible()
        } catch {
            dispatchError("Failed to launch Claude: \(error.localizedDescription)")
        }
    }

    private func startPendingTurnIfPossible() {
        guard process != nil,
              !turnInFlight,
              pendingInterruptionID == nil,
              let request = pendingTurnRequest else {
            return
        }

        pendingTurnRequest = nil
        turnInFlight = true
        emittedAssistantMessageStart = false
        didStreamAssistantDelta = false
        didEmitAssistantResult = false
        shouldIgnoreOutputUntilTurnEnds = false
        writeUserMessage(text: request.prompt)
    }

    private func writeUserMessage(text: String) {
        let payload: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    [
                        "type": "text",
                        "text": text
                    ]
                ]
            ]
        ]
        writeJSON(payload)
    }

    private func consume(data: Data) {
        buffer.append(data)

        while let newlineRange = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            guard !lineData.isEmpty else { continue }
            processLine(lineData)
        }
    }

    private func processLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                onEventText?(text)
            }
            return
        }

        switch type {
        case "system":
            if let subtype = json["subtype"] as? String,
               subtype == "init",
               let sessionID = json["session_id"] as? String {
                onSessionId?(sessionID)
            }

        case "user":
            if let interruption = makeInterruption(type: type, payload: json) {
                handleInterruption(interruption)
            }

        case "content_block_delta":
            guard !shouldIgnoreOutputUntilTurnEnds else { return }
            guard let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String,
                  !text.isEmpty else {
                return
            }
            if !emittedAssistantMessageStart {
                emittedAssistantMessageStart = true
                onAssistantMessageStarted?()
            }
            didStreamAssistantDelta = true
            onTextChunk?(text)

        case "assistant":
            guard !shouldIgnoreOutputUntilTurnEnds else { return }
            guard !didStreamAssistantDelta,
                  !didEmitAssistantResult,
                  let text = extractAssistantText(from: json),
                  !text.isEmpty else {
                return
            }
            if !emittedAssistantMessageStart {
                emittedAssistantMessageStart = true
                onAssistantMessageStarted?()
            }
            didEmitAssistantResult = true
            onResult?(text)

        case "result":
            if shouldIgnoreOutputUntilTurnEnds {
                finishSuppressedTurn()
                return
            }
            if !didStreamAssistantDelta,
               !didEmitAssistantResult,
               let text = (json["result"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                if !emittedAssistantMessageStart {
                    emittedAssistantMessageStart = true
                    onAssistantMessageStarted?()
                }
                didEmitAssistantResult = true
                onResult?(text)
            }

            turnInFlight = false
            pendingInterruptionID = nil
            onTurnCompleted?()
            onComplete?()
            startPendingTurnIfPossible()

        default:
            if let interruption = makeInterruption(type: type, payload: json) {
                handleInterruption(interruption)
                return
            }

            guard !shouldIgnoreOutputUntilTurnEnds else { return }
            if let rendered = renderEvent(type: type, payload: json) {
                onEventText?(rendered)
            }
        }
    }

    private func handleInterruption(_ interruption: ConversationInterruption) {
        if interruption.responseMode == .textReply {
            pendingInterruptionID = interruption.id
            onInterruption?(interruption)
            return
        }

        pendingInterruptionID = nil
        shouldIgnoreOutputUntilTurnEnds = true
        onInterruption?(interruption)
    }

    private func finishSuppressedTurn() {
        turnInFlight = false
        pendingInterruptionID = nil
        shouldIgnoreOutputUntilTurnEnds = false
        onTurnCompleted?()
        startPendingTurnIfPossible()
    }

    private func extractAssistantText(from payload: [String: Any]) -> String? {
        guard let message = payload["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }

        let text = content.compactMap { block -> String? in
            block["text"] as? String
        }.joined()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func makeInterruption(type: String, payload: [String: Any]) -> ConversationInterruption? {
        let normalizedType = type.lowercased()
        let payloadText = extractInterruptionText(from: payload)
        let normalizedPayload = payloadText.lowercased()
        let isInterruption = normalizedType.contains("permission")
            || normalizedType.contains("approval")
            || normalizedType.contains("question")
            || normalizedType.contains("user_input")
            || normalizedType.contains("sendusermessage")
            || normalizedPayload.contains("permission")
            || normalizedPayload.contains("approval")
            || normalizedPayload.contains("requested permissions")
            || normalizedPayload.contains("grant it yet")
            || normalizedPayload.contains("reply in chat")
            || normalizedPayload.contains("question")

        guard isInterruption else { return nil }

        let isQuestion = normalizedType.contains("question")
            || normalizedType.contains("sendusermessage")
            || normalizedPayload.contains("question")
        let title = isQuestion
            ? "Claude needs input"
            : "Claude needs approval"
        let detailsBody = payloadText.isEmpty ? (renderEvent(type: type, payload: payload) ?? title) : payloadText
        let details: String
        let responseMode: ConversationInterruption.ResponseMode

        if isQuestion {
            details = detailsBody + "\n\nReply in chat to continue."
            responseMode = .textReply
        } else {
            details = detailsBody + "\n\nClaude print mode cannot pause for inline approval here. Switch this conversation to Bypass and resend if you want it to continue outside the allowed workspace."
            responseMode = .informational
        }

        return ConversationInterruption(
            id: UUID().uuidString,
            kind: isQuestion ? .question : .permission,
            provider: .claude,
            title: title,
            details: details,
            actions: [],
            responseMode: responseMode
        )
    }

    private func extractInterruptionText(from payload: [String: Any]) -> String {
        var parts: [String] = []

        if let toolUseResult = payload["tool_use_result"] as? String,
           !toolUseResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(toolUseResult)
        }

        if let message = payload["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            for block in content {
                if let text = block["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(text)
                }
                if let toolUseResult = block["tool_use_result"] as? String,
                   !toolUseResult.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(toolUseResult)
                }
            }
        }

        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func renderEvent(type: String, payload: [String: Any]) -> String? {
        let title = "Claude \(humanize(type))"
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
           let details = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !details.isEmpty {
            return "\(title)\nDetails:\n\(details)"
        }
        return title
    }

    private func makeArguments(for request: ConversationTurnRequest) -> [String] {
        var args = [
            "-p",
            "--verbose",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--replay-user-messages",
            "--add-dir", workingDirectory
        ]

        if executionMode == .ask {
            args += ["--permission-mode", "default", "--brief"]
        } else {
            args += ["--permission-mode", "bypassPermissions"]
        }

        if let model = request.model {
            args += ["--model", model]
        }

        if request.isResume {
            args += ["--resume", request.sessionId]
        } else {
            args += ["--session-id", request.sessionId]
        }

        return args
    }

    private func makeEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
        } else {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        return env
    }

    private func writeJSON(_ payload: [String: Any]) {
        guard let stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        var line = data
        line.append(0x0A)
        stdinPipe.fileHandleForWriting.write(line)
    }

    private func cleanUpProcess() {
        process = nil
        stdoutPipe = nil
        stderrPipe = nil
        stdinPipe = nil
        buffer.removeAll()
        pendingTurnRequest = nil
        turnInFlight = false
        emittedAssistantMessageStart = false
        didStreamAssistantDelta = false
        didEmitAssistantResult = false
        pendingInterruptionID = nil
        shouldIgnoreOutputUntilTurnEnds = false
    }

    private func dispatchError(_ message: String) {
        turnInFlight = false
        pendingInterruptionID = nil
        didEmitAssistantResult = false
        shouldIgnoreOutputUntilTurnEnds = false
        onError?(message)
    }

    private func humanize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }
}
