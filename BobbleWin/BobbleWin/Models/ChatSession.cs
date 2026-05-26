using System.Text.Json.Serialization;

namespace BobbleWin.Models;

public enum ConversationExecutionMode
{
    Ask,
    Bypass,
}

public static class ConversationExecutionModeExtensions
{
    public static string DisplayName(this ConversationExecutionMode mode) => mode switch
    {
        ConversationExecutionMode.Ask => "Ask",
        ConversationExecutionMode.Bypass => "Bypass",
        _ => "Ask",
    };

    public static string HelpText(this ConversationExecutionMode mode) => mode switch
    {
        ConversationExecutionMode.Ask => "Ask before actions that need permission.",
        ConversationExecutionMode.Bypass => "Bypass approvals for this conversation.",
        _ => string.Empty,
    };

    public static ConversationExecutionMode DefaultMode(CLIBackend backend) => backend switch
    {
        CLIBackend.Codex => ConversationExecutionMode.Bypass,
        CLIBackend.Copilot => ConversationExecutionMode.Ask,
        CLIBackend.Claude => ConversationExecutionMode.Ask,
        _ => ConversationExecutionMode.Ask,
    };
}

public enum SessionStateKind
{
    Idle,
    Running,
    Error,
}

public sealed class SessionState
{
    public SessionStateKind Kind { get; set; } = SessionStateKind.Idle;
    public string? Message { get; set; }

    public static SessionState Idle() => new() { Kind = SessionStateKind.Idle };
    public static SessionState Running() => new() { Kind = SessionStateKind.Running };
    public static SessionState Error(string message) => new() { Kind = SessionStateKind.Error, Message = message };
}

public sealed class ChatSession
{
    public const string DefaultChatHeadSymbol = "Bobble1";
    public static readonly IReadOnlyList<string> AvailableChatHeadImageNames =
        Enumerable.Range(1, 9).Select(value => $"Bobble{value}").ToList();

    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "New Chat";
    public string ChatHeadSymbol { get; set; } = DefaultChatHeadSymbol;
    public bool HasAssignedChatHeadSymbol { get; set; }
    public CLIBackend Provider { get; set; } = CLIBackend.Codex;
    public ConversationExecutionMode ConversationMode { get; set; } = ConversationExecutionMode.Bypass;
    public ProviderModelOption SelectedModel { get; set; } = ProviderModelOption.Automatic;
    public List<ChatMessage> Messages { get; set; } = [];
    public SessionState State { get; set; } = SessionState.Idle();
    public string CliSessionId { get; set; } = Guid.NewGuid().ToString();
    public CLIBackend? CliSessionBackend { get; set; }
    public string WorkspaceDirectory { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.Now;
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.Now;
    public bool IsArchived { get; set; }

    [JsonIgnore]
    public string ChatHeadImageName
    {
        get
        {
            if (HasAssignedChatHeadSymbol)
            {
                var sanitized = SanitizedChatHeadImageName(ChatHeadSymbol);
                if (!string.IsNullOrWhiteSpace(sanitized))
                {
                    return sanitized;
                }
            }

            var index = Math.Abs(Id.GetHashCode()) % AvailableChatHeadImageNames.Count;
            return AvailableChatHeadImageNames[index];
        }
    }

    [JsonIgnore]
    public bool HasUnread => Messages.Any(message => message.Role == ChatMessageRole.Assistant && message.IsNew);

    [JsonIgnore]
    public bool QualifiesForHistory => Messages.Any(message => message.Role == ChatMessageRole.User);

    public string AttachmentsDirectory()
    {
        var path = Path.Combine(WorkspaceDirectory, "attachments");
        Directory.CreateDirectory(path);
        return path;
    }

    public static ChatSession Create(CLIBackend provider, string? workspaceDirectory = null)
    {
        var sessionId = Guid.NewGuid();
        return new ChatSession
        {
            Id = sessionId,
            Name = "New Chat",
            ChatHeadSymbol = DefaultChatHeadSymbol,
            HasAssignedChatHeadSymbol = false,
            Provider = provider,
            ConversationMode = ConversationExecutionModeExtensions.DefaultMode(provider),
            SelectedModel = ProviderModelOption.Automatic,
            Messages = [],
            State = SessionState.Idle(),
            CliSessionId = Guid.NewGuid().ToString(),
            CliSessionBackend = null,
            WorkspaceDirectory = workspaceDirectory ?? CreateWorkspaceDirectory(sessionId),
            CreatedAt = DateTimeOffset.Now,
            UpdatedAt = DateTimeOffset.Now,
            IsArchived = false,
        };
    }

    public void EnsureDefaults()
    {
        if (string.IsNullOrWhiteSpace(WorkspaceDirectory))
        {
            WorkspaceDirectory = CreateWorkspaceDirectory(Id);
        }

        ConversationMode = ConversationMode;
        SelectedModel = SelectedModel.Normalized(Provider);
    }

    public void MarkAssistantMessagesRead()
    {
        foreach (var message in Messages.Where(message => message.Role == ChatMessageRole.Assistant && message.IsNew))
        {
            message.IsNew = false;
        }

        TouchUpdatedAt();
    }

    public void UpdateChatHeadSymbol(string? rawValue)
    {
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            return;
        }

        var mapped = MappedChatHeadImageName(rawValue);
        if (string.IsNullOrWhiteSpace(mapped))
        {
            return;
        }

        ChatHeadSymbol = mapped;
        HasAssignedChatHeadSymbol = true;
        TouchUpdatedAt();
    }

    public void TouchUpdatedAt()
    {
        UpdatedAt = DateTimeOffset.Now;
    }

    public ChatSession NormalizedForRestore()
    {
        var copy = Clone();
        if (copy.State.Kind == SessionStateKind.Running)
        {
            copy.State = SessionState.Idle();
        }

        foreach (var message in copy.Messages)
        {
            message.IsStreaming = false;
            if (message.InterruptionActions.Count > 0)
            {
                message.InterruptionActions = [];
            }
        }

        return copy;
    }

    public ChatSession Clone()
    {
        return new ChatSession
        {
            Id = Id,
            Name = Name,
            ChatHeadSymbol = ChatHeadSymbol,
            HasAssignedChatHeadSymbol = HasAssignedChatHeadSymbol,
            Provider = Provider,
            ConversationMode = ConversationMode,
            SelectedModel = SelectedModel,
            Messages = Messages.Select(CloneMessage).ToList(),
            State = new SessionState { Kind = State.Kind, Message = State.Message },
            CliSessionId = CliSessionId,
            CliSessionBackend = CliSessionBackend,
            WorkspaceDirectory = WorkspaceDirectory,
            CreatedAt = CreatedAt,
            UpdatedAt = UpdatedAt,
            IsArchived = IsArchived,
        };
    }

    private static ChatMessage CloneMessage(ChatMessage message)
    {
        return new ChatMessage
        {
            Id = message.Id,
            Role = message.Role,
            Content = message.Content,
            Attachments = message.Attachments.Select(attachment => new ChatAttachment
            {
                Id = attachment.Id,
                Kind = attachment.Kind,
                FileName = attachment.FileName,
                FilePath = attachment.FilePath,
                RelativePath = attachment.RelativePath,
            }).ToList(),
            InterruptionTitle = message.InterruptionTitle,
            InterruptionDetails = message.InterruptionDetails,
            InterruptionActions = message.InterruptionActions.Select(action => new InterruptionAction
            {
                Id = action.Id,
                Title = action.Title,
                Role = action.Role,
                Payload = action.Payload,
            }).ToList(),
            Timestamp = message.Timestamp,
            IsStreaming = message.IsStreaming,
            IsNew = message.IsNew,
            Kind = message.Kind,
        };
    }

    public static string? SanitizedChatHeadImageName(string rawValue)
    {
        var trimmed = rawValue.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        var lower = trimmed.ToLowerInvariant();
        if (!lower.StartsWith("bobble", StringComparison.Ordinal))
        {
            return null;
        }

        var suffix = lower["bobble".Length..];
        if (!int.TryParse(suffix, out var number))
        {
            return null;
        }

        if (number < 1 || number > AvailableChatHeadImageNames.Count)
        {
            return null;
        }

        return $"Bobble{number}";
    }

    public static string? MappedChatHeadImageName(string rawValue)
    {
        var sanitized = SanitizedChatHeadImageName(rawValue);
        if (!string.IsNullOrWhiteSpace(sanitized))
        {
            return sanitized;
        }

        var trimmed = rawValue.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        var index = Math.Abs(trimmed.GetHashCode()) % AvailableChatHeadImageNames.Count;
        return AvailableChatHeadImageNames[index];
    }

    private static string CreateWorkspaceDirectory(Guid sessionId)
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var preferred = Path.Combine(appData, "BobbleWin", "ChatWorkspaces", sessionId.ToString());
        try
        {
            Directory.CreateDirectory(preferred);
            return preferred;
        }
        catch
        {
            var fallback = Path.Combine(Path.GetTempPath(), "BobbleWinChatWorkspaces", sessionId.ToString());
            Directory.CreateDirectory(fallback);
            return fallback;
        }
    }
}
