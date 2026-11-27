using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using Baddel.Core;

namespace Baddel.Linux;

/// <summary>
/// Builds layout tables from the XKB definitions installed on this system, so the
/// mapping always matches what the keyboard actually types. Nothing is copied
/// from another platform's table.
/// </summary>
public static class XkbLayouts
{
    // The same 47 keys as shared/layouts, as evdev key codes (PC scan code + 8).
    private static readonly (string Code, uint Key)[] Keys =
    {
        ("Backquote", 49), ("Digit1", 10), ("Digit2", 11), ("Digit3", 12), ("Digit4", 13),
        ("Digit5", 14), ("Digit6", 15), ("Digit7", 16), ("Digit8", 17), ("Digit9", 18),
        ("Digit0", 19), ("Minus", 20), ("Equal", 21),
        ("KeyQ", 24), ("KeyW", 25), ("KeyE", 26), ("KeyR", 27), ("KeyT", 28), ("KeyY", 29),
        ("KeyU", 30), ("KeyI", 31), ("KeyO", 32), ("KeyP", 33), ("BracketLeft", 34),
        ("BracketRight", 35), ("Backslash", 51),
        ("KeyA", 38), ("KeyS", 39), ("KeyD", 40), ("KeyF", 41), ("KeyG", 42), ("KeyH", 43),
        ("KeyJ", 44), ("KeyK", 45), ("KeyL", 46), ("Semicolon", 47), ("Quote", 48),
        ("KeyZ", 52), ("KeyX", 53), ("KeyC", 54), ("KeyV", 55), ("KeyB", 56), ("KeyN", 57),
        ("KeyM", 58), ("Comma", 59), ("Period", 60), ("Slash", 61),
    };

    /// <summary>
    /// The table for an XKB layout such as <c>us</c> or <c>ara</c>, with an optional
    /// variant. Returns <c>null</c> if the system has no such layout.
    /// </summary>
    public static KeyboardLayout? Load(string layout, string? variant, Script script)
    {
        var context = XkbCommon.xkb_context_new(0);
        if (context == IntPtr.Zero) return null;
        var names = new XkbCommon.RuleNames
        {
            layout = Marshal.StringToCoTaskMemUTF8(layout),
            variant = string.IsNullOrEmpty(variant) ? IntPtr.Zero : Marshal.StringToCoTaskMemUTF8(variant),
        };
        try
        {
            var keymap = XkbCommon.xkb_keymap_new_from_names(context, ref names, 0);
            if (keymap == IntPtr.Zero) return null;
            var keys = new List<LayoutKey>();
            foreach (var (code, key) in Keys)
            {
                keys.Add(new LayoutKey(code, Output(keymap, key, 0), Output(keymap, key, 1)));
            }
            XkbCommon.xkb_keymap_unref(keymap);
            var id = string.IsNullOrEmpty(variant) ? $"xkb-{layout}" : $"xkb-{layout}-{variant}";
            return new KeyboardLayout
            {
                Id = id,
                Name = id,
                Script = script,
                PlatformIds = new Dictionary<string, IReadOnlyList<string>> { ["linux"] = new[] { id } },
                Keys = keys,
            };
        }
        finally
        {
            Marshal.FreeCoTaskMem(names.layout);
            if (names.variant != IntPtr.Zero) Marshal.FreeCoTaskMem(names.variant);
            XkbCommon.xkb_context_unref(context);
        }
    }

    private static string Output(IntPtr keymap, uint key, uint level)
    {
        var count = XkbCommon.xkb_keymap_key_get_syms_by_level(keymap, key, 0, level, out var syms);
        if (count != 1 || syms == IntPtr.Zero) return string.Empty;
        var codePoint = XkbCommon.xkb_keysym_to_utf32(unchecked((uint)Marshal.ReadInt32(syms)));
        // Dead keys and keys without a character have no code point.
        return codePoint < 0x20 || codePoint == 0x7F ? string.Empty : char.ConvertFromUtf32((int)codePoint);
    }
}
