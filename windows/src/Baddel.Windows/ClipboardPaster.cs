using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;
using System.Windows.Forms;
using Baddel.Core;

namespace Baddel.Windows;

/// <summary>
/// Last-resort writer for controls that cannot be edited directly: pastes over a
/// selection the caller has already verified, then puts the user's clipboard
/// back. Off unless the user enables it. Must be called on an STA thread.
/// </summary>
public sealed class ClipboardPaster
{
    /// <param name="text">The replacement text.</param>
    /// <param name="confirm">
    /// Called immediately before Ctrl+V is sent. If it returns <c>false</c> nothing
    /// is pasted, the clipboard is restored and <see cref="Rejection.FocusChanged"/>
    /// is thrown.
    /// </param>
    /// <param name="wait">Called after Ctrl+V is sent; blocks until the paste has landed or timed out.</param>
    public void Paste(string text, Func<bool> confirm, Action wait)
    {
        var saved = Snapshot();
        var transient = new DataObject();
        transient.SetData(DataFormats.UnicodeText, text);
        // Ask clipboard history and cloud sync not to keep this transient entry.
        transient.SetData("ExcludeClipboardContentFromMonitorProcessing", new MemoryStream(new byte[] { 0 }));
        transient.SetData("CanIncludeInClipboardHistory", new MemoryStream(new byte[4]));
        transient.SetData("CanUploadToCloudClipboard", new MemoryStream(new byte[4]));
        try
        {
            Clipboard.SetDataObject(transient, true, 5, 40);
        }
        catch (Exception)
        {
            throw new RejectionException(Rejection.WriteFailed);
        }
        var ours = NativeMethods.GetClipboardSequenceNumber();

        try
        {
            // Ctrl+V must not be combined with a shortcut modifier that is still held.
            if (!WaitForModifiersReleased(700)) throw new RejectionException(Rejection.WriteFailed);
            if (!confirm()) throw new RejectionException(Rejection.FocusChanged);
            SendCtrlV();
            wait();
        }
        finally
        {
            // Restore only if nothing else has written to the clipboard since.
            if (NativeMethods.GetClipboardSequenceNumber() == ours) Restore(saved);
        }
    }

    private static List<KeyValuePair<string, object>> Snapshot()
    {
        var items = new List<KeyValuePair<string, object>>();
        try
        {
            var current = Clipboard.GetDataObject();
            if (current is null) return items;
            foreach (var format in current.GetFormats(false))
            {
                try
                {
                    var data = current.GetData(format, false);
                    if (data is null) continue;
                    // Streams belong to the old clipboard object; copy them out now.
                    if (data is MemoryStream stream) data = new MemoryStream(stream.ToArray());
                    items.Add(new KeyValuePair<string, object>(format, data));
                }
                catch (Exception)
                {
                    // A format that cannot be read is skipped; the rest are kept.
                }
            }
        }
        catch (Exception)
        {
        }
        return items;
    }

    private static void Restore(List<KeyValuePair<string, object>> items)
    {
        try
        {
            if (items.Count == 0)
            {
                Clipboard.Clear();
                return;
            }
            var restored = new DataObject();
            foreach (var item in items) restored.SetData(item.Key, false, item.Value);
            Clipboard.SetDataObject(restored, true, 5, 40);
        }
        catch (Exception)
        {
        }
    }

    private static bool WaitForModifiersReleased(int timeoutMs)
    {
        var deadline = Environment.TickCount64 + timeoutMs;
        while (true)
        {
            var held = false;
            foreach (var key in new[]
                     {
                         NativeMethods.VK_SHIFT, NativeMethods.VK_CONTROL, NativeMethods.VK_MENU,
                         NativeMethods.VK_LWIN, NativeMethods.VK_RWIN,
                     })
            {
                held |= (NativeMethods.GetAsyncKeyState(key) & 0x8000) != 0;
            }
            if (!held) return true;
            if (Environment.TickCount64 >= deadline) return false;
            Thread.Sleep(20);
        }
    }

    private static void SendCtrlV()
    {
        var inputs = new[]
        {
            InputSender.Key(NativeMethods.VK_CONTROL, false),
            InputSender.Key(NativeMethods.VK_V, false),
            InputSender.Key(NativeMethods.VK_V, true),
            InputSender.Key(NativeMethods.VK_CONTROL, true),
        };
        if (!InputSender.Send(inputs)) throw new RejectionException(Rejection.WriteFailed);
    }
}

/// <summary>Synthesises input. Used for the paste fallback and by the developer check tool.</summary>
public static class InputSender
{
    internal static NativeMethods.INPUT Key(int virtualKey, bool up) => new()
    {
        type = NativeMethods.INPUT_KEYBOARD,
        u = new NativeMethods.INPUTUNION
        {
            ki = new NativeMethods.KEYBDINPUT
            {
                wVk = (ushort)virtualKey,
                dwFlags = up ? NativeMethods.KEYEVENTF_KEYUP : 0,
            },
        },
    };

    internal static bool Send(NativeMethods.INPUT[] inputs) =>
        NativeMethods.SendInput((uint)inputs.Length, inputs, System.Runtime.InteropServices.Marshal.SizeOf<NativeMethods.INPUT>())
        == inputs.Length;

    /// <summary>Presses and releases a shortcut once. Returns false if the system refused the input.</summary>
    public static bool PressHotKey(HotKey hotKey)
    {
        var inputs = new List<NativeMethods.INPUT>();
        var modifiers = new List<int>();
        if (hotKey.Modifiers.HasFlag(HotKeyModifiers.Control)) modifiers.Add(NativeMethods.VK_CONTROL);
        if (hotKey.Modifiers.HasFlag(HotKeyModifiers.Alt)) modifiers.Add(NativeMethods.VK_MENU);
        if (hotKey.Modifiers.HasFlag(HotKeyModifiers.Shift)) modifiers.Add(NativeMethods.VK_SHIFT);
        if (hotKey.Modifiers.HasFlag(HotKeyModifiers.Win)) modifiers.Add(NativeMethods.VK_LWIN);
        foreach (var modifier in modifiers) inputs.Add(Key(modifier, false));
        inputs.Add(Key((int)hotKey.Key, false));
        inputs.Add(Key((int)hotKey.Key, true));
        modifiers.Reverse();
        foreach (var modifier in modifiers) inputs.Add(Key(modifier, true));
        return Send(inputs.ToArray());
    }

    /// <summary>Moves the pointer to a screen point and clicks the left button.</summary>
    public static bool Click(int x, int y)
    {
        const int SM_XVIRTUALSCREEN = 76, SM_YVIRTUALSCREEN = 77, SM_CXVIRTUALSCREEN = 78, SM_CYVIRTUALSCREEN = 79;
        var left = NativeMethods.GetSystemMetrics(SM_XVIRTUALSCREEN);
        var top = NativeMethods.GetSystemMetrics(SM_YVIRTUALSCREEN);
        var width = Math.Max(NativeMethods.GetSystemMetrics(SM_CXVIRTUALSCREEN), 1);
        var height = Math.Max(NativeMethods.GetSystemMetrics(SM_CYVIRTUALSCREEN), 1);
        NativeMethods.INPUT Mouse(uint flags) => new()
        {
            type = NativeMethods.INPUT_MOUSE,
            u = new NativeMethods.INPUTUNION
            {
                mi = new NativeMethods.MOUSEINPUT
                {
                    dx = (int)(((x - left) * 65535L) / (width - 1 == 0 ? 1 : width - 1)),
                    dy = (int)(((y - top) * 65535L) / (height - 1 == 0 ? 1 : height - 1)),
                    dwFlags = flags | NativeMethods.MOUSEEVENTF_ABSOLUTE | NativeMethods.MOUSEEVENTF_VIRTUALDESK,
                },
            },
        };
        if (!Send(new[] { Mouse(NativeMethods.MOUSEEVENTF_MOVE) })) return false;
        Thread.Sleep(60);
        if (!Send(new[] { Mouse(NativeMethods.MOUSEEVENTF_LEFTDOWN) })) return false;
        Thread.Sleep(40);
        return Send(new[] { Mouse(NativeMethods.MOUSEEVENTF_LEFTUP) });
    }
}
