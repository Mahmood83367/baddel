using System;
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
            case "--xkb-group":
                return XkbGroup(args.ElementAtOrDefault(1));
        }

        var settings = LinuxSettings.Load();
        var pair = settings.LoadPair();
        if (pair is null)
        {
            Console.WriteLine("status=error reason=xkb-layout-not-found");
            return 4;
        }
        return new Session(settings, pair).Run();
    }

    /// <summary>States what this session offers, so nothing has to be assumed.</summary>
    private static int SelfCheck()
    {
        var settings = LinuxSettings.Load();
        var pair = settings.LoadPair();
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
        foreach (var key in table.Keys) Console.WriteLine($"{key.Code}|{key.Base}|{key.Shift}");
        return 0;
    }
}
