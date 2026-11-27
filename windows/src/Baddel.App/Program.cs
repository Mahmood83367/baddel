using System;
using System.Threading;
using System.Windows.Forms;
using Baddel.Core;
using Baddel.Windows;

namespace Baddel.App;

internal static class Program
{
    internal const string Copyright = "Copyright (c) 2026 Mahmood";
    internal const string ProjectUrl = "https://github.com/Mahmood83367/baddel";

    internal static string Version =>
        typeof(Program).Assembly.GetName().Version is { } version ? $"{version.Major}.{version.Minor}.{version.Build}" : "0.0.0";

    [STAThread]
    private static int Main(string[] args)
    {
        // `Baddel.exe --self-check` verifies what needs no user interaction and exits:
        // the layout data loads and Windows accepts the configured shortcut.
        if (Array.IndexOf(args, "--self-check") >= 0)
        {
            var layouts = EmbeddedLayouts.Load().Layouts.Count;
            using var listener = new HotKeyListener();
            var accepted = listener.Register(AppSettings.Load().HotKey);
            return layouts >= 4 && accepted ? 0 : 1;
        }

        // `Baddel.exe --check-updates [stable|preview] [--out file]` performs the same
        // check as the menu item and writes the result.
        var updateIndex = Array.IndexOf(args, "--check-updates");
        if (updateIndex >= 0)
        {
            var channel = UpdateCheck.ParseChannel(updateIndex + 1 < args.Length ? args[updateIndex + 1] : null) ?? UpdateChannel.Stable;
            var result = UpdateChecker.CheckAsync(Version, channel).GetAwaiter().GetResult();
            var line = result is null
                ? "updateCheck=failed"
                : $"channel={result.Channel} current={result.Current} latest={result.Latest ?? "none"} updateAvailable={result.UpdateAvailable} page={result.ReleasePage ?? "-"}";
            line += $" automaticInstallationPossible={UpdateManifest.AutomaticInstallationPossible}";
            var outIndex = Array.IndexOf(args, "--out");
            if (outIndex >= 0 && outIndex + 1 < args.Length) System.IO.File.WriteAllText(args[outIndex + 1], line + Environment.NewLine);
            return result is null ? 1 : 0;
        }

        using var mutex = new Mutex(true, @"Local\Baddel.SingleInstance", out var first);
        if (!first) return 0;

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        using var context = new TrayContext();
        Application.Run(context);
        return 0;
    }
}
