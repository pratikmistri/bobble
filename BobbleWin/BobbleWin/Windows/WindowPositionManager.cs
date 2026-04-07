using BobbleWin.Models;
using BobbleWin.Utilities;

namespace BobbleWin.Windows;

public enum PanelDockSide
{
    Leading,
    Trailing,
}

public sealed class WindowPositionManager
{
    private const double ChatWidth = 320;
    private const double ChatHeight = 480;

    public (double Width, double Height) CollapsedPanelSize(int count, ChatHeadsLayoutMode layoutMode)
    {
        var safeCount = Math.Max(count, 0);
        return layoutMode switch
        {
            ChatHeadsLayoutMode.Vertical => CollapsedVertical(safeCount),
            ChatHeadsLayoutMode.Horizontal => CollapsedHorizontal(safeCount),
            _ => CollapsedVertical(safeCount),
        };
    }

    public (double Width, double Height) ExpandedPanelSize(int headsCount, int? expandedIndex, ChatHeadsLayoutMode layoutMode)
    {
        var safeCount = Math.Max(headsCount, 0);
        return layoutMode switch
        {
            ChatHeadsLayoutMode.Vertical => ExpandedVertical(safeCount, expandedIndex),
            ChatHeadsLayoutMode.Horizontal => ExpandedHorizontal(safeCount, expandedIndex),
            _ => ExpandedVertical(safeCount, expandedIndex),
        };
    }

    private static (double Width, double Height) CollapsedVertical(int count)
    {
        var inset = DesignTokens.HeadInset * 2;
        var add = DesignTokens.HeadControlDiameter;
        var history = DesignTokens.HeadControlDiameter;
        var stack = count > 0
            ? DesignTokens.HeadControlDiameter * count + DesignTokens.HeadSpacing * (count - 1)
            : 0;

        var rows = new List<double> { add, history };
        if (stack > 0)
        {
            rows.Add(stack);
        }

        var spacing = DesignTokens.AddHistoryControlSpacing
            + Math.Max(rows.Count - 2, 0) * DesignTokens.VerticalControlSpacing;
        var height = inset + rows.Sum() + spacing;
        var width = inset + DesignTokens.HeadDiameter + DesignTokens.HeadVisualPadding + DesignTokens.HeadPreviewOverflow;
        return (width, height);
    }

    private static (double Width, double Height) CollapsedHorizontal(int count)
    {
        var inset = DesignTokens.HeadInset * 2;
        var visibleCount = Math.Min(count, DesignTokens.MaxHorizontalCollapsedVisibleHeads);
        var stack = visibleCount > 0
            ? DesignTokens.HeadControlDiameter * visibleCount + DesignTokens.HeadSpacing * (visibleCount - 1)
            : 0;

        var columns = new List<double> { DesignTokens.HeadControlDiameter, DesignTokens.HeadControlDiameter };
        if (stack > 0)
        {
            columns.Add(stack);
        }

        var spacing = DesignTokens.AddHistoryControlSpacing + Math.Max(columns.Count - 2, 0) * DesignTokens.HeadSpacing;
        var width = inset + columns.Sum() + spacing + DesignTokens.HeadPreviewOverflow;
        var height = inset + DesignTokens.HeadControlDiameter;
        return (width, height);
    }

    private static (double Width, double Height) ExpandedVertical(int count, int? expandedIndex)
    {
        var inset = DesignTokens.HeadInset * 2;
        var safeIndex = expandedIndex.HasValue && count > 0 ? Math.Clamp(expandedIndex.Value, 0, count - 1) : 0;
        var above = Math.Max(safeIndex, 0);
        var below = Math.Max(count - safeIndex - 1, 0);

        var topDeck = above > 0 ? DesignTokens.HeadDiameter + (above - 1) * DesignTokens.DeckOffset + DesignTokens.HeadVisualPadding : 0;
        var bottomDeck = below > 0 ? DesignTokens.HeadDiameter + (below - 1) * DesignTokens.DeckOffset + DesignTokens.HeadVisualPadding : 0;

        var rows = new List<double>
        {
            DesignTokens.HeadControlDiameter,
            DesignTokens.HeadControlDiameter,
        };
        if (topDeck > 0)
        {
            rows.Add(topDeck);
        }
        rows.Add(ChatHeight);
        if (bottomDeck > 0)
        {
            rows.Add(bottomDeck);
        }

        var spacing = DesignTokens.AddHistoryControlSpacing + Math.Max(rows.Count - 2, 0) * DesignTokens.VerticalControlSpacing;
        var height = inset + rows.Sum() + spacing;
        var width = inset + ChatWidth + DesignTokens.HeadPreviewOverflow;
        return (width, height);
    }

    private static (double Width, double Height) ExpandedHorizontal(int count, int? expandedIndex)
    {
        var inset = DesignTokens.HeadInset * 2;
        var safeIndex = expandedIndex.HasValue && count > 0 ? Math.Clamp(expandedIndex.Value, 0, count - 1) : 0;

        var before = Math.Min(Math.Max(safeIndex, 0), DesignTokens.MaxHorizontalExpandedDeckHeadsPerSide);
        var after = Math.Min(Math.Max(count - safeIndex - 1, 0), DesignTokens.MaxHorizontalExpandedDeckHeadsPerSide);

        var beforeDeck = before > 0 ? DesignTokens.HeadDiameter + (before - 1) * DesignTokens.DeckOffset + DesignTokens.HeadVisualPadding : 0;
        var afterDeck = after > 0 ? DesignTokens.HeadDiameter + (after - 1) * DesignTokens.DeckOffset + DesignTokens.HeadVisualPadding : 0;

        var columns = new List<double>
        {
            DesignTokens.HeadControlDiameter,
            DesignTokens.HeadControlDiameter,
        };
        if (beforeDeck > 0)
        {
            columns.Add(beforeDeck);
        }
        columns.Add(ChatWidth);
        if (afterDeck > 0)
        {
            columns.Add(afterDeck);
        }

        var spacing = DesignTokens.AddHistoryControlSpacing + Math.Max(columns.Count - 2, 0) * DesignTokens.HeadSpacing;
        var width = inset + columns.Sum() + spacing + DesignTokens.HeadPreviewOverflow;
        var height = inset + Math.Max(ChatHeight, DesignTokens.HeadControlDiameter);
        return (width, height);
    }
}
