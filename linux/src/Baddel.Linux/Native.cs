using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Baddel.Linux;

/// <summary>Xlib and XKB. XIDs and C longs are 64-bit on the supported platforms.</summary>
internal static class X11
{
    private const string Lib = "libX11.so.6";

    internal const int KeyPress = 2;
    internal const int KeyRelease = 3;
    internal const int ButtonPress = 4;
    internal const int Expose = 12;
    internal const long ButtonPressMask = 1L << 2;
    internal const long ExposureMask = 1L << 15;
    internal const int GrabModeAsync = 1;
    internal const uint ShiftMask = 1, LockMask = 2, ControlMask = 4, Mod1Mask = 8, Mod2Mask = 16, Mod4Mask = 64;
    internal const uint XkbUseCoreKbd = 0x0100;
    internal const ulong CWOverrideRedirect = 1UL << 9;

    /// <summary>The XEvent union: 24 longs. Only the fields Baddel reads are named.</summary>
    [StructLayout(LayoutKind.Explicit, Size = 192)]
    internal struct XEvent
    {
        [FieldOffset(0)] public int type;
        [FieldOffset(32)] public IntPtr window;
        [FieldOffset(80)] public uint state;
        /// <summary>Key code for key events, button number for button events.</summary>
        [FieldOffset(84)] public uint detail;
    }

    [DllImport(Lib)] internal static extern IntPtr XOpenDisplay(string? name);
    [DllImport(Lib)] internal static extern int XCloseDisplay(IntPtr display);
    [DllImport(Lib)] internal static extern int XDefaultScreen(IntPtr display);
    [DllImport(Lib)] internal static extern IntPtr XDefaultRootWindow(IntPtr display);
    [DllImport(Lib)] internal static extern int XDisplayWidth(IntPtr display, int screen);
    [DllImport(Lib)] internal static extern int XDisplayHeight(IntPtr display, int screen);
    [DllImport(Lib)] internal static extern ulong XWhitePixel(IntPtr display, int screen);
    [DllImport(Lib)] internal static extern ulong XBlackPixel(IntPtr display, int screen);
    [DllImport(Lib)] internal static extern IntPtr XStringToKeysym(string name);
    [DllImport(Lib)] internal static extern byte XKeysymToKeycode(IntPtr display, IntPtr keysym);
    [DllImport(Lib)] internal static extern int XGrabKey(IntPtr display, int keycode, uint modifiers, IntPtr window, int ownerEvents, int pointerMode, int keyboardMode);
    [DllImport(Lib)] internal static extern int XUngrabKey(IntPtr display, int keycode, uint modifiers, IntPtr window);
    [StructLayout(LayoutKind.Sequential)]
    internal struct XClassHint
    {
        public IntPtr Name;
        public IntPtr Class;
    }

    [DllImport(Lib)] internal static extern int XGetInputFocus(IntPtr display, out IntPtr focus, out int revertTo);
    [DllImport(Lib)] internal static extern int XGetClassHint(IntPtr display, IntPtr window, out XClassHint hint);
    [DllImport(Lib)] internal static extern int XQueryTree(IntPtr display, IntPtr window, out IntPtr root, out IntPtr parent, out IntPtr children, out uint count);
    [DllImport(Lib)] internal static extern int XFree(IntPtr data);
    [DllImport(Lib)] internal static extern int XPending(IntPtr display);
    [DllImport(Lib)] internal static extern int XNextEvent(IntPtr display, out XEvent xevent);
    [DllImport(Lib)] internal static extern int XFlush(IntPtr display);
    [DllImport(Lib)] internal static extern int XSync(IntPtr display, int discard);
    [DllImport(Lib)] internal static extern IntPtr XSetErrorHandler(ErrorHandler handler);
    [DllImport(Lib)] internal static extern int XkbSetDetectableAutoRepeat(IntPtr display, int detectable, out int supported);
    [DllImport(Lib)] internal static extern int XkbLockGroup(IntPtr display, uint device, uint group);
    [DllImport(Lib)] internal static extern int XkbGetState(IntPtr display, uint device, [Out] byte[] state);
    [DllImport(Lib)] internal static extern IntPtr XCreateSimpleWindow(IntPtr display, IntPtr parent, int x, int y, uint width, uint height, uint borderWidth, ulong border, ulong background);
    [DllImport(Lib)] internal static extern int XChangeWindowAttributes(IntPtr display, IntPtr window, ulong mask, byte[] attributes);
    [DllImport(Lib)] internal static extern int XStoreName(IntPtr display, IntPtr window, string name);
    [DllImport(Lib)] internal static extern int XSelectInput(IntPtr display, IntPtr window, long mask);
    [DllImport(Lib)] internal static extern int XMapRaised(IntPtr display, IntPtr window);
    [DllImport(Lib)] internal static extern int XUnmapWindow(IntPtr display, IntPtr window);
    [DllImport(Lib)] internal static extern int XMoveWindow(IntPtr display, IntPtr window, int x, int y);
    [DllImport(Lib)] internal static extern IntPtr XCreateGC(IntPtr display, IntPtr drawable, ulong mask, IntPtr values);
    [DllImport(Lib)] internal static extern int XSetForeground(IntPtr display, IntPtr gc, ulong pixel);
    [DllImport(Lib)] internal static extern int XDrawString(IntPtr display, IntPtr drawable, IntPtr gc, int x, int y, string text, int length);
    [DllImport(Lib)] internal static extern int XClearWindow(IntPtr display, IntPtr window);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate int ErrorHandler(IntPtr display, IntPtr errorEvent);
}

/// <summary>libxkbcommon: reads the system's own XKB layout definitions.</summary>
internal static class XkbCommon
{
    private const string Lib = "libxkbcommon.so.0";

    [StructLayout(LayoutKind.Sequential)]
    internal struct RuleNames
    {
        public IntPtr rules, model, layout, variant, options;
    }

    [DllImport(Lib)] internal static extern IntPtr xkb_context_new(int flags);
    [DllImport(Lib)] internal static extern void xkb_context_unref(IntPtr context);
    [DllImport(Lib)] internal static extern IntPtr xkb_keymap_new_from_names(IntPtr context, ref RuleNames names, int flags);
    [DllImport(Lib)] internal static extern void xkb_keymap_unref(IntPtr keymap);
    [DllImport(Lib)] internal static extern int xkb_keymap_key_get_syms_by_level(IntPtr keymap, uint key, uint layout, uint level, out IntPtr syms);
    [DllImport(Lib)] internal static extern uint xkb_keysym_to_utf32(uint keysym);
}

/// <summary>libatspi: the AT-SPI 2 accessibility client library.</summary>
internal static class Atspi
{
    private const string Lib = "libatspi.so.0";

    // Values from atspi-constants.h; linux/scripts/check-atspi-constants.sh
    // compares them with the installed header in CI.
    internal const int StateActive = 1;
    internal const int StateEditable = 7;
    internal const int StateEnabled = 8;
    internal const int StateFocused = 12;
    internal const int StateSensitive = 24;
    internal const int RolePasswordText = 40;
    internal const int CoordScreen = 0;

    [StructLayout(LayoutKind.Sequential)]
    internal struct Range
    {
        public int start, end;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Rect
    {
        public int x, y, width, height;
    }

    [DllImport(Lib)] internal static extern int atspi_init();
    [DllImport(Lib)] internal static extern IntPtr atspi_get_desktop(int index);
    [DllImport(Lib)] internal static extern void atspi_accessible_clear_cache(IntPtr accessible);
    [DllImport(Lib)] internal static extern int atspi_accessible_get_child_count(IntPtr accessible, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_child_at_index(IntPtr accessible, int index, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_state_set(IntPtr accessible);
    [DllImport(Lib)] internal static extern int atspi_state_set_contains(IntPtr set, int state);
    [DllImport(Lib)] internal static extern int atspi_accessible_get_role(IntPtr accessible, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_text_iface(IntPtr accessible);
    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_editable_text_iface(IntPtr accessible);
    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_component_iface(IntPtr accessible);
    [DllImport(Lib)] internal static extern int atspi_text_get_character_count(IntPtr text, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_text_get_text(IntPtr text, int start, int end, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_text_get_caret_offset(IntPtr text, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_text_get_n_selections(IntPtr text, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_text_get_selection(IntPtr text, int index, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_text_set_caret_offset(IntPtr text, int offset, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_text_set_selection(IntPtr text, int index, int start, int end, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_text_add_selection(IntPtr text, int start, int end, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_text_remove_selection(IntPtr text, int index, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_text_get_character_extents(IntPtr text, int offset, int coordType, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_component_get_extents(IntPtr component, int coordType, IntPtr error);
    [DllImport(Lib)] internal static extern int atspi_editable_text_delete_text(IntPtr editable, int start, int end, IntPtr error);
    /// <summary>
    /// <paramref name="text"/> must be UTF-8 that ends with a NUL byte: libatspi
    /// sends it on as a C string. <paramref name="length"/> is the number of bytes
    /// before that NUL. Use <see cref="NativeText.NulTerminatedUtf8"/> to build it.
    /// </summary>
    [DllImport(Lib)] internal static extern int atspi_editable_text_insert_text(IntPtr editable, int position, byte[] text, int length, IntPtr error);

    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_role_name(IntPtr accessible, IntPtr error);
    [DllImport(Lib)] internal static extern IntPtr atspi_accessible_get_toolkit_name(IntPtr accessible, IntPtr error);

    /// <summary>Reads and frees a string libatspi allocated.</summary>
    internal static string TakeString(IntPtr pointer)
    {
        if (pointer == IntPtr.Zero) return string.Empty;
        try
        {
            return Marshal.PtrToStringUTF8(pointer) ?? string.Empty;
        }
        finally
        {
            g_free(pointer);
        }
    }

    [DllImport("libglib-2.0.so.0")] internal static extern void g_free(IntPtr memory);
    [DllImport("libgobject-2.0.so.0")] internal static extern void g_object_unref(IntPtr instance);
}

/// <summary>Text prepared for native calls that expect a C string.</summary>
public static class NativeText
{
    /// <summary>
    /// The NUL-terminated string at <paramref name="pointer"/>, or <c>null</c> if its
    /// bytes are not valid UTF-8.
    /// </summary>
    public static string? StrictUtf8(IntPtr pointer)
    {
        if (pointer == IntPtr.Zero) return null;
        var length = 0;
        while (Marshal.ReadByte(pointer, length) != 0) length++;
        var bytes = new byte[length];
        Marshal.Copy(pointer, bytes, 0, length);
        return StrictUtf8(bytes);
    }

    public static string? StrictUtf8(byte[] bytes)
    {
        try
        {
            return new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true).GetString(bytes);
        }
        catch (DecoderFallbackException)
        {
            return null;
        }
    }

    /// <summary>
    /// The text as UTF-8 followed by one NUL byte, or <c>null</c> if it cannot be
    /// passed as a C string at all: it holds a NUL itself, or an unpaired surrogate
    /// that has no UTF-8 form.
    /// </summary>
    public static byte[]? NulTerminatedUtf8(string value)
    {
        if (value.Contains('\0')) return null;
        try
        {
            var strict = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true);
            var count = strict.GetByteCount(value);
            var bytes = new byte[count + 1];
            strict.GetBytes(value, 0, value.Length, bytes, 0);
            return bytes;
        }
        catch (EncoderFallbackException)
        {
            return null;
        }
    }
}
