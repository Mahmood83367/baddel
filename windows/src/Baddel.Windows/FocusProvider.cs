using System;
using System.Diagnostics;
using System.Windows.Automation;
using Baddel.Core;

namespace Baddel.Windows;

/// <summary>Finds the text field that has keyboard focus.</summary>
public sealed class FocusProvider : IFocusProvider
{
    private static readonly int OwnProcessId = Process.GetCurrentProcess().Id;
    private readonly uint? threadId;

    /// <summary>Optional paste fallback handed to UI Automation fields; <c>null</c> disables it.</summary>
    public ClipboardPaster? Paster { get; set; }

    /// <summary>Focus of the foreground window.</summary>
    public FocusProvider()
    {
    }

    /// <summary>Focus within one window's thread (used by the developer check tool).</summary>
    public FocusProvider(IntPtr window)
    {
        threadId = NativeMethods.GetWindowThreadProcessId(window, out _);
    }

    public IEditableField? FocusedField()
    {
        uint thread;
        if (threadId is { } fixedThread)
        {
            thread = fixedThread;
        }
        else
        {
            var foreground = NativeMethods.GetForegroundWindow();
            if (foreground == IntPtr.Zero) return null;
            thread = NativeMethods.GetWindowThreadProcessId(foreground, out var processId);
            // Baddel never edits its own windows.
            if (processId == OwnProcessId) return null;
        }

        var info = new NativeMethods.GUITHREADINFO
        {
            cbSize = System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.GUITHREADINFO>(),
        };
        var focus = NativeMethods.GetGUIThreadInfo(thread, ref info) ? info.hwndFocus : IntPtr.Zero;
        if (focus != IntPtr.Zero)
        {
            var className = NativeMethods.ClassName(focus);
            if (Win32EditField.IsEditClass(className)) return new Win32EditField(focus);
            if (Win32EditField.IsRichEditClass(className) && RichEditIsSingleLine(focus))
            {
                return new Win32EditField(focus);
            }
        }

        try
        {
            var element = threadId is null
                ? AutomationElement.FocusedElement
                : focus != IntPtr.Zero ? AutomationElement.FromHandle(focus) : null;
            if (element is null || element.Current.ProcessId == OwnProcessId) return null;
            return new UiaField(element, Paster);
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>
    /// Rich edit controls count a paragraph break as one character in selection
    /// offsets but may report it as two in their text, so message-based editing is
    /// only used while the content has no line break. Anything else goes through
    /// UI Automation.
    /// </summary>
    private static bool RichEditIsSingleLine(IntPtr handle)
    {
        var field = new Win32EditField(handle);
        if (field.IsSecure) return true;
        try
        {
            return field.ReadText().AsSpan().IndexOfAny('\r', '\n') < 0;
        }
        catch (RejectionException)
        {
            return false;
        }
    }
}
