import AppKit
import Foundation

struct ProviderUsageSummary {
    let title: String
    let valueText: String
    let caption: String
    let progressState: UsageProgressState

    static func loading(for provider: CLIBackend) -> ProviderUsageSummary {
        ProviderUsageSummary(
            title: provider.displayName,
            valueText: "Refreshing",
            caption: "Scanning local usage sources...",
            progressState: .indeterminate
        )
    }

    static func unavailable(for provider: CLIBackend, caption: String) -> ProviderUsageSummary {
        ProviderUsageSummary(
            title: provider.displayName,
            valueText: "Unavailable",
            caption: caption,
            progressState: .unavailable
        )
    }
}

enum UsageProgressState {
    case determinate(Double)
    case indeterminate
    case informational
    case unavailable
}

final class UsageMonitor {
    private struct CodexRateLimitSnapshot {
        let primaryUsedPercent: Int?
        let secondaryUsedPercent: Int?
    }

    private struct LocalUsageWindow {
        var fiveHourTokens = 0
        var todayTokens = 0
        var fiveHourPrompts = 0
        var todayPrompts = 0
        var totalTokens = 0
        var hasUsageData = false
        var rateLimitSnapshot: CodexRateLimitSnapshot?
    }

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "Bobble.UsageMonitor", qos: .utility)
    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private var cachedSummaries: [CLIBackend: ProviderUsageSummary]?
    private var lastRefreshDate: Date?
    private let cacheLifetime: TimeInterval = 60

    func refresh(force: Bool = false, completion: @escaping ([CLIBackend: ProviderUsageSummary]) -> Void) {
        queue.async {
            if !force,
               let cachedSummaries = self.cachedSummaries,
               let lastRefreshDate = self.lastRefreshDate,
               Date().timeIntervalSince(lastRefreshDate) < self.cacheLifetime {
                DispatchQueue.main.async {
                    completion(cachedSummaries)
                }
                return
            }

            let summaries = [
                CLIBackend.codex: self.loadCodexSummary(),
                CLIBackend.copilot: self.loadCopilotSummary(),
                CLIBackend.claude: self.loadClaudeSummary(),
            ]

            self.cachedSummaries = summaries
            self.lastRefreshDate = Date()

            DispatchQueue.main.async {
                completion(summaries)
            }
        }
    }

    private func loadCodexSummary() -> ProviderUsageSummary {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let databaseURL = homeURL.appendingPathComponent(".codex/state_5.sqlite", isDirectory: false)

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return .unavailable(for: .codex, caption: "No local Codex usage database found.")
        }

        let now = Date()
        let startOfDay = Self.calendar.startOfDay(for: now)
        let startOfDayTimestamp = Int(startOfDay.timeIntervalSince1970)
        let fiveHourCutoff = now.addingTimeInterval(-5 * 60 * 60)
        let fiveHourCutoffTimestamp = Int(fiveHourCutoff.timeIntervalSince1970)
        let query = """
        SELECT
            COALESCE(SUM(tokens_used), 0),
            GROUP_CONCAT(CASE WHEN updated_at >= \(min(startOfDayTimestamp, fiveHourCutoffTimestamp)) THEN rollout_path END, '\n')
        FROM threads;
        """

        guard let output = runProcess(
            executablePath: "/usr/bin/sqlite3",
            arguments: [databaseURL.path, "-separator", "\t", query]
        ) else {
            return .unavailable(for: .codex, caption: "Could not read ~/.codex/state_5.sqlite.")
        }

        let parts = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false)

        guard let totalTokens = parts.first.flatMap({ Int($0) }) else {
            return .unavailable(for: .codex, caption: "Could not parse local Codex usage data.")
        }

        let recentPaths = parts.count > 1
            ? parts[1]
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            : []

        var stats = LocalUsageWindow()
        stats.totalTokens = totalTokens

        for path in Set(recentPaths) {
            let fileURL = URL(fileURLWithPath: path, isDirectory: false)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let timestamp = json["timestamp"] as? String,
                      let date = self.parseISODate(timestamp),
                      let type = json["type"] as? String else {
                    return
                }

                if type == "event_msg",
                   let payload = json["payload"] as? [String: Any],
                   let payloadType = payload["type"] as? String {
                    if payloadType == "user_message" {
                        if date >= fiveHourCutoff {
                            stats.fiveHourPrompts += 1
                        }
                        if date >= startOfDay {
                            stats.todayPrompts += 1
                        }
                    } else if payloadType == "token_count",
                              let info = payload["info"] as? [String: Any] {
                        let tokenTotal = self.integerValue(
                            from: (info["last_token_usage"] as? [String: Any])?["total_tokens"]
                        )
                        let hasTokenData = tokenTotal > 0

                        if date >= fiveHourCutoff {
                            stats.fiveHourTokens += tokenTotal
                        }
                        if date >= startOfDay {
                            stats.todayTokens += tokenTotal
                        }
                        if hasTokenData {
                            stats.hasUsageData = true
                        }

                        if let rateLimits = payload["rate_limits"] as? [String: Any] {
                            stats.rateLimitSnapshot = CodexRateLimitSnapshot(
                                primaryUsedPercent: self.intPercent(from: rateLimits["primary_used_percent"]),
                                secondaryUsedPercent: self.intPercent(from: rateLimits["secondary_used_percent"])
                            )
                        }
                    }
                }
            }
        }

        guard stats.hasUsageData || stats.fiveHourPrompts > 0 || stats.totalTokens > 0 else {
            return .unavailable(for: .codex, caption: "No recent Codex token events found in local session logs.")
        }

        let valueText = stats.fiveHourTokens > 0
            ? "\(Self.formatTokenCount(stats.fiveHourTokens)) tok / \(stats.fiveHourPrompts)p"
            : "\(stats.fiveHourPrompts) prompts"

        let progressState: UsageProgressState
        var usageFragments = [
            "Last 5h: \(Self.formatTokenCount(stats.fiveHourTokens)) tokens across \(stats.fiveHourPrompts) prompts.",
            "Today: \(Self.formatTokenCount(stats.todayTokens)) tokens across \(stats.todayPrompts) prompts.",
            "Local total: \(Self.formatTokenCount(stats.totalTokens)).",
        ]

        if let rateLimits = stats.rateLimitSnapshot,
           let primaryUsedPercent = rateLimits.primaryUsedPercent {
            progressState = .determinate(Double(primaryUsedPercent) / 100.0)
            usageFragments.insert("Session window: \(primaryUsedPercent)% used.", at: 0)
            if let secondaryUsedPercent = rateLimits.secondaryUsedPercent {
                usageFragments.insert("Weekly window: \(secondaryUsedPercent)% used.", at: 1)
            }
        } else {
            progressState = .informational
        }

        return ProviderUsageSummary(
            title: CLIBackend.codex.displayName,
            valueText: valueText,
            caption: usageFragments.joined(separator: " "),
            progressState: progressState
        )
    }

    private func loadClaudeSummary() -> ProviderUsageSummary {
        let homeURL = fileManager.homeDirectoryForCurrentUser
        let projectsURL = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)

        guard fileManager.fileExists(atPath: projectsURL.path) else {
            return .unavailable(for: .claude, caption: "No local Claude session logs found.")
        }

        let now = Date()
        let startOfDay = Self.calendar.startOfDay(for: now)
        let fiveHourCutoff = now.addingTimeInterval(-5 * 60 * 60)
        let earliestRelevantDate = min(startOfDay, fiveHourCutoff)

        var stats = LocalUsageWindow()
        var seenRequestIds = Set<String>()
        var seenPromptIds = Set<String>()

        guard let enumerator = fileManager.enumerator(
            at: projectsURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .unavailable(for: .claude, caption: "Could not enumerate ~/.claude/projects.")
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else { continue }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
                guard resourceValues.isRegularFile == true else { continue }
                if let modifiedAt = resourceValues.contentModificationDate,
                   modifiedAt < earliestRelevantDate {
                    continue
                }
            } catch {
                continue
            }

            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            content.enumerateLines { line, _ in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String,
                      let timestamp = json["timestamp"] as? String,
                      let date = self.parseISODate(timestamp) else {
                    return
                }

                if type == "user",
                   let promptIdentifier = json["uuid"] as? String,
                   seenPromptIds.insert(promptIdentifier).inserted,
                   self.isClaudePromptEvent(json),
                   date >= earliestRelevantDate {
                    if date >= fiveHourCutoff {
                        stats.fiveHourPrompts += 1
                    }
                    if date >= startOfDay {
                        stats.todayPrompts += 1
                    }
                }

                guard type == "assistant",
                      let message = json["message"] as? [String: Any] else {
                    return
                }

                let requestIdentifier = (json["requestId"] as? String)
                    ?? (message["id"] as? String)
                    ?? (json["uuid"] as? String)

                guard let requestIdentifier,
                      seenRequestIds.insert(requestIdentifier).inserted,
                      let usage = message["usage"] as? [String: Any] else {
                    return
                }

                let billedTokens = self.integerValue(from: usage["input_tokens"])
                    + self.integerValue(from: usage["output_tokens"])
                    + self.integerValue(from: usage["cache_creation_input_tokens"])
                    + self.integerValue(from: usage["cache_read_input_tokens"])

                guard billedTokens > 0 else { return }
                stats.hasUsageData = true

                if date >= fiveHourCutoff {
                    stats.fiveHourTokens += billedTokens
                }
                if date >= startOfDay {
                    stats.todayTokens += billedTokens
                }
            }
        }

        guard stats.hasUsageData || stats.fiveHourPrompts > 0 else {
            return .unavailable(for: .claude, caption: "No recent Claude billing events found in local session logs.")
        }

        let valueText = stats.fiveHourTokens > 0
            ? "\(Self.formatTokenCount(stats.fiveHourTokens)) tok / \(stats.fiveHourPrompts)p"
            : "\(stats.fiveHourPrompts) prompts"

        return ProviderUsageSummary(
            title: CLIBackend.claude.displayName,
            valueText: valueText,
            caption: "Last 5h: \(Self.formatTokenCount(stats.fiveHourTokens)) billed tokens across \(stats.fiveHourPrompts) prompts. Today: \(Self.formatTokenCount(stats.todayTokens)) billed tokens across \(stats.todayPrompts) prompts.",
            progressState: .informational
        )
    }

    private func loadCopilotSummary() -> ProviderUsageSummary {
        let hasCLI = CLIBackend.copilot.resolvedPath() != nil

        if hasCLI {
            return .unavailable(
                for: .copilot,
                caption: "GitHub Copilot CLI is installed, but Bobble does not have a reliable local usage source for quota data yet."
            )
        }

        return .unavailable(
            for: .copilot,
            caption: "GitHub Copilot CLI is not installed, and no local usage source is available."
        )
    }

    private func parseISODate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }

        return Self.fallbackISOFormatter.date(from: value)
    }

    private func runProcess(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func integerValue(from value: Any?) -> Int {
        switch value {
        case let int as Int:
            return int
        case let number as NSNumber:
            return number.intValue
        case let string as String:
            return Int(string) ?? Int(Double(string) ?? 0)
        default:
            return 0
        }
    }

    private func intPercent(from value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return max(0, min(int, 100))
        case let double as Double:
            return max(0, min(Int(double.rounded()), 100))
        case let number as NSNumber:
            return max(0, min(number.intValue, 100))
        case let string as String:
            if let int = Int(string) {
                return max(0, min(int, 100))
            }
            if let double = Double(string) {
                return max(0, min(Int(double.rounded()), 100))
            }
            return nil
        default:
            return nil
        }
    }

    private func isClaudePromptEvent(_ json: [String: Any]) -> Bool {
        guard (json["isMeta"] as? Bool) != true,
              let message = json["message"] as? [String: Any],
              let role = message["role"] as? String,
              role == "user" else {
            return false
        }

        guard containsMeaningfulClaudeContent(message["content"]) else {
            return false
        }

        return true
    }

    private func containsMeaningfulClaudeContent(_ value: Any?) -> Bool {
        if let content = value as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            return !trimmed.contains("<command-name>")
                && !trimmed.contains("<local-command-caveat>")
        }

        if let content = value as? [[String: Any]] {
            for item in content {
                let type = (item["type"] as? String)?.lowercased()
                if type == "tool_result" {
                    continue
                }

                if let text = item["text"] as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return true
                }

                if type == "image" || type == "document" {
                    return true
                }
            }
        }

        return false
    }

    private static let calendar = Calendar(identifier: .gregorian)
    private static let fallbackISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func formatTokenCount(_ value: Int) -> String {
        guard value >= 1_000 else { return "\(value)" }
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        return String(format: "%.1fK", Double(value) / 1_000.0)
    }
}
