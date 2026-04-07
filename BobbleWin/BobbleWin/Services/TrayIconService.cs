using System.Drawing;
using System.Windows.Forms;
using BobbleWin.Models;
using BobbleWin.ViewModels;
using Microsoft.UI.Xaml;

namespace BobbleWin.Services;

public sealed class TrayIconService
{
    private readonly ChatHeadsManager _manager;
    private readonly Window _window;

    private NotifyIcon? _notifyIcon;
    private readonly Dictionary<CLIBackend, ToolStripMenuItem> _providerItems = [];
    private readonly Dictionary<ChatHeadsLayoutMode, ToolStripMenuItem> _layoutItems = [];

    public TrayIconService(ChatHeadsManager manager, Window window)
    {
        _manager = manager;
        _window = window;

        _manager.SelectedProviderChanged += _ => UpdateSelectedProvider();
        _manager.LayoutModeChanged += _ => UpdateSelectedLayoutMode();
    }

    public void Install()
    {
        if (_notifyIcon is not null)
        {
            return;
        }

        _notifyIcon = new NotifyIcon
        {
            Text = "BobbleWin",
            Icon = SystemIcons.Application,
            Visible = true,
        };

        var menu = new ContextMenuStrip();
        var providerRoot = new ToolStripMenuItem("Agents");
        foreach (var backend in CLIBackendExtensions.All)
        {
            var item = new ToolStripMenuItem(backend.DisplayName())
            {
                CheckOnClick = true,
                Tag = backend,
            };
            item.Click += (_, _) => _manager.UpdateSelectedProvider(backend);
            providerRoot.DropDownItems.Add(item);
            _providerItems[backend] = item;
        }

        var layoutRoot = new ToolStripMenuItem("Layout");
        foreach (var layout in Enum.GetValues<ChatHeadsLayoutMode>())
        {
            var item = new ToolStripMenuItem(layout.MenuTitle())
            {
                CheckOnClick = true,
                Tag = layout,
            };
            item.Click += (_, _) => _manager.UpdateLayoutMode(layout);
            layoutRoot.DropDownItems.Add(item);
            _layoutItems[layout] = item;
        }

        var showItem = new ToolStripMenuItem("Show BobbleWin");
        showItem.Click += (_, _) =>
        {
            _window.DispatcherQueue.TryEnqueue(() =>
            {
                _window.Activate();
            });
        };

        var quitItem = new ToolStripMenuItem("Quit BobbleWin");
        quitItem.Click += (_, _) =>
        {
            _window.DispatcherQueue.TryEnqueue(() =>
            {
                _manager.FlushPersistence();
                _manager.TerminateAll();
                Application.Exit();
            });
        };

        menu.Items.Add(showItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(providerRoot);
        menu.Items.Add(layoutRoot);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add(quitItem);

        _notifyIcon.ContextMenuStrip = menu;
        _notifyIcon.DoubleClick += (_, _) =>
        {
            _window.DispatcherQueue.TryEnqueue(() => _window.Activate());
        };

        UpdateSelectedProvider();
        UpdateSelectedLayoutMode();
    }

    private void UpdateSelectedProvider()
    {
        foreach (var (backend, item) in _providerItems)
        {
            item.Checked = backend == _manager.SelectedProvider;
        }

        if (_notifyIcon is not null)
        {
            _notifyIcon.Text = $"BobbleWin ({_manager.SelectedProvider.DisplayName()})";
        }
    }

    private void UpdateSelectedLayoutMode()
    {
        foreach (var (layout, item) in _layoutItems)
        {
            item.Checked = layout == _manager.LayoutMode;
        }
    }
}
