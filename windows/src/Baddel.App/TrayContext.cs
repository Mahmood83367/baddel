using System;
using System.Drawing;
using System.Windows.Forms;
using Baddel.Core;
using Baddel.Windows;

namespace Baddel.App;

/// <summary>The notification-area icon, its menu, and the correction workflow.</summary>
internal sealed class TrayContext : ApplicationContext
{
    private readonly LayoutStore store = EmbeddedLayouts.Load();
    private readonly HotKeyListener hotKeys = new();
    private readonly StaWorker worker = new();
    private readonly FocusProvider focus = new();
    private readonly InputLanguageSwitcher switcher = new();
    private readonly NotifyIcon icon;
    private readonly ToolStripMenuItem shortcutItem = new() { Enabled = false };
    private readonly ToolStripMenuItem undoItem = new("Undo last correction") { Enabled = false };
    private readonly System.Windows.Forms.Timer timer = new();
    private readonly Control dispatcher = new();

    private AppSettings settings = AppSettings.Load();
    private DoublePressDetector detector;
    private int timerGeneration;
    private volatile IEditableField? capturedField;
    private (CorrectionEngine Engine, UndoRecord Record)? lastUndo;
    private UndoPopup? popup;
    private SettingsForm? settingsForm;

    public TrayContext()
    {
        dispatcher.CreateControl();
        _ = dispatcher.Handle;
        detector = new DoublePressDetector(settings.ClampedDoublePressMs);

        var menu = new ContextMenuStrip();
        menu.Items.Add(shortcutItem);
        menu.Items.Add(new ToolStripSeparator());
        undoItem.Click += (_, _) => UndoLast();
        menu.Items.Add(undoItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettings());
        menu.Items.Add("About Baddel", null, (_, _) => AboutForm.ShowSingle());
        menu.Items.Add("Exit", null, (_, _) => ExitThread());

        icon = new NotifyIcon
        {
            Icon = TrayIcon.Create(),
            Text = "Baddel",
            ContextMenuStrip = menu,
            Visible = true,
        };
        icon.DoubleClick += (_, _) => ShowSettings();

        timer.Tick += (_, _) => TimerFired();
        hotKeys.Pressed += HotKeyPressed;
        hotKeys.Register(settings.HotKey);
        RefreshMenu();
        if (!hotKeys.IsRegistered)
        {
            icon.ShowBalloonTip(
                6000, "Baddel", $"The shortcut {settings.HotKey} is not available. Choose another in Settings.", ToolTipIcon.Warning);
        }
    }

    private void RefreshMenu()
    {
        shortcutItem.Text = hotKeys.IsRegistered
            ? $"Fix text: {settings.HotKey}  (press twice for the whole field)"
            : $"Shortcut {settings.HotKey} is unavailable";
    }

    // Hot key ----------------------------------------------------------------

    private void HotKeyPressed()
    {
        var now = unchecked((int)Environment.TickCount64);
        // RegisterHotKey with MOD_NOREPEAT reports each physical press once, so
        // every notification is a distinct press.
        var action = detector.Press(now, isRepeat: false);
        detector.Release();
        switch (action)
        {
            case PressAction.Armed:
                Arm();
                break;
            case PressAction.Double:
                // Second press inside the window: nothing has been changed yet, so
                // the whole field is fixed in one operation.
                timer.Stop();
                Run(CorrectionMode.WholeField);
                break;
            case PressAction.SingleThenArmed:
                timer.Stop();
                Run(CorrectionMode.SelectionOrLastWord);
                Arm();
                break;
        }
    }

    /// <summary>Remembers which field had focus and waits for a possible second press.</summary>
    private void Arm()
    {
        worker.Post(() => capturedField = focus.FocusedField());
        timerGeneration = detector.Generation;
        timer.Stop();
        timer.Interval = detector.WindowMs;
        timer.Start();
    }

    private void TimerFired()
    {
        timer.Stop();
        if (detector.Timeout(timerGeneration) == PressAction.Single) Run(CorrectionMode.SelectionOrLastWord);
    }

    // Correction -------------------------------------------------------------

    private void Run(CorrectionMode mode)
    {
        HidePopup();
        ForgetUndo();
        var current = settings;
        worker.Post(() =>
        {
            var captured = capturedField;
            capturedField = null;
            focus.Paster = current.PasteFallback ? new ClipboardPaster() : null;
            var pair = EmbeddedLayouts.Pair(store, current.ArabicLayout);
            var engine = new CorrectionEngine(new CorrectionPlanner(pair), focus, switcher) { SwitchesLayout = current.SwitchLayout };
            var result = engine.Correct(mode, captured);
            var anchored = captured as IAnchoredField;

            if (result.Success is { } success)
            {
                // The engine re-reads the focused field; that object performed the write.
                anchored = success.Undo.Field as IAnchoredField;
                DiagnosticsLog.Record(
                    new DiagnosticEvent(DiagnosticKind.Corrected, mode, null, success.Undo.ReplacedRange.Length, success.LayoutSwitched),
                    $"strategy={anchored?.LastWriteStrategy}");
                var anchor = anchored?.TextAnchor() ?? anchored?.FieldBounds();
                OnUi(() =>
                {
                    lastUndo = (engine, success.Undo);
                    undoItem.Enabled = true;
                    ShowPopup(mode == CorrectionMode.WholeField ? "Field fixed" : "Fixed", anchor, 6000, withUndo: true);
                });
            }
            else
            {
                var rejection = result.Rejection ?? Rejection.WriteFailed;
                DiagnosticsLog.Record(new DiagnosticEvent(DiagnosticKind.Rejected, mode, rejection));
                var anchor = anchored?.FieldBounds();
                OnUi(() => ShowPopup(Messages.For(rejection), anchor, 2200, withUndo: false));
            }
        });
    }

    private void UndoLast()
    {
        if (lastUndo is not { } pending) return;
        HidePopup();
        ForgetUndo();
        worker.Post(() =>
        {
            var rejection = pending.Engine.Undo(pending.Record);
            var anchor = (pending.Record.Field as IAnchoredField)?.FieldBounds();
            DiagnosticsLog.Record(rejection is null
                ? new DiagnosticEvent(DiagnosticKind.Undone, Utf16Length: pending.Record.ReplacedRange.Length)
                : new DiagnosticEvent(DiagnosticKind.UndoRejected, Rejection: rejection));
            OnUi(() => ShowPopup(
                rejection is null ? "Restored" : "Can't undo: the text has changed", anchor, 2000, withUndo: false));
        });
    }

    /// <summary>The original text is kept only while Undo is on offer.</summary>
    private void ForgetUndo()
    {
        lastUndo = null;
        undoItem.Enabled = false;
    }

    private void OnUi(Action action)
    {
        if (dispatcher.IsHandleCreated && !dispatcher.IsDisposed) dispatcher.BeginInvoke(action);
    }

    // Popup ------------------------------------------------------------------

    private void ShowPopup(string message, Rectangle? anchor, int durationMs, bool withUndo)
    {
        HidePopup();
        var screen = anchor is { } rect ? Screen.FromRectangle(rect) : Screen.FromPoint(Cursor.Position);
        popup = new UndoPopup(message, withUndo ? UndoLast : null, durationMs);
        popup.Expired += (_, _) =>
        {
            if (withUndo) ForgetUndo();
        };
        popup.Location = PopupPlacement.Compute(popup.Size, anchor, screen.WorkingArea);
        popup.ShowWithoutActivating();
    }

    private void HidePopup()
    {
        var old = popup;
        popup = null;
        if (old is not null && !old.IsDisposed) old.Close();
    }

    // Settings ---------------------------------------------------------------

    private void ShowSettings()
    {
        if (settingsForm is { IsDisposed: false })
        {
            settingsForm.Activate();
            return;
        }
        settingsForm = new SettingsForm(settings, hotKeys);
        settingsForm.Applied += updated =>
        {
            settings = updated;
            settings.Save();
            detector = new DoublePressDetector(settings.ClampedDoublePressMs);
            timer.Stop();
            capturedField = null;
            RefreshMenu();
        };
        settingsForm.FormClosed += (_, _) =>
        {
            // Leave the working shortcut registered whatever happened in the dialog.
            if (!hotKeys.IsRegistered) hotKeys.Register(settings.HotKey);
            RefreshMenu();
        };
        settingsForm.Show();
        settingsForm.Activate();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            icon.Visible = false;
            icon.Dispose();
            timer.Dispose();
            hotKeys.Dispose();
            worker.Dispose();
            dispatcher.Dispose();
        }
        base.Dispose(disposing);
    }
}

internal static class Messages
{
    public static string For(Rejection rejection) => rejection switch
    {
        Rejection.SecureField => "Secure field — skipped",
        Rejection.NoFocusedField or Rejection.UnsupportedField or Rejection.ReadFailed => "This field isn't supported",
        Rejection.FocusChanged => "Focus changed — nothing was modified",
        Rejection.FieldChanged => "The text changed — nothing was modified",
        Rejection.FieldTooLarge => "Field too large — skipped",
        Rejection.EmptyField or Rejection.NoWord or Rejection.NothingToConvert => "Nothing to fix",
        Rejection.AmbiguousDirection => "Can't tell which layout was meant",
        Rejection.InvalidRange => "Couldn't locate the text",
        Rejection.WriteFailed => "This app didn't accept the change",
        Rejection.VerificationFailed => "Couldn't verify the change",
        _ => "Can't undo: the text has changed",
    };
}

internal static class TrayIcon
{
    /// <summary>Draws the icon at run time so the repository needs no binary assets.</summary>
    public static Icon Create()
    {
        using var bitmap = new Bitmap(32, 32);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            graphics.Clear(Color.Transparent);
            using var background = new SolidBrush(Color.FromArgb(0x1F, 0x6F, 0xEB));
            graphics.FillEllipse(background, 1, 1, 30, 30);
            using var font = new Font("Segoe UI", 15, FontStyle.Bold, GraphicsUnit.Pixel);
            using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
            graphics.DrawString("ب", font, Brushes.White, new RectangleF(0, 0, 32, 30), format);
        }
        return Icon.FromHandle(bitmap.GetHicon());
    }
}
