using System.Collections.ObjectModel;
using System.Windows.Input;
using BobbleWin.Models;
using BobbleWin.Utilities;

namespace BobbleWin.ViewModels;

public sealed class MainWindowViewModel : ObservableObject
{
    private readonly ChatHeadsManager _manager;
    private readonly RelayCommand _sendCommand;
    private readonly RelayCommand _captureScreenshotCommand;
    private Guid? _selectedSessionId;
    private ChatSessionViewModel? _selectedSessionViewModel;

    public ObservableCollection<ChatSession> Sessions => _manager.Sessions;
    public ObservableCollection<ChatSession> HistorySessions => _manager.HistorySessions;
    public IReadOnlyList<CLIBackend> AvailableProviders => CLIBackendExtensions.All;
    public IReadOnlyList<ChatHeadsLayoutMode> LayoutModes => Enum.GetValues<ChatHeadsLayoutMode>();

    public ChatHeadsManager Manager => _manager;

    public Guid? SelectedSessionId
    {
        get => _selectedSessionId;
        set
        {
            if (!SetProperty(ref _selectedSessionId, value))
            {
                return;
            }

            _manager.ExpandedSessionId = value;
            if (value.HasValue)
            {
                _manager.MarkRead(value.Value);
            }
            UpdateSelectedSessionViewModel();
            RaisePropertyChanged(nameof(IsSessionExpanded));
        }
    }

    public ChatSessionViewModel? SelectedSessionViewModel
    {
        get => _selectedSessionViewModel;
        private set
        {
            if (SetProperty(ref _selectedSessionViewModel, value))
            {
                RaisePropertyChanged(nameof(IsSessionExpanded));
            }
        }
    }

    public bool IsSessionExpanded => SelectedSessionViewModel is not null;

    public CLIBackend SelectedProvider
    {
        get => _manager.SelectedProvider;
        set => _manager.UpdateSelectedProvider(value);
    }

    public ChatHeadsLayoutMode SelectedLayoutMode
    {
        get => _manager.LayoutMode;
        set => _manager.UpdateLayoutMode(value);
    }

    public ICommand AddSessionCommand { get; }
    public ICommand ToggleSessionCommand { get; }
    public ICommand CloseSessionCommand { get; }
    public ICommand ArchiveSessionCommand { get; }
    public ICommand DeleteHistorySessionCommand { get; }
    public ICommand RestoreHistorySessionCommand { get; }
    public ICommand SendCommand => _sendCommand;
    public ICommand CaptureScreenshotCommand => _captureScreenshotCommand;

    public MainWindowViewModel(ChatHeadsManager manager)
    {
        _manager = manager;

        AddSessionCommand = new RelayCommand(AddSession);
        ToggleSessionCommand = new RelayCommand(parameter => ToggleSession(parameter as ChatSession));
        CloseSessionCommand = new RelayCommand(CloseSession);
        ArchiveSessionCommand = new RelayCommand(parameter => ArchiveSession(parameter as ChatSession));
        DeleteHistorySessionCommand = new RelayCommand(parameter => DeleteHistorySession(parameter as ChatSession));
        RestoreHistorySessionCommand = new RelayCommand(parameter => RestoreHistorySession(parameter as ChatSession));
        _sendCommand = new RelayCommand(SendCurrentSession, () => SelectedSessionViewModel is not null);
        _captureScreenshotCommand = new RelayCommand(CaptureScreenshot, () => SelectedSessionViewModel is not null);

        _manager.SessionAdded += session =>
        {
            SelectedSessionId = session.Id;
            UpdateSelectedSessionViewModel();
            RaisePropertyChanged(nameof(SelectedProvider));
        };

        _manager.SelectedProviderChanged += _ => RaisePropertyChanged(nameof(SelectedProvider));
        _manager.LayoutModeChanged += _ => RaisePropertyChanged(nameof(SelectedLayoutMode));

        _manager.SessionsChanged += _ =>
        {
            if (SelectedSessionId.HasValue && !_manager.Sessions.Any(session => session.Id == SelectedSessionId.Value))
            {
                SelectedSessionId = null;
            }
            RaisePropertyChanged(nameof(Sessions));
            UpdateSelectedSessionViewModel();
        };

        if (_manager.Sessions.Count == 0)
        {
            _manager.AddSession();
        }
        else if (_manager.Sessions.LastOrDefault() is { } latest)
        {
            SelectedSessionId = latest.Id;
        }

        UpdateSelectedSessionViewModel();
    }

    private void AddSession()
    {
        _manager.AddSession();
    }

    private void ToggleSession(ChatSession? session)
    {
        if (session is null)
        {
            return;
        }

        if (SelectedSessionId == session.Id)
        {
            CloseSession();
            return;
        }

        SelectedSessionId = session.Id;
    }

    private void CloseSession()
    {
        SelectedSessionId = null;
        SelectedSessionViewModel = null;
    }

    private void ArchiveSession(ChatSession? session)
    {
        if (session is null)
        {
            return;
        }

        _manager.ArchiveSession(session);
        if (SelectedSessionId == session.Id)
        {
            SelectedSessionId = null;
        }

        RaisePropertyChanged(nameof(HistorySessions));
    }

    private void DeleteHistorySession(ChatSession? session)
    {
        if (session is null)
        {
            return;
        }

        _manager.DeleteHistorySession(session);
        RaisePropertyChanged(nameof(HistorySessions));
    }

    private void RestoreHistorySession(ChatSession? session)
    {
        if (session is null)
        {
            return;
        }

        var restored = _manager.RestoreSessionFromHistory(session);
        if (restored is not null)
        {
            SelectedSessionId = restored.Id;
        }

        RaisePropertyChanged(nameof(HistorySessions));
        RaisePropertyChanged(nameof(Sessions));
    }

    private void SendCurrentSession()
    {
        SelectedSessionViewModel?.Send();
    }

    private void CaptureScreenshot()
    {
        SelectedSessionViewModel?.CaptureScreenshot();
    }

    private void UpdateSelectedSessionViewModel()
    {
        if (!SelectedSessionId.HasValue)
        {
            SelectedSessionViewModel = null;
            _sendCommand.NotifyCanExecuteChanged();
            _captureScreenshotCommand.NotifyCanExecuteChanged();
            return;
        }

        SelectedSessionViewModel = _manager.ViewModelFor(SelectedSessionId.Value);
        _sendCommand.NotifyCanExecuteChanged();
        _captureScreenshotCommand.NotifyCanExecuteChanged();
    }

    public void AttachFiles(IEnumerable<string> paths)
    {
        SelectedSessionViewModel?.AttachFiles(paths);
    }
}
