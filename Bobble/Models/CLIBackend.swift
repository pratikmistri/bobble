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

enum ProviderModelOption: String, CaseIterable, Identifiable, Codable {
    case automatic = "default"
    case gpt5Codex = "gpt-5-codex"
    case gpt53Codex = "gpt-5.3-codex"
    case gpt52Codex = "gpt-5.2-codex"
    case gpt51Codex = "gpt-5.1-codex"
    case gpt51CodexMax = "gpt-5.1-codex-max"
    case gpt51CodexMini = "gpt-5.1-codex-mini"
    case claudeSonnet46 = "claude-sonnet-4-6"
    case claudeOpus46 = "claude-opus-4-6"
    case claudeHaiku45 = "claude-haiku-4-5"
    case copilotClaudeSonnet45 = "Claude Sonnet 4.5"
    case copilotClaudeOpus45 = "Claude Opus 4.5"
    case copilotClaudeOpus46 = "Claude Opus 4.6"
    case copilotGPT51CodexMax = "GPT-5.1-Codex-Max"
    case copilotGPT52Codex = "GPT-5.2-Codex"

    var id: String { rawValue }

    static func availableOptions(for provider: CLIBackend) -> [ProviderModelOption] {
        allCases.filter { $0.metadata.availableProviders.contains(provider) }
    }

    func isAvailable(for provider: CLIBackend) -> Bool {
        metadata.availableProviders.contains(provider)
    }

    func normalized(for provider: CLIBackend) -> ProviderModelOption {
        isAvailable(for: provider) ? self : .automatic
    }

    func cliValue(for provider: CLIBackend) -> String? {
        guard isAvailable(for: provider), self != .automatic else { return nil }
        return rawValue
    }

    func displayName(for provider: CLIBackend) -> String {
        metadata.displayName
    }

    func shortLabel(for provider: CLIBackend) -> String {
        metadata.shortLabel
    }

    func subtitle(for provider: CLIBackend) -> String {
        metadata.subtitle.text(for: provider)
    }
}

private struct ProviderModelMetadata {
    let availableProviders: Set<CLIBackend>
    let displayName: String
    let shortLabel: String
    let subtitle: ProviderModelSubtitle
}

private enum ProviderModelSubtitle {
    case fixed(String)
    case byProvider([CLIBackend: String])

    func text(for provider: CLIBackend) -> String {
        switch self {
        case .fixed(let value):
            return value
        case .byProvider(let values):
            return values[provider] ?? ""
        }
    }
}

private extension ProviderModelOption {
    var metadata: ProviderModelMetadata {
        guard let metadata = Self.catalog[self] else {
            fatalError("Missing provider model metadata for \(self.rawValue)")
        }
        return metadata
    }

    static let catalog: [ProviderModelOption: ProviderModelMetadata] = [
        .automatic: ProviderModelMetadata(
            availableProviders: Set(CLIBackend.allCases),
            displayName: "Auto",
            shortLabel: "Auto",
            subtitle: .byProvider([
                .codex: "Use the Codex CLI default model.",
                .claude: "Use Claude Code's default model.",
                .copilot: "Use GitHub Copilot's default model."
            ])
        ),
        .gpt5Codex: ProviderModelMetadata(
            availableProviders: [.codex],
            displayName: "GPT-5 Codex",
            shortLabel: "5 Codex",
            subtitle: .fixed("General-purpose Codex-optimized coding model.")
        ),
        .gpt53Codex: ProviderModelMetadata(
            availableProviders: [.codex],
            displayName: "GPT-5.3 Codex",
            shortLabel: "5.3 Codex",
            subtitle: .fixed("Most capable current Codex model.")
        ),
        .gpt52Codex: ProviderModelMetadata(
            availableProviders: [.codex],
            displayName: "GPT-5.2 Codex",
            shortLabel: "5.2 Codex",
            subtitle: .fixed("Strong long-horizon coding model.")
        ),
        .gpt51Codex: ProviderModelMetadata(
            availableProviders: [.codex],
            displayName: "GPT-5.1 Codex",
            shortLabel: "5.1 Codex",
            subtitle: .fixed("Balanced GPT-5.1 coding model.")
        ),
        .gpt51CodexMax: ProviderModelMetadata(
            availableProviders: [.codex],
            displayName: "GPT-5.1 Codex Max",
            shortLabel: "5.1 Max",
            subtitle: .fixed("GPT-5.1 Codex variant for longer-running tasks.")
        ),
        .gpt51CodexMini: ProviderModelMetadata(
            availableProviders: [.codex],
            displayName: "GPT-5.1 Codex Mini",
            shortLabel: "5.1 Mini",
            subtitle: .fixed("Smaller, cheaper GPT-5.1 Codex variant.")
        ),
        .claudeSonnet46: ProviderModelMetadata(
            availableProviders: [.claude],
            displayName: "Claude Sonnet 4.6",
            shortLabel: "Sonnet 4.6",
            subtitle: .fixed("Balanced Claude model for most coding tasks.")
        ),
        .claudeOpus46: ProviderModelMetadata(
            availableProviders: [.claude],
            displayName: "Claude Opus 4.6",
            shortLabel: "Opus 4.6",
            subtitle: .fixed("Most capable Claude model for harder tasks.")
        ),
        .claudeHaiku45: ProviderModelMetadata(
            availableProviders: [.claude],
            displayName: "Claude Haiku 4.5",
            shortLabel: "Haiku 4.5",
            subtitle: .fixed("Fast Claude model for lighter requests.")
        ),
        .copilotClaudeSonnet45: ProviderModelMetadata(
            availableProviders: [.copilot],
            displayName: "Claude Sonnet 4.5",
            shortLabel: "Sonnet 4.5",
            subtitle: .fixed("Balanced Copilot coding-agent model.")
        ),
        .copilotClaudeOpus45: ProviderModelMetadata(
            availableProviders: [.copilot],
            displayName: "Claude Opus 4.5",
            shortLabel: "Opus 4.5",
            subtitle: .fixed("Stronger Anthropic model available in Copilot.")
        ),
        .copilotClaudeOpus46: ProviderModelMetadata(
            availableProviders: [.copilot],
            displayName: "Claude Opus 4.6",
            shortLabel: "Opus 4.6",
            subtitle: .fixed("Most capable Anthropic option currently listed for Copilot.")
        ),
        .copilotGPT51CodexMax: ProviderModelMetadata(
            availableProviders: [.copilot],
            displayName: "GPT-5.1 Codex Max",
            shortLabel: "5.1 Max",
            subtitle: .fixed("OpenAI Codex model for deeper coding tasks.")
        ),
        .copilotGPT52Codex: ProviderModelMetadata(
            availableProviders: [.copilot],
            displayName: "GPT-5.2 Codex",
            shortLabel: "5.2 Codex",
            subtitle: .fixed("Newer Codex option available through Copilot.")
        ),
    ]
}
