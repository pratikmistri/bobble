using System;
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

    // We anchor the *HeadColumn's* top-left corner to a screen-space point,
    // so the heads stay put regardless of whether the chat panel is open and
    // regardless of which screen edge they're docked against.
    private double _anchorScreenX = double.NaN;
    private double _anchorScreenY = double.NaN;

    private enum HDock { Left, Right }
    private enum VDock { Top, Bottom }
    private HDock _hDock = HDock.Right;
    private VDock _vDock = VDock.Top;

    public MainWindow(ChatHeadsManager manager)
    {
        _viewModel = new MainWindowViewModel(manager);
        DataContext = _viewModel;
        InitializeComponent();

        Loaded += OnLoaded;
        SourceInitialized += OnSourceInitialized;
        SizeChanged += OnSizeChanged;
        MessagesListView.Loaded += MessagesListView_Loaded;
        _viewModel.PropertyChanged += OnViewModelPropertyChanged;
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(MainWindowViewModel.SelectedLayoutMode))
        {
            // Layout mode changed: re-place chat panel for the active dock corner.
            ApplyDockLayout();
            Dispatcher.BeginInvoke(new Action(ApplyAnchor), System.Windows.Threading.DispatcherPriority.Loaded);
        }
        else if (e.PropertyName == nameof(MainWindowViewModel.SelectedSessionViewModel))
        {
            AnimateChatPanelVisibility(_viewModel.SelectedSessionViewModel is not null);
        }
    }

    // ---- Panel show/hide animations ----
    // Drives ChatPanel and HistoryPopup with a fade + scale + slide transition.
    // The origin/translation direction is chosen so the panel grows from the
    // edge nearest the chat-head column.

    private System.Windows.Media.Animation.Storyboard? _chatPanelShowSb;
    private System.Windows.Media.Animation.Storyboard? _chatPanelHideSb;

    private void AnimateChatPanelVisibility(bool show)
    {
        if (ChatPanel is null) return;
        UpdatePanelTransformOrigin(ChatPanel);
        _chatPanelHideSb?.Stop(ChatPanel);
        _chatPanelShowSb?.Stop(ChatPanel);

        if (show)
        {
            ChatPanel.Visibility = Visibility.Visible;
            _chatPanelShowSb = BuildPanelShowStoryboard();
            _chatPanelShowSb.Begin(ChatPanel, true);
        }
        else
        {
            if (ChatPanel.Visibility != Visibility.Visible) return;
            _chatPanelHideSb = BuildPanelHideStoryboard();
            _chatPanelHideSb.Completed += (_, _) =>
            {
                if (_viewModel.SelectedSessionViewModel is null)
                    ChatPanel.Visibility = Visibility.Collapsed;
            };
            _chatPanelHideSb.Begin(ChatPanel, true);
        }
    }

    private void AnimateHistoryPopupVisibility(bool show)
    {
        if (HistoryPopup is null || HistoryPopupBorder is null) return;

        if (show)
        {
            // Origin emanates from the side facing the head column, vertically
            // centered on the button.
            HistoryPopupBorder.RenderTransformOrigin =
                new System.Windows.Point(_hDock == HDock.Right ? 1.0 : 0.0, 0.5);

            // Open first so the popup is realized in the visual tree, then
            // position it based on its measured size on the next layout pass.
            HistoryPopup.IsOpen = true;
            Dispatcher.BeginInvoke(new Action(PositionHistoryPopup),
                System.Windows.Threading.DispatcherPriority.Loaded);
            BuildPanelShowStoryboard().Begin(HistoryPopupBorder, true);
        }
        else
        {
            if (!HistoryPopup.IsOpen) return;
            var sb = BuildPanelHideStoryboard();
            sb.Completed += (_, _) => HistoryPopup.IsOpen = false;
            sb.Begin(HistoryPopupBorder, true);
        }
    }

    /// <summary>
    /// Anchors the history flyout vertically centered on the history button.
    /// The popup is placed on the side of the button opposite the head-column's
    /// dock edge, then clamped to the active screen's work area. When the content
    /// exceeds MaxHeight, the inner ScrollViewer takes over.
    /// </summary>
    private void PositionHistoryPopup()
    {
        if (HistoryPopup is null || HistoryButton is null || HistoryPopupBorder is null) return;
        if (!HistoryButton.IsLoaded) return;

        HistoryPopupBorder.UpdateLayout();
        double borderW = HistoryPopupBorder.ActualWidth > 0
            ? HistoryPopupBorder.ActualWidth
            : HistoryPopupBorder.Width;
        double borderH = HistoryPopupBorder.ActualHeight > 0
            ? HistoryPopupBorder.ActualHeight
            : HistoryPopupBorder.MaxHeight;
        var bm = HistoryPopupBorder.Margin;

        // Button screen position (device pixels → DIPs).
        System.Windows.Point btnTLpx;
        System.Windows.Point btnBRpx;
        try
        {
            btnTLpx = HistoryButton.PointToScreen(new System.Windows.Point(0, 0));
            btnBRpx = HistoryButton.PointToScreen(new System.Windows.Point(HistoryButton.ActualWidth, HistoryButton.ActualHeight));
        }
        catch { return; }

        var btnTL = PixelsToDip(btnTLpx.X, btnTLpx.Y);
        var btnBR = PixelsToDip(btnBRpx.X, btnBRpx.Y);
        double btnCenterY = (btnTL.Y + btnBR.Y) / 2.0;

        // We position by the visible Border's edge. The popup window is larger
        // than the Border by Margin on each side (drop-shadow gutter); subtract
        // those when computing HorizontalOffset/VerticalOffset.
        const double visualGap = 6;
        double borderLeft = _hDock == HDock.Right
            ? btnTL.X - visualGap - borderW
            : btnBR.X + visualGap;
        double borderTop = btnCenterY - borderH / 2.0;

        // Clamp the visible Border to the work area.
        var wa = GetWorkAreaForPoint(btnTL.X, btnTL.Y);
        borderLeft = Math.Max(wa.Left + 4, Math.Min(borderLeft, wa.Right - borderW - 4));
        borderTop = Math.Max(wa.Top + 4, Math.Min(borderTop, wa.Bottom - borderH - 4));

        // Translate Border-edge coordinates to popup-window offsets.
        HistoryPopup.HorizontalOffset = borderLeft - bm.Left;
        HistoryPopup.VerticalOffset = borderTop - bm.Top;
    }

    private void UpdatePanelTransformOrigin(System.Windows.FrameworkElement panel)
    {
        // Anchor the scale origin to the edge nearest the chat-head column so
        // the panel appears to emanate from the heads.
        double ox = _hDock == HDock.Right ? 1.0 : 0.0;
        double oy = _vDock == VDock.Top ? 0.0 : 1.0;
        panel.RenderTransformOrigin = new System.Windows.Point(ox, oy);

        if (panel.RenderTransform is System.Windows.Media.TransformGroup tg
            && tg.Children.Count >= 2
            && tg.Children[1] is System.Windows.Media.TranslateTransform)
        {
            // We reset Translate values at Begin via the storyboard,
            // but flip sign so the slide-in direction follows the dock.
            // (Storyboard "From" values are set in BuildPanelShowStoryboard.)
        }
    }

    private System.Windows.Media.Animation.Storyboard BuildPanelShowStoryboard()
    {
        var dx = _hDock == HDock.Right ? 20.0 : -20.0;
        var dy = _vDock == VDock.Top ? -8.0 : 8.0;
        var dur = new Duration(TimeSpan.FromMilliseconds(220));
        var ease = new System.Windows.Media.Animation.CubicEase { EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut };

        var sb = new System.Windows.Media.Animation.Storyboard();
        sb.Children.Add(MakeAnim("Opacity", 0.0, 1.0, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)", 0.92, 1.0, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)", 0.92, 1.0, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.X)", dx, 0.0, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)", dy, 0.0, dur, ease));
        return sb;
    }

    private System.Windows.Media.Animation.Storyboard BuildPanelHideStoryboard()
    {
        var dx = _hDock == HDock.Right ? 16.0 : -16.0;
        var dy = _vDock == VDock.Top ? -6.0 : 6.0;
        var dur = new Duration(TimeSpan.FromMilliseconds(160));
        var ease = new System.Windows.Media.Animation.CubicEase { EasingMode = System.Windows.Media.Animation.EasingMode.EaseIn };

        var sb = new System.Windows.Media.Animation.Storyboard();
        sb.Children.Add(MakeAnim("Opacity", null, 0.0, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleX)", null, 0.94, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[0].(ScaleTransform.ScaleY)", null, 0.94, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.X)", null, dx, dur, ease));
        sb.Children.Add(MakeAnim("(UIElement.RenderTransform).(TransformGroup.Children)[1].(TranslateTransform.Y)", null, dy, dur, ease));
        return sb;
    }

    private static System.Windows.Media.Animation.DoubleAnimation MakeAnim(
        string propertyPath, double? from, double to, Duration dur,
        System.Windows.Media.Animation.IEasingFunction ease)
    {
        var a = new System.Windows.Media.Animation.DoubleAnimation
        {
            To = to,
            Duration = dur,
            EasingFunction = ease,
            FillBehavior = System.Windows.Media.Animation.FillBehavior.HoldEnd
        };
        if (from.HasValue) a.From = from.Value;
        System.Windows.Media.Animation.Storyboard.SetTargetProperty(a, new PropertyPath(propertyPath));
        return a;
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
        // Start docked top-right with a 16px inset; anchor = HeadColumn's TOP-RIGHT corner.
        _hDock = HDock.Right;
        _vDock = VDock.Top;
        ApplyDockLayout();
        UpdateLayout();
        _anchorScreenX = wa.Right - 16;
        _anchorScreenY = wa.Top + 80;
        ApplyAnchor();

        // Re-clamp + re-place when the head column grows/shrinks (e.g., as sessions are added).
        HeadColumn.SizeChanged += (_, __) => ApplyAnchor();

        // Sync initial ChatPanel visibility (in case a session was selected before Loaded).
        if (_viewModel.SelectedSessionViewModel is not null)
            AnimateChatPanelVisibility(true);
    }

    private void OnSizeChanged(object? sender, SizeChangedEventArgs e)
    {
        ApplyAnchor();
    }

    private System.Windows.Point GetHeadColumnOffsetInWindow()
    {
        if (HeadColumn is null || !HeadColumn.IsLoaded) return new System.Windows.Point(0, 0);
        try
        {
            return HeadColumn.TranslatePoint(new System.Windows.Point(0, 0), this);
        }
        catch
        {
            return new System.Windows.Point(0, 0);
        }
    }

    /// <summary>
    /// Returns the offset (window-relative) of the HeadColumn corner that faces the
    /// active dock edges (e.g. bottom-right corner if heads are docked bottom-right).
    /// </summary>
    private System.Windows.Point GetHeadAnchorCornerInWindow()
    {
        if (HeadColumn is null || !HeadColumn.IsLoaded) return new System.Windows.Point(0, 0);
        var topLeft = HeadColumn.TranslatePoint(new System.Windows.Point(0, 0), this);
        var cornerX = topLeft.X + (_hDock == HDock.Right ? HeadColumn.ActualWidth : 0);
        var cornerY = topLeft.Y + (_vDock == VDock.Bottom ? HeadColumn.ActualHeight : 0);
        return new System.Windows.Point(cornerX, cornerY);
    }

    private void ApplyAnchor()
    {
        if (double.IsNaN(_anchorScreenX) || HeadColumn is null) return;
        ClampAnchorToWorkArea();
        // Place the window so that the HeadColumn's dock-edge corner lands at
        // (_anchorScreenX, _anchorScreenY). As more heads are added, the column
        // grows AWAY from the docked edge instead of off-screen.
        var corner = GetHeadAnchorCornerInWindow();
        Left = _anchorScreenX - corner.X;
        Top = _anchorScreenY - corner.Y;

        // Keep the history flyout glued to the history button as it moves.
        if (HistoryPopup is { IsOpen: true })
            PositionHistoryPopup();
    }

    private void UpdateAnchorFromCurrentPosition()
    {
        if (HeadColumn is null) return;
        var corner = GetHeadAnchorCornerInWindow();
        _anchorScreenX = Left + corner.X;
        _anchorScreenY = Top + corner.Y;
        ClampAnchorToWorkArea();
    }

    /// <summary>
    /// Clamps the saved anchor so the HeadColumn (anchored at its dock-edge corner)
    /// stays fully within the work area of whichever monitor currently contains the head.
    /// </summary>
    private void ClampAnchorToWorkArea()
    {
        if (HeadColumn is null) return;
        var headWidth = HeadColumn.ActualWidth;
        var headHeight = HeadColumn.ActualHeight;
        if (headWidth <= 0 || headHeight <= 0) return;

        // Convert anchor (dock-edge corner) to a center for screen-lookup.
        var centerX = _anchorScreenX + (_hDock == HDock.Right ? -headWidth / 2 : headWidth / 2);
        var centerY = _anchorScreenY + (_vDock == VDock.Bottom ? -headHeight / 2 : headHeight / 2);
        var wa = GetWorkAreaForPoint(centerX, centerY);

        const double inset = 4.0;
        double minX, maxX, minY, maxY;
        if (_hDock == HDock.Right)
        {
            // Anchor is the RIGHT edge of HeadColumn.
            minX = wa.Left + headWidth + inset;
            maxX = wa.Right - inset;
        }
        else
        {
            // Anchor is the LEFT edge.
            minX = wa.Left + inset;
            maxX = wa.Right - headWidth - inset;
        }
        if (_vDock == VDock.Bottom)
        {
            minY = wa.Top + headHeight + inset;
            maxY = wa.Bottom - inset;
        }
        else
        {
            minY = wa.Top + inset;
            maxY = wa.Bottom - headHeight - inset;
        }
        if (maxX < minX) maxX = minX;
        if (maxY < minY) maxY = minY;

        _anchorScreenX = Math.Clamp(_anchorScreenX, minX, maxX);
        _anchorScreenY = Math.Clamp(_anchorScreenY, minY, maxY);
    }

    /// <summary>
    /// Picks horizontal/vertical dock side based on the HeadColumn's screen-space
    /// center vs the active screen's work-area midpoint, then re-places the chat
    /// panel and head column inside the OuterLayout grid so the chat panel always
    /// opens *away* from the nearest edge.
    /// </summary>
    private void RecomputeDockSidesFromScreenPosition()
    {
        if (HeadColumn is null || !HeadColumn.IsLoaded) return;
        var offset = GetHeadColumnOffsetInWindow();
        var headLeft = Left + offset.X;
        var headTop = Top + offset.Y;
        var headWidth = HeadColumn.ActualWidth;
        var headHeight = HeadColumn.ActualHeight;
        var headCenterX = headLeft + headWidth / 2;
        var headCenterY = headTop + headHeight / 2;

        var wa = GetWorkAreaForPoint(headCenterX, headCenterY);
        var midX = (wa.Left + wa.Right) / 2.0;
        var midY = (wa.Top + wa.Bottom) / 2.0;

        var newH = headCenterX <= midX ? HDock.Left : HDock.Right;
        var newV = headCenterY <= midY ? VDock.Top : VDock.Bottom;

        if (newH != _hDock || newV != _vDock)
        {
            _hDock = newH;
            _vDock = newV;
            ApplyDockLayout();
            // Anchor corner just changed — re-derive the screen-space anchor from the
            // head column's current screen position (which already reflects the drag).
            Dispatcher.BeginInvoke(new Action(() =>
            {
                UpdateAnchorFromCurrentPosition();
                ApplyAnchor();
            }), System.Windows.Threading.DispatcherPriority.Loaded);
        }
    }

    private System.Windows.Rect GetWorkAreaForPoint(double x, double y)
    {
        try
        {
            var (sx, sy) = DipToPixels(x, y);
            var screen = System.Windows.Forms.Screen.FromPoint(new System.Drawing.Point((int)sx, (int)sy));
            var wa = screen.WorkingArea;
            // Convert work-area pixels back to WPF DIPs.
            var tl = PixelsToDip(wa.Left, wa.Top);
            var br = PixelsToDip(wa.Right, wa.Bottom);
            return new System.Windows.Rect(tl.X, tl.Y, br.X - tl.X, br.Y - tl.Y);
        }
        catch
        {
            return SystemParameters.WorkArea;
        }
    }

    private (double X, double Y) DpiScale()
    {
        var source = PresentationSource.FromVisual(this);
        if (source?.CompositionTarget != null)
        {
            var m = source.CompositionTarget.TransformToDevice;
            return (m.M11 == 0 ? 1.0 : m.M11, m.M22 == 0 ? 1.0 : m.M22);
        }
        return (1.0, 1.0);
    }

    private (double X, double Y) DipToPixels(double xDip, double yDip)
    {
        var (sx, sy) = DpiScale();
        return (xDip * sx, yDip * sy);
    }

    private System.Windows.Point PixelsToDip(double xPx, double yPx)
    {
        var (sx, sy) = DpiScale();
        return new System.Windows.Point(xPx / sx, yPx / sy);
    }

    /// <summary>
    /// Places ChatPanel and HeadColumn inside the OuterLayout 2x2 grid based on
    /// (a) the current layout mode (vertical heads column vs horizontal heads row)
    /// and (b) the current dock corner. The chat panel is set to the cell adjacent
    /// to the head column on the side opposite the nearest screen edge.
    /// </summary>
    private void ApplyDockLayout()
    {
        if (ChatPanel is null || HeadColumn is null) return;

        var layout = _viewModel.SelectedLayoutMode;

        // Default to single-row layout; we override for the horizontal layout mode below.
        System.Windows.Controls.Grid.SetRow(ChatPanel, 0);
        System.Windows.Controls.Grid.SetRow(HeadColumn, 0);
        System.Windows.Controls.Grid.SetColumn(ChatPanel, 0);
        System.Windows.Controls.Grid.SetColumn(HeadColumn, 0);

        if (layout == BobbleWin.Models.ChatHeadsLayoutMode.Vertical)
        {
            // Heads stacked vertically -> chat panel sits LEFT or RIGHT of heads.
            if (_hDock == HDock.Right)
            {
                System.Windows.Controls.Grid.SetColumn(ChatPanel, 0);
                System.Windows.Controls.Grid.SetColumn(HeadColumn, 1);
                ChatPanel.Margin = new Thickness(0, 0, 8, 0);
            }
            else
            {
                System.Windows.Controls.Grid.SetColumn(HeadColumn, 0);
                System.Windows.Controls.Grid.SetColumn(ChatPanel, 1);
                ChatPanel.Margin = new Thickness(8, 0, 0, 0);
            }
            // Align ChatPanel to the same vertical edge as the heads so it doesn't
            // pop out off-screen when the heads are near the top/bottom.
            ChatPanel.VerticalAlignment = _vDock == VDock.Top ? VerticalAlignment.Top : VerticalAlignment.Bottom;
            ChatPanel.HorizontalAlignment = System.Windows.HorizontalAlignment.Stretch;
        }
        else
        {
            // Heads in a horizontal row -> chat panel sits ABOVE or BELOW heads.
            if (_vDock == VDock.Top)
            {
                System.Windows.Controls.Grid.SetRow(HeadColumn, 0);
                System.Windows.Controls.Grid.SetRow(ChatPanel, 1);
                ChatPanel.Margin = new Thickness(0, 8, 0, 0);
            }
            else
            {
                System.Windows.Controls.Grid.SetRow(ChatPanel, 0);
                System.Windows.Controls.Grid.SetRow(HeadColumn, 1);
                ChatPanel.Margin = new Thickness(0, 0, 0, 8);
            }
            ChatPanel.HorizontalAlignment = _hDock == HDock.Right ? System.Windows.HorizontalAlignment.Right : System.Windows.HorizontalAlignment.Left;
            ChatPanel.VerticalAlignment = VerticalAlignment.Stretch;
        }
    }

    // -- Window-level drag: drag from anywhere except interactive controls --

    private System.Windows.Point? _dragStartScreenPoint;
    private bool _dragArmed;
    private bool _justDragged;
    private const double DragThreshold = 4.0;

    private void Window_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        _justDragged = false;
        // Arm a potential drag whenever the user presses outside of pure-input controls.
        // Buttons still get their click (we only call DragMove once the threshold is exceeded).
        if (e.OriginalSource is DependencyObject dep
            && (dep is System.Windows.Controls.TextBox || dep is System.Windows.Controls.PasswordBox))
        {
            _dragArmed = false;
            _dragStartScreenPoint = null;
            return;
        }

        _dragStartScreenPoint = PointToScreen(e.GetPosition(this));
        _dragArmed = true;
    }

    private void Window_PreviewMouseMove(object sender, System.Windows.Input.MouseEventArgs e)
    {
        if (!_dragArmed || _dragStartScreenPoint is null) return;
        if (e.LeftButton != MouseButtonState.Pressed)
        {
            _dragArmed = false;
            _dragStartScreenPoint = null;
            return;
        }

        var current = PointToScreen(e.GetPosition(this));
        var dx = current.X - _dragStartScreenPoint.Value.X;
        var dy = current.Y - _dragStartScreenPoint.Value.Y;
        if (Math.Abs(dx) < DragThreshold && Math.Abs(dy) < DragThreshold) return;

        _dragArmed = false;
        _justDragged = true;

        // If a Button (or anything else) captured the mouse, release it so DragMove() can take over.
        var captured = Mouse.Captured;
        if (captured is not null)
        {
            try { captured.ReleaseMouseCapture(); } catch { }
        }

        try
        {
            DragMove();
            UpdateAnchorFromCurrentPosition();
            RecomputeDockSidesFromScreenPosition();
        }
        catch
        {
            // DragMove throws if mouse button isn't down anymore — ignore.
        }
    }

    private void Window_PreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        // If we dragged, swallow the mouse-up so the captured Button doesn't fire its Click.
        if (_justDragged)
        {
            e.Handled = true;
        }
        _dragArmed = false;
        _justDragged = false;
        _dragStartScreenPoint = null;
    }

    private void HeadColumn_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        // Legacy handler — drag is now serviced at the window level. Keep for compatibility.
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
        AnimateHistoryPopupVisibility(!HistoryPopup.IsOpen);
    }

    private void RestoreHistory_Click(object sender, RoutedEventArgs e)
    {
        if (sender is System.Windows.Controls.Button btn && btn.Tag is Guid id)
        {
            var session = _viewModel.HistorySessions.FirstOrDefault(s => s.Id == id);
            if (session is not null)
            {
                _viewModel.RestoreHistorySessionCommand.Execute(session);
                AnimateHistoryPopupVisibility(false);
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
