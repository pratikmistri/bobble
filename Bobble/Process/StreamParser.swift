import Foundation

class StreamParser {
    private var buffer = Data()
    private let backend: CLIBackend
    private var codexAccumulatedText = ""

    var onTextDelta: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onSessionId: ((String) -> Void)?
    var onEventText: ((String) -> Void)?
    var onAssistantMessageStarted: (() -> Void)?

    init(backend: CLIBackend) {
        self.backend = backend
    }

    func feed(_ data: Data) {
        buffer.append(data)

        // Split on newlines and process complete lines
        while let newlineRange = buffer.range(of: Data("\n".utf8)) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
            buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

            guard !lineData.isEmpty else { continue }

            processLine(lineData)
        }
    }

    private func processLine(_ data: Data) {
        switch backend {
        case .claude:
            processClaudeLine(data)
        case .codex:
            processCodexLine(data)
        }
    }

    private func processClaudeLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Not JSON — could be plain text output, treat as text
            if let text = String(data: data, encoding: .utf8) {
                onTextDelta?(text)
            }
            return
        }

        guard let type = json["type"] as? String else {
            if let result = json["result"] as? String {
                onResult?(result)
            }
            return
        }

        switch type {
        case "content_block_delta":
            if let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                onTextDelta?(text)
            }

        case "assistant":
            // Claude Code stream-json: assistant message with content blocks
            if let message = json["message"] as? [String: Any],
               let content = message["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        onTextDelta?(text)
                    }
                }
            }
            // Also handle top-level content array
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        onTextDelta?(text)
                    }
                }
            }

        case "result":
            if let result = json["result"] as? String {
                onResult?(result)
            }
            // Handle result with content blocks
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        onResult?(text)
                    }
                }
            }

        case "message_stop", "message_delta":
            break // Signals end, handled by process termination

        default:
            break
        }
    }

    private func processCodexLine(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Codex exec --json emits JSONL on stdout. Ignore non-JSON lines.
            return
        }

        guard let type = json["type"] as? String else { return }

        switch type {
        case "thread.started":
            if let threadId = json["thread_id"] as? String {
                onSessionId?(threadId)
            } else if let thread = json["thread"] as? [String: Any],
                      let threadId = thread["id"] as? String {
                onSessionId?(threadId)
            }

        case "turn.started":
            codexAccumulatedText = ""

        case "agent_message.delta":
            if let delta = json["delta"] as? String {
                codexAccumulatedText += delta
                onTextDelta?(delta)
            }

        case "item.started":
            guard let item = json["item"] as? [String: Any] else { return }
            if let itemType = item["type"] as? String, itemType == "agent_message" {
                codexAccumulatedText = ""
                onAssistantMessageStarted?()
                return
            }
            if let eventText = renderCodexItem(eventType: type, item: item) {
                onEventText?(eventText)
            }

        case "item.completed":
            guard let item = json["item"] as? [String: Any],
                  let itemType = item["type"] as? String else {
                if let eventText = renderCodexEvent(type: type, payload: json) {
                    onEventText?(eventText)
                }
                return
            }

            if itemType == "agent_message", let fullText = item["text"] as? String {
                onResult?(fullText)
                codexAccumulatedText = ""
            } else {
                if let eventText = renderCodexItem(eventType: type, item: item) {
                    onEventText?(eventText)
                }
            }

        case "error", "turn.failed":
            if let eventText = renderCodexEvent(type: type, payload: json) {
                onEventText?(eventText)
            }

        default:
            if let eventText = renderCodexEvent(type: type, payload: json) {
                onEventText?(eventText)
            }
            break
        }
    }

    private func renderCodexItem(eventType: String, item: [String: Any]) -> String? {
        guard let itemType = item["type"] as? String else { return nil }
        let itemTypeKey = itemType.lowercased()

        if itemTypeKey == "command_execution" || (itemTypeKey.contains("command") && itemTypeKey.contains("execution")) {
            let command = (item["command"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "(unknown command)"
            let status = (item["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "in_progress"
            var lines: [String] = []
            if eventType == "item.started" || status == "in_progress" {
                lines.append("Running command: `\(command)`")
            } else {
                lines.append("Command \(status): `\(command)`")
                if let exitCode = item["exit_code"] as? Int {
                    lines.append("Exit code: \(exitCode)")
                }
                if let output = sanitizeMultiline(item["aggregated_output"] as? String), !output.isEmpty {
                    lines.append("Output:\n\(output)")
                }
            }
            return lines.joined(separator: "\n")
        }

        if itemTypeKey.contains("approval")
            || itemTypeKey.contains("permission")
            || itemTypeKey.contains("request_user_input")
            || itemTypeKey.contains("user_input")
            || itemTypeKey.contains("question")
            || itemTypeKey.contains("answer") {
            let title = "Codex \(humanize(itemType))"
            if let body = compactJSON(item) {
                return "\(title)\nDetails:\n\(body)"
            }
            return title
        }

        return nil
    }

    private func renderCodexEvent(type: String, payload: [String: Any]) -> String? {
        let eventKey = type.lowercased()
        if eventKey.contains("approval")
            || eventKey.contains("permission")
            || eventKey.contains("request_user_input")
            || eventKey.contains("user_input")
            || eventKey.contains("question")
            || eventKey.contains("answer")
            || eventKey == "error"
            || eventKey == "turn.failed" {
            let title = "Codex \(humanize(type))"
            if let body = compactJSON(payload) {
                return "\(title)\nDetails:\n\(body)"
            }
            return title
        }
        return nil
    }

    private func compactJSON(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              var text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let maxCharacters = 3000
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)) + "\n... (truncated)"
        }
        return text
    }

    private func humanize(_ raw: String) -> String {
        return raw
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .capitalized
    }

    private func sanitizeMultiline(_ text: String?) -> String? {
        guard var text else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }

        let maxCharacters = 2500
        if text.count > maxCharacters {
            text = String(text.prefix(maxCharacters)) + "\n... (truncated)"
        }
        return text
    }
}
