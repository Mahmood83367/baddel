using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.Json;
using System.Threading;
using Baddel.Core;

namespace Baddel.Windows;

/// <summary>Layout data compiled into the assembly from <c>shared/layouts</c>.</summary>
public static class EmbeddedLayouts
{
    public const string Latin = "us-english";
    public const string DefaultArabic = "arabic-windows-101";

    /// <summary>The built-in layouts plus any valid user-supplied ones from <paramref name="customDirectory"/>.</summary>
    public static LayoutStore LoadWithCustom(string customDirectory) =>
        LayoutValidator.AddCustomLayouts(Load(), customDirectory).Store;

    public static LayoutStore Load()
    {
        var assembly = typeof(EmbeddedLayouts).Assembly;
        var documents = assembly.GetManifestResourceNames()
            .Where(name => name.StartsWith("Baddel.Layouts.", StringComparison.Ordinal))
            .OrderBy(name => name, StringComparer.Ordinal)
            .Select(name =>
            {
                using var reader = new StreamReader(assembly.GetManifestResourceStream(name)!);
                return reader.ReadToEnd();
            });
        return new LayoutStore(documents);
    }

    /// <summary>Layouts of one script that have a Windows layout id, plus valid custom ones.</summary>
    public static IEnumerable<KeyboardLayout> Choices(LayoutStore store, Script script) =>
        store.Layouts.Values
            .Where(layout => layout.Script == script
                             && (layout.PlatformIds.ContainsKey("windows") || layout.Id.StartsWith(LayoutValidator.CustomPrefix, StringComparison.Ordinal)))
            .OrderBy(layout => layout.Id.StartsWith(LayoutValidator.CustomPrefix, StringComparison.Ordinal))
            .ThenBy(layout => layout.Id, StringComparer.Ordinal);

    /// <summary>
    /// The chosen English and Arabic layouts. A missing, unknown or wrong-script
    /// choice falls back to US English and Arabic (101), the defaults of earlier
    /// versions.
    /// </summary>
    public static LayoutPair Pair(LayoutStore store, string? arabicLayoutId, string? latinLayoutId = null)
    {
        KeyboardLayout Pick(string? id, Script script, string fallback) =>
            id is not null && store.Layouts.TryGetValue(id, out var chosen) && chosen.Script == script
            && (chosen.PlatformIds.ContainsKey("windows") || chosen.Id.StartsWith(LayoutValidator.CustomPrefix, StringComparison.Ordinal))
                ? chosen
                : store.Get(fallback);
        return new LayoutPair(Pick(latinLayoutId, Script.Latin, Latin), Pick(arabicLayoutId, Script.Arabic, DefaultArabic));
    }

    /// <summary>The Windows keyboard layout id of a layout, or <c>null</c> for a custom layout.</summary>
    public static string? Klid(KeyboardLayout layout) =>
        layout.PlatformIds.TryGetValue("windows", out var ids) && ids.Count > 0 ? ids[0] : null;
}

/// <summary>User preferences. Nothing here is user text.</summary>
public sealed class AppSettings
{
    public string Shortcut { get; set; } = HotKey.Default.ToString();
    public string ArabicLayout { get; set; } = EmbeddedLayouts.DefaultArabic;

    /// <summary>Absent in settings files written by 0.1.0, which means US English.</summary>
    public string EnglishLayout { get; set; } = EmbeddedLayouts.Latin;
    public int DoublePressMs { get; set; } = 300;
    public bool SwitchLayout { get; set; } = true;

    /// <summary>Experimental and off by default.</summary>
    public bool PasteFallback { get; set; }

    /// <summary>"stable" (default) or "preview": which releases "Check for updates" reports.</summary>
    public string UpdateChannel { get; set; } = "stable";

    /// <summary>
    /// Off by default. When on, Baddel asks GitHub for the release list once a day
    /// and mentions a newer version. It never downloads or installs.
    /// </summary>
    public bool CheckForUpdatesAutomatically { get; set; }

    public DateTime? LastAutomaticUpdateCheckUtc { get; set; }

    public UpdateChannel Channel => UpdateCheck.ParseChannel(UpdateChannel) ?? Baddel.Core.UpdateChannel.Stable;

    /// <summary>Where a user can place their own layout files.</summary>
    public static string CustomLayoutsDirectory => Path.Combine(Directory, "layouts");

    public HotKey HotKey => HotKey.TryParse(Shortcut, out var parsed) ? parsed : HotKey.Default;

    public int ClampedDoublePressMs => Math.Clamp(DoublePressMs, 150, 600);

    /// <summary>
    /// <c>%APPDATA%\Baddel</c>, or the folder named by <c>BADDEL_SETTINGS_DIR</c>
    /// (used by checks so they never touch real settings).
    /// </summary>
    public static string Directory =>
        Environment.GetEnvironmentVariable("BADDEL_SETTINGS_DIR") is { Length: > 0 } custom
            ? custom
            : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Baddel");

    public static string FilePath => Path.Combine(Directory, "settings.json");

    private static readonly JsonSerializerOptions Options = new() { WriteIndented = true };

    public static AppSettings Parse(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<AppSettings>(json, Options) ?? new AppSettings();
        }
        catch (JsonException)
        {
            return new AppSettings();
        }
    }

    public string Serialize() => JsonSerializer.Serialize(this, Options);

    public static AppSettings Load()
    {
        try
        {
            return File.Exists(FilePath) ? Parse(File.ReadAllText(FilePath)) : new AppSettings();
        }
        catch (IOException)
        {
            return new AppSettings();
        }
    }

    public void Save()
    {
        System.IO.Directory.CreateDirectory(Directory);
        File.WriteAllText(FilePath, Serialize());
    }
}

/// <summary>Works out where the Undo popup goes. Pure geometry, in screen pixels.</summary>
public static class PopupPlacement
{
    public const int Gap = 6;

    /// <param name="popup">Size of the popup.</param>
    /// <param name="anchor">Rectangle of the edited text or field, or <c>null</c> when unknown.</param>
    /// <param name="workArea">Usable area of the screen the popup should appear on.</param>
    public static Point Compute(Size popup, Rectangle? anchor, Rectangle workArea)
    {
        if (anchor is not { } rect || !rect.IntersectsWith(workArea))
        {
            // No usable coordinates: lower middle of the screen.
            return new Point(
                workArea.Left + (workArea.Width - popup.Width) / 2,
                Math.Max(workArea.Top, workArea.Bottom - popup.Height - 96));
        }
        var x = rect.Left;
        var y = rect.Bottom + Gap;
        if (y + popup.Height > workArea.Bottom) y = rect.Top - popup.Height - Gap;
        x = Math.Clamp(x, workArea.Left + 4, Math.Max(workArea.Left + 4, workArea.Right - popup.Width - 4));
        y = Math.Clamp(y, workArea.Top + 4, Math.Max(workArea.Top + 4, workArea.Bottom - popup.Height - 4));
        return new Point(x, y);
    }
}

/// <summary>
/// Writes diagnostics to the debugger output stream. Records are built from
/// <see cref="DiagnosticEvent"/>, which cannot carry field text.
/// </summary>
public static class DiagnosticsLog
{
    public static void Record(DiagnosticEvent diagnostic, string? detail = null) =>
        Trace.WriteLine($"[Baddel] {diagnostic.Summary}{(detail is null ? string.Empty : " " + detail)}");
}

/// <summary>
/// One long-lived STA thread that runs corrections in order. UI Automation and
/// the clipboard are used from here, never from the window message loop.
/// </summary>
public sealed class StaWorker : IDisposable
{
    private readonly BlockingCollection<Action> queue = new();
    private readonly Thread thread;

    public StaWorker()
    {
        thread = new Thread(Run) { IsBackground = true, Name = "Baddel worker" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
    }

    public void Post(Action action) => queue.Add(action);

    private void Run()
    {
        foreach (var action in queue.GetConsumingEnumerable())
        {
            try
            {
                action();
            }
            catch (Exception)
            {
                // A failed job must not take the worker down. No text is logged.
                Trace.WriteLine("[Baddel] event=WorkerError");
            }
        }
    }

    public void Dispose() => queue.CompleteAdding();
}

/// <summary>Reads layout tables from Windows keyboard layout DLLs (developer tool).</summary>
public static class LayoutDumper
{
    private static readonly (string Code, uint Scan)[] Keys =
    {
        ("Backquote", 0x29), ("Digit1", 0x02), ("Digit2", 0x03), ("Digit3", 0x04), ("Digit4", 0x05),
        ("Digit5", 0x06), ("Digit6", 0x07), ("Digit7", 0x08), ("Digit8", 0x09), ("Digit9", 0x0A),
        ("Digit0", 0x0B), ("Minus", 0x0C), ("Equal", 0x0D),
        ("KeyQ", 0x10), ("KeyW", 0x11), ("KeyE", 0x12), ("KeyR", 0x13), ("KeyT", 0x14), ("KeyY", 0x15),
        ("KeyU", 0x16), ("KeyI", 0x17), ("KeyO", 0x18), ("KeyP", 0x19), ("BracketLeft", 0x1A),
        ("BracketRight", 0x1B), ("Backslash", 0x2B),
        ("KeyA", 0x1E), ("KeyS", 0x1F), ("KeyD", 0x20), ("KeyF", 0x21), ("KeyG", 0x22), ("KeyH", 0x23),
        ("KeyJ", 0x24), ("KeyK", 0x25), ("KeyL", 0x26), ("Semicolon", 0x27), ("Quote", 0x28),
        ("KeyZ", 0x2C), ("KeyX", 0x2D), ("KeyC", 0x2E), ("KeyV", 0x2F), ("KeyB", 0x30), ("KeyN", 0x31),
        ("KeyM", 0x32), ("Comma", 0x33), ("Period", 0x34), ("Slash", 0x35),
    };

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryExW(string fileName, IntPtr reserved, uint flags);

    [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Ansi)]
    private static extern IntPtr GetProcAddress(IntPtr module, string name);

    [System.Runtime.InteropServices.UnmanagedFunctionPointer(System.Runtime.InteropServices.CallingConvention.Winapi)]
    private delegate IntPtr KbdLayerDescriptor();

    private const ushort WchNone = 0xF000;
    private const ushort WchDead = 0xF001;
    private const ushort WchLigature = 0xF002;

    /// <summary>The layout DLL registered for a keyboard layout id such as <c>00000401</c>.</summary>
    public static string? LayoutFile(string klid)
    {
        using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(
            @"SYSTEM\CurrentControlSet\Control\Keyboard Layouts\" + klid);
        return key?.GetValue("Layout File") as string;
    }

    /// <summary>
    /// Base and Shift output of each key, read from the tables inside the layout
    /// DLL that Windows registers for <paramref name="klid"/>. This works for any
    /// layout present on the system, whether or not the user has added it, and
    /// changes no setting. Dead keys are reported as empty. 64-bit processes only.
    /// </summary>
    public static List<LayoutKey>? Dump(string klid)
    {
        if (IntPtr.Size != 8 || LayoutFile(klid) is not { } file) return null;
        const uint LOAD_LIBRARY_SEARCH_SYSTEM32 = 0x800;
        var module = LoadLibraryExW(file, IntPtr.Zero, LOAD_LIBRARY_SEARCH_SYSTEM32);
        if (module == IntPtr.Zero) return null;
        var entry = GetProcAddress(module, "KbdLayerDescriptor");
        if (entry == IntPtr.Zero) return null;
        var tables = System.Runtime.InteropServices.Marshal.GetDelegateForFunctionPointer<KbdLayerDescriptor>(entry)();
        if (tables == IntPtr.Zero) return null;

        static IntPtr Pointer(IntPtr address, int offset) => System.Runtime.InteropServices.Marshal.ReadIntPtr(address, offset);
        static ushort Word(IntPtr address, int offset) => unchecked((ushort)System.Runtime.InteropServices.Marshal.ReadInt16(address, offset));
        static byte Byte(IntPtr address, int offset) => System.Runtime.InteropServices.Marshal.ReadByte(address, offset);

        // KBDTABLES (x64): modifiers @0, VK-to-WCHAR tables @8, scan-code table @48,
        // its length @56, ligature entry count @84, entry size @85, ligatures @88.
        var modifiers = Pointer(tables, 0);
        var maxModifierBits = Word(modifiers, 8);
        int Column(int bits) => bits <= maxModifierBits ? Byte(modifiers, 10 + bits) : 0x0F;
        var baseColumn = Column(0);
        var shiftColumn = Column(1);

        var scanToVirtualKey = Pointer(tables, 48);
        var scanCount = Byte(tables, 56);
        var ligatureMax = Byte(tables, 84);
        var ligatureSize = Byte(tables, 85);
        var ligatures = Pointer(tables, 88);

        string Ligature(byte virtualKey, int column)
        {
            if (ligatures == IntPtr.Zero || ligatureSize == 0) return string.Empty;
            for (var entryAddress = ligatures; Byte(entryAddress, 0) != 0; entryAddress += ligatureSize)
            {
                if (Byte(entryAddress, 0) != virtualKey || Word(entryAddress, 2) != column) continue;
                var text = new System.Text.StringBuilder();
                for (var index = 0; index < ligatureMax; index++)
                {
                    var unit = Word(entryAddress, 4 + index * 2);
                    if (unit == WchNone) break;
                    text.Append((char)unit);
                }
                return text.ToString();
            }
            return string.Empty;
        }

        string Output(byte virtualKey, int column)
        {
            if (column == 0x0F) return string.Empty;
            var table = Pointer(tables, 8);
            for (; Pointer(table, 0) != IntPtr.Zero; table += 16)
            {
                var rows = Pointer(table, 0);
                var columns = Byte(table, 8);
                var rowSize = Byte(table, 9);
                if (column >= columns) continue;
                for (var row = rows; Byte(row, 0) != 0; row += rowSize)
                {
                    if (Byte(row, 0) != virtualKey) continue;
                    var unit = Word(row, 2 + column * 2);
                    return unit switch
                    {
                        0 or WchNone or WchDead => string.Empty,
                        WchLigature => Ligature(virtualKey, column),
                        _ => ((char)unit).ToString(),
                    };
                }
            }
            return string.Empty;
        }

        var result = new List<LayoutKey>();
        foreach (var (code, scan) in Keys)
        {
            if (scan >= scanCount) return null;
            var virtualKey = (byte)(Word(scanToVirtualKey, (int)scan * 2) & 0xFF);
            result.Add(new LayoutKey(code, Output(virtualKey, baseColumn), Output(virtualKey, shiftColumn)));
        }
        return result;
    }

    /// <summary>
    /// The same data obtained by asking Windows to translate each key
    /// (<c>ToUnicodeEx</c>), for a layout the user already has installed. Nothing
    /// is loaded: if the layout is not in the session's list this returns
    /// <c>null</c>. Used to cross-check <see cref="Dump"/>.
    /// </summary>
    public static List<LayoutKey>? DumpByTranslation(string klid)
    {
        const uint MAPVK_VSC_TO_VK_EX = 3;
        var layout = InputLanguageSwitcher.InstalledLayouts().FirstOrDefault(
            candidate => string.Equals(InputLanguageSwitcher.KlidOf(candidate), klid, StringComparison.OrdinalIgnoreCase));
        if (layout == IntPtr.Zero) return null;
        var result = new List<LayoutKey>();
        foreach (var (code, scan) in Keys)
        {
            var virtualKey = NativeMethods.MapVirtualKeyExW(scan, MAPVK_VSC_TO_VK_EX, layout);
            result.Add(new LayoutKey(code, Translate(virtualKey, scan, false, layout), Translate(virtualKey, scan, true, layout)));
        }
        return result;
    }

    private static string Translate(uint virtualKey, uint scan, bool shift, IntPtr layout)
    {
        var state = new byte[256];
        if (shift) state[NativeMethods.VK_SHIFT] = 0x80;
        // The API does not null-terminate its output, so a plain array is used
        // and exactly `count` characters are taken.
        var buffer = new char[8];
        // Flag 4: do not change the keyboard state kept by the system.
        var count = NativeMethods.ToUnicodeEx(virtualKey, scan, state, buffer, buffer.Length, 4, layout);
        if (count <= 0) return string.Empty;
        var text = new string(buffer, 0, Math.Min(count, buffer.Length));
        // Keys with no character report a control code or NUL; treat as empty.
        return text.Length == 1 && text[0] < 0x20 ? string.Empty : text;
    }
}
