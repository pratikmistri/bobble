import Foundation

class CLIProcessManager {
    private var process: Process?
    private let backend: CLIBackend
    private let executablePath: String
    private let model: String?
    private let prompt: String
    private let imagePaths: [String]
    private let sessionId: String
    private let isResume: Bool
    private let workingDirectory: String
    private let parser: StreamParser
    private let usesStdinPrompt: Bool

    var onTextChunk: ((String) -> Void)?
    var onResult: ((String) -> Void)?
    var onEventText: ((String) -> Void)?
    var onComplete: (() -> Void)?
    var onError: ((String) -> Void)?
    var onSessionId: ((String) -> Void)?
    var onAssistantMessageStarted: (() -> Void)?
    var onTurnCompleted: (() -> Void)?

    init(
        backend: CLIBackend,
        executablePath: String,
        model: String?,
        prompt: String,
        imagePaths: [String],
        sessionId: String,
        isResume: Bool,
        workingDirectory: String
    ) {
        self.backend = backend
        self.executablePath = executablePath
        self.model = model
        self.prompt = prompt
        self.imagePaths = imagePaths
        self.sessionId = sessionId
        self.isResume = isResume
        self.workingDirectory = workingDirectory
        self.parser = StreamParser(backend: backend)
        self.usesStdinPrompt = backend == .codex
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
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if usesStdinPrompt {
            process.standardInput = stdinPipe
        }

        parser.onTextDelta = { [weak self] text in
            self?.onTextChunk?(text)
        }

        parser.onResult = { [weak self] text in
            self?.onResult?(text)
        }

        parser.onEventText = { [weak self] text in
            self?.onEventText?(text)
        }

        parser.onSessionId = { [weak self] id in
            self?.onSessionId?(id)
        }

        parser.onAssistantMessageStarted = { [weak self] in
            self?.onAssistantMessageStarted?()
        }

        parser.onTurnCompleted = { [weak self] in
            self?.onTurnCompleted?()
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
            if usesStdinPrompt {
                writePromptToStdin(using: stdinPipe)
            }
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
        let imageArguments = imagePaths.flatMap { ["--image", $0] }
        let modelArguments = model.map { ["--model", $0] } ?? []

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
                ] + modelArguments + [
                    "--json",
                    "--skip-git-repo-check",
                    "--dangerously-bypass-approvals-and-sandbox",
                ] + imageArguments + [
                    sessionId,
                    "-"
                ]
            }

            return [
                "exec",
            ] + modelArguments + [
                "--json",
                "--skip-git-repo-check",
                "--dangerously-bypass-approvals-and-sandbox",
                "--cd",
                workingDirectory,
            ] + imageArguments + [
                "-"
            ]
        }
    }

    private func writePromptToStdin(using pipe: Pipe) {
        let data = Data(prompt.utf8)
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.closeFile()
    }
}
