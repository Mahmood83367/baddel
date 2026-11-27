using System;
using System.Drawing;
using System.Threading;
using Baddel.Core;

namespace Baddel.Windows;

/// <summary>Where the Undo popup should appear, in screen pixels.</summary>
public interface IAnchoredField
{
    /// <summary>Rectangle of the caret or edited text, or <c>null</c> if unknown.</summary>
    Rectangle? TextAnchor();

    /// <summary>Rectangle of the whole field, or <c>null</c> if unknown.</summary>
    Rectangle? FieldBounds();

    /// <summary>Which write strategy the last successful replace used. A code, not text.</summary>
    string LastWriteStrategy { get; }
}

/// <summary>
/// A standard Win32 edit control in another process, edited with edit-control
/// messages. Offsets are UTF-16 indices into the control's text, which is what
/// <c>EM_GETSEL</c> / <c>EM_SETSEL</c> use.
/// </summary>
public sealed class Win32EditField : IEditableField, IAnchoredField
{
    public IntPtr Handle { get; }
    public string ClassName { get; }
    public string LastWriteStrategy { get; private set; } = "none";

    public Win32EditField(IntPtr handle)
    {
        Handle = handle;
        ClassName = NativeMethods.ClassName(handle);
    }

    /// <summary>The classic edit control and frameworks that superclass it (for example WinForms).</summary>
    public static bool IsEditClass(string className) =>
        className.Equals("Edit", StringComparison.OrdinalIgnoreCase)
        || className.Contains(".EDIT.", StringComparison.OrdinalIgnoreCase);

    public static bool IsRichEditClass(string className) =>
        className.Contains("RichEdit", StringComparison.OrdinalIgnoreCase);

    public bool IsSameField(IEditableField other) => other is Win32EditField field && field.Handle == Handle;

    public bool IsSecure
    {
        get
        {
            if ((NativeMethods.GetWindowStyle(Handle) & NativeMethods.ES_PASSWORD) != 0) return true;
            // If the control does not answer, treat it as secure rather than guess.
            if (!NativeMethods.Send(Handle, NativeMethods.EM_GETPASSWORDCHAR, IntPtr.Zero, IntPtr.Zero, out var mask)) return true;
            return mask != IntPtr.Zero;
        }
    }

    public bool IsEditableText
    {
        get
        {
            if (!NativeMethods.IsWindow(Handle)) return false;
            var style = NativeMethods.GetWindowStyle(Handle);
            return (style & (NativeMethods.ES_READONLY | NativeMethods.WS_DISABLED)) == 0;
        }
    }

    public string ReadText()
    {
        if (IsSecure) throw new RejectionException(Rejection.SecureField);
        if (!NativeMethods.Send(Handle, NativeMethods.WM_GETTEXTLENGTH, IntPtr.Zero, IntPtr.Zero, out var lengthResult))
        {
            throw new RejectionException(Rejection.ReadFailed);
        }
        var length = lengthResult.ToInt32();
        if (length <= 0) return string.Empty;
        if (length > CorrectionEngine.MaxFieldLength) throw new RejectionException(Rejection.FieldTooLarge);
        var buffer = new char[length + 1];
        var sent = NativeMethods.SendMessageTimeoutText(
            Handle, NativeMethods.WM_GETTEXT, new IntPtr(buffer.Length), buffer,
            NativeMethods.SMTO_ABORTIFHUNG, NativeMethods.MessageTimeoutMs, out var copied);
        if (sent == IntPtr.Zero) throw new RejectionException(Rejection.ReadFailed);
        return new string(buffer, 0, Math.Min(copied.ToInt32(), length));
    }

    public Utf16Range ReadSelection()
    {
        var sent = NativeMethods.SendMessageTimeoutSel(
            Handle, NativeMethods.EM_GETSEL, out var start, out var end,
            NativeMethods.SMTO_ABORTIFHUNG, NativeMethods.MessageTimeoutMs, out _);
        if (sent == IntPtr.Zero || end < start) throw new RejectionException(Rejection.ReadFailed);
        return new Utf16Range((int)start, (int)(end - start));
    }

    public void SetSelection(Utf16Range range)
    {
        NativeMethods.Send(Handle, NativeMethods.EM_SETSEL, new IntPtr(range.Location), new IntPtr(range.End), out _);
    }

    /// <summary>
    /// Selects exactly <paramref name="range"/>, confirms the selection and that the
    /// text is still the planned snapshot, then replaces the selection with
    /// <c>EM_REPLACESEL</c> (which the control records in its own undo buffer).
    /// </summary>
    public void Replace(Utf16Range range, string snapshot, string replacement)
    {
        if (IsSecure) throw new RejectionException(Rejection.SecureField);
        var expected = CorrectionEngine.ValidatedReplacement(range, snapshot, ReadText(), replacement);
        Utf16Range? original = null;
        try
        {
            original = ReadSelection();
        }
        catch (RejectionException)
        {
        }

        void RestoreSelection()
        {
            if (original is { } selection && SafeRead() == snapshot) SetSelection(selection);
        }

        SetSelection(range);
        Utf16Range selected;
        try
        {
            selected = ReadSelection();
        }
        catch (RejectionException)
        {
            RestoreSelection();
            throw new RejectionException(Rejection.WriteFailed);
        }
        if (selected != range)
        {
            RestoreSelection();
            throw new RejectionException(Rejection.WriteFailed);
        }
        // Re-checked immediately before the mutation.
        if (SafeRead() != snapshot)
        {
            throw new RejectionException(Rejection.FieldChanged);
        }

        NativeMethods.SendMessageTimeoutString(
            Handle, NativeMethods.EM_REPLACESEL, new IntPtr(1), replacement,
            NativeMethods.SMTO_ABORTIFHUNG, NativeMethods.MessageTimeoutMs, out _);

        var deadline = Environment.TickCount64 + 200;
        while (true)
        {
            var now = SafeRead();
            if (now == expected)
            {
                LastWriteStrategy = "editMessages";
                return;
            }
            if (now != snapshot) throw new RejectionException(Rejection.VerificationFailed);
            if (Environment.TickCount64 >= deadline) break;
            Thread.Sleep(15);
        }
        RestoreSelection();
        throw new RejectionException(Rejection.WriteFailed);
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

    public Rectangle? TextAnchor()
    {
        var thread = NativeMethods.GetWindowThreadProcessId(Handle, out _);
        var info = new NativeMethods.GUITHREADINFO { cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.GUITHREADINFO>() };
        if (!NativeMethods.GetGUIThreadInfo(thread, ref info) || info.hwndCaret == IntPtr.Zero) return null;
        var topLeft = new NativeMethods.POINT { X = info.rcCaret.Left, Y = info.rcCaret.Top };
        var bottomRight = new NativeMethods.POINT { X = info.rcCaret.Right, Y = info.rcCaret.Bottom };
        if (!NativeMethods.ClientToScreen(info.hwndCaret, ref topLeft)
            || !NativeMethods.ClientToScreen(info.hwndCaret, ref bottomRight))
        {
            return null;
        }
        var height = bottomRight.Y - topLeft.Y;
        return height > 0 ? new Rectangle(topLeft.X, topLeft.Y, Math.Max(bottomRight.X - topLeft.X, 1), height) : null;
    }

    public Rectangle? FieldBounds()
    {
        if (!NativeMethods.GetWindowRect(Handle, out var rect)) return null;
        var bounds = Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
        return bounds.Width > 0 && bounds.Height > 0 ? bounds : null;
    }
}
