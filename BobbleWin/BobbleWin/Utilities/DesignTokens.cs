using Microsoft.UI;
using Microsoft.UI.Xaml.Media;

namespace BobbleWin.Utilities;

public static class DesignTokens
{
    public const double HeadDiameter = 56;
    public const double HeadControlDiameter = HeadDiameter + 8;
    public const double HeadSpacing = 8;
    public const double HeadInset = 14;
    public const double HeadVisualPadding = 8;
    public const double HeadPreviewOverflow = 250;
    public const double AddHistoryControlSpacing = HeadSpacing + 12;
    public const double VerticalControlSpacing = HeadSpacing + (HeadVisualPadding / 2);
    public const double DeckOffset = 14;
    public const int MaxHorizontalCollapsedVisibleHeads = 18;
    public const int MaxHorizontalExpandedDeckHeadsPerSide = 12;
    public const double ScreenMargin = 16;

    public static readonly SolidColorBrush SurfaceColor = new(ColorFromHex("#FF25221F"));
    public static readonly SolidColorBrush SurfaceElevated = new(ColorFromHex("#FF2E2A26"));
    public static readonly SolidColorBrush SurfaceAccent = new(ColorFromHex("#FF7A6B5D"));
    public static readonly SolidColorBrush BorderColor = new(ColorFromHex("#FF544A41"));
    public static readonly SolidColorBrush TextPrimary = new(ColorFromHex("#FFF3E9DF"));
    public static readonly SolidColorBrush TextSecondary = new(ColorFromHex("#FFD0BFB2"));

    public static readonly SolidColorBrush UserBubbleColor = new(ColorFromHex("#FF6E5A4B"));
    public static readonly SolidColorBrush AssistantBubbleColor = new(ColorFromHex("#FF3A342F"));
    public static readonly SolidColorBrush ErrorBubbleColor = new(ColorFromHex("#FF5B2E2E"));

    private static Color ColorFromHex(string hex)
    {
        hex = hex.TrimStart('#');
        if (hex.Length != 8)
        {
            return Colors.White;
        }

        return Color.FromArgb(
            Convert.ToByte(hex.Substring(0, 2), 16),
            Convert.ToByte(hex.Substring(2, 2), 16),
            Convert.ToByte(hex.Substring(4, 2), 16),
            Convert.ToByte(hex.Substring(6, 2), 16));
    }
}
