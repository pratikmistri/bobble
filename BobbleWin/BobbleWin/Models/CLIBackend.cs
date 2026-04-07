using System.Diagnostics;
using System.Runtime.InteropServices;

namespace BobbleWin.Models;

public enum CLIBackend
{
    Codex,
    Copilot,
    Claude,
}

public static class CLIBackendExtensions
{
    public static IReadOnlyList<CLIBackend> All => [CLIBackend.Codex, CLIBackend.Copilot, CLIBackend.Claude];

    public static string Id(this CLIBackend backend) => backend switch
    {
        CLIBackend.Codex => "codex",
        CLIBackend.Copilot => "copilot",
        CLIBackend.Claude => "claude",
        _ => "codex",
    };

    public static string Command(this CLIBackend backend) => backend switch
    {
        CLIBackend.Codex => "codex",
        CLIBackend.Copilot => "copilot",
        CLIBackend.Claude => "claude",
        _ => "codex",
    };

    public static string DisplayName(this CLIBackend backend) => backend switch
    {
        CLIBackend.Codex => "Codex",
        CLIBackend.Copilot => "GitHub Copilot",
        CLIBackend.Claude => "Claude Code",
        _ => "Codex",
    };

    public static string ShortLabel(this CLIBackend backend) => backend switch
    {
        CLIBackend.Codex => "Codex",
        CLIBackend.Copilot => "Copilot",
        CLIBackend.Claude => "Claude",
        _ => "Codex",
    };

    public static string MissingCliMessage(this CLIBackend backend) => backend switch
    {
        CLIBackend.Codex => "Codex CLI not found. Install with `npm install -g @openai/codex`.",
        CLIBackend.Copilot => "GitHub Copilot CLI not found. Install and authenticate the `copilot` CLI.",
        CLIBackend.Claude => "Claude Code CLI not found. Install Claude Code so the `claude` command is available.",
        _ => "CLI not found.",
    };

    public static CLIBackend? Detect()
    {
        var available = AvailableBackends().ToHashSet();
        return PreferredDefault(available);
    }

    public static IReadOnlyList<CLIBackend> AvailableBackends()
    {
        return All.Where(backend => backend.ResolvedPath() is not null).ToList();
    }

    public static CLIBackend? PreferredDefault(HashSet<CLIBackend> available)
    {
        if (available.Contains(CLIBackend.Codex))
        {
            return CLIBackend.Codex;
        }

        if (available.Contains(CLIBackend.Copilot))
        {
            return CLIBackend.Copilot;
        }

        if (available.Contains(CLIBackend.Claude))
        {
            return CLIBackend.Claude;
        }

        return All.FirstOrDefault();
    }

    public static string? ResolvedPath(this CLIBackend backend)
    {
        var command = backend.Command();

        var whereCandidates = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? new[] { "where.exe", "where" }
            : new[] { "which" };

        foreach (var locator in whereCandidates)
        {
            try
            {
                var process = new Process
                {
                    StartInfo = new ProcessStartInfo
                    {
                        FileName = locator,
                        Arguments = command,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                    },
                };
                process.Start();
                var output = process.StandardOutput.ReadToEnd();
                process.WaitForExit(1500);
                if (process.ExitCode == 0)
                {
                    var path = output
                        .Split(["\r\n", "\n"], StringSplitOptions.RemoveEmptyEntries)
                        .Select(value => value.Trim())
                        .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
                    if (!string.IsNullOrWhiteSpace(path))
                    {
                        return path;
                    }
                }
            }
            catch
            {
                // no-op
            }
        }

        foreach (var directory in SearchPaths())
        {
            var directPath = Path.Combine(directory, command);
            if (File.Exists(directPath))
            {
                return directPath;
            }

            var cmdPath = Path.Combine(directory, $"{command}.cmd");
            if (File.Exists(cmdPath))
            {
                return cmdPath;
            }

            var exePath = Path.Combine(directory, $"{command}.exe");
            if (File.Exists(exePath))
            {
                return exePath;
            }
        }

        return null;
    }

    private static IReadOnlyList<string> SearchPaths()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        return
        [
            Path.Combine(home, ".local", "bin"),
            Path.Combine(home, "AppData", "Roaming", "npm"),
            Path.Combine(localAppData, "Programs", "nodejs"),
            Path.Combine(home, ".volta", "bin"),
            Path.Combine(home, ".cargo", "bin"),
            Path.Combine(home, "scoop", "shims"),
        ];
    }
}
