using System;
using System.IO;
using System.Linq;

namespace Baddel.Linux;

/// <summary>
/// "Start Baddel at login", the standard way for a desktop session: one
/// <c>.desktop</c> file in the user's own autostart folder
/// (<c>$XDG_CONFIG_HOME/autostart</c>, normally <c>~/.config/autostart</c>), as the
/// freedesktop.org Desktop Application Autostart Specification describes. GNOME,
/// KDE Plasma, Xfce and others read it at login, on X11 and on Wayland.
///
/// Nothing is installed system-wide and nothing runs as root. The file is only
/// ever created by an explicit <c>baddel --autostart enable</c>, and Baddel only
/// replaces or removes a file it wrote itself.
/// </summary>
public static class Autostart
{
    public const string FileName = "app.baddel.Baddel.desktop";
    private const string Marker = "X-Baddel-Autostart=true";

    public enum State
    {
        Off,
        On,
        /// <summary>Our file exists but points at a program that is no longer there.</summary>
        Stale,
        /// <summary>A file with this name exists that Baddel did not write.</summary>
        Foreign,
    }

    public static string Directory =>
        Path.Combine(
            Environment.GetEnvironmentVariable("XDG_CONFIG_HOME") is { Length: > 0 } config
                ? config
                : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config"),
            "autostart");

    public static string FilePath => Path.Combine(Directory, FileName);

    /// <summary>
    /// The command the session should run: the installed launcher when this is the
    /// packaged copy, otherwise this executable where it is.
    /// </summary>
    public static string ProgramPath()
    {
        var current = Environment.ProcessPath ?? "baddel";
        foreach (var launcher in new[] { "/usr/bin/baddel", Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local/bin/baddel") })
        {
            try
            {
                if (File.Exists(launcher) && Path.GetFullPath(new FileInfo(launcher).ResolveLinkTarget(true)?.FullName ?? launcher) == Path.GetFullPath(current))
                {
                    return launcher;
                }
            }
            catch (IOException)
            {
            }
        }
        return current;
    }

    public static string Entry(string program) =>
        "[Desktop Entry]\n"
        + "Type=Application\n"
        + "Name=Baddel\n"
        + "Comment=Fix text typed with the wrong keyboard layout\n"
        + $"Exec={Quote(program)}\n"
        // A desktop skips the entry instead of reporting an error if the program has been removed.
        + $"TryExec={program}\n"
        + "Terminal=false\n"
        + "X-GNOME-Autostart-enabled=true\n"
        + Marker + "\n";

    /// <summary>Quotes a path for the Exec key (spaces and the characters the specification reserves).</summary>
    private static string Quote(string path) =>
        path.Any(c => " \t\n\"'\\><~|&;$*?#()`".Contains(c))
            ? "\"" + path.Replace("\\", "\\\\").Replace("\"", "\\\"").Replace("$", "\\$").Replace("`", "\\`") + "\""
            : path;

    public static State Read(string? file = null)
    {
        file ??= FilePath;
        if (!File.Exists(file)) return State.Off;
        string[] lines;
        try
        {
            lines = File.ReadAllLines(file);
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return State.Foreign;
        }
        if (!lines.Contains(Marker)) return State.Foreign;
        if (lines.Any(l => l.Trim() is "Hidden=true" or "X-GNOME-Autostart-enabled=false")) return State.Off;
        var program = lines.FirstOrDefault(l => l.StartsWith("TryExec=", StringComparison.Ordinal))?["TryExec=".Length..];
        return program is not null && File.Exists(program) ? State.On : State.Stale;
    }

    /// <returns><c>null</c> on success, otherwise a code saying why nothing was changed.</returns>
    public static string? Enable(string program, string? file = null)
    {
        file ??= FilePath;
        if (Read(file) == State.Foreign) return "anotherFileIsInTheWay";
        try
        {
            System.IO.Directory.CreateDirectory(Path.GetDirectoryName(file)!);
            File.WriteAllText(file, Entry(program));
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return "cannotWrite";
        }
    }

    /// <returns><c>null</c> on success, otherwise a code saying why nothing was changed.</returns>
    public static string? Disable(string? file = null)
    {
        file ??= FilePath;
        switch (Read(file))
        {
            case State.Foreign: return "notBaddelsFile";
            case State.Off when !File.Exists(file): return null;
        }
        try
        {
            File.Delete(file);
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return "cannotWrite";
        }
    }

    /// <summary><c>baddel --autostart status|enable|disable</c>.</summary>
    public static int RunCommand(string? action)
    {
        string? problem = null;
        switch (action ?? "status")
        {
            case "enable": problem = Enable(ProgramPath()); break;
            case "disable": problem = Disable(); break;
            case "status": break;
            default:
                Console.Error.WriteLine("baddel: usage: --autostart status|enable|disable");
                return 2;
        }
        var state = Read();
        Console.WriteLine($"startAtLogin={state switch { State.On => "on", State.Off => "off", State.Stale => "on-but-the-program-is-missing", _ => "unknown (a file Baddel did not write is in the way)" }}");
        Console.WriteLine($"file={FilePath}");
        if (problem is not null) Console.WriteLine($"notChanged={problem}");
        if (state == State.On && Session.IsWayland)
        {
            Console.WriteLine("note=on Wayland Baddel starts but cannot hold a shortcut itself: bind a desktop shortcut to `baddel --trigger`");
        }
        return problem is null ? 0 : 1;
    }
}
