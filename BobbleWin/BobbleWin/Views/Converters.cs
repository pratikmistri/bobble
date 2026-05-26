using BobbleWin.Models;
using BobbleWin.Utilities;
using System.Collections;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Media;

using HorizontalAlignment = System.Windows.HorizontalAlignment;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Orientation = System.Windows.Controls.Orientation;

namespace BobbleWin.Views;

public sealed class LayoutModeToOuterOrientationConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is ChatHeadsLayoutMode.Horizontal
            ? Orientation.Vertical
            : Orientation.Horizontal;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => ChatHeadsLayoutMode.Vertical;
}

public sealed class LayoutModeToInnerOrientationConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is ChatHeadsLayoutMode.Horizontal
            ? Orientation.Horizontal
            : Orientation.Vertical;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => ChatHeadsLayoutMode.Vertical;
}

public sealed class LayoutModeChatMarginConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        // In vertical mode the chat panel sits to the left of the heads column.
        // In horizontal mode the chat panel sits above the heads row.
        return value is ChatHeadsLayoutMode.Horizontal
            ? new Thickness(0, 0, 0, 12)
            : new Thickness(0, 0, 14, 0);
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => new Thickness(0);
}

public sealed class SessionStatusToBrushConverter : IValueConverter
{
    private static readonly Brush WorkingBrush = new SolidColorBrush(Color.FromRgb(0x6F, 0xCF, 0x7A));
    private static readonly Brush ErrorBrush = new SolidColorBrush(Color.FromRgb(0xE3, 0xB5, 0x6E));
    private static readonly Brush ReadyBrush = new SolidColorBrush(Color.FromRgb(0x6F, 0xCF, 0x7A));

    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is SessionState state)
        {
            return state.Kind switch
            {
                SessionStateKind.Running => WorkingBrush,
                SessionStateKind.Error => ErrorBrush,
                _ => ReadyBrush,
            };
        }
        return ReadyBrush;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => SessionState.Idle();
}

public sealed class SessionToStatusVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is ChatSession session)
        {
            var kind = session.State.Kind;
            // Green dot = unread assistant message (e.g. response arrived while the chat panel
            // was closed). Amber dot = error. While running, no dot — the bobble animation is
            // the working indicator.
            if (kind == SessionStateKind.Error || session.HasUnread)
            {
                return Visibility.Visible;
            }
        }
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => false;
}

public sealed class BackendBadgeTextConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not CLIBackend backend) return string.Empty;
        return backend switch
        {
            CLIBackend.Codex => "CX",
            CLIBackend.Copilot => "GH",
            CLIBackend.Claude => "CL",
            _ => string.Empty,
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => CLIBackend.Codex;
}

public sealed class BackendBadgeBackgroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not CLIBackend backend) return Brushes.Transparent;
        return backend switch
        {
            CLIBackend.Codex => new SolidColorBrush(Color.FromRgb(0xDB, 0xEA, 0xFA)),
            CLIBackend.Copilot => new SolidColorBrush(Color.FromRgb(0xE3, 0xF2, 0xE6)),
            CLIBackend.Claude => new SolidColorBrush(Color.FromRgb(0xFA, 0xE7, 0xD6)),
            _ => Brushes.Transparent,
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => CLIBackend.Codex;
}

public sealed class BackendBadgeForegroundConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not CLIBackend backend) return Brushes.Black;
        return backend switch
        {
            CLIBackend.Codex => new SolidColorBrush(Color.FromRgb(0x29, 0x4A, 0x70)),
            CLIBackend.Copilot => new SolidColorBrush(Color.FromRgb(0x1E, 0x50, 0x2E)),
            CLIBackend.Claude => new SolidColorBrush(Color.FromRgb(0x73, 0x3D, 0x14)),
            _ => Brushes.Black,
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => CLIBackend.Codex;
}

public sealed class MessageRoleToMarkdownVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is ChatMessageRole.Assistant ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => ChatMessageRole.Assistant;
}

public sealed class MessageRoleToPlainVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is ChatMessageRole.Assistant ? Visibility.Collapsed : Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => ChatMessageRole.Assistant;
}

public sealed class LayoutModeToToggleIconConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        // Show the icon for the *other* mode (i.e. the mode the user would switch to).
        return value is ChatHeadsLayoutMode.Horizontal ? "\uF0E2" /* Vertical bars */ : "\uF0E4" /* Horizontal bars */;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) => ChatHeadsLayoutMode.Vertical;
}

public sealed class ProviderDisplayConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is CLIBackend backend ? backend.DisplayName() : string.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return CLIBackend.Codex;
    }
}

public sealed class LayoutTitleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is ChatHeadsLayoutMode mode ? mode.MenuTitle() : string.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return ChatHeadsLayoutMode.Vertical;
    }
}

public sealed class MessageRoleToAlignmentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not ChatMessageRole role)
        {
            return HorizontalAlignment.Left;
        }

        return role switch
        {
            ChatMessageRole.User => HorizontalAlignment.Right,
            ChatMessageRole.Assistant => HorizontalAlignment.Left,
            ChatMessageRole.Error => HorizontalAlignment.Stretch,
            ChatMessageRole.System => HorizontalAlignment.Left,
            _ => HorizontalAlignment.Left,
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return ChatMessageRole.Assistant;
    }
}

public sealed class MessageRoleToBubbleBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is not ChatMessageRole role)
        {
            return DesignTokens.AssistantBubbleColor;
        }

        return role switch
        {
            ChatMessageRole.User => DesignTokens.UserBubbleColor,
            ChatMessageRole.Assistant => DesignTokens.AssistantBubbleColor,
            ChatMessageRole.Error => DesignTokens.ErrorBubbleColor,
            ChatMessageRole.System => DesignTokens.SurfaceElevated,
            _ => DesignTokens.AssistantBubbleColor,
        };
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return ChatMessageRole.Assistant;
    }
}

public sealed class NullToCollapsedConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is null ? Visibility.Collapsed : Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return null!;
    }
}

public sealed class NullToVisibleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is null ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return null!;
    }
}

public sealed class BooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        var invert = parameter?.ToString() == "invert";
        var state = value is bool boolean && boolean;
        if (invert)
        {
            state = !state;
        }

        return state ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return false;
    }
}

