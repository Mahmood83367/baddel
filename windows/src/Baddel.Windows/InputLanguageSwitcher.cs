using System;
using System.Globalization;
using System.Linq;
using System.Threading;
using Baddel.Core;

namespace Baddel.Windows;

/// <summary>
/// Reads and requests the keyboard layout of the foreground window. Only layouts
/// the user has already installed are ever requested.
/// </summary>
public sealed class InputLanguageSwitcher : ILayoutSwitcher
{
    private const int PrimaryLanguageMask = 0x3FF;
    private const int LangArabic = 0x01;
    private const int LangEnglish = 0x09;

    private readonly IntPtr? fixedWindow;

    public InputLanguageSwitcher()
    {
    }

    /// <summary>Targets one window instead of the foreground window (developer check tool).</summary>
    public InputLanguageSwitcher(IntPtr window)
    {
        fixedWindow = window;
    }

    private IntPtr Window => fixedWindow ?? NativeMethods.GetForegroundWindow();

    private static IntPtr LayoutOf(IntPtr window) =>
        window == IntPtr.Zero ? IntPtr.Zero : NativeMethods.GetKeyboardLayout(NativeMethods.GetWindowThreadProcessId(window, out _));

    public static Script? ScriptOf(IntPtr layout)
    {
        var primary = (int)(layout.ToInt64() & 0xFFFF) & PrimaryLanguageMask;
        return primary switch
        {
            LangArabic => Script.Arabic,
            LangEnglish => Script.Latin,
            _ => null,
        };
    }

    public static IntPtr[] InstalledLayouts()
    {
        var count = NativeMethods.GetKeyboardLayoutList(0, null);
        if (count <= 0) return Array.Empty<IntPtr>();
        var list = new IntPtr[count];
        var copied = NativeMethods.GetKeyboardLayoutList(count, list);
        return list.Take(Math.Max(copied, 0)).ToArray();
    }

    public static string Format(IntPtr layout) => layout.ToInt64().ToString("X", CultureInfo.InvariantCulture);

    public string? CurrentLayoutId()
    {
        var layout = LayoutOf(Window);
        return layout == IntPtr.Zero ? null : Format(layout);
    }

    public Script? CurrentScript() => ScriptOf(LayoutOf(Window));

    public bool SelectLayout(Script script)
    {
        var layout = InstalledLayouts().FirstOrDefault(candidate => ScriptOf(candidate) == script);
        return layout != IntPtr.Zero && Request(layout);
    }

    public bool SelectLayoutById(string id)
    {
        if (!long.TryParse(id, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var raw)) return false;
        var layout = InstalledLayouts().FirstOrDefault(candidate => candidate.ToInt64() == raw);
        return layout != IntPtr.Zero && Request(layout);
    }

    /// <summary>Asks the target window to switch, then confirms that it did.</summary>
    private bool Request(IntPtr layout)
    {
        var window = Window;
        if (window == IntPtr.Zero) return false;
        if (LayoutOf(window) == layout) return true;
        if (!NativeMethods.PostMessage(window, NativeMethods.WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, layout)) return false;
        var deadline = Environment.TickCount64 + 400;
        while (Environment.TickCount64 < deadline)
        {
            if (LayoutOf(window) == layout) return true;
            Thread.Sleep(20);
        }
        return LayoutOf(window) == layout;
    }
}

/// <summary>A switcher that never changes anything; used by checks.</summary>
public sealed class InertLayoutSwitcher(Script? script = null) : ILayoutSwitcher
{
    public string? CurrentLayoutId() => null;
    public Script? CurrentScript() => script;
    public bool SelectLayout(Script script) => false;
    public bool SelectLayoutById(string id) => false;
}
