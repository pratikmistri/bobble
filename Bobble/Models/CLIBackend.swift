import Foundation

enum CLIBackend: String, CaseIterable, Identifiable, Codable {
    case codex
    case copilot
    case claude

    var id: String { rawValue }

    var command: String {
        switch self {
        case .codex:
            return "codex"
        case .copilot:
            return "copilot"
        case .claude:
            return "claude"
        }
    }

    var displayName: String {
        switch self {
        case .codex:
            return "Codex"
        case .copilot:
            return "GitHub Copilot"
        case .claude:
            return "Claude Code"
        }
    }

    var shortLabel: String {
        switch self {
        case .codex:
            return "Codex"
        case .copilot:
            return "Copilot"
        case .claude:
            return "Claude"
        }
    }

    var missingCLIMessage: String {
        switch self {
        case .codex:
            return "Codex CLI not found. Install with `npm install -g @openai/codex`."
        case .copilot:
            return "GitHub Copilot CLI not found. Install and authenticate the `copilot` CLI."
        case .claude:
            return "Claude Code CLI not found. Install Claude Code so the `claude` command is available."
        }
    }

    static func detect() -> CLIBackend? {
        preferredDefault(from: Set(availableBackends()))
    }

    static func availableBackends() -> [CLIBackend] {
        allCases.filter { $0.resolvedPath() != nil }
    }

    static func preferredDefault(from availableBackends: Set<CLIBackend>) -> CLIBackend? {
        if availableBackends.contains(.codex) {
            return .codex
        }
        if availableBackends.contains(.copilot) {
            return .copilot
        }
        if availableBackends.contains(.claude) {
            return .claude
        }
        return allCases.first
    }

    /// Common directories where npm/brew/cargo installs end up,
    /// which are NOT on PATH when a macOS .app is launched from Dock/Spotlight.
    private static let searchPaths: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "\(home)/.local/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "\(home)/.nvm/versions/node/default/bin",   // nvm symlink
            "\(home)/.volta/bin",
            "\(home)/.cargo/bin",
        ]
    }()

    func resolvedPath() -> String? {
        // 1. Try `which` (works if PATH is rich enough)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {}

        // 2. Fallback: probe well-known directories
        let fm = FileManager.default
        for dir in Self.searchPaths {
            let candidate = "\(dir)/\(command)"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }
}

enum CodexModelOption: String, CaseIterable, Identifiable, Codable {
    case `default` = "default"
    case gpt5Codex = "gpt-5-codex"
    case gpt53Codex = "gpt-5.3-codex"
    case gpt52Codex = "gpt-5.2-codex"
    case gpt51Codex = "gpt-5.1-codex"
    case gpt51CodexMax = "gpt-5.1-codex-max"
    case gpt51CodexMini = "gpt-5.1-codex-mini"

    var id: String { rawValue }

    var cliValue: String? {
        self == .default ? nil : rawValue
    }

    var displayName: String {
        switch self {
        case .default:
            return "Auto"
        case .gpt5Codex:
            return "GPT-5 Codex"
        case .gpt53Codex:
            return "GPT-5.3 Codex"
        case .gpt52Codex:
            return "GPT-5.2 Codex"
        case .gpt51Codex:
            return "GPT-5.1 Codex"
        case .gpt51CodexMax:
            return "GPT-5.1 Codex Max"
        case .gpt51CodexMini:
            return "GPT-5.1 Codex Mini"
        }
    }

    var shortLabel: String {
        switch self {
        case .default:
            return "Auto"
        case .gpt5Codex:
            return "5 Codex"
        case .gpt53Codex:
            return "5.3 Codex"
        case .gpt52Codex:
            return "5.2 Codex"
        case .gpt51Codex:
            return "5.1 Codex"
        case .gpt51CodexMax:
            return "5.1 Max"
        case .gpt51CodexMini:
            return "5.1 Mini"
        }
    }

    var subtitle: String {
        switch self {
        case .default:
            return "Use the Codex CLI default model."
        case .gpt5Codex:
            return "General-purpose Codex-optimized coding model."
        case .gpt53Codex:
            return "Most capable current Codex model."
        case .gpt52Codex:
            return "Strong long-horizon coding model."
        case .gpt51Codex:
            return "Balanced GPT-5.1 coding model."
        case .gpt51CodexMax:
            return "GPT-5.1 Codex variant for longer-running tasks."
        case .gpt51CodexMini:
            return "Smaller, cheaper GPT-5.1 Codex variant."
        }
    }
}
