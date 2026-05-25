using BobbleWin.Models;
using BobbleWin.Utilities;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

using HorizontalAlignment = System.Windows.HorizontalAlignment;

namespace BobbleWin.Views;

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

