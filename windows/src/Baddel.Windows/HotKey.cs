using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace Baddel.Windows;

[Flags]
public enum HotKeyModifiers
{
    None = 0,
    Alt = 1,
    Control = 2,
    Shift = 4,
    Win = 8,
}

/// <summary>A global shortcut: modifiers plus one virtual key.</summary>
public readonly record struct HotKey(HotKeyModifiers Modifiers, Keys Key)
{
    /// <summary>Ctrl+Alt+Space.</summary>
    public static readonly HotKey Default = new(HotKeyModifiers.Control | HotKeyModifiers.Alt, Keys.Space);

    /// <summary>
    /// A usable shortcut has a real key and at least Ctrl, Alt or Win; Shift alone
    /// would shadow ordinary typing.
    /// </summary>
    public bool IsValid =>
        Key != Keys.None
        && Key is not (Keys.ControlKey or Keys.ShiftKey or Keys.Menu or Keys.LWin or Keys.RWin)
        && (Modifiers & (HotKeyModifiers.Alt | HotKeyModifiers.Control | HotKeyModifiers.Win)) != 0;

    public override string ToString()
    {
        var parts = new List<string>();
        if (Modifiers.HasFlag(HotKeyModifiers.Control)) parts.Add("Ctrl");
        if (Modifiers.HasFlag(HotKeyModifiers.Alt)) parts.Add("Alt");
        if (Modifiers.HasFlag(HotKeyModifiers.Shift)) parts.Add("Shift");
        if (Modifiers.HasFlag(HotKeyModifiers.Win)) parts.Add("Win");
        parts.Add(Key.ToString());
        return string.Join("+", parts);
    }

    public static bool TryParse(string? text, out HotKey hotKey)
    {
        hotKey = default;
        if (string.IsNullOrWhiteSpace(text)) return false;
        var modifiers = HotKeyModifiers.None;
        var key = Keys.None;
        foreach (var raw in text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (raw.ToLowerInvariant())
            {
                case "ctrl" or "control": modifiers |= HotKeyModifiers.Control; break;
                case "alt": modifiers |= HotKeyModifiers.Alt; break;
                case "shift": modifiers |= HotKeyModifiers.Shift; break;
                case "win" or "windows": modifiers |= HotKeyModifiers.Win; break;
                default:
                    if (key != Keys.None || !Enum.TryParse(raw, true, out key) || !Enum.IsDefined(key)) return false;
                    break;
            }
        }
        hotKey = new HotKey(modifiers, key);
        return hotKey.IsValid;
    }

    /// <summary>Builds a shortcut from a key event in Baddel's own settings window.</summary>
    public static HotKey FromKeyEvent(Keys keyData)
    {
        var modifiers = HotKeyModifiers.None;
        if ((keyData & Keys.Control) != 0) modifiers |= HotKeyModifiers.Control;
        if ((keyData & Keys.Alt) != 0) modifiers |= HotKeyModifiers.Alt;
        if ((keyData & Keys.Shift) != 0) modifiers |= HotKeyModifiers.Shift;
        return new HotKey(modifiers, keyData & Keys.KeyCode);
    }
}

/// <summary>
/// Registers one system-wide hot key with <c>RegisterHotKey</c>. Windows posts a
/// message only when that combination is pressed; no keyboard hook is installed,
/// so Baddel never sees ordinary typing. <c>MOD_NOREPEAT</c> makes the system
/// suppress auto-repeat, so every notification is a distinct press.
/// </summary>
public sealed class HotKeyListener : NativeWindow, IDisposable
{
    private const int HotKeyId = 0x4244;
    private bool registered;

    public event Action? Pressed;

    public HotKeyListener()
    {
        // A message-only window: never visible, never focused.
        CreateHandle(new CreateParams { Parent = new IntPtr(-3) });
    }

    public bool IsRegistered => registered;

    /// <returns><c>false</c> if Windows refused the combination, for example because another app owns it.</returns>
    public bool Register(HotKey hotKey)
    {
        Unregister();
        if (!hotKey.IsValid) return false;
        registered = NativeMethods.RegisterHotKey(
            Handle, HotKeyId, (uint)hotKey.Modifiers | NativeMethods.MOD_NOREPEAT, (uint)hotKey.Key);
        return registered;
    }

    public void Unregister()
    {
        if (registered) NativeMethods.UnregisterHotKey(Handle, HotKeyId);
        registered = false;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == NativeMethods.WM_HOTKEY && m.WParam.ToInt32() == HotKeyId)
        {
            Pressed?.Invoke();
            return;
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        Unregister();
        DestroyHandle();
    }
}
