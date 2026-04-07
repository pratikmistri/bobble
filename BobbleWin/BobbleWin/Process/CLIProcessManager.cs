using System.Diagnostics;
using System.Runtime.InteropServices;
using BobbleWin.Models;

namespace BobbleWin.Process;

public abstract record CLIProcessLaunchPurpose
{
    public sealed record Conversation(ConversationExecutionMode Mode) : CLIProcessLaunchPurpose;
    public sealed record HelperAutonomous : CLIProcessLaunchPurpose;
}

public sealed class CLIProcessManager
{
    private readonly CLIBackend _backend;
    private readonly string _executablePath;
    private readonly string? _model;
    private readonly string _prompt;
    private readonly List<string> _imagePaths;
    private readonly string _sessionId;
    private readonly bool _isResume;
    private readonly string _workingDirectory;
    private readonly StreamParser _parser;
    private readonly bool _usesStdinPrompt;
    private readonly CLIProcessLaunchPurpose _launchPurpose;

    private Process? _process;

    public event Action<string>? OnTextChunk;
    public event Action<string>? OnResult;
    public event Action<string>? OnEventText;
    public event Action? OnComplete;
    public event Action<string>? OnError;
    public event Action<string>? OnSessionId;
    public event Action? OnAssistantMessageStarted;
    public event Action? OnTurnCompleted;

    public CLIProcessManager(
        CLIBackend backend,
        string executablePath,
        string? model,
        string prompt,
        List<string> imagePaths,
        string sessionId,
        bool isResume,
        string workingDirectory,
        CLIProcessLaunchPurpose launchPurpose)
    {
        _backend = backend;
        _executablePath = executablePath;
        _model = model;
        _prompt = prompt;
        _imagePaths = imagePaths;
        _sessionId = sessionId;
        _isResume = isResume;
        _workingDirectory = workingDirectory;
        _parser = new StreamParser(backend);
        _usesStdinPrompt = backend == CLIBackend.Codex;
        _launchPurpose = launchPurpose;

        _parser.OnTextDelta += text => OnTextChunk?.Invoke(text);
        _parser.OnResult += text => OnResult?.Invoke(text);
        _parser.OnEventText += text => OnEventText?.Invoke(text);
        _parser.OnSessionId += id => OnSessionId?.Invoke(id);
        _parser.OnAssistantMessageStarted += () => OnAssistantMessageStarted?.Invoke();
        _parser.OnTurnCompleted += () => OnTurnCompleted?.Invoke();
    }

    public void Start()
    {
        try
        {
            Directory.CreateDirectory(_workingDirectory);
        }
        catch (Exception exception)
        {
            OnError?.Invoke($"Failed to create workspace directory: {exception.Message}");
            return;
        }

        var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = _executablePath,
                Arguments = string.Join(" ", MakeArguments().Select(EscapeArgument)),
                WorkingDirectory = _workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                RedirectStandardInput = _usesStdinPrompt,
                UseShellExecute = false,
                CreateNoWindow = true,
            },
            EnableRaisingEvents = true,
        };

        foreach (var kvp in BuildEnvironment())
        {
            process.StartInfo.Environment[kvp.Key] = kvp.Value;
        }

        process.OutputDataReceived += (_, eventArgs) =>
        {
            if (eventArgs.Data is null)
            {
                return;
            }

            _parser.Feed(eventArgs.Data + "\n");
        };

        process.Exited += (_, _) =>
        {
            Task.Run(async () =>
            {
                await Task.Delay(100).ConfigureAwait(false);
                _parser.Finish();

                if (process.ExitCode != 0)
                {
                    var stderr = process.StandardError.ReadToEnd();
                    if (!string.IsNullOrWhiteSpace(stderr))
                    {
                        OnError?.Invoke(stderr);
                        return;
                    }
                }

                OnComplete?.Invoke();
            });
        };

        try
        {
            process.Start();
            _process = process;
            process.BeginOutputReadLine();

            if (_usesStdinPrompt)
            {
                process.StandardInput.Write(_prompt);
                process.StandardInput.Close();
            }
        }
        catch (Exception exception)
        {
            OnError?.Invoke($"Failed to launch CLI: {exception.Message}");
        }
    }

    public void Stop()
    {
        try
        {
            if (_process is { HasExited: false })
            {
                _process.Kill(entireProcessTree: true);
            }
        }
        catch
        {
            // no-op
        }
        finally
        {
            _process = null;
        }
    }

    private List<string> MakeArguments()
    {
        var modelArguments = _model is null ? [] : new List<string> { "--model", _model };
        var imageArguments = _imagePaths.SelectMany(path => new[] { "--image", path }).ToList();

        var executionMode = _launchPurpose switch
        {
            CLIProcessLaunchPurpose.Conversation conversation => conversation.Mode,
            CLIProcessLaunchPurpose.HelperAutonomous => ConversationExecutionMode.Bypass,
            _ => ConversationExecutionMode.Bypass,
        };

        return _backend switch
        {
            CLIBackend.Claude => BuildClaudeArguments(executionMode),
            CLIBackend.Copilot => BuildCopilotArguments(executionMode, modelArguments),
            CLIBackend.Codex => BuildCodexArguments(executionMode, modelArguments, imageArguments),
            _ => [],
        };
    }

    private List<string> BuildClaudeArguments(ConversationExecutionMode executionMode)
    {
        var args = new List<string>
        {
            "-p", _prompt,
            "--output-format", "stream-json",
            "--verbose",
        };

        if (executionMode == ConversationExecutionMode.Ask && _launchPurpose is CLIProcessLaunchPurpose.Conversation)
        {
            args.AddRange(["--permission-mode", "default", "--brief"]);
        }
        else
        {
            args.AddRange(["--permission-mode", "bypassPermissions"]);
        }

        if (_isResume)
        {
            args.AddRange(["--resume", _sessionId]);
        }
        else
        {
            args.AddRange(["--session-id", _sessionId]);
        }

        return args;
    }

    private List<string> BuildCopilotArguments(ConversationExecutionMode executionMode, List<string> modelArguments)
    {
        var args = new List<string>
        {
            "--prompt", _prompt,
            "--silent",
        };

        if (executionMode == ConversationExecutionMode.Bypass)
        {
            args.AddRange(["--no-ask-user", "--allow-all"]);
        }

        args.AddRange(modelArguments);
        return args;
    }

    private List<string> BuildCodexArguments(ConversationExecutionMode executionMode, List<string> modelArguments, List<string> imageArguments)
    {
        var approvalArguments = executionMode == ConversationExecutionMode.Ask
            ? new List<string>
            {
                "-c", "approval_policy=\"untrusted\"",
                "--sandbox", "danger-full-access",
            }
            : new List<string> { "--dangerously-bypass-approvals-and-sandbox" };

        if (_isResume)
        {
            var args = new List<string> { "exec", "resume" };
            args.AddRange(modelArguments);
            args.AddRange(["--json", "--skip-git-repo-check"]);
            args.AddRange(approvalArguments);
            args.AddRange(imageArguments);
            args.AddRange([_sessionId, "-"]);
            return args;
        }

        var fresh = new List<string> { "exec" };
        fresh.AddRange(modelArguments);
        fresh.AddRange(["--json", "--skip-git-repo-check", "--cd", _workingDirectory]);
        fresh.AddRange(approvalArguments);
        fresh.AddRange(imageArguments);
        fresh.Add("-");
        return fresh;
    }

    private Dictionary<string, string> BuildEnvironment()
    {
        var env = Environment.GetEnvironmentVariables()
            .Cast<System.Collections.DictionaryEntry>()
            .ToDictionary(entry => entry.Key!.ToString()!, entry => entry.Value?.ToString() ?? string.Empty);

        env.TryGetValue("PATH", out var existingPath);
        var prefix = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? string.Join(Path.PathSeparator, [
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "AppData", "Roaming", "npm"),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin"),
            ])
            : "/usr/local/bin:/opt/homebrew/bin";

        env["PATH"] = string.IsNullOrWhiteSpace(existingPath)
            ? prefix
            : $"{prefix}{Path.PathSeparator}{existingPath}";

        return env;
    }

    private static string EscapeArgument(string value)
    {
        if (value.Length == 0)
        {
            return "\"\"";
        }

        if (!value.Any(character => char.IsWhiteSpace(character) || character is '"' or '\\'))
        {
            return value;
        }

        return "\"" + value.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
