using Microsoft.UI.Xaml;

namespace BobbleWin.Windows;

// WinUI 3 host placeholder maintained for parity with macOS FloatingPanel abstraction.
public sealed class FloatingPanel
{
    public Window Window { get; }

    public FloatingPanel(Window window)
    {
        Window = window;
    }
}
