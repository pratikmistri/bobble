namespace BobbleWin.Models;

public enum ChatHeadsLayoutMode
{
    Vertical,
    Horizontal,
}

public static class ChatHeadsLayoutModeExtensions
{
    public static string RawValue(this ChatHeadsLayoutMode value) => value switch
    {
        ChatHeadsLayoutMode.Vertical => "vertical",
        ChatHeadsLayoutMode.Horizontal => "horizontal",
        _ => "vertical",
    };

    public static string MenuTitle(this ChatHeadsLayoutMode value) => value switch
    {
        ChatHeadsLayoutMode.Vertical => "Vertical",
        ChatHeadsLayoutMode.Horizontal => "Horizontal",
        _ => "Vertical",
    };

    public static ChatHeadsLayoutMode FromRawValue(string? value)
    {
        return value?.Trim().ToLowerInvariant() switch
        {
            "horizontal" => ChatHeadsLayoutMode.Horizontal,
            _ => ChatHeadsLayoutMode.Vertical,
        };
    }
}
