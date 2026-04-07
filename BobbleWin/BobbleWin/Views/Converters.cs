using BobbleWin.Models;
using BobbleWin.Utilities;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;
using Microsoft.UI.Xaml.Media;

namespace BobbleWin.Views;

public sealed class ProviderDisplayConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is CLIBackend backend ? backend.DisplayName() : string.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return CLIBackend.Codex;
    }
}

public sealed class LayoutTitleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is ChatHeadsLayoutMode mode ? mode.MenuTitle() : string.Empty;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return ChatHeadsLayoutMode.Vertical;
    }
}

public sealed class MessageRoleToAlignmentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
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

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return ChatMessageRole.Assistant;
    }
}

public sealed class MessageRoleToBubbleBrushConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
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

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return ChatMessageRole.Assistant;
    }
}

public sealed class NullToCollapsedConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is null ? Visibility.Collapsed : Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return null!;
    }
}

public sealed class NullToVisibleConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        return value is null ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return null!;
    }
}

public sealed class BooleanToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, string language)
    {
        var invert = parameter?.ToString() == "invert";
        var state = value is bool boolean && boolean;
        if (invert)
        {
            state = !state;
        }

        return state ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
    {
        return false;
    }
}
