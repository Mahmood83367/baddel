using System;
using System.Collections.Generic;
using System.Linq;
using Baddel.Core;

namespace Baddel.Linux;

internal static class Program
{
    private const string Copyright = "Copyright (c) 2026 Mahmood";

    private static string Version =>
        typeof(Program).Assembly.GetName().Version is { } version ? $"{version.Major}.{version.Minor}.{version.Build}" : "0.0.0";

    private static int Main(string[] args)
    {
        // `baddel --fix-text …` and `baddel --fix-draft FILE` correct text for a shell
        // line editor or for Claude Code's external editor, then exit. They do not
        // talk to a running Baddel and need no accessibility bus. See docs/TERMINAL.md.
        if (TextFixCommand.Handles(args)) return FixText(args);

        // `baddel --terminal-key bash|zsh|claude|status` says how the shortcut in
        // settings.json reaches a terminal; the shell integration asks once on load.
        if (args.FirstOrDefault() == "--terminal-key")
        {
            var current = LinuxSettings.Load();
            return TerminalSharing.RunCommand(
                args.ElementAtOrDefault(1), current.Shortcut, TerminalPlatform.Linux, current.TerminalSharing,
                LinuxSettings.Directory, "Bash", Console.Out, Console.Error);
        }

        switch (args.FirstOrDefault())
        {
            case "--version":
                Console.WriteLine($"Baddel {Version} (Linux prototype)\n{Copyright}\nReleased under the MIT License.");
                return 0;
            case "--help" or "-h":
                Console.WriteLine(
                    "baddel                 run in the foreground\n"
                    + "baddel --trigger       tell the running Baddel the shortcut was pressed\n"
                    + "baddel --undo          undo the last correction\n"
                    + "baddel --quit          stop the running Baddel\n"
                    + "baddel --self-check    report what this session supports\n"
                    + "baddel --focus-report [seconds]   what the accessibility bus shows as focused (no text)\n"
                    + "baddel --check-updates [stable|preview]   look for a newer release (installs nothing)\n"
                    + "baddel --fix-text …    correct a shell command line (used by shell/baddel.bash)\n"
                    + "baddel --fix-draft FILE   correct a Claude Code draft (used as its external editor)\n"
                    + "baddel --terminal-key status   how the shortcut reaches a terminal\n"
                    + "baddel --dump-layout <xkb layout> [variant]\n"
                    + "baddel --version");
                return 0;
            case "--trigger":
                return TriggerChannel.Send("press") ? 0 : 1;
            case "--undo":
                return TriggerChannel.Send("undo") ? 0 : 1;
            case "--quit":
                return TriggerChannel.Send("quit") ? 0 : 1;
            case "--dump-layout":
                return DumpLayout(args.ElementAtOrDefault(1) ?? "us", args.ElementAtOrDefault(2));
            case "--self-check":
                return SelfCheck();
            case "--focus-report":
                // What Baddel sees through the accessibility bus right now: toolkits,
                // windows and focused elements with their roles. No text is read.
                // `baddel --focus-report 3` waits three seconds first, to let you
                // click into the field in question.
                if (int.TryParse(args.ElementAtOrDefault(1), out var wait) && wait is > 0 and <= 60) System.Threading.Thread.Sleep(wait * 1000);
                Console.WriteLine($"session={(Session.IsWayland ? "wayland" : string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DISPLAY")) ? "none" : "x11")}");
                Console.WriteLine($"desktopAccessibilitySwitch={(DesktopAccessibility.IsOn() switch { true => "on", false => "off (Qt and KDE applications stay invisible until it is on; a running Baddel turns it on)", null => "unreadable" })}");
                foreach (var line in AtspiFocus.Describe()) Console.WriteLine(line);
                return 0;
            case "--check-updates":
                return CheckUpdates(args.ElementAtOrDefault(1));
            case "--socket-path":
                // Where the trigger socket would live, or a refusal. Used by the checks.
                if (TriggerChannel.SocketPath(create: args.Contains("--create")) is { } socketPath)
                {
                    Console.WriteLine(socketPath);
                    return 0;
                }
                Console.WriteLine("refused: no private directory");
                return 1;
            case "--xkb-group":
                return XkbGroup(args.ElementAtOrDefault(1));
        }

        var settings = LinuxSettings.Load();
        var groups = SessionGroups();
        var (latin, arabic) = settings.Resolve(groups);
        var pair = LinuxSettings.LoadPair(latin, arabic);
        if (pair is null)
        {
            Console.WriteLine("status=error reason=xkb-layout-not-found");
            return 4;
        }
        return new Session(settings, pair, groups, latin, arabic).Run();
    }

    private static int FixText(string[] args)
    {
        var settings = LinuxSettings.Load();
        var groups = SessionGroups();
        var (latin, arabic) = settings.Resolve(groups);
        using var input = Console.OpenStandardInput();
        using var output = Console.OpenStandardOutput();
        return TextFixCommand.Run(
            args,
            () => LinuxSettings.LoadPair(latin, arabic),
            () =>
            {
                // The active XKB group, where an X11 session reports one.
                if (groups.Count == 0) return null;
                var display = X11.XOpenDisplay(null);
                if (display == IntPtr.Zero) return null;
                var script = new XkbGroupSwitcher(display, groups, latin, arabic).CurrentScript();
                X11.XCloseDisplay(display);
                return script;
            },
            input, output, Console.Error);
    }

    /// <summary>The session's XKB groups; only an X11 session reports them.</summary>
    private static IReadOnlyList<XkbGroup> SessionGroups() =>
        !Session.IsWayland && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DISPLAY"))
            ? XkbGroupSwitcher.QuerySession()
            : Array.Empty<XkbGroup>();

    /// <summary>
    /// Asks GitHub for the public release list and says whether a newer version
    /// exists on the channel. Runs only when asked; downloads and installs nothing.
    /// </summary>
    private static int CheckUpdates(string? channelName)
    {
        var channel = UpdateCheck.ParseChannel(channelName) ?? UpdateChannel.Stable;
        var result = UpdateChecker.CheckAsync(Version, channel).GetAwaiter().GetResult();
        Console.WriteLine(result is null
            ? "updateCheck=failed"
            : $"channel={result.Channel} current={result.Current} latest={result.Latest ?? "none"} updateAvailable={result.UpdateAvailable} page={result.ReleasePage ?? "-"}");
        Console.WriteLine($"automaticInstallationPossible={UpdateManifest.AutomaticInstallationPossible}");
        return result is null ? 1 : 0;
    }

    /// <summary>States what this session offers, so nothing has to be assumed.</summary>
    private static int SelfCheck()
    {
        var settings = LinuxSettings.Load();
        var groups = SessionGroups();
        var (latin, arabic) = settings.Resolve(groups);
        var pair = LinuxSettings.LoadPair(latin, arabic);
        var accessibility = AtspiFocus.Initialise();
        Console.WriteLine($"version={Version}");
        Console.WriteLine($"session={(Session.IsWayland ? "wayland" : string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DISPLAY")) ? "none" : "x11")}");
        Console.WriteLine($"accessibilityBus={accessibility}");
        Console.WriteLine($"latinLayout={pair?.Latin.Id ?? "missing"} arabicLayout={pair?.Arabic.Id ?? "missing"}");
        if (pair is not null)
        {
            var converter = new LayoutConverter(pair.Latin, pair.Arabic);
            Console.WriteLine($"conversionWorks={converter.Convert("ugd;l") == "عليكم"}");
        }
        Console.WriteLine($"triggerSocket={TriggerChannel.SocketPath(create: true) ?? "refused: no private directory"}");
        Console.WriteLine($"shortcut={(Session.IsWayland ? "bind a desktop shortcut to: baddel --trigger" : "X11 key grab: " + settings.Shortcut)}");
        return pair is not null && accessibility ? 0 : 1;
    }

    /// <summary>Prints the active XKB group of the X11 session, or selects one (used by the checks).</summary>
    private static int XkbGroup(string? wanted)
    {
        var display = X11.XOpenDisplay(null);
        if (display == IntPtr.Zero) return 1;
        if (wanted is not null && uint.TryParse(wanted, out var group))
        {
            X11.XkbLockGroup(display, X11.XkbUseCoreKbd, group);
            X11.XSync(display, 0);
        }
        var state = new byte[64];
        var status = X11.XkbGetState(display, X11.XkbUseCoreKbd, state);
        Console.WriteLine(status == 0 ? state[0].ToString() : "unknown");
        X11.XCloseDisplay(display);
        return status == 0 ? 0 : 1;
    }

    private static int DumpLayout(string layout, string? variant)
    {
        var table = XkbLayouts.Load(layout, variant, Script.Latin);
        if (table is null) return 1;
        Console.WriteLine($"# {table.Id}");
        foreach (var key in table.Keys) Console.WriteLine($"{key.Code}|{key.Base}|{key.Shift}");
        return 0;
    }
}
