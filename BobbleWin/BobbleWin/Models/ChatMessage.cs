using System.Text.Json.Serialization;

namespace BobbleWin.Models;

public enum ChatMessageRole
{
    User,
    Assistant,
    System,
    Error,
}

public enum ChatMessageKind
{
    Regular,
    Permission,
    Question,
    AgentThought,
    ToolUse,
}

public enum InterruptionActionRole
{
    Primary,
    Secondary,
    Destructive,
}

public sealed class InterruptionAction
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Title { get; set; } = string.Empty;
    public InterruptionActionRole Role { get; set; } = InterruptionActionRole.Primary;
    public string? Payload { get; set; }
}

public enum ChatAttachmentKind
{
    File,
    Image,
}

public sealed class ChatAttachment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ChatAttachmentKind Kind { get; set; }
    public string FileName { get; set; } = string.Empty;
    public string FilePath { get; set; } = string.Empty;
    public string RelativePath { get; set; } = string.Empty;

    [JsonIgnore]
    public bool IsImage => Kind == ChatAttachmentKind.Image;

    [JsonIgnore]
    public bool IsTextPreviewable
    {
        get
        {
            var extension = Path.GetExtension(FileName).TrimStart('.').ToLowerInvariant();
            return extension is "txt" or "md" or "markdown" or "json" or "jsonl" or "yaml" or "yml" or "xml"
                or "swift" or "m" or "mm" or "h" or "c" or "cc" or "cpp" or "js" or "ts" or "tsx" or "jsx"
                or "html" or "css" or "scss" or "sql" or "sh" or "zsh" or "py" or "rb" or "go" or "rs";
        }
    }

    [JsonIgnore]
    public string PreviewBadgeLabel
    {
        get
        {
            var extension = Path.GetExtension(FileName).TrimStart('.');
            return string.IsNullOrWhiteSpace(extension) ? "FILE" : extension.ToUpperInvariant();
        }
    }
}

public sealed class ChatMessage
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ChatMessageRole Role { get; set; }
    public string Content { get; set; } = string.Empty;
    public List<ChatAttachment> Attachments { get; set; } = [];
    public string? InterruptionTitle { get; set; }
    public string? InterruptionDetails { get; set; }
    public List<InterruptionAction> InterruptionActions { get; set; } = [];
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.Now;
    public bool IsStreaming { get; set; }
    public bool IsNew { get; set; }
    public ChatMessageKind Kind { get; set; } = ChatMessageKind.Regular;

    [JsonIgnore]
    public bool IsInterruptionCard => Kind is ChatMessageKind.Permission or ChatMessageKind.Question;

    [JsonIgnore]
    public bool IsVisibleInPrimaryTimeline
    {
        get
        {
            return Role switch
            {
                ChatMessageRole.User => true,
                ChatMessageRole.Assistant => true,
                ChatMessageRole.Error => true,
                ChatMessageRole.System => Kind == ChatMessageKind.AgentThought || IsInterruptionCard,
                _ => true,
            };
        }
    }

    [JsonIgnore]
    public string? InterruptionCardTitle => InterruptionTitle ?? DefaultInterruptionCardTitle;

    [JsonIgnore]
    public string InterruptionCardBody => InterruptionDetails ?? Content;

    private string? DefaultInterruptionCardTitle => Kind switch
    {
        ChatMessageKind.Permission => "Permission required",
        ChatMessageKind.Question => "Question",
        _ => null,
    };

    public static ChatMessage Make(ChatMessageRole role, string content, List<ChatAttachment>? attachments = null, ChatMessageKind kind = ChatMessageKind.Regular)
    {
        return new ChatMessage
        {
            Id = Guid.NewGuid(),
            Role = role,
            Content = content,
            Attachments = attachments ?? [],
            Timestamp = DateTimeOffset.Now,
            IsStreaming = false,
            IsNew = role == ChatMessageRole.Assistant,
            Kind = kind,
        };
    }
}
