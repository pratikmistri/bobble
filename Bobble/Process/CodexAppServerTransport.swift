import Foundation

final class CodexAppServerTransport: ConversationTransport {
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

    private enum PendingServerRequest {
        case commandExecution(requestID: Int)
        case fileChange(requestID: Int)
        case permissions(requestID: Int, permissions: [String: Any])
        case userInput(requestID: Int, questionID: String)
    }

    private let executablePath: String
    private let workingDirectory: String
    private let executionMode: ConversationExecutionMode
    private let queue = DispatchQueue(label: "Bobble.CodexAppServerTransport")

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var nextRequestID = 1
    private var pendingResponses: [Int: ([String: Any]) -> Void] = [:]
    private var pendingTurnRequest: ConversationTurnRequest?
    private var pendingServerRequests: [String: PendingServerRequest] = [:]
    private var threadID: String?
    private var didInitialize = false
    private var isOpeningThread = false
    private var turnInFlight = false
    private var emittedAssistantMessageStart = false
    private var isStopping = false

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

            self.openThreadIfNeeded()
            self.startPendingTurnIfPossible()
        }
    }

    func stop() {
        queue.async {
            self.isStopping = true
            self.pendingTurnRequest = nil
            self.turnInFlight = false
            self.pendingServerRequests.removeAll()
            self.process?.terminate()
            self.cleanUpProcess()
        }
    }

    func resolveInterruption(id: String, actionTransportValue: String?, textResponse: String?) {
        queue.async {
            guard let pending = self.pendingServerRequests.removeValue(forKey: id) else { return }

            switch pending {
            case .commandExecution(let requestID):
                let decision = self.codexDecision(from: actionTransportValue) ?? "cancel"
                self.writeJSON([
                    "id": requestID,
                    "result": [
                        "decision": decision
                    ]
                ])

            case .fileChange(let requestID):
                let decision = self.fileChangeDecision(from: actionTransportValue) ?? "cancel"
                self.writeJSON([
                    "id": requestID,
                    "result": [
                        "decision": decision
                    ]
                ])

            case .permissions(let requestID, let permissions):
                let scope = actionTransportValue == "session" ? "session" : "turn"
                let grantedPermissions: [String: Any] = actionTransportValue == "deny" ? [:] : permissions
                self.writeJSON([
                    "id": requestID,
                    "result": [
                        "permissions": grantedPermissions,
                        "scope": scope
                    ]
                ])

            case .userInput(let requestID, let questionID):
                let answer = actionTransportValue ?? textResponse ?? ""
                self.writeJSON([
                    "id": requestID,
                    "result": [
                        "answers": [
                            questionID: [
                                "answers": [answer]
                            ]
                        ]
                    ]
                ])
            }
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
        process.arguments = ["app-server"]
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
                    self.dispatchError(stderrText?.isEmpty == false ? stderrText! : "Codex app-server terminated unexpectedly.")
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
            dispatchError("Failed to launch Codex app-server: \(error.localizedDescription)")
        }
    }

    private func initializeConnection() {
        sendRequest(
            method: "initialize",
            params: [
                "clientInfo": [
                    "name": "Bobble",
                    "title": "Bobble",
                    "version": "1.0"
                ],
                "capabilities": NSNull()
            ]
        ) { [weak self] _ in
            self?.didInitialize = true
            self?.openThreadIfNeeded()
        }
    }

    private func openThreadIfNeeded() {
        guard didInitialize,
              !isOpeningThread,
              threadID == nil,
              let request = pendingTurnRequest else {
            return
        }

        isOpeningThread = true

        if request.isResume {
            sendRequest(method: "thread/resume", params: makeThreadResumeParams(for: request)) { [weak self] result in
                guard let self else { return }
                self.isOpeningThread = false

                if result["__errorMessage"] != nil {
                    self.startNewThread(for: request)
                    return
                }

                self.handleThreadOpenResponse(result)
            }
        } else {
            startNewThread(for: request)
        }
    }

    private func startNewThread(for request: ConversationTurnRequest) {
        sendRequest(method: "thread/start", params: makeThreadStartParams(for: request)) { [weak self] result in
            guard let self else { return }
            self.isOpeningThread = false
            self.handleThreadOpenResponse(result)
        }
    }

    private func handleThreadOpenResponse(_ result: [String: Any]) {
        if let errorMessage = result["__errorMessage"] as? String {
            dispatchError(errorMessage)
            return
        }

        guard let thread = result["thread"] as? [String: Any],
              let newThreadID = thread["id"] as? String else {
            dispatchError("Codex app-server did not return a thread id.")
            return
        }

        threadID = newThreadID
        onSessionId?(newThreadID)
        startPendingTurnIfPossible()
    }

    private func startPendingTurnIfPossible() {
        guard didInitialize,
              !isOpeningThread,
              !turnInFlight,
              let request = pendingTurnRequest,
              let threadID else {
            return
        }

        pendingTurnRequest = nil
        turnInFlight = true
        emittedAssistantMessageStart = false

        sendRequest(
            method: "turn/start",
            params: makeTurnStartParams(for: request, threadID: threadID)
        ) { [weak self] result in
            guard let self else { return }
            if let errorMessage = result["__errorMessage"] as? String {
                self.dispatchError(errorMessage)
            }
        }
    }

    private func sendRequest(method: String, params: Any, completion: @escaping ([String: Any]) -> Void) {
        let requestID = nextRequestID
        nextRequestID += 1
        pendingResponses[requestID] = completion

        writeJSON([
            "id": requestID,
            "method": method,
            "params": params
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
            let params = json["params"] as? [String: Any] ?? [:]
            if let idValue = json["id"], let requestID = requestID(from: idValue) {
                handleServerRequest(method: method, requestID: requestID, params: params)
            } else {
                handleNotification(method: method, params: params)
            }
            return
        }

        guard let idValue = json["id"],
              let responseID = requestID(from: idValue),
              let callback = pendingResponses.removeValue(forKey: responseID) else {
            return
        }

        if let result = json["result"] as? [String: Any] {
            callback(result)
            return
        }

        if let error = json["error"] as? [String: Any] {
            callback([
                "__errorMessage": (error["message"] as? String) ?? "Unknown Codex app-server error."
            ])
        }
    }

    private func handleNotification(method: String, params: [String: Any]) {
        switch method {
        case "thread/started":
            if let thread = params["thread"] as? [String: Any],
               let newThreadID = thread["id"] as? String {
                threadID = newThreadID
                onSessionId?(newThreadID)
            }

        case "item/agentMessage/delta":
            guard let delta = params["delta"] as? String,
                  !delta.isEmpty else {
                return
            }
            if !emittedAssistantMessageStart {
                emittedAssistantMessageStart = true
                onAssistantMessageStarted?()
            }
            onTextChunk?(delta)

        case "item/started", "item/completed":
            guard let item = params["item"] as? [String: Any] else { return }
            if let text = renderItem(method: method, item: item) {
                onEventText?(text)
            }
            if method == "item/completed",
               let itemType = item["type"] as? String,
               itemType == "agentMessage",
               let text = item["text"] as? String,
               !text.isEmpty {
                if !emittedAssistantMessageStart {
                    emittedAssistantMessageStart = true
                    onAssistantMessageStarted?()
                }
                onResult?(text)
            }

        case "item/reasoning/textDelta", "item/reasoning/summaryTextDelta":
            if let delta = params["delta"] as? String,
               !delta.isEmpty {
                onEventText?("Reasoning\n\(delta)")
            }

        case "item/plan/delta":
            if let delta = params["delta"] as? String,
               !delta.isEmpty {
                onEventText?("Plan\n\(delta)")
            }

        case "turn/completed":
            turnInFlight = false
            emittedAssistantMessageStart = false
            if let turn = params["turn"] as? [String: Any],
               let status = turn["status"] as? [String: Any],
               let statusType = status["type"] as? String,
               statusType == "failed",
               let error = turn["error"] as? [String: Any],
               let message = error["message"] as? String {
                dispatchError(message)
                return
            }
            onTurnCompleted?()
            onComplete?()
            startPendingTurnIfPossible()

        case "error":
            if let message = params["message"] as? String {
                dispatchError(message)
            }

        default:
            break
        }
    }

    private func handleServerRequest(method: String, requestID: Int, params: [String: Any]) {
        let interruptionID = UUID().uuidString

        switch method {
        case "item/commandExecution/requestApproval":
            pendingServerRequests[interruptionID] = .commandExecution(requestID: requestID)
            onInterruption?(
                ConversationInterruption(
                    id: interruptionID,
                    kind: .permission,
                    provider: .codex,
                    title: "Codex needs approval",
                    details: renderCommandApprovalDetails(params),
                    actions: makeCommandApprovalActions(from: params["availableDecisions"] as? [Any]),
                    responseMode: .actionButtons
                )
            )

        case "item/fileChange/requestApproval":
            pendingServerRequests[interruptionID] = .fileChange(requestID: requestID)
            onInterruption?(
                ConversationInterruption(
                    id: interruptionID,
                    kind: .permission,
                    provider: .codex,
                    title: "Codex wants to apply changes",
                    details: renderFileChangeApprovalDetails(params),
                    actions: [
                        .init(id: "accept", label: "Allow Once", role: .primary, transportValue: "accept"),
                        .init(id: "acceptForSession", label: "Allow For Session", role: .secondary, transportValue: "acceptForSession"),
                        .init(id: "decline", label: "Deny", role: .destructive, transportValue: "decline")
                    ],
                    responseMode: .actionButtons
                )
            )

        case "item/permissions/requestApproval":
            let permissions = params["permissions"] as? [String: Any] ?? [:]
            pendingServerRequests[interruptionID] = .permissions(requestID: requestID, permissions: permissions)
            onInterruption?(
                ConversationInterruption(
                    id: interruptionID,
                    kind: .permission,
                    provider: .codex,
                    title: "Codex requests more permissions",
                    details: renderPermissionsApprovalDetails(params),
                    actions: [
                        .init(id: "turn", label: "Allow Once", role: .primary, transportValue: "turn"),
                        .init(id: "session", label: "Allow For Session", role: .secondary, transportValue: "session"),
                        .init(id: "deny", label: "Deny", role: .destructive, transportValue: "deny")
                    ],
                    responseMode: .actionButtons
                )
            )

        case "item/tool/requestUserInput":
            guard let questions = params["questions"] as? [[String: Any]],
                  let question = questions.first,
                  let questionID = question["id"] as? String else {
                return
            }

            pendingServerRequests[interruptionID] = .userInput(requestID: requestID, questionID: questionID)
            let options = (question["options"] as? [[String: Any]]) ?? []
            let actions = options.compactMap { option -> ConversationInterruption.Action? in
                guard let label = option["label"] as? String else { return nil }
                return ConversationInterruption.Action(
                    id: label,
                    label: label,
                    role: .primary,
                    transportValue: label
                )
            }
            let details = renderUserInputDetails(question)
            let responseMode: ConversationInterruption.ResponseMode = actions.isEmpty ? .textReply : .actionButtons
            let fullDetails = responseMode == .textReply ? details + "\n\nReply in chat to continue." : details

            onInterruption?(
                ConversationInterruption(
                    id: interruptionID,
                    kind: .question,
                    provider: .codex,
                    title: "Codex needs input",
                    details: fullDetails,
                    actions: actions,
                    responseMode: responseMode
                )
            )

        default:
            break
        }
    }

    private func makeThreadStartParams(for request: ConversationTurnRequest) -> [String: Any] {
        var params: [String: Any] = [
            "cwd": request.workingDirectory,
            "approvalPolicy": approvalPolicy(for: request.executionMode),
            "approvalsReviewer": "user",
            "sandbox": "danger-full-access",
            "experimentalRawEvents": false,
            "persistExtendedHistory": false
        ]
        if let model = request.model {
            params["model"] = model
        }
        return params
    }

    private func makeThreadResumeParams(for request: ConversationTurnRequest) -> [String: Any] {
        var params: [String: Any] = [
            "threadId": request.sessionId,
            "cwd": request.workingDirectory,
            "approvalPolicy": approvalPolicy(for: request.executionMode),
            "approvalsReviewer": "user",
            "sandbox": "danger-full-access",
            "persistExtendedHistory": false
        ]
        if let model = request.model {
            params["model"] = model
        }
        return params
    }

    private func makeTurnStartParams(for request: ConversationTurnRequest, threadID: String) -> [String: Any] {
        var input: [[String: Any]] = [
            [
                "type": "text",
                "text": request.prompt,
                "text_elements": []
            ]
        ]

        input.append(contentsOf: request.imagePaths.map { path in
            [
                "type": "localImage",
                "path": path
            ]
        })

        var params: [String: Any] = [
            "threadId": threadID,
            "input": input,
            "cwd": request.workingDirectory,
            "approvalPolicy": approvalPolicy(for: request.executionMode),
            "approvalsReviewer": "user",
            "sandboxPolicy": [
                "type": "dangerFullAccess"
            ]
        ]
        if let model = request.model {
            params["model"] = model
        }
        return params
    }

    private func approvalPolicy(for mode: ConversationExecutionMode) -> String {
        mode == .ask ? "untrusted" : "never"
    }

    private func makeCommandApprovalActions(from decisions: [Any]?) -> [ConversationInterruption.Action] {
        let availableDecisions = decisions ?? ["accept", "acceptForSession", "decline"]

        return availableDecisions.compactMap { rawDecision in
            guard let decision = rawDecision as? String else { return nil }

            switch decision {
            case "accept":
                return .init(id: decision, label: "Allow Once", role: .primary, transportValue: decision)
            case "acceptForSession":
                return .init(id: decision, label: "Allow For Session", role: .secondary, transportValue: decision)
            case "decline", "cancel":
                return .init(id: decision, label: "Deny", role: .destructive, transportValue: "decline")
            default:
                return nil
            }
        }
    }

    private func renderCommandApprovalDetails(_ params: [String: Any]) -> String {
        var lines: [String] = []
        if let command = params["command"] as? String, !command.isEmpty {
            lines.append("Command: \(command)")
        }
        if let cwd = params["cwd"] as? String, !cwd.isEmpty {
            lines.append("Directory: \(cwd)")
        }
        if let reason = params["reason"] as? String, !reason.isEmpty {
            lines.append("Reason: \(reason)")
        }
        return lines.isEmpty ? "Codex wants to run a command." : lines.joined(separator: "\n")
    }

    private func renderFileChangeApprovalDetails(_ params: [String: Any]) -> String {
        if let changes = params["changes"] as? [[String: Any]], !changes.isEmpty {
            return "Codex wants to apply \(changes.count) file change\(changes.count == 1 ? "" : "s")."
        }
        return "Codex wants to apply file changes."
    }

    private func renderPermissionsApprovalDetails(_ params: [String: Any]) -> String {
        var lines: [String] = []
        if let reason = params["reason"] as? String, !reason.isEmpty {
            lines.append(reason)
        }
        if let permissions = params["permissions"] as? [String: Any],
           let pretty = prettyJSONString(permissions) {
            lines.append("Permissions:\n\(pretty)")
        }
        return lines.isEmpty ? "Codex requested additional permissions." : lines.joined(separator: "\n")
    }

    private func renderUserInputDetails(_ question: [String: Any]) -> String {
        var lines: [String] = []
        if let header = question["header"] as? String, !header.isEmpty {
            lines.append(header)
        }
        if let prompt = question["question"] as? String, !prompt.isEmpty {
            lines.append(prompt)
        }
        return lines.isEmpty ? "Codex needs more input." : lines.joined(separator: "\n")
    }

    private func renderItem(method: String, item: [String: Any]) -> String? {
        guard let itemType = item["type"] as? String else { return nil }

        switch itemType {
        case "commandExecution":
            let command = (item["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(unknown command)"
            let status = ((item["status"] as? [String: Any])?["type"] as? String) ?? "inProgress"
            return status == "inProgress" || method == "item/started"
                ? "Running command: `\(command)`"
                : "Command \(status): `\(command)`"

        case "fileChange":
            if let changes = item["changes"] as? [[String: Any]] {
                return "File changes: \(changes.count)"
            }
            return "File changes updated."

        case "plan":
            if let text = item["text"] as? String, !text.isEmpty {
                return "Plan\n\(text)"
            }
            return nil

        case "mcpToolCall":
            let server = item["server"] as? String ?? "MCP"
            let tool = item["tool"] as? String ?? "tool"
            return "\(server): \(tool)"

        default:
            return nil
        }
    }

    private func codexDecision(from value: String?) -> Any? {
        guard let value else { return nil }
        switch value {
        case "accept", "acceptForSession", "decline", "cancel":
            return value
        default:
            return nil
        }
    }

    private func fileChangeDecision(from value: String?) -> String? {
        guard let value else { return nil }
        switch value {
        case "accept", "acceptForSession", "decline", "cancel":
            return value
        default:
            return nil
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
        pendingTurnRequest = nil
        pendingServerRequests.removeAll()
        threadID = nil
        didInitialize = false
        isOpeningThread = false
        turnInFlight = false
        emittedAssistantMessageStart = false
    }

    private func dispatchError(_ message: String) {
        turnInFlight = false
        pendingServerRequests.removeAll()
        onError?(message)
    }
}
