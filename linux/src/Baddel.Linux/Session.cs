using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using Baddel.Core;

namespace Baddel.Linux;

/// <summary>User preferences. Nothing here is user text.</summary>
public sealed class LinuxSettings
{
    /// <summary>Modifiers (Ctrl, Alt, Shift, Super) and an X keysym name, joined by '+'.</summary>
    public string Shortcut { get; set; } = "Ctrl+Alt+space";

    /// <summary>XKB layout names; the tables are read from this system's XKB data.</summary>
    public string LatinXkbLayout { get; set; } = "us";
    public string ArabicXkbLayout { get; set; } = "ara";
    public string ArabicXkbVariant { get; set; } = "";
    public int DoublePressMs { get; set; } = 300;
    public bool SwitchLayout { get; set; } = true;

    public static string Directory =>
        Environment.GetEnvironmentVariable("BADDEL_SETTINGS_DIR") is { Length: > 0 } custom
            ? custom
            : Path.Combine(
                Environment.GetEnvironmentVariable("XDG_CONFIG_HOME") is { Length: > 0 } config
                    ? config
                    : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config"),
                "baddel");

    public static LinuxSettings Load()
    {
        try
        {
            var path = Path.Combine(Directory, "settings.json");
            return File.Exists(path) ? JsonSerializer.Deserialize<LinuxSettings>(File.ReadAllText(path)) ?? new LinuxSettings() : new LinuxSettings();
        }
        catch (Exception exception) when (exception is IOException or JsonException)
        {
            return new LinuxSettings();
        }
    }

    public LayoutPair? LoadPair()
    {
        var latin = XkbLayouts.Load(LatinXkbLayout, null, Script.Latin);
        var arabic = XkbLayouts.Load(ArabicXkbLayout, ArabicXkbVariant, Script.Arabic);
        return latin is null || arabic is null ? null : new LayoutPair(latin, arabic);
    }
}

/// <summary>
/// How another process tells the running app that the shortcut was pressed: a
/// Unix socket in the user's runtime directory. This is the path for desktops
/// where the user binds a key to <c>baddel --trigger</c> in their own keyboard
/// settings (for example on Wayland), and it needs no privileges.
/// </summary>
public static class TriggerChannel
{
    public static string SocketPath =>
        Path.Combine(
            Environment.GetEnvironmentVariable("XDG_RUNTIME_DIR") is { Length: > 0 } runtime ? runtime : Path.GetTempPath(),
            "baddel.sock");

    public static bool Send(string command)
    {
        try
        {
            using var socket = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            socket.Connect(new UnixDomainSocketEndPoint(SocketPath));
            socket.Send(Encoding.ASCII.GetBytes(command + "\n"));
            return true;
        }
        catch (SocketException)
        {
            return false;
        }
    }

    public static Socket? Listen(ConcurrentQueue<string> queue)
    {
        try
        {
            // A stale socket from a previous run; a live instance would have answered.
            if (File.Exists(SocketPath))
            {
                if (Send("ping")) return null;
                File.Delete(SocketPath);
            }
            var listener = new Socket(AddressFamily.Unix, SocketType.Stream, ProtocolType.Unspecified);
            listener.Bind(new UnixDomainSocketEndPoint(SocketPath));
            File.SetUnixFileMode(SocketPath, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            listener.Listen(8);
            var thread = new Thread(() =>
            {
                var buffer = new byte[64];
                while (true)
                {
                    try
                    {
                        using var client = listener.Accept();
                        client.ReceiveTimeout = 500;
                        var read = client.Receive(buffer);
                        var command = Encoding.ASCII.GetString(buffer, 0, read).Trim();
                        if (command is "press" or "undo" or "quit") queue.Enqueue(command);
                    }
                    catch (SocketException)
                    {
                    }
                    catch (ObjectDisposedException)
                    {
                        return;
                    }
                }
            }) { IsBackground = true, Name = "Baddel trigger listener" };
            thread.Start();
            return listener;
        }
        catch (Exception exception) when (exception is SocketException or IOException)
        {
            return null;
        }
    }
}

/// <summary>XKB groups of an X11 session. Only groups the user configured are selected.</summary>
public sealed class XkbGroupSwitcher : ILayoutSwitcher
{
    private readonly IntPtr display;
    private readonly string[] layouts;
    private readonly LinuxSettings settings;

    public XkbGroupSwitcher(IntPtr display, LinuxSettings settings)
    {
        this.display = display;
        this.settings = settings;
        layouts = QueryLayouts();
    }

    public IReadOnlyList<string> Layouts => layouts;

    /// <summary>The configured layout names, as reported by <c>setxkbmap -query</c>.</summary>
    private static string[] QueryLayouts()
    {
        try
        {
            using var process = Process.Start(new ProcessStartInfo("setxkbmap", "-query") { RedirectStandardOutput = true, UseShellExecute = false });
            if (process is null) return Array.Empty<string>();
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit(2000);
            var line = output.Split('\n').FirstOrDefault(l => l.StartsWith("layout:", StringComparison.Ordinal));
            return line is null ? Array.Empty<string>() : line["layout:".Length..].Trim().Split(',', StringSplitOptions.TrimEntries);
        }
        catch (Exception)
        {
            return Array.Empty<string>();
        }
    }

    private int CurrentGroup()
    {
        var state = new byte[64];
        return X11.XkbGetState(display, X11.XkbUseCoreKbd, state) == 0 ? state[0] : -1;
    }

    private Script? ScriptOf(int group)
    {
        if (group < 0 || group >= layouts.Length) return null;
        if (layouts[group] == settings.ArabicXkbLayout) return Script.Arabic;
        if (layouts[group] == settings.LatinXkbLayout) return Script.Latin;
        return null;
    }

    public string? CurrentLayoutId()
    {
        var group = CurrentGroup();
        return group < 0 ? null : group.ToString();
    }

    public Script? CurrentScript() => ScriptOf(CurrentGroup());

    public bool SelectLayout(Script script)
    {
        var wanted = script == Script.Arabic ? settings.ArabicXkbLayout : settings.LatinXkbLayout;
        var group = Array.IndexOf(layouts, wanted);
        return group >= 0 && Lock(group);
    }

    public bool SelectLayoutById(string id) => int.TryParse(id, out var group) && group >= 0 && group < Math.Max(layouts.Length, 1) && Lock(group);

    private bool Lock(int group)
    {
        X11.XkbLockGroup(display, X11.XkbUseCoreKbd, (uint)group);
        X11.XSync(display, 0);
        return CurrentGroup() == group;
    }
}

/// <summary>Used where no supported way to switch layouts exists: nothing is changed.</summary>
public sealed class NoLayoutSwitcher : ILayoutSwitcher
{
    public string? CurrentLayoutId() => null;
    public Script? CurrentScript() => null;
    public bool SelectLayout(Script script) => false;
    public bool SelectLayoutById(string id) => false;
}

/// <summary>
/// The running app: receives shortcut presses (an X11 key grab, or the trigger
/// socket), decides single or double, runs the shared correction engine through
/// AT-SPI, and offers Undo.
/// </summary>
public sealed class Session
{
    private readonly LinuxSettings settings;
    private readonly LayoutPair pair;
    private readonly AtspiFocus focus = new();
    private readonly ConcurrentQueue<string> triggers = new();
    private DoublePressDetector detector;

    private IntPtr display;
    private IntPtr root;
    private int grabbedKeycode;
    private bool keyDown;
    private ILayoutSwitcher switcher = new NoLayoutSwitcher();

    private IEditableField? captured;
    private long? timerDeadline;
    private int timerGeneration;
    private (CorrectionEngine Engine, UndoRecord Record)? lastUndo;

    private IntPtr popup;
    private IntPtr popupGc;
    private string popupText = string.Empty;
    private long popupHideAt;
    private bool popupVisible;
    private static X11.ErrorHandler? errorHandler;
    private static volatile bool xError;

    public Session(LinuxSettings settings, LayoutPair pair)
    {
        this.settings = settings;
        this.pair = pair;
        detector = new DoublePressDetector(Math.Clamp(settings.DoublePressMs, 150, 600));
    }

    public static bool IsWayland =>
        !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WAYLAND_DISPLAY"))
        || Environment.GetEnvironmentVariable("XDG_SESSION_TYPE") == "wayland";

    private static void Say(string line)
    {
        Console.Out.WriteLine(line);
        Console.Out.Flush();
    }

    public int Run()
    {
        if (!AtspiFocus.Initialise())
        {
            Say("status=error reason=accessibility-bus-unavailable");
            return 2;
        }
        using var listener = TriggerChannel.Listen(triggers);
        if (listener is null)
        {
            Say("status=error reason=already-running-or-socket-unavailable");
            return 3;
        }

        var shortcutMode = "trigger-only";
        if (!IsWayland && !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("DISPLAY")))
        {
            display = X11.XOpenDisplay(null);
            if (display != IntPtr.Zero)
            {
                root = X11.XDefaultRootWindow(display);
                errorHandler = (_, _) =>
                {
                    xError = true;
                    return 0;
                };
                X11.XSetErrorHandler(errorHandler);
                switcher = new XkbGroupSwitcher(display, settings);
                shortcutMode = GrabShortcut() ? "x11-grab" : "trigger-only(shortcut-unavailable)";
                CreatePopup();
            }
        }
        // On Wayland a client cannot grab keys or place its own windows, so the
        // shortcut comes from the desktop (bound to `baddel --trigger`) and no
        // popup is shown; Undo is `baddel --undo`.
        Say($"status=ready session={(IsWayland ? "wayland" : display != IntPtr.Zero ? "x11" : "none")} shortcut={shortcutMode} "
            + $"layouts={pair.Latin.Id},{pair.Arabic.Id} xkbGroups={string.Join("|", (switcher as XkbGroupSwitcher)?.Layouts ?? Array.Empty<string>())}");

        try
        {
            while (true)
            {
                PumpX11();
                while (triggers.TryDequeue(out var command))
                {
                    if (command == "quit") return 0;
                    if (command == "undo") UndoLast();
                    if (command == "press")
                    {
                        // Each trigger is one distinct press.
                        Pressed(isRepeat: false);
                        detector.Release();
                    }
                }
                var now = Environment.TickCount64;
                if (timerDeadline is { } deadline && now >= deadline)
                {
                    timerDeadline = null;
                    if (detector.Timeout(timerGeneration) == PressAction.Single) Correct(CorrectionMode.SelectionOrLastWord);
                }
                if (popupVisible && now >= popupHideAt)
                {
                    HidePopup();
                    // The original text is kept only while Undo is on offer.
                    lastUndo = null;
                }
                Thread.Sleep(8);
            }
        }
        finally
        {
            try
            {
                File.Delete(TriggerChannel.SocketPath);
            }
            catch (IOException)
            {
            }
        }
    }

    // Shortcut -----------------------------------------------------------------

    /// <summary>
    /// A passive grab of one key combination on the root window. X delivers only
    /// that combination to Baddel; nothing else that is typed is seen.
    /// </summary>
    private bool GrabShortcut()
    {
        uint modifiers = 0;
        string? keyName = null;
        foreach (var part in settings.Shortcut.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries))
        {
            switch (part.ToLowerInvariant())
            {
                case "ctrl" or "control": modifiers |= X11.ControlMask; break;
                case "alt": modifiers |= X11.Mod1Mask; break;
                case "shift": modifiers |= X11.ShiftMask; break;
                case "super" or "win": modifiers |= X11.Mod4Mask; break;
                default: keyName = part; break;
            }
        }
        if (keyName is null || (modifiers & (X11.ControlMask | X11.Mod1Mask | X11.Mod4Mask)) == 0) return false;
        var keysym = X11.XStringToKeysym(keyName);
        if (keysym == IntPtr.Zero) return false;
        grabbedKeycode = X11.XKeysymToKeycode(display, keysym);
        if (grabbedKeycode == 0) return false;

        xError = false;
        // Caps Lock and Num Lock are modifiers too; grab each combination.
        foreach (var extra in new[] { 0u, X11.LockMask, X11.Mod2Mask, X11.LockMask | X11.Mod2Mask })
        {
            X11.XGrabKey(display, grabbedKeycode, modifiers | extra, root, 0, X11.GrabModeAsync, X11.GrabModeAsync);
        }
        // With detectable auto-repeat a held key sends presses without releases,
        // so a press that follows a press is a repeat.
        X11.XkbSetDetectableAutoRepeat(display, 1, out _);
        X11.XSync(display, 0);
        return !xError;
    }

    private void PumpX11()
    {
        if (display == IntPtr.Zero) return;
        while (X11.XPending(display) > 0)
        {
            X11.XNextEvent(display, out var xevent);
            switch (xevent.type)
            {
                case X11.KeyPress when xevent.detail == grabbedKeycode:
                    Pressed(isRepeat: keyDown);
                    keyDown = true;
                    break;
                case X11.KeyRelease when xevent.detail == grabbedKeycode:
                    keyDown = false;
                    detector.Release();
                    break;
                case X11.ButtonPress when xevent.window == popup:
                    UndoLast();
                    break;
                case X11.Expose when xevent.window == popup:
                    DrawPopup();
                    break;
            }
        }
    }

    private void Pressed(bool isRepeat)
    {
        var now = unchecked((int)Environment.TickCount64);
        switch (detector.Press(now, isRepeat))
        {
            case PressAction.Armed:
                Arm();
                break;
            case PressAction.Double:
                timerDeadline = null;
                Correct(CorrectionMode.WholeField);
                break;
            case PressAction.SingleThenArmed:
                timerDeadline = null;
                Correct(CorrectionMode.SelectionOrLastWord);
                Arm();
                break;
        }
    }

    /// <summary>Remembers the focused field and waits for a possible second press; no text is touched yet.</summary>
    private void Arm()
    {
        captured = focus.FocusedField();
        timerGeneration = detector.Generation;
        timerDeadline = Environment.TickCount64 + detector.WindowMs;
    }

    // Correction ---------------------------------------------------------------

    private void Correct(CorrectionMode mode)
    {
        HidePopup();
        lastUndo = null;
        var field = captured;
        captured = null;
        var engine = new CorrectionEngine(new CorrectionPlanner(pair), focus, switcher) { SwitchesLayout = settings.SwitchLayout };
        var result = engine.Correct(mode, field);
        if (result.Success is { } success)
        {
            lastUndo = (engine, success.Undo);
            Say(new DiagnosticEvent(DiagnosticKind.Corrected, mode, null, success.Undo.ReplacedRange.Length, success.LayoutSwitched).Summary);
            ShowPopup("Fixed - click to Undo", (success.Undo.Field as AtspiField)?.Anchor(), 6000);
        }
        else
        {
            Say(new DiagnosticEvent(DiagnosticKind.Rejected, mode, result.Rejection ?? Rejection.WriteFailed).Summary);
        }
    }

    private void UndoLast()
    {
        if (lastUndo is not { } pending)
        {
            Say(new DiagnosticEvent(DiagnosticKind.UndoRejected, Rejection: Rejection.UndoStateChanged).Summary);
            return;
        }
        lastUndo = null;
        HidePopup();
        var rejection = pending.Engine.Undo(pending.Record);
        Say(rejection is null
            ? new DiagnosticEvent(DiagnosticKind.Undone, Utf16Length: pending.Record.ReplacedRange.Length).Summary
            : new DiagnosticEvent(DiagnosticKind.UndoRejected, Rejection: rejection).Summary);
    }

    // Undo popup (X11) ---------------------------------------------------------

    private const int PopupWidth = 176;
    private const int PopupHeight = 26;

    /// <summary>
    /// An override-redirect window: the window manager does not manage it and it is
    /// never given input focus, so the edited field keeps the keyboard.
    /// </summary>
    private void CreatePopup()
    {
        var screen = X11.XDefaultScreen(display);
        popup = X11.XCreateSimpleWindow(
            display, root, 0, 0, PopupWidth, PopupHeight, 1, X11.XBlackPixel(display, screen), X11.XWhitePixel(display, screen));
        var attributes = new byte[112];
        BitConverter.GetBytes(1).CopyTo(attributes, 88); // override_redirect = True
        X11.XChangeWindowAttributes(display, popup, X11.CWOverrideRedirect, attributes);
        X11.XStoreName(display, popup, "Baddel Undo");
        X11.XSelectInput(display, popup, X11.ButtonPressMask | X11.ExposureMask);
        popupGc = X11.XCreateGC(display, popup, 0, IntPtr.Zero);
        X11.XSetForeground(display, popupGc, X11.XBlackPixel(display, screen));
        X11.XFlush(display);
    }

    private void ShowPopup(string text, (int X, int Y, int Width, int Height)? anchor, int durationMs)
    {
        if (popup == IntPtr.Zero) return;
        var screen = X11.XDefaultScreen(display);
        var width = X11.XDisplayWidth(display, screen);
        var height = X11.XDisplayHeight(display, screen);
        int x, y;
        if (anchor is { } rect)
        {
            x = rect.X;
            y = rect.Y + rect.Height + 6;
            if (y + PopupHeight > height) y = rect.Y - PopupHeight - 6;
        }
        else
        {
            // No coordinates from the application: lower middle of the screen.
            x = (width - PopupWidth) / 2;
            y = height - PopupHeight - 96;
        }
        x = Math.Clamp(x, 4, Math.Max(4, width - PopupWidth - 4));
        y = Math.Clamp(y, 4, Math.Max(4, height - PopupHeight - 4));
        popupText = text;
        X11.XMoveWindow(display, popup, x, y);
        X11.XMapRaised(display, popup);
        DrawPopup();
        popupVisible = true;
        popupHideAt = Environment.TickCount64 + durationMs;
    }

    private void DrawPopup()
    {
        X11.XClearWindow(display, popup);
        X11.XDrawString(display, popup, popupGc, 10, 17, popupText, popupText.Length);
        X11.XFlush(display);
    }

    private void HidePopup()
    {
        if (!popupVisible) return;
        X11.XUnmapWindow(display, popup);
        X11.XFlush(display);
        popupVisible = false;
    }
}
