using System.Collections.ObjectModel;
using System.Drawing;
using System.Drawing.Imaging;
using System.Text;
using System.Text.RegularExpressions;
using BobbleWin.Models;
using BobbleWin.Process;
using BobbleWin.Utilities;

namespace BobbleWin.ViewModels;

public sealed class ChatSessionViewModel : ObservableObject
{
    public static readonly IReadOnlyList<string> SupportedDropTypeExtensions =
    [
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".webp", ".txt", ".md", ".json", ".cs", ".swift", ".ts", ".tsx", ".js",
    ];

    private static readonly Regex MarkdownLinkRegex = new(@"!?\[[^\]]*\]\((.+?)\)", RegexOptions.Compiled);
    private static readonly Regex LineSuffixRegex = new(@":\d+(?::\d+)?$", RegexOptions.Compiled);

    private readonly object _sync = new();

    private ChatSession _session;
    private string _inputText = string.Empty;
    private bool _isCapturingScreenshot;

    private IConversationTransport? _conversationTransport;
    private CLIBackend? _conversationTransportBackend;
    private IConversationTransport? _callbackTransport;
    private bool _shouldRecycleCopilotTransportAfterTurn;
    private bool _shouldResetTransportAfterTurn;
    private string? _pendingTextReplyInterruptionId;

    public ChatSession Session
    {
        get => _session;
        private set => SetProperty(ref _session, value);
    }

    public string InputText
    {
        get => _inputText;
        set => SetProperty(ref _inputText, value);
    }

    public ObservableCollection<ChatAttachment> PendingAttachments { get; } = [];

    public IReadOnlyList<ChatMessage> VisibleMessages
        => Session.Messages.Where(message => message.IsVisibleInPrimaryTimeline).ToList();

    public bool IsCapturingScreenshot
    {
        get => _isCapturingScreenshot;
        private set => SetProperty(ref _isCapturingScreenshot, value);
    }

    public event Action<ChatSession>? OnSessionUpdated;

    public ChatSessionViewModel(ChatSession session)
    {
        Session = session;
        HydrateDerivedAssistantAttachments();
    }

    public void Send()
    {
        lock (_sync)
        {
            var prompt = InputText.Trim();
            var attachments = PendingAttachments.ToList();
            if (prompt.Length == 0 && attachments.Count == 0)
            {
                return;
            }

            InputText = string.Empty;
            PendingAttachments.Clear();

            if (Session.Messages.Count == 0)
            {
                var seed = prompt.Length == 0 ? (attachments.FirstOrDefault()?.FileName ?? "New Chat") : prompt;
                Session.Name = seed.Length > 30 ? seed[..30] : seed;
            }

            var userMessage = ChatMessage.Make(ChatMessageRole.User, prompt, attachments);
            Session.Messages.Add(userMessage);
            NotifyUpdate();

            if (!string.IsNullOrWhiteSpace(_pendingTextReplyInterruptionId) && _conversationTransport is not null)
            {
                Session.State = SessionState.Running();
                var interruptionId = _pendingTextReplyInterruptionId;
                _pendingTextReplyInterruptionId = null;
                _conversationTransport.ResolveInterruption(interruptionId!, null, BuildPrompt(prompt, attachments));
                NotifyUpdate();
                return;
            }

            var backend = Session.Provider;
            var resolvedPath = backend.ResolvedPath();
            if (string.IsNullOrWhiteSpace(resolvedPath))
            {
                Session.Messages.Add(ChatMessage.Make(ChatMessageRole.Error, backend.MissingCliMessage()));
                Session.State = SessionState.Error("CLI not found");
                NotifyUpdate();
                return;
            }

            Session.State = SessionState.Running();
            NotifyUpdate();

            var userMessageCount = Session.Messages.Count(message => message.Role == ChatMessageRole.User);
            var shouldResume = Session.CliSessionBackend == backend && userMessageCount > 1;
            if (!shouldResume)
            {
                Session.CliSessionId = Guid.NewGuid().ToString();
            }
            Session.CliSessionBackend = backend;

            var transport = TransportForCurrentConversation(resolvedPath);
            ConfigureTransportCallbacks(transport);

            var request = new ConversationTurnRequest
            {
                Backend = backend,
                Prompt = BuildPrompt(prompt, attachments),
                ImagePaths = attachments.Where(item => item.IsImage).Select(item => item.FilePath).ToList(),
                SessionId = Session.CliSessionId,
                IsResume = shouldResume,
                WorkingDirectory = Session.WorkspaceDirectory,
                Model = Session.SelectedModel.CliValue(backend),
                ExecutionMode = Session.ConversationMode,
            };

            transport.SendTurn(request);
        }
    }

    public void Terminate()
    {
        lock (_sync)
        {
            ResetConversationTransport();
        }
    }

    public void SelectModel(ProviderModelOption model)
    {
        lock (_sync)
        {
            var normalized = model.Normalized(Session.Provider);
            if (!normalized.IsAvailable(Session.Provider) || normalized == Session.SelectedModel)
            {
                return;
            }

            Session.SelectedModel = normalized;
            Session.CliSessionId = Guid.NewGuid().ToString();
            Session.CliSessionBackend = null;

            if (Session.State.Kind == SessionStateKind.Running)
            {
                _shouldResetTransportAfterTurn = true;
                NotifyUpdate();
                return;
            }

            ResetConversationTransport();
            NotifyUpdate();
        }
    }

    public void UpdateProvider(CLIBackend provider)
    {
        lock (_sync)
        {
            if (Session.Provider == provider)
            {
                return;
            }

            Session.Provider = provider;
            Session.SelectedModel = Session.SelectedModel.Normalized(provider);
            Session.CliSessionId = Guid.NewGuid().ToString();
            Session.CliSessionBackend = null;
            ResetConversationTransport();
            NotifyUpdate();
        }
    }

    public void UpdateConversationMode(ConversationExecutionMode mode)
    {
        lock (_sync)
        {
            if (Session.ConversationMode == mode)
            {
                return;
            }

            Session.ConversationMode = mode;
            if (Session.State.Kind != SessionStateKind.Running)
            {
                Session.CliSessionId = Guid.NewGuid().ToString();
                Session.CliSessionBackend = null;
                ResetConversationTransport();
            }

            NotifyUpdate();
        }
    }

    public void HandleInterruptionAction(InterruptionAction action)
    {
        lock (_sync)
        {
            if (string.IsNullOrWhiteSpace(action.Payload))
            {
                return;
            }

            var parts = action.Payload.Split('|');
            if (parts.Length != 3)
            {
                return;
            }

            var interruptionId = parts[0];
            var actionId = parts[1];
            var transportValue = parts[2].Length == 0 ? null : parts[2];

            if (actionId == "bypass-conversation")
            {
                _shouldRecycleCopilotTransportAfterTurn = true;
                Session.ConversationMode = ConversationExecutionMode.Bypass;
            }

            if (_pendingTextReplyInterruptionId == interruptionId)
            {
                _pendingTextReplyInterruptionId = null;
            }

            _conversationTransport?.ResolveInterruption(interruptionId, transportValue, null);
            ClearInterruptionActionsContaining(action.Id);
            NotifyUpdate();
        }
    }

    public void AttachFiles(IEnumerable<string> filePaths)
    {
        lock (_sync)
        {
            foreach (var path in filePaths)
            {
                try
                {
                    var attachment = MakeAttachment(path);
                    if (PendingAttachments.All(item => item.FilePath != attachment.FilePath))
                    {
                        PendingAttachments.Add(attachment);
                    }
                }
                catch (Exception exception)
                {
                    AppendAttachmentError($"Couldn't attach {Path.GetFileName(path)}: {exception.Message}");
                }
            }
        }
    }

    public void RemovePendingAttachment(Guid id)
    {
        var item = PendingAttachments.FirstOrDefault(attachment => attachment.Id == id);
        if (item is not null)
        {
            PendingAttachments.Remove(item);
        }
    }

    public void MarkAssistantMessagesRead(bool notify = true)
    {
        var hadUnread = Session.HasUnread;
        Session.MarkAssistantMessagesRead();
        if (notify && hadUnread)
        {
            NotifyUpdate();
        }
    }

    public void CaptureScreenshot()
    {
        if (IsCapturingScreenshot)
        {
            return;
        }

        IsCapturingScreenshot = true;

        Task.Run(() =>
        {
            try
            {
                var fileName = MakeUniqueFileName($"screenshot-{TimestampSlug()}", "png");
                var destination = Path.Combine(AttachmentsDirectoryPath(), fileName);

                using var bitmap = new Bitmap((int)System.Windows.Forms.Screen.PrimaryScreen!.Bounds.Width, (int)System.Windows.Forms.Screen.PrimaryScreen!.Bounds.Height);
                using var graphics = Graphics.FromImage(bitmap);
                graphics.CopyFromScreen(0, 0, 0, 0, bitmap.Size);
                bitmap.Save(destination, ImageFormat.Png);

                lock (_sync)
                {
                    var attachment = MakeStoredAttachment(ChatAttachmentKind.Image, Path.GetFileName(destination), destination);
                    PendingAttachments.Add(attachment);
                }
            }
            catch (Exception exception)
            {
                lock (_sync)
                {
                    AppendAttachmentError($"Couldn't capture screenshot: {exception.Message}");
                }
            }
            finally
            {
                IsCapturingScreenshot = false;
            }
        });
    }

    private void ConfigureTransportCallbacks(IConversationTransport transport)
    {
        if (ReferenceEquals(_callbackTransport, transport))
        {
            return;
        }

        _callbackTransport = transport;

        transport.OnTextChunk += text =>
        {
            lock (_sync)
            {
                ApplyAssistantDelta(text);
                NotifyUpdate();
            }
        };

        transport.OnResult += text =>
        {
            lock (_sync)
            {
                CompleteAssistantMessage(text);
                NotifyUpdate();
            }
        };

        transport.OnEventText += text =>
        {
            lock (_sync)
            {
                AppendSystemEvent(text);
                NotifyUpdate();
            }
        };

        transport.OnInterruption += interruption =>
        {
            lock (_sync)
            {
                AppendInterruptionMessage(interruption);
                FinishAssistantRun();
                if (interruption.ResponseMode == ConversationInterruptionResponseMode.TextReply)
                {
                    _pendingTextReplyInterruptionId = interruption.Id;
                }
                NotifyUpdate();
            }
        };

        transport.OnComplete += () =>
        {
            lock (_sync)
            {
                FinishAssistantRun();
                _pendingTextReplyInterruptionId = null;
                HandleTurnLifecycleCompletion();
                NotifyUpdate();
            }
        };

        transport.OnSessionId += newId =>
        {
            lock (_sync)
            {
                if (Session.CliSessionId != newId)
                {
                    Session.CliSessionId = newId;
                    NotifyUpdate();
                }
            }
        };

        transport.OnAssistantMessageStarted += () =>
        {
            lock (_sync)
            {
                StartAssistantMessageIfNeeded();
                NotifyUpdate();
            }
        };

        transport.OnTurnCompleted += () =>
        {
            lock (_sync)
            {
                FinishAssistantRun();
                _pendingTextReplyInterruptionId = null;
                NotifyUpdate();
            }
        };

        transport.OnError += error =>
        {
            lock (_sync)
            {
                var streaming = Session.Messages.LastOrDefault(message => message.Role == ChatMessageRole.Assistant && message.IsStreaming);
                if (streaming is not null)
                {
                    Session.Messages.Remove(streaming);
                }

                Session.Messages.Add(ChatMessage.Make(ChatMessageRole.Error, error));
                Session.State = SessionState.Error(error);
                Session.CliSessionBackend = null;
                _pendingTextReplyInterruptionId = null;
                HandleTurnLifecycleCompletion(forceReset: true);
                NotifyUpdate();
            }
        };
    }

    private IConversationTransport TransportForCurrentConversation(string executablePath)
    {
        return Session.Provider switch
        {
            CLIBackend.Copilot when _conversationTransport is CopilotACPTransport && _conversationTransportBackend == CLIBackend.Copilot => _conversationTransport,
            CLIBackend.Claude when _conversationTransport is ClaudeInteractiveTransport && _conversationTransportBackend == CLIBackend.Claude => _conversationTransport,
            CLIBackend.Codex when _conversationTransport is CodexAppServerTransport && _conversationTransportBackend == CLIBackend.Codex => _conversationTransport,
            CLIBackend.Copilot => CreateTransport(new CopilotACPTransport(executablePath, Session.WorkspaceDirectory, Session.ConversationMode), CLIBackend.Copilot),
            CLIBackend.Claude => CreateTransport(new ClaudeInteractiveTransport(executablePath, Session.WorkspaceDirectory, Session.ConversationMode), CLIBackend.Claude),
            _ => CreateTransport(new CodexAppServerTransport(executablePath, Session.WorkspaceDirectory, Session.ConversationMode), CLIBackend.Codex),
        };
    }

    private IConversationTransport CreateTransport(IConversationTransport transport, CLIBackend backend)
    {
        ResetConversationTransport();
        _conversationTransport = transport;
        _conversationTransportBackend = backend;
        return transport;
    }

    private void ResetConversationTransport()
    {
        _conversationTransport?.Stop();
        _conversationTransport = null;
        _conversationTransportBackend = null;
        _callbackTransport = null;
        _shouldRecycleCopilotTransportAfterTurn = false;
        _shouldResetTransportAfterTurn = false;
        _pendingTextReplyInterruptionId = null;
    }

    private void HandleTurnLifecycleCompletion(bool forceReset = false)
    {
        var shouldReset = forceReset
            || !(_conversationTransport?.PersistsAcrossTurns ?? false)
            || _shouldRecycleCopilotTransportAfterTurn
            || _shouldResetTransportAfterTurn;

        if (shouldReset)
        {
            ResetConversationTransport();
        }
        else
        {
            _shouldRecycleCopilotTransportAfterTurn = false;
        }
    }

    private void AppendInterruptionMessage(ConversationInterruption interruption)
    {
        var actions = interruption.Actions.Select(action => new InterruptionAction
        {
            Id = Guid.NewGuid(),
            Title = action.Label,
            Role = action.Role switch
            {
                ConversationInterruptionActionRole.Primary => InterruptionActionRole.Primary,
                ConversationInterruptionActionRole.Secondary => InterruptionActionRole.Secondary,
                ConversationInterruptionActionRole.Destructive => InterruptionActionRole.Destructive,
                _ => InterruptionActionRole.Primary,
            },
            Payload = $"{interruption.Id}|{action.Id}|{action.TransportValue ?? string.Empty}",
        }).ToList();

        var kind = interruption.Kind == ConversationInterruptionKind.Question
            ? ChatMessageKind.Question
            : ChatMessageKind.Permission;

        Session.Messages.Add(new ChatMessage
        {
            Role = ChatMessageRole.System,
            Content = interruption.Details,
            InterruptionTitle = interruption.Title,
            InterruptionDetails = interruption.Details,
            InterruptionActions = actions,
            Kind = kind,
            IsNew = false,
            Timestamp = DateTimeOffset.Now,
        });
    }

    private void ClearInterruptionActionsContaining(Guid actionId)
    {
        var message = Session.Messages.FirstOrDefault(item => item.InterruptionActions.Any(action => action.Id == actionId));
        if (message is not null)
        {
            message.InterruptionActions = [];
        }
    }

    private void NotifyUpdate()
    {
        Session.TouchUpdatedAt();
        RaisePropertyChanged(nameof(Session));
        RaisePropertyChanged(nameof(VisibleMessages));
        OnSessionUpdated?.Invoke(Session.Clone());
    }

    private void StartAssistantMessageIfNeeded()
    {
        if (Session.Messages.Any(message => message.Role == ChatMessageRole.Assistant && message.IsStreaming))
        {
            return;
        }

        Session.Messages.Add(new ChatMessage
        {
            Role = ChatMessageRole.Assistant,
            Content = string.Empty,
            IsStreaming = true,
            IsNew = true,
            Timestamp = DateTimeOffset.Now,
        });
    }

    private void ApplyAssistantDelta(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        StartAssistantMessageIfNeeded();
        var index = Session.Messages.FindLastIndex(message => message.Role == ChatMessageRole.Assistant && message.IsStreaming);
        if (index < 0)
        {
            return;
        }

        var current = Session.Messages[index].Content;
        var merged = MergeAssistantContent(current, text);
        if (merged is null)
        {
            return;
        }

        Session.Messages[index].Content = merged;
        SyncDerivedAttachments(index);
    }

    private void CompleteAssistantMessage(string text)
    {
        var index = Session.Messages.FindLastIndex(message => message.Role == ChatMessageRole.Assistant && message.IsStreaming);
        if (index >= 0)
        {
            if (!string.IsNullOrEmpty(text))
            {
                Session.Messages[index].Content = text;
            }

            Session.Messages[index].IsStreaming = false;
            SyncDerivedAttachments(index);
            if (Session.Messages[index].Content.Length == 0)
            {
                Session.Messages.RemoveAt(index);
            }
            return;
        }

        if (text.Length == 0)
        {
            return;
        }

        Session.Messages.Add(ChatMessage.Make(ChatMessageRole.Assistant, text));
        SyncDerivedAttachments(Session.Messages.Count - 1);
    }

    private void FinishAssistantRun()
    {
        var index = Session.Messages.FindLastIndex(message => message.Role == ChatMessageRole.Assistant && message.IsStreaming);
        if (index >= 0)
        {
            Session.Messages[index].IsStreaming = false;
            SyncDerivedAttachments(index);

            if (Session.Messages[index].Content.Length == 0)
            {
                var hasFollowupEvent = Session.Messages.Skip(index + 1).Any(message => message.Role == ChatMessageRole.System && message.Content.Trim().Length > 0);
                if (hasFollowupEvent)
                {
                    Session.Messages.RemoveAt(index);
                }
                else
                {
                    Session.Messages[index].Content = "(No response)";
                }
            }
        }

        if (Session.State.Kind == SessionStateKind.Running)
        {
            Session.State = SessionState.Idle();
        }
    }

    private void AppendSystemEvent(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0)
        {
            return;
        }

        var kind = ClassifySystemEventKind(trimmed);
        if (kind != ChatMessageKind.AgentThought)
        {
            return;
        }

        AppendOrMergeAgentThought(trimmed);
    }

    private void AppendOrMergeAgentThought(string incoming)
    {
        var normalizedIncoming = NormalizeThoughtEventText(incoming);
        if (normalizedIncoming is null)
        {
            return;
        }

        var last = Session.Messages.LastOrDefault();
        if (last is null || last.Role != ChatMessageRole.System || last.Kind != ChatMessageKind.AgentThought)
        {
            Session.Messages.Add(new ChatMessage
            {
                Role = ChatMessageRole.System,
                Kind = ChatMessageKind.AgentThought,
                Content = normalizedIncoming,
                IsNew = false,
                Timestamp = DateTimeOffset.Now,
            });
            return;
        }

        last.Content = MergeThoughtEventText(last.Content, normalizedIncoming);
    }

    private void HydrateDerivedAssistantAttachments()
    {
        for (var index = 0; index < Session.Messages.Count; index += 1)
        {
            if (Session.Messages[index].Role == ChatMessageRole.Assistant)
            {
                SyncDerivedAttachments(index);
            }
        }
    }

    private void SyncDerivedAttachments(int index)
    {
        if (index < 0 || index >= Session.Messages.Count)
        {
            return;
        }

        if (Session.Messages[index].Role != ChatMessageRole.Assistant)
        {
            return;
        }

        Session.Messages[index].Attachments = ExtractAttachments(Session.Messages[index].Content);
    }

    private List<ChatAttachment> ExtractAttachments(string content)
    {
        var destinations = ExtractMarkdownLinkDestinations(content);
        if (destinations.Count == 0)
        {
            return [];
        }

        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var attachments = new List<ChatAttachment>();

        foreach (var destination in destinations)
        {
            var resolved = ResolveLinkedFilePath(destination);
            if (resolved is null)
            {
                continue;
            }

            if (!seen.Add(resolved))
            {
                continue;
            }

            attachments.Add(MakeDerivedAttachment(resolved));
        }

        return attachments;
    }

    private List<string> ExtractMarkdownLinkDestinations(string content)
    {
        return MarkdownLinkRegex.Matches(content)
            .Select(match => match.Groups.Count > 1 ? match.Groups[1].Value : string.Empty)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .ToList();
    }

    private string? ResolveLinkedFilePath(string rawDestination)
    {
        var candidate = rawDestination.Trim();
        if (candidate.Length == 0)
        {
            return null;
        }

        if (candidate.StartsWith("<", StringComparison.Ordinal) && candidate.EndsWith(">", StringComparison.Ordinal))
        {
            candidate = candidate[1..^1];
        }

        var hashIndex = candidate.IndexOf('#');
        if (hashIndex >= 0)
        {
            candidate = candidate[..hashIndex];
        }

        candidate = Uri.UnescapeDataString(candidate);

        if (candidate.StartsWith("file://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var uri = new Uri(candidate, UriKind.Absolute);
                if (uri.IsFile)
                {
                    var path = uri.LocalPath;
                    return File.Exists(path) ? path : null;
                }
            }
            catch
            {
                return null;
            }
        }

        if (!Path.IsPathRooted(candidate))
        {
            return null;
        }

        if (File.Exists(candidate))
        {
            return candidate;
        }

        var stripped = LineSuffixRegex.Replace(candidate, string.Empty);
        return File.Exists(stripped) ? stripped : null;
    }

    private ChatAttachment MakeDerivedAttachment(string path)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        var kind = extension is ".png" or ".jpg" or ".jpeg" or ".gif" or ".bmp" or ".webp"
            ? ChatAttachmentKind.Image
            : ChatAttachmentKind.File;

        return new ChatAttachment
        {
            Kind = kind,
            FileName = Path.GetFileName(path),
            FilePath = path,
            RelativePath = RelativePathForPreviewAttachment(path),
        };
    }

    private string RelativePathForPreviewAttachment(string filePath)
    {
        var workspacePath = Path.GetFullPath(Session.WorkspaceDirectory);
        var normalizedPath = Path.GetFullPath(filePath);

        if (!normalizedPath.StartsWith(workspacePath, StringComparison.OrdinalIgnoreCase))
        {
            return normalizedPath;
        }

        var relative = Path.GetRelativePath(workspacePath, normalizedPath);
        return string.IsNullOrWhiteSpace(relative) ? Path.GetFileName(filePath) : relative.Replace('\\', '/');
    }

    private string BuildPrompt(string userPrompt, List<ChatAttachment> attachments)
    {
        if (attachments.Count == 0)
        {
            return userPrompt;
        }

        var attachmentLines = string.Join('\n', attachments.Select(attachment => $"- {(attachment.IsImage ? "image" : "file")}: {attachment.RelativePath}"));
        var effectivePrompt = userPrompt.Length == 0
            ? "Inspect the attachments and respond appropriately. If the intended task is unclear, summarize what was attached and ask one focused clarifying question."
            : userPrompt;

        return $"The user attached the following workspace files for this message:\n{attachmentLines}\n\nUse those paths when you need to inspect the attachments.\n\nUser request:\n{effectivePrompt}";
    }

    private void AppendAttachmentError(string message)
    {
        Session.Messages.Add(ChatMessage.Make(ChatMessageRole.Error, message));
        NotifyUpdate();
    }

    private ChatAttachment MakeAttachment(string sourcePath)
    {
        if (!File.Exists(sourcePath))
        {
            throw new FileNotFoundException("Only files can be attached.", sourcePath);
        }

        var fileName = Path.GetFileName(sourcePath);
        var extension = Path.GetExtension(sourcePath).TrimStart('.');
        var baseName = Path.GetFileNameWithoutExtension(sourcePath);
        var storedName = MakeUniqueFileName(baseName, extension);
        var destination = Path.Combine(AttachmentsDirectoryPath(), storedName);
        File.Copy(sourcePath, destination, overwrite: false);

        var image = IsImageFile(sourcePath);
        return MakeStoredAttachment(image ? ChatAttachmentKind.Image : ChatAttachmentKind.File, fileName, destination);
    }

    private ChatAttachment MakeStoredAttachment(ChatAttachmentKind kind, string fileName, string storedPath)
    {
        return new ChatAttachment
        {
            Kind = kind,
            FileName = fileName,
            FilePath = storedPath,
            RelativePath = $"attachments/{Path.GetFileName(storedPath)}",
        };
    }

    private bool IsImageFile(string path)
    {
        var extension = Path.GetExtension(path).ToLowerInvariant();
        return extension is ".png" or ".jpg" or ".jpeg" or ".gif" or ".bmp" or ".webp";
    }

    private string MakeUniqueFileName(string baseName, string extension)
    {
        var safeBase = SanitizeFileComponent(baseName);
        var safeExtension = SanitizeFileComponent(extension);
        var suffix = Guid.NewGuid().ToString("N")[..8];

        return safeExtension.Length == 0
            ? $"{safeBase}-{suffix}"
            : $"{safeBase}-{suffix}.{safeExtension}";
    }

    private string SanitizeFileComponent(string value)
    {
        var builder = new StringBuilder();
        foreach (var character in value)
        {
            if (char.IsLetterOrDigit(character) || character is '-' or '_')
            {
                builder.Append(character);
            }
            else
            {
                builder.Append('-');
            }
        }

        var sanitized = builder.ToString().Trim('-');
        return sanitized.Length == 0 ? "attachment" : sanitized;
    }

    private string TimestampSlug()
    {
        return DateTimeOffset.Now.ToString("yyyyMMdd-HHmmss");
    }

    private string AttachmentsDirectoryPath()
    {
        return Session.AttachmentsDirectory();
    }

    private static ChatMessageKind ClassifySystemEventKind(string text)
    {
        var normalized = text.ToLowerInvariant();

        if (normalized.Contains("approval", StringComparison.Ordinal)
            || normalized.Contains("permission", StringComparison.Ordinal)
            || normalized.Contains("request user input", StringComparison.Ordinal)
            || normalized.Contains("question", StringComparison.Ordinal))
        {
            return ChatMessageKind.Permission;
        }

        if (normalized.Contains("agent thought", StringComparison.Ordinal)
            || normalized.Contains("reasoning", StringComparison.Ordinal)
            || normalized.Contains("codex reasoning", StringComparison.Ordinal))
        {
            return ChatMessageKind.AgentThought;
        }

        if (normalized.StartsWith("running command:", StringComparison.Ordinal)
            || normalized.Contains("tool call", StringComparison.Ordinal)
            || normalized.Contains("tool use", StringComparison.Ordinal))
        {
            return ChatMessageKind.ToolUse;
        }

        return ChatMessageKind.Regular;
    }

    public static string? MergeAssistantContent(string current, string incoming)
    {
        if (incoming.Length == 0 || incoming == current)
        {
            return null;
        }

        if (incoming.StartsWith(current, StringComparison.Ordinal))
        {
            return incoming;
        }

        if (current.StartsWith(incoming, StringComparison.Ordinal) || current.EndsWith(incoming, StringComparison.Ordinal))
        {
            return null;
        }

        var overlap = SuffixPrefixOverlapLength(current, incoming);
        if (overlap > 0)
        {
            return current + incoming[overlap..];
        }

        if (incoming.Length > current.Length && incoming.Contains(current, StringComparison.Ordinal))
        {
            return incoming;
        }

        return current + incoming;
    }

    public static string? NormalizeThoughtEventText(string eventText)
    {
        var trimmed = eventText.Trim();
        if (trimmed.Length == 0)
        {
            return null;
        }

        var lines = trimmed.Split('\n');
        var title = lines.FirstOrDefault()?.Trim().ToLowerInvariant() ?? string.Empty;
        var isKnownThoughtTitle = title.StartsWith("agent thought", StringComparison.Ordinal)
            || title.StartsWith("codex reasoning", StringComparison.Ordinal)
            || title == "reasoning"
            || title.StartsWith("reasoning ", StringComparison.Ordinal);

        var body = isKnownThoughtTitle
            ? string.Join('\n', lines.Skip(1))
            : trimmed;
        var bodyTrimmed = body.Trim();
        return bodyTrimmed.Length == 0 ? "Agent thought" : $"Agent thought\n{bodyTrimmed}";
    }

    public static string MergeThoughtEventText(string existing, string incoming)
    {
        var normalizedExisting = NormalizeThoughtEventText(existing);
        var normalizedIncoming = NormalizeThoughtEventText(incoming);
        if (normalizedExisting is null || normalizedIncoming is null)
        {
            return existing;
        }

        if (normalizedIncoming == normalizedExisting)
        {
            return normalizedExisting;
        }

        if (normalizedIncoming.StartsWith(normalizedExisting, StringComparison.Ordinal))
        {
            return normalizedIncoming;
        }

        if (normalizedExisting.StartsWith(normalizedIncoming, StringComparison.Ordinal))
        {
            return normalizedExisting;
        }

        var existingBody = ThoughtBody(normalizedExisting);
        var incomingBody = ThoughtBody(normalizedIncoming);
        if (existingBody is null || incomingBody is null)
        {
            return normalizedExisting.Contains(normalizedIncoming, StringComparison.Ordinal)
                ? normalizedExisting
                : normalizedExisting + "\n" + normalizedIncoming;
        }

        var mergedBody = MergeThoughtBody(existingBody, incomingBody);
        return mergedBody.Length == 0 ? "Agent thought" : $"Agent thought\n{mergedBody}";
    }

    public static string? ThoughtBody(string eventText)
    {
        const string prefix = "Agent thought";
        if (!eventText.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var lines = eventText.Split('\n');
        return lines.Length <= 1 ? string.Empty : string.Join('\n', lines.Skip(1));
    }

    public static string MergeThoughtBody(string current, string incoming)
    {
        if (incoming == current)
        {
            return current;
        }

        if (incoming.StartsWith(current, StringComparison.Ordinal))
        {
            return incoming;
        }

        if (current.StartsWith(incoming, StringComparison.Ordinal) || current.EndsWith(incoming, StringComparison.Ordinal))
        {
            return current;
        }

        if (incoming.Contains(current, StringComparison.Ordinal))
        {
            return incoming;
        }

        if (current.Length == 0)
        {
            return incoming;
        }

        if (incoming.Length == 0)
        {
            return current;
        }

        var overlap = SuffixPrefixOverlapLength(current, incoming);
        if (overlap > 0)
        {
            return current + incoming[overlap..];
        }

        return current + incoming;
    }

    public static int SuffixPrefixOverlapLength(string current, string incoming)
    {
        var maxOverlap = Math.Min(current.Length, incoming.Length);
        for (var overlap = maxOverlap; overlap >= 1; overlap -= 1)
        {
            if (current[^overlap..] == incoming[..overlap])
            {
                return overlap;
            }
        }

        return 0;
    }
}
