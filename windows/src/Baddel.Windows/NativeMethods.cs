using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Baddel.Windows;

internal static class NativeMethods
{
    internal const int WM_GETTEXT = 0x000D;
    internal const int WM_GETTEXTLENGTH = 0x000E;
    internal const int WM_INPUTLANGCHANGEREQUEST = 0x0050;
    internal const int WM_HOTKEY = 0x0312;
    internal const int WM_MOUSEACTIVATE = 0x0021;
    internal const int EM_GETSEL = 0x00B0;
    internal const int EM_SETSEL = 0x00B1;
    internal const int EM_REPLACESEL = 0x00C2;
    internal const int EM_GETPASSWORDCHAR = 0x00D2;

    internal const int GWL_STYLE = -16;
    internal const long ES_PASSWORD = 0x0020;
    internal const long ES_READONLY = 0x0800;
    internal const long WS_DISABLED = 0x08000000;

    internal const uint SMTO_ABORTIFHUNG = 0x0002;
    internal const uint MessageTimeoutMs = 1000;

    internal const uint MOD_NOREPEAT = 0x4000;

    internal const int VK_SHIFT = 0x10;
    internal const int VK_CONTROL = 0x11;
    internal const int VK_MENU = 0x12;
    internal const int VK_LWIN = 0x5B;
    internal const int VK_RWIN = 0x5C;
    internal const int VK_V = 0x56;

    internal const uint INPUT_MOUSE = 0;
    internal const uint INPUT_KEYBOARD = 1;
    internal const uint KEYEVENTF_KEYUP = 0x0002;
    internal const uint MOUSEEVENTF_MOVE = 0x0001;
    internal const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    internal const uint MOUSEEVENTF_LEFTUP = 0x0004;
    internal const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    internal const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;

    [StructLayout(LayoutKind.Sequential)]
    internal struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct GUITHREADINFO
    {
        public int cbSize;
        public uint flags;
        public IntPtr hwndActive;
        public IntPtr hwndFocus;
        public IntPtr hwndCapture;
        public IntPtr hwndMenuOwner;
        public IntPtr hwndMoveSize;
        public IntPtr hwndCaret;
        public RECT rcCaret;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Explicit)]
    internal struct INPUTUNION
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct INPUT
    {
        public uint type;
        public INPUTUNION u;
    }

    [DllImport("user32.dll")]
    internal static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetGUIThreadInfo(uint idThread, ref GUITHREADINFO info);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetClassNameW(IntPtr hWnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int index);

    [DllImport("user32.dll", EntryPoint = "GetWindowLongW")]
    private static extern int GetWindowLong32(IntPtr hWnd, int index);

    internal static long GetWindowStyle(IntPtr hWnd) =>
        IntPtr.Size == 8 ? GetWindowLongPtr64(hWnd, GWL_STYLE).ToInt64() : GetWindowLong32(hWnd, GWL_STYLE);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsWindow(IntPtr hWnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
    internal static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam, uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
    internal static extern IntPtr SendMessageTimeoutText(
        IntPtr hWnd, int msg, IntPtr wParam, [Out] char[] lParam, uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageTimeoutW")]
    internal static extern IntPtr SendMessageTimeoutString(
        IntPtr hWnd, int msg, IntPtr wParam, string lParam, uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll", EntryPoint = "SendMessageTimeoutW")]
    internal static extern IntPtr SendMessageTimeoutSel(
        IntPtr hWnd, int msg, out uint wParam, out uint lParam, uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll", EntryPoint = "PostMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PostMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(IntPtr hWnd, int id, uint modifiers, uint vk);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    [DllImport("user32.dll")]
    internal static extern IntPtr GetKeyboardLayout(uint idThread);

    [DllImport("user32.dll")]
    internal static extern int GetKeyboardLayoutList(int count, [Out] IntPtr[]? list);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern IntPtr LoadKeyboardLayoutW(string klid, uint flags);

    [DllImport("user32.dll")]
    internal static extern uint MapVirtualKeyExW(uint code, uint mapType, IntPtr hkl);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int ToUnicodeEx(
        uint virtualKey, uint scanCode, byte[] keyState, [Out] char[] buffer, int bufferSize, uint flags, IntPtr hkl);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);

    [DllImport("user32.dll", SetLastError = true)]
    internal static extern uint SendInput(uint count, INPUT[] inputs, int size);

    [DllImport("user32.dll")]
    internal static extern short GetAsyncKeyState(int vk);

    [DllImport("user32.dll")]
    internal static extern uint GetClipboardSequenceNumber();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern IntPtr FindWindowW(string? className, string? windowName);

    [DllImport("user32.dll")]
    internal static extern int GetSystemMetrics(int index);

    internal static string ClassName(IntPtr hWnd)
    {
        var builder = new StringBuilder(256);
        return GetClassNameW(hWnd, builder, builder.Capacity) > 0 ? builder.ToString() : string.Empty;
    }

    internal static bool Send(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam, out IntPtr result) =>
        SendMessageTimeout(hWnd, msg, wParam, lParam, SMTO_ABORTIFHUNG, MessageTimeoutMs, out result) != IntPtr.Zero;
}
