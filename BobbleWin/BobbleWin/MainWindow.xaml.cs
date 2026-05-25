using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using BobbleWin.Models;
using BobbleWin.ViewModels;
using Microsoft.Win32;

namespace BobbleWin;

public partial class MainWindow : Window
{
    private readonly MainWindowViewModel _viewModel;
    private double _anchorRight = double.NaN;
    private double _anchorTop = double.NaN;

    public MainWindow(ChatHeadsManager manager)
    {
        _viewModel = new MainWindowViewModel(manager);
        DataContext = _viewModel;
        InitializeComponent();

        Loaded += OnLoaded;
        SourceInitialized += OnSourceInitialized;
        SizeChanged += OnSizeChanged;
        MessagesListView.Loaded += MessagesListView_Loaded;
    }

    private System.Windows.Controls.ScrollViewer? _messagesScrollViewer;
    private bool _autoScrollMessages = true;

    // ---- Scroll smoothing state ----
    // Wheel events feed _targetOffset; the frame loop critically-damps _currentOffset
    // toward it. After input stops, _inputVelocity extends the target so the scroll
    // glides to rest instead of cutting hard.
    private double _targetOffset;
    private double _currentOffset;
    private double _inputVelocity;        // px/sec — derived from recent wheel input
    private DateTime _lastWheelTime = DateTime.MinValue;
    private DateTime _lastFrameTime;
    private bool _frameRunning;
    private bool _suppressScrollSync;

    private void MessagesListView_PreviewMouseWheel(object sender, System.Windows.Input.MouseWheelEventArgs e)
    {
        var sv = _messagesScrollViewer;
        if (sv is null) return;

        e.Handled = true;
        _autoScrollMessages = false;

        var now = DateTime.UtcNow;
        double dt = (now - _lastWheelTime).TotalSeconds;
        double max = Math.Max(0, sv.ExtentHeight - sv.ViewportHeight);

        // Resync when idle so an external scroll (e.g. autoscroll) doesn't fight us.
        if (!_frameRunning || dt > 0.25)
        {
            _currentOffset = sv.VerticalOffset;
            _targetOffset = _currentOffset;
            _inputVelocity = 0;
        }

        // Acceleration: rapid ticks (small dt) get more amplification.
        // dt≈16ms → gain≈1.45; dt≈40ms → ≈1.2; dt≈100ms → ≈1.0; idle (>200ms) → 0.9.
        double gain = 1.0;
        if (dt > 0 && dt < 0.25)
        {
            gain = 0.9 + 0.6 * Math.Exp(-dt / 0.030);
        }

        double step = -e.Delta * 0.25 * gain;
        _targetOffset = Math.Clamp(_targetOffset + step, 0, max);

        // Track instantaneous velocity (EMA) for post-lift glide.
        if (dt > 0.001 && dt < 0.1)
        {
            double instant = step / dt;
            _inputVelocity = 0.45 * _inputVelocity + 0.55 * instant;
        }

        _lastWheelTime = now;
        if (_targetOffset >= max - 1) _autoScrollMessages = true;

        StartFrame();
    }

    private void StartFrame()
    {
        if (_frameRunning) return;
        _frameRunning = true;
        _lastFrameTime = DateTime.UtcNow;
        System.Windows.Media.CompositionTarget.Rendering += OnFrame;
    }

    private void StopFrame()
    {
        if (!_frameRunning) return;
        _frameRunning = false;
        System.Windows.Media.CompositionTarget.Rendering -= OnFrame;
    }

    private void OnFrame(object? sender, EventArgs e)
    {
        var sv = _messagesScrollViewer;
        if (sv is null) { StopFrame(); return; }

        var now = DateTime.UtcNow;
        double dt = Math.Min(0.05, Math.Max(1.0 / 240.0, (now - _lastFrameTime).TotalSeconds));
        _lastFrameTime = now;

        double max = Math.Max(0, sv.ExtentHeight - sv.ViewportHeight);
        bool inputActive = (now - _lastWheelTime).TotalMilliseconds < 60;

        // After the user lifts, extend the target with decaying momentum so the
        // glide tapers smoothly instead of stopping where the last wheel event was.
        if (!inputActive)
        {
            _targetOffset = Math.Clamp(_targetOffset + _inputVelocity * dt, 0, max);
            _inputVelocity *= Math.Exp(-3.2 * dt);   // ~310ms time constant
            if (Math.Abs(_inputVelocity) < 4) _inputVelocity = 0;
        }

        // Critically-damped lerp of current toward target. The exponential form is
        // frame-rate independent: alpha = 1 - exp(-k * dt). k=22 gives ~30% catch-up
        // per 60fps frame — smooth, no overshoot, no jitter.
        double alpha = 1.0 - Math.Exp(-22.0 * dt);
        _currentOffset += (_targetOffset - _currentOffset) * alpha;

        _suppressScrollSync = true;
        sv.ScrollToVerticalOffset(_currentOffset);
        _suppressScrollSync = false;

        // Rest condition.
        if (!inputActive
            && Math.Abs(_inputVelocity) < 1
            && Math.Abs(_targetOffset - _currentOffset) < 0.4)
        {
            _currentOffset = _targetOffset;
            sv.ScrollToVerticalOffset(_currentOffset);
            StopFrame();
        }
    }

    private void MessagesListView_Loaded(object sender, RoutedEventArgs e)
    {
        if (_messagesScrollViewer is not null) return;
        _messagesScrollViewer = FindDescendant<System.Windows.Controls.ScrollViewer>(MessagesListView);
        if (_messagesScrollViewer is not null)
        {
            _messagesScrollViewer.ScrollChanged += MessagesScroll_ScrollChanged;
        }
    }

    private void MessagesScroll_ScrollChanged(object sender, System.Windows.Controls.ScrollChangedEventArgs e)
    {
        if (_messagesScrollViewer is null) return;
        if (_suppressScrollSync) return;
        if (e.ExtentHeightChange > 0 && _autoScrollMessages)
        {
            double newMax = Math.Max(0, _messagesScrollViewer.ExtentHeight - _messagesScrollViewer.ViewportHeight);
            _suppressScrollSync = true;
            _messagesScrollViewer.ScrollToVerticalOffset(newMax);
            _suppressScrollSync = false;
            _targetOffset = newMax;
            _currentOffset = newMax;
            _inputVelocity = 0;
        }
    }

    private static T? FindDescendant<T>(DependencyObject root) where T : DependencyObject
    {
        for (int i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(root); i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(root, i);
            if (child is T match) return match;
            var deeper = FindDescendant<T>(child);
            if (deeper is not null) return deeper;
        }
        return null;
    }

    private void OnSourceInitialized(object? sender, EventArgs e)
    {
        // Hide from Alt-Tab via WS_EX_TOOLWINDOW
        var hwnd = new WindowInteropHelper(this).Handle;
        const int GWL_EXSTYLE = -20;
        const int WS_EX_TOOLWINDOW = 0x00000080;
        var ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, ex | WS_EX_TOOLWINDOW);
    }

    private void OnLoaded(object? sender, RoutedEventArgs e)
    {
        var wa = SystemParameters.WorkArea;
        UpdateLayout();
        _anchorRight = wa.Right - 16;
        _anchorTop = wa.Top + 80;
        ApplyAnchor();
    }

    private void OnSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        ApplyAnchor();
    }

    private void ApplyAnchor()
    {
        if (double.IsNaN(_anchorRight)) return;
        Left = _anchorRight - ActualWidth;
        Top = _anchorTop;
    }

    private void HeadColumn_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left)
        {
            try
            {
                DragMove();
                _anchorRight = Left + ActualWidth;
                _anchorTop = Top;
            }
            catch { }
        }
    }

    private void ChatHead_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn && btn.Tag is Guid id)
        {
            if (_viewModel.SelectedSessionId == id)
            {
                _viewModel.SelectedSessionId = null;
            }
            else
            {
                _viewModel.SelectedSessionId = id;
            }
        }
    }

    private void HistoryButton_Click(object sender, RoutedEventArgs e)
    {
        HistoryPopup.Visibility = HistoryPopup.Visibility == Visibility.Visible
            ? Visibility.Collapsed
            : Visibility.Visible;
    }

    private void RestoreHistory_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn && btn.Tag is Guid id)
        {
            var session = _viewModel.HistorySessions.FirstOrDefault(s => s.Id == id);
            if (session is not null)
            {
                _viewModel.RestoreHistorySessionCommand.Execute(session);
                HistoryPopup.Visibility = Visibility.Collapsed;
            }
        }
    }

    private void DeleteHistory_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn && btn.Tag is Guid id)
        {
            var session = _viewModel.HistorySessions.FirstOrDefault(s => s.Id == id);
            if (session is not null)
            {
                _viewModel.DeleteHistorySessionCommand.Execute(session);
            }
        }
    }

    private void InputTextBox_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter && (Keyboard.Modifiers & ModifierKeys.Shift) == 0)
        {
            e.Handled = true;
            if (_viewModel.SendCommand.CanExecute(null))
            {
                _viewModel.SendCommand.Execute(null);
            }
        }
    }

    private void AttachButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Multiselect = true,
            Title = "Attach files",
        };
        if (dialog.ShowDialog(this) == true)
        {
            _viewModel.AttachFiles(dialog.FileNames);
        }
    }

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
