using BobbleWin.Models;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using WinRT.Interop;

namespace BobbleWin.Windows;

public sealed class PanelCoordinator
{
    private readonly Window _window;
    private readonly WindowPositionManager _positionManager;

    public PanelDockSide DockSide { get; private set; } = PanelDockSide.Trailing;

    public event Action<PanelDockSide>? DockSideChanged;

    public PanelCoordinator(Window window, WindowPositionManager? positionManager = null)
    {
        _window = window;
        _positionManager = positionManager ?? new WindowPositionManager();
    }

    public void ApplyCollapsedFrame(int sessionCount, ChatHeadsLayoutMode layoutMode)
    {
        var size = _positionManager.CollapsedPanelSize(sessionCount, layoutMode);
        ResizeWindow(size.Width, size.Height);
    }

    public void Expand(int sessionCount, int? expandedIndex, ChatHeadsLayoutMode layoutMode)
    {
        var size = _positionManager.ExpandedPanelSize(sessionCount, expandedIndex, layoutMode);
        ResizeWindow(size.Width, size.Height);
    }

    public void Collapse(int sessionCount, ChatHeadsLayoutMode layoutMode)
    {
        var size = _positionManager.CollapsedPanelSize(sessionCount, layoutMode);
        ResizeWindow(size.Width, size.Height);
    }

    public void HandleSessionsChanged(int sessionCount, int? expandedIndex, ChatHeadsLayoutMode layoutMode)
    {
        if (expandedIndex.HasValue)
        {
            Expand(sessionCount, expandedIndex, layoutMode);
        }
        else
        {
            ApplyCollapsedFrame(sessionCount, layoutMode);
        }
    }

    public void SetDockSide(PanelDockSide side)
    {
        if (DockSide == side)
        {
            return;
        }

        DockSide = side;
        DockSideChanged?.Invoke(side);
    }

    private void ResizeWindow(double width, double height)
    {
        var hwnd = WindowNative.GetWindowHandle(_window);
        var windowId = Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd);
        var appWindow = AppWindow.GetFromWindowId(windowId);
        appWindow.Resize(new Windows.Graphics.SizeInt32((int)Math.Ceiling(width), (int)Math.Ceiling(height)));
    }
}
