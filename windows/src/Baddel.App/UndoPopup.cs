using System;
using System.Drawing;
using System.Windows.Forms;

namespace Baddel.App;

/// <summary>
/// A small top-most window that is never activated, so the field being edited
/// keeps keyboard focus while the popup is shown and while Undo is clicked.
/// </summary>
internal sealed class UndoPopup : Form
{
    internal const string WindowTitle = "Baddel Undo";
    private const int WS_EX_TOPMOST = 0x00000008;
    private const int WS_EX_TOOLWINDOW = 0x00000080;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WM_MOUSEACTIVATE = 0x0021;
    private const int MA_NOACTIVATE = 3;

    private readonly System.Windows.Forms.Timer timer = new();

    /// <summary>Raised when the popup closes because its time ran out.</summary>
    public event EventHandler? Expired;

    public UndoPopup(string message, Action? undo, int durationMs)
    {
        Text = WindowTitle;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        AutoScaleMode = AutoScaleMode.Dpi;
        BackColor = Color.FromArgb(32, 32, 36);
        Padding = new Padding(10, 6, 8, 6);
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;

        var layout = new FlowLayoutPanel
        {
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false,
            BackColor = BackColor,
            Dock = DockStyle.Fill,
        };
        layout.Controls.Add(new Label
        {
            Text = message,
            AutoSize = true,
            ForeColor = Color.White,
            Font = new Font("Segoe UI", 9.5f),
            Margin = new Padding(0, 5, 8, 0),
        });
        if (undo is not null)
        {
            var button = new Button
            {
                Text = "Undo",
                AutoSize = true,
                FlatStyle = FlatStyle.System,
                AccessibleName = "Undo keyboard layout correction",
                TabStop = false,
            };
            button.Click += (_, _) =>
            {
                timer.Stop();
                Close();
                undo();
            };
            layout.Controls.Add(button);
        }
        Controls.Add(layout);

        timer.Interval = durationMs;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            Close();
            Expired?.Invoke(this, EventArgs.Empty);
        };
    }

    protected override bool ShowWithoutActivation => true;

    protected override CreateParams CreateParams
    {
        get
        {
            var parameters = base.CreateParams;
            parameters.ExStyle |= WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST;
            return parameters;
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_MOUSEACTIVATE)
        {
            // Let the click through without taking activation from the edited app.
            m.Result = new IntPtr(MA_NOACTIVATE);
            return;
        }
        base.WndProc(ref m);
    }

    public void ShowWithoutActivating()
    {
        Show();
        timer.Start();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) timer.Dispose();
        base.Dispose(disposing);
    }
}
