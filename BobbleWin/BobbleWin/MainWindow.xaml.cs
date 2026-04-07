using BobbleWin.ViewModels;
using BobbleWin.Windows;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace BobbleWin;

public sealed partial class MainWindow : Window
{
    private readonly PanelCoordinator _panelCoordinator;

    public MainWindowViewModel ViewModel { get; }

    public MainWindow(ChatHeadsManager manager)
    {
        InitializeComponent();

        ViewModel = new MainWindowViewModel(manager);
        DataContext = ViewModel;

        _panelCoordinator = new PanelCoordinator(this);
        _panelCoordinator.ApplyCollapsedFrame(ViewModel.Sessions.Count, ViewModel.Manager.LayoutMode);

        ViewModel.Manager.SessionsChanged += _ =>
        {
            var expandedIndex = ViewModel.SelectedSessionId.HasValue
                ? ViewModel.Sessions.ToList().FindIndex(session => session.Id == ViewModel.SelectedSessionId.Value)
                : (int?)null;
            _panelCoordinator.HandleSessionsChanged(ViewModel.Sessions.Count, expandedIndex, ViewModel.Manager.LayoutMode);
        };

        ViewModel.Manager.LayoutModeChanged += mode =>
        {
            var expandedIndex = ViewModel.SelectedSessionId.HasValue
                ? ViewModel.Sessions.ToList().FindIndex(session => session.Id == ViewModel.SelectedSessionId.Value)
                : (int?)null;
            _panelCoordinator.HandleSessionsChanged(ViewModel.Sessions.Count, expandedIndex, mode);
        };

        Closed += (_, _) =>
        {
            manager.FlushPersistence();
            manager.TerminateAll();
        };
    }

    private void AttachButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Windows.Storage.Pickers.FileOpenPicker();
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        WinRT.Interop.InitializeWithWindow.Initialize(dialog, hwnd);

        dialog.SuggestedStartLocation = Windows.Storage.Pickers.PickerLocationId.DocumentsLibrary;
        dialog.FileTypeFilter.Add("*");

        _ = PickAndAttachAsync(dialog);
    }

    private async Task PickAndAttachAsync(Windows.Storage.Pickers.FileOpenPicker dialog)
    {
        var files = await dialog.PickMultipleFilesAsync();
        if (files is null || files.Count == 0)
        {
            return;
        }

        var paths = files.Select(file => file.Path).Where(path => !string.IsNullOrWhiteSpace(path)).ToList();
        ViewModel.AttachFiles(paths);
    }
}
