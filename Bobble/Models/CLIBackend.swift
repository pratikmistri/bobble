import Foundation

enum CLIBackend: String, CaseIterable {
    case codex
    case claude

    var command: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        }
    }

    static func detect() -> CLIBackend? {
        return CLIBackend.codex.resolvedPath() == nil ? nil : .codex
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
