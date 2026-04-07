using BobbleWin.Models;

namespace BobbleWin.Process;

public sealed class ConversationTurnRequest
{
    public required CLIBackend Backend { get; init; }
    public required string Prompt { get; init; }
    public required List<string> ImagePaths { get; init; }
    public required string SessionId { get; init; }
    public required bool IsResume { get; init; }
    public required string WorkingDirectory { get; init; }
    public string? Model { get; init; }
    public required ConversationExecutionMode ExecutionMode { get; init; }
}

public enum ConversationInterruptionKind
{
    Permission,
    Question,
}

public enum ConversationInterruptionResponseMode
{
    Informational,
    ActionButtons,
    TextReply,
}

public enum ConversationInterruptionActionRole
{
    Primary,
    Secondary,
    Destructive,
}

public sealed class ConversationInterruptionAction
{
    public required string Id { get; init; }
    public required string Label { get; init; }
    public required ConversationInterruptionActionRole Role { get; init; }
    public string? TransportValue { get; init; }
}

public sealed class ConversationInterruption
{
    public required string Id { get; init; }
    public required ConversationInterruptionKind Kind { get; init; }
    public required CLIBackend Provider { get; init; }
    public required string Title { get; init; }
    public required string Details { get; init; }
    public required List<ConversationInterruptionAction> Actions { get; init; }
    public required ConversationInterruptionResponseMode ResponseMode { get; init; }
}

public interface IConversationTransport
{
    bool PersistsAcrossTurns { get; }

    event Action<string>? OnTextChunk;
    event Action<string>? OnResult;
    event Action<string>? OnEventText;
    event Action<ConversationInterruption>? OnInterruption;
    event Action? OnComplete;
    event Action<string>? OnError;
    event Action<string>? OnSessionId;
    event Action? OnAssistantMessageStarted;
    event Action? OnTurnCompleted;

    void SendTurn(ConversationTurnRequest request);
    void Stop();
    void ResolveInterruption(string id, string? actionTransportValue, string? textResponse);
}

public sealed class CLIConversationTransport : IConversationTransport
{
    private CLIProcessManager? _processManager;
    private bool _didStopForBlockingInterruption;

    public bool PersistsAcrossTurns => false;

    public event Action<string>? OnTextChunk;
    public event Action<string>? OnResult;
    public event Action<string>? OnEventText;
    public event Action<ConversationInterruption>? OnInterruption;
    public event Action? OnComplete;
    public event Action<string>? OnError;
    public event Action<string>? OnSessionId;
    public event Action? OnAssistantMessageStarted;
    public event Action? OnTurnCompleted;

    public void SendTurn(ConversationTurnRequest request)
    {
        Stop();
        _didStopForBlockingInterruption = false;

        var executablePath = request.Backend.ResolvedPath();
        if (string.IsNullOrWhiteSpace(executablePath))
        {
            OnError?.Invoke(request.Backend.MissingCliMessage());
            return;
        }

        _processManager = new CLIProcessManager(
            backend: request.Backend,
            executablePath: executablePath,
            model: request.Model,
            prompt: request.Prompt,
            imagePaths: request.ImagePaths,
            sessionId: request.SessionId,
            isResume: request.IsResume,
            workingDirectory: request.WorkingDirectory,
            launchPurpose: new CLIProcessLaunchPurpose.Conversation(request.ExecutionMode));

        _processManager.OnTextChunk += text => OnTextChunk?.Invoke(text);
        _processManager.OnResult += text => OnResult?.Invoke(text);
        _processManager.OnEventText += text =>
        {
            var trimmed = text.Trim();
            if (trimmed.Length == 0)
            {
                return;
            }

            if (request.ExecutionMode == ConversationExecutionMode.Ask)
            {
                var interruption = MakeBlockingInterruption(request.Backend, trimmed);
                if (interruption is not null)
                {
                    _didStopForBlockingInterruption = true;
                    OnInterruption?.Invoke(interruption);
                    Stop();
                    return;
                }
            }

            OnEventText?.Invoke(trimmed);
        };
        _processManager.OnComplete += () =>
        {
            _processManager = null;
            OnComplete?.Invoke();
        };
        _processManager.OnSessionId += id => OnSessionId?.Invoke(id);
        _processManager.OnAssistantMessageStarted += () => OnAssistantMessageStarted?.Invoke();
        _processManager.OnTurnCompleted += () => OnTurnCompleted?.Invoke();
        _processManager.OnError += error =>
        {
            if (_didStopForBlockingInterruption)
            {
                _didStopForBlockingInterruption = false;
                return;
            }

            _processManager = null;
            OnError?.Invoke(error);
        };

        _processManager.Start();
    }

    public void Stop()
    {
        _processManager?.Stop();
        _processManager = null;
    }

    public void ResolveInterruption(string id, string? actionTransportValue, string? textResponse)
    {
        // One-shot CLI transport interruption cards are informational only.
    }

    private static ConversationInterruption? MakeBlockingInterruption(CLIBackend backend, string text)
    {
        var normalized = text.ToLowerInvariant();
        var isPermissionLike = normalized.Contains("approval", StringComparison.Ordinal)
            || normalized.Contains("permission", StringComparison.Ordinal)
            || normalized.Contains("request user input", StringComparison.Ordinal)
            || normalized.Contains("user input", StringComparison.Ordinal)
            || normalized.Contains("question", StringComparison.Ordinal);

        if (!isPermissionLike)
        {
            return null;
        }

        var title = backend switch
        {
            CLIBackend.Codex => "Codex needs approval",
            CLIBackend.Claude => "Claude needs input",
            CLIBackend.Copilot => "Copilot needs input",
            _ => "Approval required",
        };

        return new ConversationInterruption
        {
            Id = Guid.NewGuid().ToString(),
            Kind = normalized.Contains("question", StringComparison.Ordinal)
                ? ConversationInterruptionKind.Question
                : ConversationInterruptionKind.Permission,
            Provider = backend,
            Title = title,
            Details = text,
            Actions = [],
            ResponseMode = ConversationInterruptionResponseMode.Informational,
        };
    }
}
