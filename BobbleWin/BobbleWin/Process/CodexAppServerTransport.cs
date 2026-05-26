using BobbleWin.Models;

namespace BobbleWin.Process;

// Windows fallback transport: keeps the same surface as macOS app-server transport,
// but routes through CLIProcessManager until codex app-server parity is implemented.
public sealed class CodexAppServerTransport : IConversationTransport
{
    private readonly CLIConversationTransport _inner = new();
    private string? _threadId;

    public CodexAppServerTransport(string executablePath, string workingDirectory, ConversationExecutionMode executionMode)
    {
        _inner.OnSessionId += id =>
        {
            _threadId = id;
            OnSessionId?.Invoke(id);
        };
        _inner.OnTextChunk += text => OnTextChunk?.Invoke(text);
        _inner.OnResult += text => OnResult?.Invoke(text);
        _inner.OnEventText += text => OnEventText?.Invoke(text);
        _inner.OnInterruption += interruption => OnInterruption?.Invoke(interruption);
        _inner.OnComplete += () => OnComplete?.Invoke();
        _inner.OnError += error => OnError?.Invoke(error);
        _inner.OnAssistantMessageStarted += () => OnAssistantMessageStarted?.Invoke();
        _inner.OnTurnCompleted += () => OnTurnCompleted?.Invoke();
    }

    public bool PersistsAcrossTurns => true;

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
        var adjusted = new ConversationTurnRequest
        {
            Backend = CLIBackend.Codex,
            Prompt = request.Prompt,
            ImagePaths = request.ImagePaths,
            SessionId = _threadId ?? request.SessionId,
            IsResume = !string.IsNullOrWhiteSpace(_threadId) || request.IsResume,
            WorkingDirectory = request.WorkingDirectory,
            Model = request.Model,
            ExecutionMode = request.ExecutionMode,
        };
        _inner.SendTurn(adjusted);
    }

    public void Stop()
    {
        _inner.Stop();
    }

    public void ResolveInterruption(string id, string? actionTransportValue, string? textResponse)
    {
        _inner.ResolveInterruption(id, actionTransportValue, textResponse);
    }
}
