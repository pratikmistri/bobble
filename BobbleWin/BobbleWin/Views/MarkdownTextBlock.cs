using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using FontFamily = System.Windows.Media.FontFamily;
using Color = System.Windows.Media.Color;

namespace BobbleWin.Views;

/// <summary>
/// Lightweight markdown renderer for streaming assistant messages.
/// Supports headings (#…######), bold (**…**), italic (*…* / _…_), inline code (`…`),
/// fenced code blocks (```…```), block quotes (&gt;), unordered lists (- / *)
/// and ordered lists (1.). Re-renders on every Text change so it is safe to bind
/// to a streaming Content property.
/// </summary>
public sealed class MarkdownTextBlock : ItemsControl
{
    public static readonly DependencyProperty MarkdownProperty = DependencyProperty.Register(
        nameof(Markdown),
        typeof(string),
        typeof(MarkdownTextBlock),
        new PropertyMetadata(string.Empty, OnMarkdownChanged));

    public static readonly DependencyProperty ForegroundBrushProperty = DependencyProperty.Register(
        nameof(ForegroundBrush),
        typeof(Brush),
        typeof(MarkdownTextBlock),
        new PropertyMetadata(Brushes.White, (d, _) => ((MarkdownTextBlock)d).Rebuild()));

    public static readonly DependencyProperty SecondaryBrushProperty = DependencyProperty.Register(
        nameof(SecondaryBrush),
        typeof(Brush),
        typeof(MarkdownTextBlock),
        new PropertyMetadata(new SolidColorBrush(Color.FromRgb(0xD0, 0xBF, 0xB2)), (d, _) => ((MarkdownTextBlock)d).Rebuild()));

    public string Markdown
    {
        get => (string)GetValue(MarkdownProperty);
        set => SetValue(MarkdownProperty, value);
    }

    public Brush ForegroundBrush
    {
        get => (Brush)GetValue(ForegroundBrushProperty);
        set => SetValue(ForegroundBrushProperty, value);
    }

    public Brush SecondaryBrush
    {
        get => (Brush)GetValue(SecondaryBrushProperty);
        set => SetValue(SecondaryBrushProperty, value);
    }

    public MarkdownTextBlock()
    {
        ItemsPanel = new ItemsPanelTemplate(new FrameworkElementFactory(typeof(StackPanel)));
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(0);
    }

    private static void OnMarkdownChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((MarkdownTextBlock)d).Rebuild();
    }

    private void Rebuild()
    {
        Items.Clear();
        var blocks = MarkdownParser.Parse(Markdown ?? string.Empty);
        foreach (var block in blocks)
        {
            var element = RenderBlock(block);
            if (element is not null)
            {
                Items.Add(element);
            }
        }
    }

    private UIElement? RenderBlock(MarkdownBlock block)
    {
        switch (block)
        {
            case MarkdownBlock.Heading heading:
                return BuildParagraphTextBlock(heading.Text, headingLevel: heading.Level);
            case MarkdownBlock.Paragraph paragraph:
                return BuildParagraphTextBlock(paragraph.Text);
            case MarkdownBlock.UnorderedList ul:
                return BuildList(ul.Items, ordered: false);
            case MarkdownBlock.OrderedList ol:
                return BuildList(ol.Items, ordered: true);
            case MarkdownBlock.Quote quote:
                return BuildQuote(quote.Lines);
            case MarkdownBlock.CodeBlock code:
                return BuildCodeBlock(code.Language, code.Content);
            default:
                return null;
        }
    }

    private TextBlock BuildParagraphTextBlock(string text, int? headingLevel = null)
    {
        var tb = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Foreground = ForegroundBrush,
            Margin = new Thickness(0, 0, 0, 4),
        };

        if (headingLevel is int level)
        {
            tb.FontWeight = FontWeights.SemiBold;
            tb.FontSize = level switch
            {
                1 => 17,
                2 => 15,
                _ => 14,
            };
        }

        AddInlines(tb.Inlines, text);
        return tb;
    }

    private UIElement BuildList(IReadOnlyList<string> items, bool ordered)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 4) };
        for (int i = 0; i < items.Count; i++)
        {
            var row = new Grid { Margin = new Thickness(0, 2, 0, 0) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(22) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

            var marker = new TextBlock
            {
                Text = ordered ? $"{i + 1}." : "•",
                Foreground = SecondaryBrush,
                FontWeight = FontWeights.SemiBold,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Right,
                Margin = new Thickness(0, 0, 6, 0),
            };
            Grid.SetColumn(marker, 0);
            row.Children.Add(marker);

            var content = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap,
                Foreground = ForegroundBrush,
            };
            AddInlines(content.Inlines, items[i]);
            Grid.SetColumn(content, 1);
            row.Children.Add(content);

            panel.Children.Add(row);
        }
        return panel;
    }

    private UIElement BuildQuote(IReadOnlyList<string> lines)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 0, 0, 4) };
        foreach (var line in lines)
        {
            var tb = new TextBlock
            {
                TextWrapping = TextWrapping.Wrap,
                Foreground = SecondaryBrush,
                FontStyle = FontStyles.Italic,
                Margin = new Thickness(8, 2, 0, 2),
            };
            AddInlines(tb.Inlines, line);
            panel.Children.Add(tb);
        }

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var bar = new Border
        {
            Background = new SolidColorBrush(Color.FromRgb(0x54, 0x4A, 0x41)),
            CornerRadius = new CornerRadius(2),
            Margin = new Thickness(0, 2, 6, 2),
        };
        Grid.SetColumn(bar, 0);
        grid.Children.Add(bar);

        Grid.SetColumn(panel, 1);
        grid.Children.Add(panel);
        return grid;
    }

    private UIElement BuildCodeBlock(string? language, string content)
    {
        var panel = new StackPanel { Margin = new Thickness(0, 2, 0, 6) };

        if (!string.IsNullOrWhiteSpace(language))
        {
            panel.Children.Add(new TextBlock
            {
                Text = language!.ToUpperInvariant(),
                FontSize = 10,
                FontWeight = FontWeights.SemiBold,
                Foreground = SecondaryBrush,
                Margin = new Thickness(2, 0, 0, 2),
            });
        }

        var codeText = new TextBlock
        {
            Text = content,
            FontFamily = new FontFamily("Consolas, Cascadia Code, Menlo, monospace"),
            FontSize = 12,
            Foreground = ForegroundBrush,
            TextWrapping = TextWrapping.NoWrap,
        };

        var border = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(0xE6, 0x25, 0x22, 0x1F)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0xB3, 0x54, 0x4A, 0x41)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(10),
            Child = new ScrollViewer
            {
                HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
                VerticalScrollBarVisibility = ScrollBarVisibility.Disabled,
                Content = codeText,
                Background = Brushes.Transparent,
                BorderThickness = new Thickness(0),
            },
        };
        panel.Children.Add(border);
        return panel;
    }

    private void AddInlines(InlineCollection target, string text)
    {
        foreach (var inline in MarkdownParser.ParseInline(text, ForegroundBrush, SecondaryBrush))
        {
            target.Add(inline);
        }
    }
}

internal abstract record MarkdownBlock
{
    public sealed record Heading(int Level, string Text) : MarkdownBlock;
    public sealed record Paragraph(string Text) : MarkdownBlock;
    public sealed record UnorderedList(IReadOnlyList<string> Items) : MarkdownBlock;
    public sealed record OrderedList(IReadOnlyList<string> Items) : MarkdownBlock;
    public sealed record Quote(IReadOnlyList<string> Lines) : MarkdownBlock;
    public sealed record CodeBlock(string? Language, string Content) : MarkdownBlock;
}

internal static class MarkdownParser
{
    private static readonly Regex HeadingRegex = new(@"^(#{1,6})\s+(.+)$", RegexOptions.Compiled);
    private static readonly Regex UnorderedItemRegex = new(@"^\s*[-*+]\s+(.*)$", RegexOptions.Compiled);
    private static readonly Regex OrderedItemRegex = new(@"^\s*\d+\.\s+(.*)$", RegexOptions.Compiled);
    private static readonly Regex CodeFenceRegex = new(@"^\s*```\s*([\w+-]*)\s*$", RegexOptions.Compiled);

    public static IReadOnlyList<MarkdownBlock> Parse(string markdown)
    {
        var blocks = new List<MarkdownBlock>();
        if (string.IsNullOrEmpty(markdown))
        {
            return blocks;
        }

        var lines = markdown.Replace("\r\n", "\n").Split('\n');
        int i = 0;
        while (i < lines.Length)
        {
            var line = lines[i];
            if (string.IsNullOrWhiteSpace(line))
            {
                i++;
                continue;
            }

            var codeFence = CodeFenceRegex.Match(line);
            if (codeFence.Success)
            {
                var language = codeFence.Groups[1].Value;
                var codeLines = new List<string>();
                i++;
                while (i < lines.Length && !CodeFenceRegex.IsMatch(lines[i]))
                {
                    codeLines.Add(lines[i]);
                    i++;
                }
                if (i < lines.Length) i++;
                blocks.Add(new MarkdownBlock.CodeBlock(string.IsNullOrEmpty(language) ? null : language, string.Join("\n", codeLines)));
                continue;
            }

            var headingMatch = HeadingRegex.Match(line);
            if (headingMatch.Success)
            {
                blocks.Add(new MarkdownBlock.Heading(headingMatch.Groups[1].Value.Length, headingMatch.Groups[2].Value.Trim()));
                i++;
                continue;
            }

            if (line.TrimStart().StartsWith(">"))
            {
                var quoteLines = new List<string>();
                while (i < lines.Length)
                {
                    var trimmed = lines[i].TrimStart();
                    if (!trimmed.StartsWith(">")) break;
                    quoteLines.Add(trimmed.Length > 1 ? trimmed[1..].TrimStart() : string.Empty);
                    i++;
                }
                blocks.Add(new MarkdownBlock.Quote(quoteLines));
                continue;
            }

            var unorderedMatch = UnorderedItemRegex.Match(line);
            if (unorderedMatch.Success)
            {
                var items = new List<string> { unorderedMatch.Groups[1].Value };
                i++;
                while (i < lines.Length)
                {
                    var next = UnorderedItemRegex.Match(lines[i]);
                    if (!next.Success) break;
                    items.Add(next.Groups[1].Value);
                    i++;
                }
                blocks.Add(new MarkdownBlock.UnorderedList(items));
                continue;
            }

            var orderedMatch = OrderedItemRegex.Match(line);
            if (orderedMatch.Success)
            {
                var items = new List<string> { orderedMatch.Groups[1].Value };
                i++;
                while (i < lines.Length)
                {
                    var next = OrderedItemRegex.Match(lines[i]);
                    if (!next.Success) break;
                    items.Add(next.Groups[1].Value);
                    i++;
                }
                blocks.Add(new MarkdownBlock.OrderedList(items));
                continue;
            }

            // Paragraph: collect until a blank line or block-starting line.
            var paragraphLines = new List<string> { line };
            i++;
            while (i < lines.Length)
            {
                var candidate = lines[i];
                if (string.IsNullOrWhiteSpace(candidate) || StartsNewBlock(candidate))
                {
                    break;
                }
                paragraphLines.Add(candidate);
                i++;
            }
            blocks.Add(new MarkdownBlock.Paragraph(string.Join(" ", paragraphLines)));
        }

        return blocks;
    }

    private static bool StartsNewBlock(string line)
    {
        return CodeFenceRegex.IsMatch(line)
            || HeadingRegex.IsMatch(line)
            || UnorderedItemRegex.IsMatch(line)
            || OrderedItemRegex.IsMatch(line)
            || line.TrimStart().StartsWith(">");
    }

    public static IEnumerable<Inline> ParseInline(string text, Brush foreground, Brush secondary)
    {
        var inlines = new List<Inline>();
        int i = 0;
        var buffer = new System.Text.StringBuilder();

        void FlushBuffer()
        {
            if (buffer.Length == 0) return;
            inlines.Add(new Run(buffer.ToString()) { Foreground = foreground });
            buffer.Clear();
        }

        while (i < text.Length)
        {
            char c = text[i];

            if (c == '`')
            {
                int end = text.IndexOf('`', i + 1);
                if (end > i)
                {
                    FlushBuffer();
                    var code = text.Substring(i + 1, end - i - 1);
                    inlines.Add(new Run(code)
                    {
                        FontFamily = new FontFamily("Consolas, Cascadia Code, Menlo, monospace"),
                        Background = new SolidColorBrush(Color.FromArgb(0x66, 0x25, 0x22, 0x1F)),
                        Foreground = foreground,
                    });
                    i = end + 1;
                    continue;
                }
            }

            if (c == '*' && i + 1 < text.Length && text[i + 1] == '*')
            {
                int end = text.IndexOf("**", i + 2, StringComparison.Ordinal);
                if (end > i + 2)
                {
                    FlushBuffer();
                    var inner = text.Substring(i + 2, end - i - 2);
                    inlines.Add(new Bold(new Run(inner) { Foreground = foreground }));
                    i = end + 2;
                    continue;
                }
            }

            if ((c == '*' || c == '_') && i + 1 < text.Length && text[i + 1] != c)
            {
                int end = text.IndexOf(c, i + 1);
                if (end > i + 1)
                {
                    FlushBuffer();
                    var inner = text.Substring(i + 1, end - i - 1);
                    inlines.Add(new Italic(new Run(inner) { Foreground = foreground }));
                    i = end + 1;
                    continue;
                }
            }

            // Markdown link [text](url) -> render text only (we cannot click out in this UI yet).
            if (c == '[')
            {
                int closeBracket = text.IndexOf(']', i + 1);
                if (closeBracket > i && closeBracket + 1 < text.Length && text[closeBracket + 1] == '(')
                {
                    int closeParen = text.IndexOf(')', closeBracket + 2);
                    if (closeParen > closeBracket)
                    {
                        FlushBuffer();
                        var label = text.Substring(i + 1, closeBracket - i - 1);
                        inlines.Add(new Run(label)
                        {
                            Foreground = foreground,
                            TextDecorations = TextDecorations.Underline,
                        });
                        i = closeParen + 1;
                        continue;
                    }
                }
            }

            buffer.Append(c);
            i++;
        }

        FlushBuffer();
        return inlines;
    }
}
