namespace BobbleWin.Models;

public enum ProviderModelOption
{
    Automatic,
    GPT5Codex,
    GPT53Codex,
    GPT52Codex,
    GPT51Codex,
    GPT51CodexMax,
    GPT51CodexMini,
    ClaudeSonnet46,
    ClaudeOpus46,
    ClaudeHaiku45,
    CopilotClaudeSonnet45,
    CopilotClaudeOpus45,
    CopilotClaudeOpus46,
    CopilotGPT51CodexMax,
    CopilotGPT52Codex,
}

public sealed record ProviderModelMetadata(
    HashSet<CLIBackend> AvailableProviders,
    string RawValue,
    string DisplayName,
    string ShortLabel,
    string CodexSubtitle,
    string ClaudeSubtitle,
    string CopilotSubtitle);

public static class ProviderModelOptionExtensions
{
    private static readonly Dictionary<ProviderModelOption, ProviderModelMetadata> Catalog = new()
    {
        [ProviderModelOption.Automatic] = new(
            [CLIBackend.Codex, CLIBackend.Claude, CLIBackend.Copilot],
            "default",
            "Auto",
            "Auto",
            "Use the Codex CLI default model.",
            "Use Claude Code's default model.",
            "Use GitHub Copilot's default model."),
        [ProviderModelOption.GPT5Codex] = new([CLIBackend.Codex], "gpt-5-codex", "GPT-5 Codex", "5 Codex", "General-purpose Codex-optimized coding model.", "", ""),
        [ProviderModelOption.GPT53Codex] = new([CLIBackend.Codex], "gpt-5.3-codex", "GPT-5.3 Codex", "5.3 Codex", "Most capable current Codex model.", "", ""),
        [ProviderModelOption.GPT52Codex] = new([CLIBackend.Codex], "gpt-5.2-codex", "GPT-5.2 Codex", "5.2 Codex", "Strong long-horizon coding model.", "", ""),
        [ProviderModelOption.GPT51Codex] = new([CLIBackend.Codex], "gpt-5.1-codex", "GPT-5.1 Codex", "5.1 Codex", "Balanced GPT-5.1 coding model.", "", ""),
        [ProviderModelOption.GPT51CodexMax] = new([CLIBackend.Codex], "gpt-5.1-codex-max", "GPT-5.1 Codex Max", "5.1 Max", "GPT-5.1 Codex variant for longer-running tasks.", "", ""),
        [ProviderModelOption.GPT51CodexMini] = new([CLIBackend.Codex], "gpt-5.1-codex-mini", "GPT-5.1 Codex Mini", "5.1 Mini", "Smaller, cheaper GPT-5.1 Codex variant.", "", ""),
        [ProviderModelOption.ClaudeSonnet46] = new([CLIBackend.Claude], "claude-sonnet-4-6", "Claude Sonnet 4.6", "Sonnet 4.6", "", "Balanced Claude model for most coding tasks.", ""),
        [ProviderModelOption.ClaudeOpus46] = new([CLIBackend.Claude], "claude-opus-4-6", "Claude Opus 4.6", "Opus 4.6", "", "Most capable Claude model for harder tasks.", ""),
        [ProviderModelOption.ClaudeHaiku45] = new([CLIBackend.Claude], "claude-haiku-4-5", "Claude Haiku 4.5", "Haiku 4.5", "", "Fast Claude model for lighter requests.", ""),
        [ProviderModelOption.CopilotClaudeSonnet45] = new([CLIBackend.Copilot], "Claude Sonnet 4.5", "Claude Sonnet 4.5", "Sonnet 4.5", "", "", "Balanced Copilot coding-agent model."),
        [ProviderModelOption.CopilotClaudeOpus45] = new([CLIBackend.Copilot], "Claude Opus 4.5", "Claude Opus 4.5", "Opus 4.5", "", "", "Stronger Anthropic model available in Copilot."),
        [ProviderModelOption.CopilotClaudeOpus46] = new([CLIBackend.Copilot], "Claude Opus 4.6", "Claude Opus 4.6", "Opus 4.6", "", "", "Most capable Anthropic option currently listed for Copilot."),
        [ProviderModelOption.CopilotGPT51CodexMax] = new([CLIBackend.Copilot], "GPT-5.1-Codex-Max", "GPT-5.1 Codex Max", "5.1 Max", "", "", "OpenAI Codex model for deeper coding tasks."),
        [ProviderModelOption.CopilotGPT52Codex] = new([CLIBackend.Copilot], "GPT-5.2-Codex", "GPT-5.2 Codex", "5.2 Codex", "", "", "Newer Codex option available through Copilot."),
    };

    public static IReadOnlyList<ProviderModelOption> AvailableOptions(CLIBackend provider)
    {
        return Enum.GetValues<ProviderModelOption>()
            .Where(option => Catalog[option].AvailableProviders.Contains(provider))
            .ToList();
    }

    public static ProviderModelOption Normalized(this ProviderModelOption option, CLIBackend provider)
    {
        return option.IsAvailable(provider) ? option : ProviderModelOption.Automatic;
    }

    public static bool IsAvailable(this ProviderModelOption option, CLIBackend provider)
    {
        return Catalog[option].AvailableProviders.Contains(provider);
    }

    public static string DisplayName(this ProviderModelOption option, CLIBackend provider)
    {
        return Catalog[option].DisplayName;
    }

    public static string ShortLabel(this ProviderModelOption option, CLIBackend provider)
    {
        return Catalog[option].ShortLabel;
    }

    public static string Subtitle(this ProviderModelOption option, CLIBackend provider)
    {
        var metadata = Catalog[option];
        return provider switch
        {
            CLIBackend.Codex => metadata.CodexSubtitle,
            CLIBackend.Claude => metadata.ClaudeSubtitle,
            CLIBackend.Copilot => metadata.CopilotSubtitle,
            _ => string.Empty,
        };
    }

    public static string? CliValue(this ProviderModelOption option, CLIBackend provider)
    {
        if (!option.IsAvailable(provider) || option == ProviderModelOption.Automatic)
        {
            return null;
        }

        return Catalog[option].RawValue;
    }

    public static string RawValue(this ProviderModelOption option)
    {
        return Catalog[option].RawValue;
    }

    public static ProviderModelOption FromRawValue(string? rawValue)
    {
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            return ProviderModelOption.Automatic;
        }

        var match = Catalog.FirstOrDefault(item => string.Equals(item.Value.RawValue, rawValue, StringComparison.OrdinalIgnoreCase));
        return match.Equals(default(KeyValuePair<ProviderModelOption, ProviderModelMetadata>))
            ? ProviderModelOption.Automatic
            : match.Key;
    }
}
