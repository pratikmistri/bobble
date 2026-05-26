using System.Windows;
using BobbleWin.Services;
using BobbleWin.ViewModels;
using Application = System.Windows.Application;

namespace BobbleWin;

public partial class App : Application
{
    private MainWindow? _window;
    private TrayIconService? _trayIconService;

    public ChatHeadsManager Manager { get; } = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        DispatcherUnhandledException += (_, args) =>
        {
            try
            {
                System.IO.File.WriteAllText(
                    System.IO.Path.Combine(System.IO.Path.GetTempPath(), "BobbleWin_crash.txt"),
                    args.Exception.ToString());
            }
            catch { }
        };

        _window = new MainWindow(Manager);
        _window.Show();

        _trayIconService = new TrayIconService(Manager, _window);
        _trayIconService.Install();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try
        {
            Manager.FlushPersistence();
            Manager.TerminateAll();
        }
        catch { }
        base.OnExit(e);
    }
}
