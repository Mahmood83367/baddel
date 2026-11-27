// Developer check tool for Windows. It runs the real correction engine, and the
// real app, against a throwaway window that it creates itself, and writes
// outcome codes to a results file. It never prints or stores field text.
//
//   baddel-wincheck --dump-layouts <dir>
//   baddel-wincheck --engine --out results.txt
//   baddel-wincheck --e2e <path to Baddel.exe> --out results.txt [--notepad]
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Baddel.Core;
using Baddel.Windows;

namespace Baddel.WinCheck;

internal static class Program
{
    private static readonly List<string> Lines = new();
    private static int failures;
    private static string? outFile;

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool GetWindowRect(IntPtr window, out Rect rect);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr FindWindowW(string? className, string? title);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

    [DllImport("user32.dll")]
    private static extern bool IsWindowVisible(IntPtr window);

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left, Top, Right, Bottom;
    }

    private static void Log(string line)
    {
        Lines.Add(line);
        if (outFile is not null) File.WriteAllLines(outFile, Lines, new UTF8Encoding(false));
    }

    private static void Check(string name, bool passed, string detail = "")
    {
        if (!passed) failures++;
        Log($"{(passed ? "PASS" : "FAIL")} {name}{(detail.Length > 0 ? " [" + detail + "]" : string.Empty)}");
    }

    [STAThread]
    private static int Main(string[] args)
    {
        string? Option(string name)
        {
            var index = Array.IndexOf(args, name);
            return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
        }
        bool Flag(string name) => Array.IndexOf(args, name) >= 0;

        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        outFile = Option("--out");

        if (Flag("--host"))
        {
            (int, int)? selection = null;
            if (Option("--select") is { } raw)
            {
                var parts = raw.Split(',').Select(int.Parse).ToArray();
                selection = (parts[0], parts[1]);
            }
            Application.EnableVisualStyles();
            Application.Run(new HostForm(
                Option("--control") ?? "plain",
                File.ReadAllText(Option("--text-file")!, Encoding.UTF8),
                Option("--caret") is { } caret ? int.Parse(caret, CultureInfo.InvariantCulture) : null,
                selection, Option("--layout"), Option("--ready")!));
            return 0;
        }

        try
        {
            if (Option("--dump-layouts") is { } directory) return DumpLayouts(directory);
            Log($"machine={Environment.MachineName} os={Environment.OSVersion.Version} session={Process.GetCurrentProcess().SessionId} interactive={Environment.UserInteractive}");
            Log($"installedLayoutIds={string.Join(",", InputLanguageSwitcher.InstalledLayouts().Select(l => InputLanguageSwitcher.KlidOf(l) ?? "unknown"))}");
            if (Flag("--engine")) EngineChecks();
            if (Option("--e2e") is { } app) EndToEnd(app, Flag("--notepad"));
        }
        catch (Exception exception)
        {
            // Type and location only: exception messages could quote field text.
            failures++;
            Log($"FAIL unexpected-exception [{exception.GetType().Name} at {exception.TargetSite?.DeclaringType?.Name}.{exception.TargetSite?.Name}]");
        }
        Log(failures == 0 ? "RESULT all checks passed" : $"RESULT {failures} check(s) failed");
        return failures == 0 ? 0 : 1;
    }

    // Layout data -------------------------------------------------------------

    private static int DumpLayouts(string directory)
    {
        Directory.CreateDirectory(directory);
        var layouts = new[]
        {
            ("00000409", "us-english-windows", "US English (Windows)", "latin"),
            ("00000809", "uk-english-windows", "UK English (Windows)", "latin"),
            ("00000401", "arabic-windows-101", "Arabic (101)", "arabic"),
            ("00010401", "arabic-windows-102", "Arabic (102)", "arabic"),
        };
        foreach (var (klid, id, name, script) in layouts)
        {
            var keys = LayoutDumper.Dump(klid);
            if (keys is null)
            {
                Console.Error.WriteLine($"missing layout {klid}");
                return 1;
            }
            var builder = new StringBuilder();
            builder.Append("{\n");
            builder.Append($"  \"id\": \"{id}\",\n  \"name\": \"{name}\",\n  \"script\": \"{script}\",\n");
            builder.Append($"  \"platformIds\": {{ \"windows\": [\"{klid}\"] }},\n  \"keys\": [\n");
            builder.Append(string.Join(",\n", keys.Select(k =>
                $"    {{ \"code\": \"{k.Code}\", \"base\": {Escape(k.Base)}, \"shift\": {Escape(k.Shift)} }}")));
            builder.Append("\n  ]\n}\n");
            File.WriteAllText(Path.Combine(directory, id + ".json"), builder.ToString(), new UTF8Encoding(false));
        }
        return 0;
    }

    private static string Escape(string value)
    {
        var builder = new StringBuilder("\"");
        foreach (var c in value)
        {
            if (c == '"') builder.Append("\\\"");
            else if (c == '\\') builder.Append("\\\\");
            else if ((c >= 0x20 && c <= 0x7E) || (c >= 0x0621 && c <= 0x064A)) builder.Append(c);
            else builder.Append("\\u").Append(((int)c).ToString("X4", CultureInfo.InvariantCulture));
        }
        return builder.Append('"').ToString();
    }

    // Fixture host ------------------------------------------------------------

    private sealed class Host : IDisposable
    {
        public Process Process = null!;
        public IntPtr Window;
        private string directory = null!;

        public static Host? Start(string kind, string text, int? caret = null, (int, int)? selection = null, string? layout = null)
        {
            var directory = Path.Combine(Path.GetTempPath(), "baddel-check-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(directory);
            var textFile = Path.Combine(directory, "text.txt");
            var ready = Path.Combine(directory, "ready.txt");
            File.WriteAllText(textFile, text, new UTF8Encoding(false));
            var arguments = new List<string> { "--host", "--control", kind, "--text-file", textFile, "--ready", ready };
            if (caret is { } c) arguments.AddRange(new[] { "--caret", c.ToString(CultureInfo.InvariantCulture) });
            if (selection is { } s) arguments.AddRange(new[] { "--select", $"{s.Item1},{s.Item2}" });
            if (layout is not null) arguments.AddRange(new[] { "--layout", layout });
            var info = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false };
            foreach (var argument in arguments) info.ArgumentList.Add(argument);
            var host = new Host { Process = Process.Start(info)!, directory = directory };
            var deadline = Environment.TickCount64 + 15000;
            while (!File.Exists(ready) && Environment.TickCount64 < deadline) Thread.Sleep(50);
            if (!File.Exists(ready))
            {
                host.Dispose();
                return null;
            }
            Thread.Sleep(150);
            host.Window = new IntPtr(long.Parse(File.ReadAllText(ready), CultureInfo.InvariantCulture));
            return host;
        }

        public void Dispose()
        {
            try
            {
                if (!Process.HasExited) Process.Kill();
                Process.WaitForExit(3000);
            }
            catch (Exception)
            {
            }
            try
            {
                Directory.Delete(directory, true);
            }
            catch (Exception)
            {
            }
        }
    }

    private static string? Read(IntPtr window)
    {
        try
        {
            return new FocusProvider(window).FocusedField()?.ReadText();
        }
        catch (Exception)
        {
            return null;
        }
    }

    // Engine against a real control --------------------------------------------

    private static void EngineChecks()
    {
        var store = EmbeddedLayouts.Load();

        void Case(
            string name, string kind, string initial, string? expected, CorrectionMode mode,
            int? caret = null, (int, int)? selection = null, Rejection? reject = null, bool tamper = false, bool eitherWay = false,
            string? arabic = null)
        {
            var pair = EmbeddedLayouts.Pair(store, arabic);
            using var host = Host.Start(kind, initial, caret, selection);
            if (host is null)
            {
                Check(name, false, "host-did-not-start");
                return;
            }
            var focus = new FocusProvider(host.Window);
            var engine = new CorrectionEngine(new CorrectionPlanner(pair), focus, new InertLayoutSwitcher(Script.Latin));
            var field = focus.FocusedField();
            if (field is null)
            {
                Check(name, false, "no-focused-field");
                return;
            }
            var path = field.GetType().Name;
            // What the control itself reports before the attempt (a control may
            // report line breaks differently from the text it was given).
            var before = Read(host.Window);
            var result = engine.Correct(mode, field);

            if (result.Success is not { } success)
            {
                var unchanged = kind == "password" || (before is not null && Read(host.Window) == before);
                var acceptable = reject == result.Rejection || eitherWay;
                Check(name, acceptable && unchanged, $"path={path} rejected={result.Rejection} fieldUnchanged={unchanged}");
                return;
            }
            // The engine re-reads the focused field; that object performed the write.
            field = success.Undo.Field;
            var strategy = (field as IAnchoredField)?.LastWriteStrategy;
            if (reject is not null || Read(host.Window) != expected)
            {
                Check(name, false, $"path={path} strategy={strategy} textMatches={Read(host.Window) == expected}");
                return;
            }
            var anchor = (field as IAnchoredField)?.TextAnchor() is not null;
            if (tamper)
            {
                // Change the field behind the engine's back; undo must refuse.
                field.SetSelection(new Utf16Range(0, 0));
                field.Replace(new Utf16Range(0, 0), expected!, "x");
                var refused = engine.Undo(success.Undo);
                Check(name, refused == Rejection.UndoStateChanged && Read(host.Window) == "x" + expected,
                    $"path={path} strategy={strategy} undoAfterEdit={refused}");
                return;
            }
            var undo = engine.Undo(success.Undo);
            Check(name, undo is null && Read(host.Window) == initial,
                $"path={path} strategy={strategy} caretAnchor={anchor} undo={(undo is null ? "ok" : undo.ToString())}");
        }

        Log("-- engine against a real control (no keyboard or mouse input) --");
        Case("edit: whole field, then undo", "plain", "hgsghl ugd;l", "السلام عليكم", CorrectionMode.WholeField);
        Case("edit: last word, trailing spaces, RTL context", "plain", "مرحبا ugd;l  ", "مرحبا عليكم  ", CorrectionMode.SelectionOrLastWord, caret: 13);
        Case("edit: exact selection; undo refused after an edit", "plain", "say ugd;l now", "say عليكم now", CorrectionMode.SelectionOrLastWord, selection: (4, 5), tamper: true);
        Case("edit: UTF-16 offsets after an emoji", "plain", "😀 ugd;l", "😀 عليكم", CorrectionMode.SelectionOrLastWord, caret: 8);
        Case("edit: Arabic typed instead of English", "plain", "اثممخ", "hello", CorrectionMode.SelectionOrLastWord, caret: 5);
        Case("edit: nothing before the caret", "plain", "   ", null, CorrectionMode.SelectionOrLastWord, caret: 3, reject: Rejection.NoWord);
        Case("multi-line edit: last word on the second line", "multi", "first line\r\nugd;l", "first line\r\nعليكم", CorrectionMode.SelectionOrLastWord, caret: 17);
        Case("multi-line edit: whole field keeps line breaks", "multi", "hgsghl\r\nugd;l", "السلام\r\nعليكم", CorrectionMode.WholeField);
        Case("password field is skipped", "password", "ugd;l", null, CorrectionMode.WholeField, reject: Rejection.SecureField);
        Case("read-only field is skipped", "readonly", "ugd;l", null, CorrectionMode.WholeField, reject: Rejection.UnsupportedField);
        Case("rich edit, single line: last word", "rich", "hgsghl ugd;l", "hgsghl عليكم", CorrectionMode.SelectionOrLastWord, caret: 12);
        // The backslash key types a letter on Arabic (102) and a backslash on Arabic (101).
        Case("Arabic (101) selected: variant-specific key", "plain", "\\hg", "\\ال", CorrectionMode.WholeField, arabic: "arabic-windows-101");
        Case("Arabic (102) selected: variant-specific key", "plain", "\\hg", "ذال", CorrectionMode.WholeField, arabic: "arabic-windows-102");
        Case("rich edit, multi-line: refused without touching the text", "rich", "hgsghl\nugd;l", null, CorrectionMode.WholeField, reject: Rejection.WriteFailed);
    }

    // The running app, with real input ----------------------------------------

    private static bool EnsureForeground(IntPtr window)
    {
        for (var attempt = 0; attempt < 10; attempt++)
        {
            if (GetForegroundWindow() == window) return true;
            SetForegroundWindow(window);
            Thread.Sleep(150);
        }
        return GetForegroundWindow() == window;
    }

    private static IntPtr FindUndoPopup()
    {
        var deadline = Environment.TickCount64 + 2500;
        while (Environment.TickCount64 < deadline)
        {
            var popup = FindWindowW(null, "Baddel Undo");
            if (popup != IntPtr.Zero && IsWindowVisible(popup)) return popup;
            Thread.Sleep(50);
        }
        return IntPtr.Zero;
    }

    private static void EndToEnd(string appPath, bool notepad)
    {
        Log("-- running app with real key presses and mouse clicks --");
        if (Process.GetProcessesByName("Baddel").Length > 0)
        {
            Check("app not already running", false, "close Baddel first");
            return;
        }
        var originalCursor = Cursor.Position;
        try
        {
            WithApp(appPath, null, hotKey =>
            {
                AppCase(hotKey, "one press fixes only the last word", "hgsghl ugd;l", "hgsghl عليكم", 12, 1, 0, "ar", false, null);
                AppCase(hotKey, "two presses 120 ms apart fix the whole field once", "hgsghl ugd;l", "السلام عليكم", 12, 2, 120, "ar", false, null);
                AppCase(hotKey, "English typed as Arabic: layout switches to Arabic", "ugd;l", "عليكم", 5, 1, 0, "en", true, Script.Arabic, "00000401");
                AppCase(hotKey, "Arabic typed as English: layout switches to English", "اثممخ", "hello", 5, 1, 0, "ar", true, Script.Latin, "00000409");
                if (notepad) NotepadCase(hotKey);
            });
            // Settings are read from a throwaway folder, never from the real profile.
            WithApp(appPath, new AppSettings { ArabicLayout = "arabic-windows-102", Shortcut = "Ctrl+Shift+F9" }, hotKey =>
            {
                AppCase(hotKey, "settings: Arabic (102) and a custom shortcut are used", "\\hg", "ذال", 3, 1, 0, "ar", false, null);
            });
            // A chosen variant decides both the table and which installed layout is
            // selected. If that exact layout is not installed, nothing is switched.
            WithApp(appPath, new AppSettings { ArabicLayout = "arabic-windows-102" }, hotKey =>
            {
                AppCase(hotKey, "Arabic (102) chosen: converted with its table", "\\hg", "ذال", 3, 1, 0, "en", false, null, "00010401");
            });
            // The pound key: UK types # on the key that is backslash on Arabic (101);
            // on the US layout # is Shift+3, which is # on Arabic (101) as well.
            WithApp(appPath, new AppSettings { EnglishLayout = "uk-english-windows" }, hotKey =>
            {
                AppCase(hotKey, "UK English chosen: converted with the UK table", "ugd;l#", "عليكم\\", 6, 1, 0, "en", false, null);
                AppCase(hotKey, "UK English chosen: switching back to English", "اثممخ", "hello", 5, 1, 0, "ar", false, null, "00000809");
            });
            WithApp(appPath, new AppSettings { EnglishLayout = "us-english" }, hotKey =>
            {
                AppCase(hotKey, "US English chosen: converted with the US table", "ugd;l#", "عليكم#", 6, 1, 0, "en", false, null);
            });
            // A settings file written by 0.1.0 has no English choice: US English.
            WithApp(appPath, null, hotKey =>
            {
                AppCase(hotKey, "no English choice stored: US English", "ugd;l#", "عليكم#", 6, 1, 0, "en", false, null);
            }, rawSettings: "{ \"Shortcut\": \"Ctrl+Alt+Space\", \"ArabicLayout\": \"arabic-windows-101\", \"DoublePressMs\": 300, \"SwitchLayout\": true, \"PasteFallback\": false }");
            // A user-supplied layout: US English with a section sign on the 1 key.
            // It is validated and loaded from the settings folder, converts by its
            // own table, and - having no Windows layout behind it - never switches.
            var customJson = System.Text.Json.JsonSerializer.Serialize(new
            {
                id = "custom-check", name = "Check layout", script = "arabic",
                platformIds = new Dictionary<string, string[]>(),
                keys = EmbeddedLayouts.Load().Get("arabic-windows-101").Keys.Select(k => new
                {
                    code = k.Code, @base = k.Code == "Digit1" ? "\u0661" : k.Base, shift = k.Shift,
                }),
            });
            WithApp(appPath, new AppSettings { ArabicLayout = "custom-check" }, hotKey =>
            {
                AppCase(hotKey, "custom layout from a file: converted with its table", "ugd;l1", "عليكم\u0661", 6, 1, 0, "en", false, null);
                AppCase(hotKey, "custom layout: the keyboard is not switched", "ugd;l", "عليكم", 5, 1, 0, "en", false, null, InputLanguageSwitcher.NoSystemLayout);
            }, customLayout: customJson);
            // A broken custom file is ignored and the default is used.
            WithApp(appPath, new AppSettings { ArabicLayout = "custom-check" }, hotKey =>
            {
                AppCase(hotKey, "invalid custom layout is ignored: default Arabic (101) is used", "ugd;l1", "عليكم1", 6, 1, 0, "en", false, null);
            }, customLayout: customJson.Replace("\"Digit1\"", "\"NotAKey\""));
            WithApp(appPath, new AppSettings { ArabicLayout = "arabic-windows-101" }, hotKey =>
            {
                AppCase(hotKey, "settings: Arabic (101) is used", "\\hg", "\\ال", 3, 1, 0, "ar", false, null);
            });
        }
        finally
        {
            Cursor.Position = originalCursor;
        }
    }

    private static void WithApp(string appPath, AppSettings? settings, Action<HotKey> body, string? rawSettings = null, string? customLayout = null)
    {
        var settingsDirectory = Path.Combine(Path.GetTempPath(), "baddel-check-settings-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(settingsDirectory);
        if (settings is not null) File.WriteAllText(Path.Combine(settingsDirectory, "settings.json"), settings.Serialize());
        if (rawSettings is not null) File.WriteAllText(Path.Combine(settingsDirectory, "settings.json"), rawSettings);
        if (customLayout is not null)
        {
            Directory.CreateDirectory(Path.Combine(settingsDirectory, "layouts"));
            File.WriteAllText(Path.Combine(settingsDirectory, "layouts", "check.json"), customLayout);
        }
        var info = new ProcessStartInfo(appPath) { UseShellExecute = false };
        info.Environment["BADDEL_SETTINGS_DIR"] = settingsDirectory;
        // The packaged app is self-contained; make sure it is not helped by a shared runtime.
        info.Environment.Remove("DOTNET_ROOT");
        using var app = Process.Start(info)!;
        try
        {
            Thread.Sleep(3000);
            Check("app starts and keeps running", !app.HasExited);
            body((settings ?? new AppSettings()).HotKey);
        }
        finally
        {
            try
            {
                if (!app.HasExited) app.Kill();
                app.WaitForExit(3000);
            }
            catch (Exception)
            {
            }
            try
            {
                Directory.Delete(settingsDirectory, true);
            }
            catch (Exception)
            {
            }
        }
    }

    private static void AppCase(
        HotKey hotKey, string name, string initial, string expected, int caret, int presses, int gapMs, string layout, bool undo, Script? layoutAfter,
        string? expectedKlid = null)
    {
        var installed = InputLanguageSwitcher.InstalledLayouts().Select(InputLanguageSwitcher.ScriptOf).ToArray();
        if (layoutAfter is not null && !(installed.Contains(Script.Arabic) && installed.Contains(Script.Latin)))
        {
            // Without both an Arabic and an English layout installed there is
            // nothing to switch to; the text correction is still checked.
            Log("NOTE layout switching not exercised: this account has no Arabic or no English layout installed");
            layoutAfter = null;
        }
        using var host = Host.Start("plain", initial, caret, null, layout);
        if (host is null || !EnsureForeground(host.Window))
        {
            Check(name, false, host is null ? "host-did-not-start" : "host-not-foreground");
            return;
        }
        var switcher = new InputLanguageSwitcher(host.Window);
        var layoutBefore = switcher.CurrentScript();
        for (var press = 0; press < presses; press++)
        {
            if (press > 0) Thread.Sleep(gapMs);
            if (!InputSender.PressHotKey(hotKey))
            {
                Check(name, false, "input-not-accepted");
                return;
            }
        }
        Thread.Sleep(1300);
        var corrected = Read(host.Window) == expected;
        var scriptAfter = switcher.CurrentScript();
        var layoutOk = layoutAfter is null || scriptAfter == layoutAfter;
        Check(name, corrected && layoutOk, $"textMatches={corrected} layout={layoutBefore}->{scriptAfter}");
        if (expectedKlid is not null && corrected)
        {
            // The layout Windows is now using must be the very layout whose table
            // did the conversion - or, if that layout is not installed, unchanged.
            var installedNow = InputLanguageSwitcher.IsInstalled(expectedKlid);
            var klidAfter = switcher.CurrentKlid();
            Check(
                name + (installedNow ? " / Windows switched to the same layout used for conversion" : " / layout not installed, keyboard left as it was"),
                installedNow ? string.Equals(klidAfter, expectedKlid, StringComparison.OrdinalIgnoreCase) : scriptAfter == layoutBefore,
                $"wanted={expectedKlid} installed={installedNow} active={klidAfter}");
        }
        if (!undo || !corrected) return;

        var popup = FindUndoPopup();
        if (popup == IntPtr.Zero || !GetWindowRect(popup, out var rect))
        {
            Check(name + " / undo popup", false, "popup-not-found");
            return;
        }
        var caretRect = (new FocusProvider(host.Window).FocusedField() as IAnchoredField)?.TextAnchor();
        var gap = caretRect is { } anchorRect ? rect.Top - anchorRect.Bottom : int.MinValue;
        Check(name + " / undo popup is next to the caret", gap is >= 0 and <= 16, $"gapPx={gap}");
        InputSender.Click(rect.Right - 38, (rect.Top + rect.Bottom) / 2);
        Thread.Sleep(1000);
        var restored = Read(host.Window) == initial;
        var stillForeground = GetForegroundWindow() == host.Window;
        var scriptRestored = switcher.CurrentScript();
        Check(name + " / click Undo restores text, focus stays in the field",
            restored && stillForeground && scriptRestored == layoutBefore,
            $"restored={restored} focusKept={stillForeground} layout={scriptAfter}->{scriptRestored}");
    }

    /// <summary>
    /// One correction in a real Notepad window holding a throwaway file. Skipped if
    /// Notepad is already open, so no existing Notepad window can be affected.
    /// </summary>
    private static void NotepadCase(HotKey hotKey)
    {
        const string name = "Notepad: one press fixes the last word";
        if (Process.GetProcessesByName("notepad").Length > 0)
        {
            Log("SKIP " + name + " [Notepad is already open]");
            return;
        }
        var directory = Path.Combine(Path.GetTempPath(), "baddel-check-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var fileName = "baddel-fixture-" + Guid.NewGuid().ToString("N").Substring(0, 8) + ".txt";
        var file = Path.Combine(directory, fileName);
        File.WriteAllText(file, "hgsghl ugd;l", new UTF8Encoding(false));
        Process.Start(new ProcessStartInfo("notepad.exe") { UseShellExecute = false, ArgumentList = { file } });
        try
        {
            IntPtr window = IntPtr.Zero;
            var deadline = Environment.TickCount64 + 15000;
            while (window == IntPtr.Zero && Environment.TickCount64 < deadline)
            {
                Thread.Sleep(200);
                window = Process.GetProcessesByName("notepad")
                    .Select(p => p.MainWindowHandle)
                    .FirstOrDefault(h => h != IntPtr.Zero);
            }
            if (window == IntPtr.Zero || !EnsureForeground(window))
            {
                Check(name, false, "notepad-window-not-foreground");
                return;
            }
            Thread.Sleep(1200);
            var focus = new FocusProvider(window);
            var field = focus.FocusedField();
            if (field is null || SafeText(field) != "hgsghl ugd;l")
            {
                // Not our fixture (for example a restored tab): leave it alone.
                Log("SKIP " + name + $" [path={field?.GetType().Name ?? "none"} fixture-not-focused]");
                return;
            }
            field.SetSelection(new Utf16Range(12, 0));
            InputSender.PressHotKey(hotKey);
            Thread.Sleep(1500);
            var after = SafeText(focus.FocusedField());
            var corrected = after == "hgsghl عليكم";
            var unchanged = after == "hgsghl ugd;l";
            Check(name, corrected || unchanged,
                $"path={field.GetType().Name} class={(field as Win32EditField)?.ClassName ?? (field as UiaField)?.ControlTypeName} outcome={(corrected ? "corrected" : unchanged ? "safely-refused" : "unexpected")}");
            if (corrected)
            {
                var popup = FindUndoPopup();
                if (popup != IntPtr.Zero && GetWindowRect(popup, out var rect))
                {
                    InputSender.Click(rect.Right - 38, (rect.Top + rect.Bottom) / 2);
                    Thread.Sleep(1000);
                    Check("Notepad: click Undo restores the text", SafeText(focus.FocusedField()) == "hgsghl ugd;l");
                }
                else
                {
                    Check("Notepad: undo popup", false, "popup-not-found");
                }
            }
        }
        finally
        {
            // Only Notepad processes started by this check exist (none ran before).
            foreach (var process in Process.GetProcessesByName("notepad"))
            {
                try
                {
                    process.Kill();
                }
                catch (Exception)
                {
                }
            }
            try
            {
                Directory.Delete(directory, true);
            }
            catch (Exception)
            {
            }
        }
    }

    private static string? SafeText(IEditableField? field)
    {
        try
        {
            return field?.ReadText();
        }
        catch (Exception)
        {
            return null;
        }
    }
}
