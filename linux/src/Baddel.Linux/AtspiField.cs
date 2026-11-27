using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using Baddel.Core;

namespace Baddel.Linux;

/// <summary>
/// AT-SPI counts text in characters (Unicode code points); the shared core counts
/// UTF-16 units. These helpers convert at the boundary.
/// </summary>
public static class TextOffsets
{
    /// <summary>UTF-16 index of the code point at <paramref name="characters"/>, or -1 if out of range.</summary>
    public static int ToUtf16(string text, int characters)
    {
        if (characters < 0) return -1;
        var index = 0;
        for (var count = 0; count < characters; count++)
        {
            if (index >= text.Length) return -1;
            index += char.IsHighSurrogate(text[index]) && index + 1 < text.Length && char.IsLowSurrogate(text[index + 1]) ? 2 : 1;
        }
        return index;
    }

    /// <summary>Number of code points before a UTF-16 index, or -1 if the index splits a surrogate pair.</summary>
    public static int ToCharacters(string text, int utf16)
    {
        if (utf16 < 0 || utf16 > text.Length) return -1;
        if (utf16 > 0 && utf16 < text.Length && char.IsHighSurrogate(text[utf16 - 1]) && char.IsLowSurrogate(text[utf16])) return -1;
        var count = 0;
        for (var index = 0; index < utf16; count++)
        {
            index += char.IsHighSurrogate(text[index]) && index + 1 < text.Length && char.IsLowSurrogate(text[index + 1]) ? 2 : 1;
        }
        return count;
    }
}

/// <summary>A focused text element reached through AT-SPI.</summary>
public sealed class AtspiField : IEditableField
{
    private readonly IntPtr accessible;
    private readonly IntPtr text;
    private readonly IntPtr editable;
    private readonly int role;

    internal AtspiField(IntPtr accessible)
    {
        this.accessible = accessible;
        role = Atspi.atspi_accessible_get_role(accessible, IntPtr.Zero);
        text = Atspi.atspi_accessible_get_text_iface(accessible);
        editable = Atspi.atspi_accessible_get_editable_text_iface(accessible);
    }

    /// <summary>libatspi hands out one object per remote accessible, so identity is pointer identity.</summary>
    public bool IsSameField(IEditableField other) => other is AtspiField field && field.accessible == accessible;

    public bool IsSecure => role == Atspi.RolePasswordText;

    private bool HasState(int state)
    {
        var set = Atspi.atspi_accessible_get_state_set(accessible);
        if (set == IntPtr.Zero) return false;
        var result = Atspi.atspi_state_set_contains(set, state) != 0;
        Atspi.g_object_unref(set);
        return result;
    }

    public bool IsEditableText =>
        text != IntPtr.Zero && editable != IntPtr.Zero && HasState(Atspi.StateEditable) && HasState(Atspi.StateEnabled);

    public bool HasFocus => HasState(Atspi.StateFocused);

    public string ReadText()
    {
        if (IsSecure) throw new RejectionException(Rejection.SecureField);
        if (text == IntPtr.Zero) throw new RejectionException(Rejection.ReadFailed);
        var count = Atspi.atspi_text_get_character_count(text, IntPtr.Zero);
        if (count < 0) throw new RejectionException(Rejection.ReadFailed);
        if (count > CorrectionEngine.MaxFieldLength) throw new RejectionException(Rejection.FieldTooLarge);
        var pointer = Atspi.atspi_text_get_text(text, 0, count, IntPtr.Zero);
        if (pointer == IntPtr.Zero) throw new RejectionException(Rejection.ReadFailed);
        try
        {
            return Marshal.PtrToStringUTF8(pointer) ?? string.Empty;
        }
        finally
        {
            Atspi.g_free(pointer);
        }
    }

    public Utf16Range ReadSelection()
    {
        var content = ReadText();
        int start, end;
        if (Atspi.atspi_text_get_n_selections(text, IntPtr.Zero) > 0)
        {
            var pointer = Atspi.atspi_text_get_selection(text, 0, IntPtr.Zero);
            if (pointer == IntPtr.Zero) throw new RejectionException(Rejection.ReadFailed);
            var range = Marshal.PtrToStructure<Atspi.Range>(pointer);
            Atspi.g_free(pointer);
            start = Math.Min(range.start, range.end);
            end = Math.Max(range.start, range.end);
        }
        else
        {
            start = end = Atspi.atspi_text_get_caret_offset(text, IntPtr.Zero);
        }
        var from = TextOffsets.ToUtf16(content, start);
        var to = TextOffsets.ToUtf16(content, end);
        if (from < 0 || to < from) throw new RejectionException(Rejection.ReadFailed);
        return new Utf16Range(from, to - from);
    }

    public void SetSelection(Utf16Range range)
    {
        try
        {
            var content = ReadText();
            var start = TextOffsets.ToCharacters(content, range.Location);
            var end = TextOffsets.ToCharacters(content, range.End);
            if (start < 0 || end < 0) return;
            if (start == end)
            {
                while (Atspi.atspi_text_get_n_selections(text, IntPtr.Zero) > 0
                       && Atspi.atspi_text_remove_selection(text, 0, IntPtr.Zero) != 0)
                {
                }
                Atspi.atspi_text_set_caret_offset(text, start, IntPtr.Zero);
            }
            else if (Atspi.atspi_text_get_n_selections(text, IntPtr.Zero) > 0)
            {
                Atspi.atspi_text_set_selection(text, 0, start, end, IntPtr.Zero);
            }
            else
            {
                Atspi.atspi_text_add_selection(text, start, end, IntPtr.Zero);
            }
        }
        catch (RejectionException)
        {
        }
    }

    /// <summary>
    /// Deletes exactly the target range and inserts the replacement at its start.
    /// Nothing is written unless the field still holds the planned snapshot. If
    /// the insertion does not arrive, the deleted text is put back.
    /// </summary>
    public void Replace(Utf16Range range, string snapshot, string replacement)
    {
        if (IsSecure) throw new RejectionException(Rejection.SecureField);
        var expected = CorrectionEngine.ValidatedReplacement(range, snapshot, ReadText(), replacement);
        var start = TextOffsets.ToCharacters(snapshot, range.Location);
        var end = TextOffsets.ToCharacters(snapshot, range.End);
        if (start < 0 || end < start) throw new RejectionException(Rejection.InvalidRange);
        var old = snapshot.Substring(range.Location, range.Length);
        var afterDelete = CorrectionEngine.Replacing(range, snapshot, string.Empty);

        if (end > start && Atspi.atspi_editable_text_delete_text(editable, start, end, IntPtr.Zero) == 0)
        {
            if (SafeRead() == snapshot) throw new RejectionException(Rejection.WriteFailed);
            throw new RejectionException(Rejection.VerificationFailed);
        }
        if (!WaitFor(afterDelete, 300))
        {
            if (SafeRead() == snapshot) throw new RejectionException(Rejection.WriteFailed);
            throw new RejectionException(Rejection.VerificationFailed);
        }

        Insert(start, replacement);
        if (WaitFor(expected, 300)) return;

        // The replacement did not arrive: restore what was deleted.
        if (SafeRead() == afterDelete)
        {
            Insert(start, old);
            if (WaitFor(snapshot, 300)) throw new RejectionException(Rejection.WriteFailed);
        }
        throw new RejectionException(Rejection.VerificationFailed);
    }

    private void Insert(int position, string value)
    {
        if (value.Length == 0) return;
        var bytes = Encoding.UTF8.GetBytes(value);
        Atspi.atspi_editable_text_insert_text(editable, position, bytes, bytes.Length, IntPtr.Zero);
    }

    private bool WaitFor(string? wanted, int timeoutMs)
    {
        var deadline = Environment.TickCount64 + timeoutMs;
        while (true)
        {
            if (SafeRead() == wanted) return true;
            if (Environment.TickCount64 >= deadline) return false;
            Thread.Sleep(15);
        }
    }

    private string? SafeRead()
    {
        try
        {
            return ReadText();
        }
        catch (RejectionException)
        {
            return null;
        }
    }

    /// <summary>Screen rectangle of the caret, or of the element; <c>null</c> if unknown.</summary>
    public (int X, int Y, int Width, int Height)? Anchor()
    {
        (int, int, int, int)? Read(IntPtr pointer)
        {
            if (pointer == IntPtr.Zero) return null;
            var rect = Marshal.PtrToStructure<Atspi.Rect>(pointer);
            Atspi.g_free(pointer);
            return rect.height > 0 && rect.x > -10000 && rect.y > -10000 ? (rect.x, rect.y, Math.Max(rect.width, 1), rect.height) : null;
        }
        var caret = Atspi.atspi_text_get_caret_offset(text, IntPtr.Zero);
        var count = Atspi.atspi_text_get_character_count(text, IntPtr.Zero);
        var result = caret >= 0 && count > 0
            ? Read(Atspi.atspi_text_get_character_extents(text, Math.Min(caret, count - 1), Atspi.CoordScreen, IntPtr.Zero))
            : null;
        if (result is not null) return result;
        var component = Atspi.atspi_accessible_get_component_iface(accessible);
        return component == IntPtr.Zero ? null : Read(Atspi.atspi_component_get_extents(component, Atspi.CoordScreen, IntPtr.Zero));
    }
}

/// <summary>Finds the focused text element by walking the accessibility tree of the active window.</summary>
public sealed class AtspiFocus : IFocusProvider
{
    private const int MaxNodes = 4000;
    private static bool initialised;

    public static bool Initialise()
    {
        if (!initialised)
        {
            var status = Atspi.atspi_init();
            initialised = status == 0 || status == 1;
        }
        return initialised;
    }

    public IEditableField? FocusedField()
    {
        if (!Initialise()) return null;
        var desktop = Atspi.atspi_get_desktop(0);
        if (desktop == IntPtr.Zero) return null;
        // No GLib main loop runs here, so cached state is dropped before each search.
        Atspi.atspi_accessible_clear_cache(desktop);

        var budget = MaxNodes;
        IntPtr fallback = IntPtr.Zero;
        var applications = Atspi.atspi_accessible_get_child_count(desktop, IntPtr.Zero);
        for (var a = 0; a < applications && budget > 0; a++)
        {
            var application = Atspi.atspi_accessible_get_child_at_index(desktop, a, IntPtr.Zero);
            if (application == IntPtr.Zero) continue;
            var windows = Atspi.atspi_accessible_get_child_count(application, IntPtr.Zero);
            for (var w = 0; w < windows && budget > 0; w++)
            {
                var window = Atspi.atspi_accessible_get_child_at_index(application, w, IntPtr.Zero);
                if (window == IntPtr.Zero) continue;
                var found = FindFocused(window, ref budget, 0);
                if (found == IntPtr.Zero) continue;
                if (Has(window, Atspi.StateActive)) return new AtspiField(found);
                if (fallback == IntPtr.Zero) fallback = found;
            }
        }
        // Without a window manager no window is "active"; a single focused element is still usable.
        return fallback == IntPtr.Zero ? null : new AtspiField(fallback);
    }

    private static bool Has(IntPtr accessible, int state)
    {
        var set = Atspi.atspi_accessible_get_state_set(accessible);
        if (set == IntPtr.Zero) return false;
        var result = Atspi.atspi_state_set_contains(set, state) != 0;
        Atspi.g_object_unref(set);
        return result;
    }

    private static IntPtr FindFocused(IntPtr node, ref int budget, int depth)
    {
        if (budget-- <= 0 || depth > 40) return IntPtr.Zero;
        if (Has(node, Atspi.StateFocused) && Atspi.atspi_accessible_get_text_iface(node) != IntPtr.Zero) return node;
        var children = Atspi.atspi_accessible_get_child_count(node, IntPtr.Zero);
        for (var index = 0; index < children && index < 500; index++)
        {
            var child = Atspi.atspi_accessible_get_child_at_index(node, index, IntPtr.Zero);
            if (child == IntPtr.Zero) continue;
            var found = FindFocused(child, ref budget, depth + 1);
            if (found != IntPtr.Zero) return found;
        }
        return IntPtr.Zero;
    }
}
