using System.Text;
using System.Text.Json;
using BobbleWin.Models;

namespace BobbleWin.Process;

public sealed class StreamParser
{
    private readonly CLIBackend _backend;
    private readonly StringBuilder _buffer = new();
    private readonly StringBuilder _codexAccumulatedText = new();
    private readonly StringBuilder _copilotAccumulatedText = new();

    private bool _claudeDidStreamDelta;
    private bool _claudeDidEmitFinalResult;

    public event Action<string>? OnTextDelta;
    public event Action<string>? OnResult;
    public event Action<string>? OnSessionId;
    public event Action<string>? OnEventText;
    public event Action? OnAssistantMessageStarted;
    public event Action? OnTurnCompleted;

    public StreamParser(CLIBackend backend)
    {
        _backend = backend;
    }

    public void Feed(string text)
    {
        if (_backend == CLIBackend.Copilot)
        {
            ProcessCopilotData(text);
            return;
        }

        _buffer.Append(text);

        while (true)
        {
            var current = _buffer.ToString();
            var newlineIndex = current.IndexOf('\n');
            if (newlineIndex < 0)
            {
                break;
            }

            var line = current[..newlineIndex];
            _buffer.Clear();
            _buffer.Append(current[(newlineIndex + 1)..]);

            if (line.Length == 0)
            {
                continue;
            }

            ProcessLine(line);
        }
    }

    public void Finish()
    {
        if (_backend == CLIBackend.Copilot)
        {
            if (_buffer.Length > 0)
            {
                ProcessCopilotData(string.Empty);
            }

            var finalText = _copilotAccumulatedText.ToString().Trim();
            if (finalText.Length > 0)
            {
                OnResult?.Invoke(finalText);
            }

            _copilotAccumulatedText.Clear();
            return;
        }

        if (_buffer.Length == 0)
        {
            return;
        }

        var trailing = _buffer.ToString();
        _buffer.Clear();
        ProcessLine(trailing);
    }

    private void ProcessLine(string line)
    {
        switch (_backend)
        {
            case CLIBackend.Claude:
                ProcessClaudeLine(line);
                break;
            case CLIBackend.Codex:
                ProcessCodexLine(line);
                break;
        }
    }

    private void ProcessCopilotData(string text)
    {
        _buffer.Append(text);
        var content = _buffer.ToString();
        if (content.Length == 0)
        {
            return;
        }

        _buffer.Clear();
        _copilotAccumulatedText.Append(content);
        OnAssistantMessageStarted?.Invoke();
        OnTextDelta?.Invoke(content);
    }

    private void ProcessClaudeLine(string line)
    {
        JsonDocument? document;
        try
        {
            document = JsonDocument.Parse(line);
        }
        catch
        {
            var normalized = line.ToLowerInvariant();
            if (normalized.Contains("permission", StringComparison.Ordinal)
                || normalized.Contains("approval", StringComparison.Ordinal)
                || normalized.Contains("question", StringComparison.Ordinal)
                || normalized.Contains("user input", StringComparison.Ordinal)
                || normalized.Contains("sendusermessage", StringComparison.Ordinal))
            {
                OnEventText?.Invoke(line);
            }
            else
            {
                OnTextDelta?.Invoke(line);
            }
            return;
        }

        using (document)
        {
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var typeElement) || typeElement.ValueKind != JsonValueKind.String)
            {
                if (root.TryGetProperty("result", out var resultElement) && resultElement.ValueKind == JsonValueKind.String)
                {
                    if (!_claudeDidEmitFinalResult)
                    {
                        _claudeDidEmitFinalResult = true;
                        OnResult?.Invoke(resultElement.GetString() ?? string.Empty);
                    }
                }
                return;
            }

            var type = typeElement.GetString() ?? string.Empty;
            var normalizedType = type.ToLowerInvariant();
            if (normalizedType.Contains("permission", StringComparison.Ordinal)
                || normalizedType.Contains("approval", StringComparison.Ordinal)
                || normalizedType.Contains("question", StringComparison.Ordinal)
                || normalizedType.Contains("user_input", StringComparison.Ordinal)
                || normalizedType.Contains("sendusermessage", StringComparison.Ordinal))
            {
                var rendered = RenderClaudeEvent(type, root);
                if (!string.IsNullOrWhiteSpace(rendered))
                {
                    OnEventText?.Invoke(rendered);
                }
                return;
            }

            switch (type)
            {
                case "content_block_delta":
                    if (root.TryGetProperty("delta", out var deltaElement)
                        && deltaElement.ValueKind == JsonValueKind.Object
                        && deltaElement.TryGetProperty("text", out var textElement)
                        && textElement.ValueKind == JsonValueKind.String)
                    {
                        var deltaText = textElement.GetString() ?? string.Empty;
                        if (deltaText.Length > 0)
                        {
                            _claudeDidStreamDelta = true;
                            OnTextDelta?.Invoke(deltaText);
                        }
                    }
                    break;

                case "assistant":
                    if (_claudeDidStreamDelta)
                    {
                        break;
                    }

                    var assistantText = ExtractClaudeText(root);
                    if (assistantText.Length > 0 && !_claudeDidEmitFinalResult)
                    {
                        _claudeDidEmitFinalResult = true;
                        OnResult?.Invoke(assistantText);
                    }
                    break;

                case "result":
                    if (root.TryGetProperty("result", out var resultTextElement)
                        && resultTextElement.ValueKind == JsonValueKind.String)
                    {
                        var resultText = resultTextElement.GetString() ?? string.Empty;
                        if (!_claudeDidEmitFinalResult)
                        {
                            _claudeDidEmitFinalResult = true;
                            OnResult?.Invoke(resultText);
                        }
                    }

                    if (!_claudeDidEmitFinalResult)
                    {
                        var extracted = ExtractClaudeText(root);
                        if (extracted.Length > 0)
                        {
                            _claudeDidEmitFinalResult = true;
                            OnResult?.Invoke(extracted);
                        }
                    }
                    break;
            }
        }
    }

    private void ProcessCodexLine(string line)
    {
        JsonDocument? document;
        try
        {
            document = JsonDocument.Parse(line);
        }
        catch
        {
            return;
        }

        using (document)
        {
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var typeElement) || typeElement.ValueKind != JsonValueKind.String)
            {
                return;
            }

            var type = typeElement.GetString() ?? string.Empty;
            switch (type)
            {
                case "thread.started":
                    if (root.TryGetProperty("thread_id", out var threadIdElement) && threadIdElement.ValueKind == JsonValueKind.String)
                    {
                        OnSessionId?.Invoke(threadIdElement.GetString() ?? string.Empty);
                    }
                    else if (root.TryGetProperty("thread", out var threadElement)
                             && threadElement.ValueKind == JsonValueKind.Object
                             && threadElement.TryGetProperty("id", out var nestedIdElement)
                             && nestedIdElement.ValueKind == JsonValueKind.String)
                    {
                        OnSessionId?.Invoke(nestedIdElement.GetString() ?? string.Empty);
                    }
                    break;

                case "turn.started":
                    _codexAccumulatedText.Clear();
                    break;

                case "agent_message.delta":
                    if (root.TryGetProperty("delta", out var deltaElement) && deltaElement.ValueKind == JsonValueKind.String)
                    {
                        var delta = deltaElement.GetString() ?? string.Empty;
                        if (delta.Length > 0)
                        {
                            _codexAccumulatedText.Append(delta);
                            OnTextDelta?.Invoke(delta);
                        }
                    }
                    break;

                case "item.started":
                    if (root.TryGetProperty("item", out var startedItem) && startedItem.ValueKind == JsonValueKind.Object)
                    {
                        if (startedItem.TryGetProperty("type", out var startedType) && startedType.ValueKind == JsonValueKind.String
                            && startedType.GetString() == "agent_message")
                        {
                            _codexAccumulatedText.Clear();
                            OnAssistantMessageStarted?.Invoke();
                            return;
                        }

                        var renderedItem = RenderCodexItem(type, startedItem);
                        if (!string.IsNullOrWhiteSpace(renderedItem))
                        {
                            OnEventText?.Invoke(renderedItem);
                        }
                    }
                    break;

                case "item.completed":
                    if (root.TryGetProperty("item", out var completedItem) && completedItem.ValueKind == JsonValueKind.Object)
                    {
                        if (completedItem.TryGetProperty("type", out var completedType)
                            && completedType.ValueKind == JsonValueKind.String
                            && completedType.GetString() == "agent_message"
                            && completedItem.TryGetProperty("text", out var fullText)
                            && fullText.ValueKind == JsonValueKind.String)
                        {
                            OnResult?.Invoke(fullText.GetString() ?? string.Empty);
                            _codexAccumulatedText.Clear();
                        }
                        else
                        {
                            var renderedItem = RenderCodexItem(type, completedItem);
                            if (!string.IsNullOrWhiteSpace(renderedItem))
                            {
                                OnEventText?.Invoke(renderedItem);
                            }
                        }
                    }
                    else
                    {
                        var rendered = RenderCodexEvent(type, root);
                        if (!string.IsNullOrWhiteSpace(rendered))
                        {
                            OnEventText?.Invoke(rendered);
                        }
                    }
                    break;

                case "turn.completed":
                    OnTurnCompleted?.Invoke();
                    break;

                case "error":
                case "turn.failed":
                    var renderedError = RenderCodexEvent(type, root);
                    if (!string.IsNullOrWhiteSpace(renderedError))
                    {
                        OnEventText?.Invoke(renderedError);
                    }
                    break;

                default:
                    var renderedDefault = RenderCodexEvent(type, root);
                    if (!string.IsNullOrWhiteSpace(renderedDefault))
                    {
                        OnEventText?.Invoke(renderedDefault);
                    }
                    break;
            }
        }
    }

    private static string ExtractClaudeText(JsonElement payload)
    {
        var builder = new StringBuilder();

        if (payload.TryGetProperty("message", out var message)
            && message.ValueKind == JsonValueKind.Object
            && message.TryGetProperty("content", out var content)
            && content.ValueKind == JsonValueKind.Array)
        {
            AppendTextBlocks(builder, content);
        }

        if (payload.TryGetProperty("content", out var rootContent) && rootContent.ValueKind == JsonValueKind.Array)
        {
            AppendTextBlocks(builder, rootContent);
        }

        return builder.ToString().Trim();
    }

    private static void AppendTextBlocks(StringBuilder builder, JsonElement blocks)
    {
        foreach (var block in blocks.EnumerateArray())
        {
            if (block.ValueKind == JsonValueKind.Object
                && block.TryGetProperty("text", out var text)
                && text.ValueKind == JsonValueKind.String)
            {
                builder.Append(text.GetString());
            }
        }
    }

    private static string? RenderClaudeEvent(string type, JsonElement payload)
    {
        var title = $"Claude {Humanize(type)}";
        var details = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }).Trim();
        return details.Length == 0 ? title : $"{title}\nDetails:\n{details}";
    }

    private static string? RenderCodexItem(string eventType, JsonElement item)
    {
        if (!item.TryGetProperty("type", out var itemTypeElement) || itemTypeElement.ValueKind != JsonValueKind.String)
        {
            return null;
        }

        var itemType = itemTypeElement.GetString() ?? string.Empty;
        var itemTypeKey = itemType.ToLowerInvariant();

        if (itemTypeKey == "command_execution" || (itemTypeKey.Contains("command", StringComparison.Ordinal) && itemTypeKey.Contains("execution", StringComparison.Ordinal)))
        {
            var command = item.TryGetProperty("command", out var commandElement) && commandElement.ValueKind == JsonValueKind.String
                ? commandElement.GetString()?.Trim() ?? "(unknown command)"
                : "(unknown command)";
            var status = item.TryGetProperty("status", out var statusElement) && statusElement.ValueKind == JsonValueKind.String
                ? statusElement.GetString()?.Trim() ?? "in_progress"
                : "in_progress";

            var lines = new List<string>();
            if (eventType == "item.started" || status == "in_progress")
            {
                lines.Add($"Running command: `{command}`");
            }
            else
            {
                lines.Add($"Command {status}: `{command}`");
                if (item.TryGetProperty("exit_code", out var exitCodeElement) && exitCodeElement.ValueKind == JsonValueKind.Number)
                {
                    lines.Add($"Exit code: {exitCodeElement.GetInt32()}");
                }

                var output = item.TryGetProperty("aggregated_output", out var outputElement) && outputElement.ValueKind == JsonValueKind.String
                    ? SanitizeMultiline(outputElement.GetString())
                    : null;
                if (!string.IsNullOrWhiteSpace(output))
                {
                    lines.Add($"Output:\n{output}");
                }
            }

            return string.Join("\n", lines);
        }

        if (itemTypeKey.Contains("approval", StringComparison.Ordinal)
            || itemTypeKey.Contains("permission", StringComparison.Ordinal)
            || itemTypeKey.Contains("request_user_input", StringComparison.Ordinal)
            || itemTypeKey.Contains("user_input", StringComparison.Ordinal)
            || itemTypeKey.Contains("question", StringComparison.Ordinal)
            || itemTypeKey.Contains("answer", StringComparison.Ordinal))
        {
            var title = $"Codex {Humanize(itemType)}";
            var body = CompactJson(item);
            return string.IsNullOrWhiteSpace(body) ? title : $"{title}\nDetails:\n{body}";
        }

        if (itemTypeKey.Contains("reasoning", StringComparison.Ordinal) || itemTypeKey.Contains("thought", StringComparison.Ordinal))
        {
            var title = "Agent thought";
            var body = CompactJson(item);
            return string.IsNullOrWhiteSpace(body) ? title : $"{title}\nDetails:\n{body}";
        }

        return null;
    }

    private static string? RenderCodexEvent(string type, JsonElement payload)
    {
        var eventKey = type.ToLowerInvariant();
        var isRelevant = eventKey.Contains("approval", StringComparison.Ordinal)
            || eventKey.Contains("permission", StringComparison.Ordinal)
            || eventKey.Contains("request_user_input", StringComparison.Ordinal)
            || eventKey.Contains("user_input", StringComparison.Ordinal)
            || eventKey.Contains("question", StringComparison.Ordinal)
            || eventKey.Contains("answer", StringComparison.Ordinal)
            || eventKey == "error"
            || eventKey == "turn.failed"
            || eventKey.Contains("reasoning", StringComparison.Ordinal)
            || eventKey.Contains("thought", StringComparison.Ordinal);

        if (!isRelevant)
        {
            return null;
        }

        var title = eventKey.Contains("reasoning", StringComparison.Ordinal) || eventKey.Contains("thought", StringComparison.Ordinal)
            ? "Agent thought"
            : $"Codex {Humanize(type)}";
        var body = CompactJson(payload);
        return string.IsNullOrWhiteSpace(body) ? title : $"{title}\nDetails:\n{body}";
    }

    private static string CompactJson(JsonElement element)
    {
        var text = JsonSerializer.Serialize(element, new JsonSerializerOptions { WriteIndented = true });
        if (text.Length > 3000)
        {
            return text[..3000] + "\n... (truncated)";
        }
        return text;
    }

    private static string Humanize(string value)
    {
        return value
            .Replace('.', ' ')
            .Replace('_', ' ')
            .Trim();
    }

    private static string? SanitizeMultiline(string? text)
    {
        if (string.IsNullOrWhiteSpace(text))
        {
            return null;
        }

        var trimmed = text.Trim();
        if (trimmed.Length > 2500)
        {
            return trimmed[..2500] + "\n... (truncated)";
        }
        return trimmed;
    }
}
