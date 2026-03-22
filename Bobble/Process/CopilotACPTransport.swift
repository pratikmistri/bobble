import Foundation

final class CopilotACPTransport: ConversationTransport {
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
    private let queue = DispatchQueue(label: "Bobble.CopilotACPTransport")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var nextRequestID = 1
    private var pendingResponses: [Int: ([String: Any]) -> Void] = [:]
    private var activeSessionID: String?
    private var pendingTurnRequest: ConversationTurnRequest?
    private var turnInFlight = false
    private var emittedAssistantMessageStart = false
    private var isStopping = false
    private var interruptionRequestIDs: [String: Int] = [:]

    init(executablePath: String, workingDirectory: String, executionMode: ConversationExecutionMode) {
        self.executablePath = executablePath
        self.workingDirectory = workingDirectory
        self.executionMode = executionMode
    }

    func sendTurn(_ request: ConversationTurnRequest) {
        queue.async {
            self.pendingTurnRequest = request

            if self.process == nil {
                self.startProcess()
                return
            }

            self.startPendingTurnIfPossible()
        }
    }

    func stop() {
        queue.async {
            self.isStopping = true
            for (interruptionID, requestID) in self.interruptionRequestIDs {
                self.respondToPermissionRequest(requestID: requestID, optionID: nil)
                self.interruptionRequestIDs.removeValue(forKey: interruptionID)
            }
            self.turnInFlight = false
            self.pendingTurnRequest = nil
            self.process?.terminate()
            self.cleanUpProcess()
        }
    }

    func resolveInterruption(id: String, actionTransportValue: String?, textResponse: String?) {
        queue.async {
            guard let requestID = self.interruptionRequestIDs.removeValue(forKey: id) else { return }
            self.respondToPermissionRequest(requestID: requestID, optionID: actionTransportValue)
        }
    }

    private func startProcess() {
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
        process.arguments = makeArguments()
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
                    self.dispatchError(stderrText?.isEmpty == false ? stderrText! : "Copilot ACP terminated unexpectedly.")
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
            initializeConnection()
        } catch {
            dispatchError("Failed to launch Copilot ACP: \(error.localizedDescription)")
        }
    }

    private func initializeConnection() {
        sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": 1,
                "clientCapabilities": [
                    "fs": [
                        "readTextFile": false,
                        "writeTextFile": false
                    ],
                    "terminal": false
                ],
                "clientInfo": [
                    "name": "Bobble",
                    "version": "1.0"
                ]
            ]
        ) { [weak self] _ in
            self?.openSession()
        }
    }

    private func openSession() {
        sendRequest(
            method: "session/new",
            params: [
                "cwd": workingDirectory,
                "mcpServers": []
            ]
        ) { [weak self] result in
            guard let self else { return }
            if let sessionID = result["sessionId"] as? String {
                self.activeSessionID = sessionID
                self.onSessionId?(sessionID)
            }
            self.startPendingTurnIfPossible()
        }
    }

    private func startPendingTurnIfPossible() {
        guard !turnInFlight,
              let request = pendingTurnRequest,
              let sessionID = activeSessionID else {
            return
        }

        pendingTurnRequest = nil
        turnInFlight = true
        emittedAssistantMessageStart = false

        var promptBlocks: [[String: Any]] = [
            [
                "type": "text",
                "text": request.prompt
            ]
        ]

        if !request.imagePaths.isEmpty {
            let attachmentText = request.imagePaths.map { "- \($0)" }.joined(separator: "\n")
            promptBlocks.append([
                "type": "text",
                "text": "Images attached for context:\n\(attachmentText)"
            ])
        }

        sendRequest(
            method: "session/prompt",
            params: [
                "sessionId": sessionID,
                "prompt": promptBlocks
            ]
        ) { [weak self] result in
            guard let self else { return }
            self.turnInFlight = false
            if let stopReason = result["stopReason"] as? String, stopReason != "end_turn" {
                self.onEventText?("Copilot finished with stop reason: \(stopReason)")
            }
            self.onTurnCompleted?()
            self.onComplete?()
            self.startPendingTurnIfPossible()
        }
    }

    private func sendRequest(method: String, params: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let requestID = nextRequestID
        nextRequestID += 1
        pendingResponses[requestID] = completion

        writeJSON([
            "jsonrpc": "2.0",
            "id": requestID,
            "method": method,
            "params": params
        ])
    }

    private func respondToPermissionRequest(requestID: Int, optionID: String?) {
        let outcome: [String: Any] = {
            if let optionID {
                return [
                    "outcome": "selected",
                    "optionId": optionID
                ]
            }
            return [
                "outcome": "cancelled"
            ]
        }()

        writeJSON([
            "jsonrpc": "2.0",
            "id": requestID,
            "result": [
                "outcome": outcome
            ]
        ])
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
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let method = json["method"] as? String {
            switch method {
            case "session/update":
                if let params = json["params"] as? [String: Any] {
                    handleSessionUpdate(params)
                }
            case "session/request_permission":
                handlePermissionRequest(json)
            default:
                break
            }
            return
        }

        guard let idValue = json["id"] else { return }
        let requestID = requestID(from: idValue)
        guard let requestID,
              let callback = pendingResponses.removeValue(forKey: requestID) else {
            return
        }

        if let result = json["result"] as? [String: Any] {
            callback(result)
        } else {
            callback(json)
        }
    }

    private func handleSessionUpdate(_ params: [String: Any]) {
        guard let update = params["update"] as? [String: Any],
              let updateType = update["sessionUpdate"] as? String else {
            return
        }

        switch updateType {
        case "agent_message_chunk":
            guard let content = update["content"] as? [String: Any],
                  let text = content["text"] as? String,
                  !text.isEmpty else {
                return
            }
            if !emittedAssistantMessageStart {
                emittedAssistantMessageStart = true
                onAssistantMessageStarted?()
            }
            onTextChunk?(text)

        case "agent_thought_chunk":
            guard let content = update["content"] as? [String: Any],
                  let text = content["text"] as? String,
                  !text.isEmpty else {
                return
            }
            onEventText?("Agent thought\n\(text)")

        case "tool_call", "tool_call_update":
            let title = (update["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (update["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            var lines: [String] = []
            if let title, !title.isEmpty {
                lines.append(title)
            }
            if let status, !status.isEmpty {
                lines.append("Status: \(status)")
            }
            if let rawInput = prettyJSONString(update["rawInput"]), !rawInput.isEmpty {
                lines.append("Input:\n\(rawInput)")
            }
            if let rawOutput = prettyJSONString(update["rawOutput"]), !rawOutput.isEmpty {
                lines.append("Output:\n\(rawOutput)")
            }
            let text = lines.joined(separator: "\n")
            if !text.isEmpty {
                onEventText?(text)
            }

        default:
            break
        }
    }

    private func handlePermissionRequest(_ json: [String: Any]) {
        guard let idValue = json["id"],
              let requestID = requestID(from: idValue),
              let params = json["params"] as? [String: Any],
              let options = params["options"] as? [[String: Any]] else {
            return
        }

        let interruptionID = UUID().uuidString
        interruptionRequestIDs[interruptionID] = requestID

        let toolCall = params["toolCall"] as? [String: Any]
        let baseTitle = (toolCall?["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "Copilot needs approval"

        var details: [String] = [baseTitle]
        if let kind = toolCall?["kind"] as? String, !kind.isEmpty {
            details.append("Tool: \(kind)")
        }
        if let rawInput = prettyJSONString(toolCall?["rawInput"]), !rawInput.isEmpty {
            details.append("Input:\n\(rawInput)")
        }

        var actions = options.compactMap { makeAction(from: $0) }
        if executionMode == .ask,
           let allowOption = preferredAllowOptionID(from: options) {
            actions.append(
                ConversationInterruption.Action(
                    id: "bypass-conversation",
                    label: "Bypass Conversation",
                    role: .secondary,
                    transportValue: allowOption
                )
            )
        }

        onInterruption?(
            ConversationInterruption(
                id: interruptionID,
                kind: .permission,
                provider: .copilot,
                title: "Copilot needs approval",
                details: details.joined(separator: "\n"),
                actions: actions,
                responseMode: .actionButtons
            )
        )
    }

    private func makeAction(from option: [String: Any]) -> ConversationInterruption.Action? {
        guard let optionID = option["optionId"] as? String ?? option["id"] as? String else {
            return nil
        }

        let kind = option["kind"] as? String
        let label = (option["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? defaultLabel(for: kind)
        let role: ConversationInterruption.Action.Role
        switch kind {
        case "reject_once", "reject_always":
            role = .destructive
        case "allow_once", "allow_always":
            role = .primary
        default:
            role = .secondary
        }

        return ConversationInterruption.Action(
            id: optionID,
            label: label,
            role: role,
            transportValue: optionID
        )
    }

    private func preferredAllowOptionID(from options: [[String: Any]]) -> String? {
        for preferredKind in ["allow_always", "allow_once"] {
            if let option = options.first(where: { ($0["kind"] as? String) == preferredKind }) {
                return option["optionId"] as? String ?? option["id"] as? String
            }
        }
        return nil
    }

    private func defaultLabel(for kind: String?) -> String {
        switch kind {
        case "allow_once":
            return "Allow Once"
        case "allow_always":
            return "Always Allow"
        case "reject_once":
            return "Deny Once"
        case "reject_always":
            return "Always Deny"
        default:
            return "Choose"
        }
    }

    private func requestID(from value: Any) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string)
        }
        return nil
    }

    private func prettyJSONString(_ value: Any?) -> String? {
        guard let value,
              JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func makeArguments() -> [String] {
        var args = ["--acp", "--stdio"]
        if let model = pendingTurnRequest?.model {
            args += ["--model", model]
        }
        if executionMode == .bypass {
            args += ["--allow-all", "--no-ask-user"]
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
        pendingResponses.removeAll()
        activeSessionID = nil
        interruptionRequestIDs.removeAll()
    }

    private func dispatchError(_ message: String) {
        turnInFlight = false
        onError?(message)
    }
}
