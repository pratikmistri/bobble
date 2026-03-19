import Foundation

class CLIProcessManager {
    private var process: Process?
    private let backend: CLIBackend
    private let executablePath: String
    private let prompt: String
    private let sessionId: String
    private let isResume: Bool
    private let workingDirectory: String
    private let parser: StreamParser

    var onTextChunk: ((String) -> Void)?
    var onEventText: ((String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSessionId: ((String) -> Void)?

    init(
        backend: CLIBackend,
        executablePath: String,
        prompt: String,
        sessionId: String,
        isResume: Bool,
        workingDirectory: String
    ) {
        self.backend = backend
        self.executablePath = executablePath
        self.prompt = prompt
        self.sessionId = sessionId
        self.isResume = isResume
        self.workingDirectory = workingDirectory
        self.parser = StreamParser(backend: backend)
    }

    func start() {
        let process = Process()
        self.process = process

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: workingDirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
        } catch {
            onError?("Failed to create workspace directory: \(error.localizedDescription)")
            return
        }

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)

        let args = makeArguments()
        process.arguments = args

        // Inherit user's PATH so installed CLIs can find their dependencies.
        var env = ProcessInfo.processInfo.environment
        if let path = env["PATH"] {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:\(path)"
        } else {
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        }
        process.environment = env

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        parser.onTextDelta = { [weak self] text in
            self?.onTextChunk?(text)
        }

        parser.onResult = { [weak self] text in
            self?.onTextChunk?(text)
        }

        parser.onEventText = { [weak self] text in
            self?.onEventText?(text)
        }

        parser.onSessionId = { [weak self] id in
            self?.onSessionId?(id)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                return
            }
            self?.parser.feed(data)
        }

        process.terminationHandler = { [weak self] proc in
            // Give a moment for final data to flush
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus != 0 {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrText = String(data: stderrData, encoding: .utf8) ?? "Unknown error"
                    if !stderrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self?.onError?(stderrText)
                        return
                    }
                }
                self?.onComplete?()
            }
        }

        do {
            try process.run()
        } catch {
            onError?("Failed to launch CLI: \(error.localizedDescription)")
        }
    }

    func stop() {
        if let process = process, process.isRunning {
            process.terminate()
        }
        process = nil
    }

    private func makeArguments() -> [String] {
        switch backend {
        case .claude:
            var args = [
                "-p", prompt,
                "--output-format", "stream-json",
                "--verbose"
            ]
            if isResume {
                args += ["--resume", sessionId]
            } else {
                args += ["--session-id", sessionId]
            }
            return args

        case .codex:
            if isResume {
                return [
                    "exec",
                    "resume",
                    "--json",
                    "--skip-git-repo-check",
                    "--full-auto",
                    sessionId,
                    prompt
                ]
            }

            return [
                "exec",
                "--json",
                "--skip-git-repo-check",
                "--full-auto",
                "--cd",
                workingDirectory,
                prompt
            ]
        }
    }
}
