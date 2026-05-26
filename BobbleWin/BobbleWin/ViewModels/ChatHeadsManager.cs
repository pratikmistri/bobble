using System.Collections.ObjectModel;
using System.Text.Json;
using BobbleWin.Models;
using BobbleWin.Utilities;

namespace BobbleWin.ViewModels;

public sealed class ChatHeadsManager : ObservableObject
{
    public sealed record HistoryEntry(ChatSession Session, bool IsArchived)
    {
        public Guid Id => Session.Id;
    }

    private readonly Dictionary<Guid, ChatSessionViewModel> _viewModels = [];
    private readonly ChatHistoryStore _historyStore = new();
    private CancellationTokenSource? _persistDebounce;

    private Guid? _expandedSessionId;
    private Guid? _closingSessionId;
    private Guid? _deletingSessionId;
    private CLIBackend _selectedProvider = CLIBackend.Codex;
    private ChatHeadsLayoutMode _layoutMode = ChatHeadsLayoutMode.Vertical;
    private HashSet<CLIBackend> _availableBackends = [];

    public ObservableCollection<ChatSession> Sessions { get; } = [];
    public ObservableCollection<ChatSession> HistorySessions { get; } = [];

    public Guid? ExpandedSessionId
    {
        get => _expandedSessionId;
        set
        {
            if (SetProperty(ref _expandedSessionId, value))
            {
                SyncSelectedProviderFromExpandedSession();
                RaisePropertyChanged(nameof(ExpandedSession));
            }
        }
    }

    public Guid? ClosingSessionId
    {
        get => _closingSessionId;
        set => SetProperty(ref _closingSessionId, value);
    }

    public Guid? DeletingSessionId
    {
        get => _deletingSessionId;
        set => SetProperty(ref _deletingSessionId, value);
    }

    public CLIBackend SelectedProvider
    {
        get => _selectedProvider;
        set
        {
            if (SetProperty(ref _selectedProvider, value))
            {
                SelectedProviderChanged?.Invoke(value);
            }
        }
    }

    public ChatHeadsLayoutMode LayoutMode
    {
        get => _layoutMode;
        set
        {
            if (SetProperty(ref _layoutMode, value))
            {
                SaveLayoutMode(value);
                LayoutModeChanged?.Invoke(value);
            }
        }
    }

    public HashSet<CLIBackend> AvailableBackends
    {
        get => _availableBackends;
        private set => SetProperty(ref _availableBackends, value);
    }

    public ChatSession? ExpandedSession => ExpandedSessionId.HasValue
        ? Sessions.FirstOrDefault(session => session.Id == ExpandedSessionId.Value)
        : null;

    public bool HasMixedProviders => Sessions.Select(session => session.Provider).Distinct().Count() > 1;

    public IReadOnlyList<HistoryEntry> HistoryEntries =>
        Sessions.Where(session => session.QualifiesForHistory).Select(session => new HistoryEntry(session, false))
            .Concat(HistorySessions.Where(session => session.QualifiesForHistory).Select(session => new HistoryEntry(session, true)))
            .OrderByDescending(entry => entry.Session.UpdatedAt)
            .ToList();

    public event Action<int>? SessionsChanged;
    public event Action<ChatSession>? SessionAdded;
    public event Action<CLIBackend>? SelectedProviderChanged;
    public event Action<ChatHeadsLayoutMode>? LayoutModeChanged;

    public ChatHeadsManager()
    {
        _layoutMode = LoadLayoutMode();
        RestoreSessions();
        _ = DetectAvailableBackendsAsync();
    }

    public ChatSessionViewModel? ViewModelFor(Guid sessionId)
    {
        return _viewModels.TryGetValue(sessionId, out var viewModel) ? viewModel : null;
    }

    public bool IsActiveSession(Guid sessionId)
    {
        return Sessions.Any(session => session.Id == sessionId);
    }

    public void AddSession()
    {
        var imageName = NextChatHeadImageName(Sessions.Concat(HistorySessions).ToList());
        var session = ChatSession.Create(SelectedProvider);
        session.ChatHeadSymbol = imageName;
        session.HasAssignedChatHeadSymbol = true;

        Sessions.Add(session);
        ConfigureViewModel(session);

        SchedulePersistence();
        SessionsChanged?.Invoke(Sessions.Count);
        SessionAdded?.Invoke(session);
    }

    public ChatSession? RestoreSessionFromHistory(ChatSession session)
    {
        var archived = HistorySessions.FirstOrDefault(item => item.Id == session.Id);
        if (archived is null)
        {
            return null;
        }

        HistorySessions.Remove(archived);
        var restored = archived.NormalizedForRestore();
        restored.IsArchived = false;
        restored.TouchUpdatedAt();

        Sessions.Add(restored);
        ConfigureViewModel(restored);

        SchedulePersistence();
        SessionsChanged?.Invoke(Sessions.Count);
        SessionAdded?.Invoke(restored);
        return restored;
    }

    public void ArchiveSession(ChatSession session)
    {
        var existing = Sessions.FirstOrDefault(item => item.Id == session.Id);
        if (existing is null)
        {
            return;
        }

        if (_viewModels.TryGetValue(existing.Id, out var viewModel))
        {
            viewModel.Terminate();
            _viewModels.Remove(existing.Id);
        }

        Sessions.Remove(existing);

        var archived = existing.Clone();
        archived.IsArchived = true;
        archived.MarkAssistantMessagesRead();
        if (archived.State.Kind == SessionStateKind.Running)
        {
            archived.State = SessionState.Idle();
        }

        var dup = HistorySessions.FirstOrDefault(item => item.Id == archived.Id);
        if (dup is not null)
        {
            HistorySessions.Remove(dup);
        }

        HistorySessions.Add(archived);
        ResortHistorySessions();

        if (ClosingSessionId == existing.Id)
        {
            ClosingSessionId = null;
        }

        if (DeletingSessionId == existing.Id)
        {
            DeletingSessionId = null;
        }

        if (ExpandedSessionId == existing.Id)
        {
            ExpandedSessionId = null;
        }

        SchedulePersistence();
        SessionsChanged?.Invoke(Sessions.Count);
    }

    public void DeleteHistorySession(ChatSession session)
    {
        var existing = HistorySessions.FirstOrDefault(item => item.Id == session.Id);
        if (existing is null)
        {
            return;
        }

        HistorySessions.Remove(existing);
        SchedulePersistence();
        DeleteWorkspace(existing);
    }

    public void RemoveSession(ChatSession session)
    {
        var existing = Sessions.FirstOrDefault(item => item.Id == session.Id);
        if (existing is null)
        {
            return;
        }

        if (_viewModels.TryGetValue(existing.Id, out var viewModel))
        {
            viewModel.Terminate();
            _viewModels.Remove(existing.Id);
        }

        Sessions.Remove(existing);

        if (ClosingSessionId == existing.Id)
        {
            ClosingSessionId = null;
        }

        if (DeletingSessionId == existing.Id)
        {
            DeletingSessionId = null;
        }

        if (ExpandedSessionId == existing.Id)
        {
            ExpandedSessionId = null;
        }

        SchedulePersistence();
        SessionsChanged?.Invoke(Sessions.Count);
        DeleteWorkspace(existing);
    }

    public void MarkRead(Guid sessionId)
    {
        var existing = Sessions.FirstOrDefault(session => session.Id == sessionId);
        if (existing is null)
        {
            return;
        }

        existing.MarkAssistantMessagesRead();
        if (_viewModels.TryGetValue(sessionId, out var viewModel))
        {
            viewModel.MarkAssistantMessagesRead(notify: false);
        }
        SchedulePersistence();
    }

    public void UpdateSelectedProvider(CLIBackend provider)
    {
        if (SelectedProvider != provider)
        {
            SelectedProvider = provider;
        }

        var activeSession = ExpandedSessionId.HasValue
            ? Sessions.FirstOrDefault(session => session.Id == ExpandedSessionId.Value)
            : Sessions.LastOrDefault();
        if (activeSession is null)
        {
            return;
        }

        SetProvider(provider, activeSession.Id);
    }

    public void UpdateLayoutMode(ChatHeadsLayoutMode mode)
    {
        LayoutMode = mode;
    }

    public void SetProvider(CLIBackend provider, Guid sessionId)
    {
        var session = Sessions.FirstOrDefault(item => item.Id == sessionId);
        if (session is null || session.Provider == provider)
        {
            return;
        }

        session.Provider = provider;
        session.TouchUpdatedAt();
        if (_viewModels.TryGetValue(sessionId, out var viewModel))
        {
            viewModel.UpdateProvider(provider);
        }

        if (ExpandedSessionId == sessionId && SelectedProvider != provider)
        {
            SelectedProvider = provider;
        }

        SchedulePersistence();
    }

    public void FlushPersistence()
    {
        _persistDebounce?.Cancel();
        _historyStore.Save(Sessions.ToList(), HistorySessions.ToList());
    }

    public void TerminateAll()
    {
        foreach (var viewModel in _viewModels.Values)
        {
            viewModel.Terminate();
        }
    }

    private async Task DetectAvailableBackendsAsync()
    {
        var available = await Task.Run(() => CLIBackendExtensions.AvailableBackends().ToHashSet()).ConfigureAwait(false);
        AvailableBackends = available;

        if (Sessions.Count == 0)
        {
            SelectedProvider = CLIBackendExtensions.PreferredDefault(available) ?? CLIBackend.Codex;
        }
    }

    private void SyncSelectedProviderFromExpandedSession()
    {
        var expanded = ExpandedSession;
        if (expanded is null)
        {
            return;
        }

        if (SelectedProvider != expanded.Provider)
        {
            SelectedProvider = expanded.Provider;
        }
    }

    private void RestoreSessions()
    {
        var restored = _historyStore.Load().Select(session => session.NormalizedForRestore()).ToList();
        var didAssignMissingHeads = AssignMissingChatHeadsIfNeeded(restored);

        var active = restored.Where(session => !session.IsArchived).OrderBy(session => session.UpdatedAt).ToList();
        var history = restored.Where(session => session.IsArchived).OrderByDescending(session => session.UpdatedAt).ToList();

        Sessions.Clear();
        foreach (var session in active)
        {
            Sessions.Add(session);
            ConfigureViewModel(session);
        }

        HistorySessions.Clear();
        foreach (var session in history)
        {
            HistorySessions.Add(session);
        }

        if (didAssignMissingHeads)
        {
            _historyStore.Save(Sessions.ToList(), HistorySessions.ToList());
        }

        if (Sessions.LastOrDefault() is { } latest)
        {
            SelectedProvider = latest.Provider;
        }
    }

    private void ConfigureViewModel(ChatSession session)
    {
        var viewModel = new ChatSessionViewModel(session);
        viewModel.OnSessionUpdated += updated =>
        {
            var synced = updated;
            if (ExpandedSessionId == updated.Id)
            {
                synced.MarkAssistantMessagesRead();
                if (_viewModels.TryGetValue(updated.Id, out var expandedViewModel))
                {
                    expandedViewModel.MarkAssistantMessagesRead(notify: false);
                }
            }

            var current = Sessions.FirstOrDefault(item => item.Id == updated.Id);
            if (current is not null)
            {
                var index = Sessions.IndexOf(current);
                Sessions[index] = synced;
                RaisePropertyChanged(nameof(Sessions));
                SchedulePersistence();
            }
        };

        _viewModels[session.Id] = viewModel;
    }

    private void SchedulePersistence()
    {
        _persistDebounce?.Cancel();
        _persistDebounce = new CancellationTokenSource();
        var token = _persistDebounce.Token;

        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(200, token).ConfigureAwait(false);
                if (token.IsCancellationRequested)
                {
                    return;
                }

                _historyStore.Save(Sessions.ToList(), HistorySessions.ToList());
            }
            catch (OperationCanceledException)
            {
                // no-op
            }
        }, token);
    }

    private bool AssignMissingChatHeadsIfNeeded(List<ChatSession> restoredSessions)
    {
        var didAssign = false;
        var usage = EmptyChatHeadUsageCounts();

        foreach (var session in restoredSessions.Where(session => session.HasAssignedChatHeadSymbol))
        {
            usage[session.ChatHeadImageName] += 1;
        }

        foreach (var session in restoredSessions.Where(session => !session.HasAssignedChatHeadSymbol))
        {
            var imageName = NextChatHeadImageName(usage);
            session.ChatHeadSymbol = imageName;
            session.HasAssignedChatHeadSymbol = true;
            usage[imageName] += 1;
            didAssign = true;
        }

        return didAssign;
    }

    private string NextChatHeadImageName(List<ChatSession> sessions)
    {
        var usage = EmptyChatHeadUsageCounts();
        foreach (var session in sessions)
        {
            usage[session.ChatHeadImageName] += 1;
        }

        return NextChatHeadImageName(usage);
    }

    private static string NextChatHeadImageName(Dictionary<string, int> usage)
    {
        foreach (var imageName in ChatSession.AvailableChatHeadImageNames)
        {
            if (usage[imageName] == 0)
            {
                return imageName;
            }
        }

        var minimumUsage = usage.Values.Min();
        return ChatSession.AvailableChatHeadImageNames.FirstOrDefault(name => usage[name] == minimumUsage)
            ?? ChatSession.DefaultChatHeadSymbol;
    }

    private static Dictionary<string, int> EmptyChatHeadUsageCounts()
    {
        return ChatSession.AvailableChatHeadImageNames.ToDictionary(name => name, _ => 0);
    }

    private static void DeleteWorkspace(ChatSession session)
    {
        try
        {
            if (Directory.Exists(session.WorkspaceDirectory))
            {
                Directory.Delete(session.WorkspaceDirectory, recursive: true);
            }
        }
        catch
        {
            // no-op
        }
    }

    private static string SettingsPath
        => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BobbleWin", "settings.json");

    private static ChatHeadsLayoutMode LoadLayoutMode()
    {
        try
        {
            if (!File.Exists(SettingsPath))
            {
                return ChatHeadsLayoutMode.Vertical;
            }

            var json = File.ReadAllText(SettingsPath);
            var model = JsonSerializer.Deserialize<Dictionary<string, string>>(json);
            if (model is null || !model.TryGetValue("layoutMode", out var layoutMode))
            {
                return ChatHeadsLayoutMode.Vertical;
            }

            return ChatHeadsLayoutModeExtensions.FromRawValue(layoutMode);
        }
        catch
        {
            return ChatHeadsLayoutMode.Vertical;
        }
    }

    private static void SaveLayoutMode(ChatHeadsLayoutMode layoutMode)
    {
        try
        {
            var directory = Path.GetDirectoryName(SettingsPath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var model = new Dictionary<string, string>
            {
                ["layoutMode"] = layoutMode.RawValue(),
            };
            var json = JsonSerializer.Serialize(model, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(SettingsPath, json);
        }
        catch
        {
            // no-op
        }
    }

    private void ResortHistorySessions()
    {
        var sorted = HistorySessions.OrderByDescending(session => session.UpdatedAt).ToList();
        HistorySessions.Clear();
        foreach (var session in sorted)
        {
            HistorySessions.Add(session);
        }
    }
}

internal sealed class ChatHistoryStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    private string StoragePath
    {
        get
        {
            var baseDirectory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "BobbleWin");
            return Path.Combine(baseDirectory, "session-history.json");
        }
    }

    public List<ChatSession> Load()
    {
        try
        {
            if (!File.Exists(StoragePath))
            {
                return [];
            }

            var json = File.ReadAllText(StoragePath);
            var sessions = JsonSerializer.Deserialize<List<ChatSession>>(json, SerializerOptions) ?? [];
            foreach (var session in sessions)
            {
                session.EnsureDefaults();
            }

            return sessions;
        }
        catch
        {
            return [];
        }
    }

    public void Save(List<ChatSession> activeSessions, List<ChatSession> historySessions)
    {
        try
        {
            var directory = Path.GetDirectoryName(StoragePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            var payload = activeSessions.Concat(historySessions).ToList();
            var json = JsonSerializer.Serialize(payload, SerializerOptions);
            File.WriteAllText(StoragePath, json);
        }
        catch
        {
            // no-op
        }
    }
}
