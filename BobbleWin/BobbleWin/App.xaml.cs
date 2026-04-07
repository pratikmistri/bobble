using BobbleWin.Services;
using BobbleWin.ViewModels;
using Microsoft.UI.Xaml;

namespace BobbleWin;

public partial class App : Application
{
    private MainWindow? _window;
    private TrayIconService? _trayIconService;

    public ChatHeadsManager Manager { get; } = new();

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new MainWindow(Manager);
        _window.Activate();

        _trayIconService = new TrayIconService(Manager, _window);
        _trayIconService.Install();
    }
}
