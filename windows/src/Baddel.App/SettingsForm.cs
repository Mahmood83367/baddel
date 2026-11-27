using System;
using System.Drawing;
using System.Windows.Forms;
using Baddel.Windows;

namespace Baddel.App;

/// <summary>
/// Settings window. A new shortcut is recorded from key events delivered to this
/// window only, and only while its shortcut box has focus.
/// </summary>
internal sealed class SettingsForm : Form
{
    private readonly HotKeyListener hotKeys;
    private readonly TextBox shortcutBox = new() { ReadOnly = true, Width = 220, ShortcutsEnabled = false };
    private readonly Label shortcutStatus = new() { AutoSize = true, ForeColor = SystemColors.GrayText };
    private readonly ComboBox arabicBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
    private readonly NumericUpDown interval = new() { Minimum = 150, Maximum = 600, Increment = 25, Width = 80 };
    private readonly CheckBox switchLayout = new() { Text = "Switch the keyboard layout after a correction", AutoSize = true };
    private readonly CheckBox pasteFallback = new() { Text = "Paste fallback for controls that refuse direct edits (experimental)", AutoSize = true };
    private readonly AppSettings working;
    private HotKey activeHotKey;

    private static readonly (string Title, string Id)[] ArabicChoices =
    {
        ("Arabic (101)", "arabic-windows-101"),
        ("Arabic (102)", "arabic-windows-102"),
    };

    /// <summary>Raised with the updated settings each time something is applied.</summary>
    public event Action<AppSettings>? Applied;

    public SettingsForm(AppSettings settings, HotKeyListener hotKeys)
    {
        this.hotKeys = hotKeys;
        working = AppSettings.Parse(settings.Serialize());
        activeHotKey = working.HotKey;

        Text = "Baddel Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(16);
        KeyPreview = false;

        shortcutBox.Text = activeHotKey.ToString();
        shortcutStatus.Text = "Click the box and press a new shortcut. Press once: selection or last word. Twice: whole field.";
        shortcutBox.Enter += (_, _) => hotKeys.Unregister();
        shortcutBox.Leave += (_, _) => hotKeys.Register(activeHotKey);
        shortcutBox.KeyDown += ShortcutKeyDown;

        foreach (var choice in ArabicChoices) arabicBox.Items.Add(choice.Title);
        arabicBox.SelectedIndex = Math.Max(Array.FindIndex(ArabicChoices, c => c.Id == working.ArabicLayout), 0);
        interval.Value = working.ClampedDoublePressMs;
        switchLayout.Checked = working.SwitchLayout;
        pasteFallback.Checked = working.PasteFallback;

        arabicBox.SelectedIndexChanged += (_, _) => Apply();
        interval.ValueChanged += (_, _) => Apply();
        switchLayout.CheckedChanged += (_, _) => Apply();
        pasteFallback.CheckedChanged += (_, _) => Apply();

        var table = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Fill };
        void Row(string label, Control control)
        {
            table.Controls.Add(new Label { Text = label, AutoSize = true, Margin = new Padding(0, 6, 8, 6) });
            table.Controls.Add(control);
        }
        Row("Shortcut:", shortcutBox);
        Row(string.Empty, shortcutStatus);
        Row("Arabic layout:", arabicBox);
        Row("Double-press window (ms):", interval);
        Row(string.Empty, switchLayout);
        Row(string.Empty, pasteFallback);
        Row(string.Empty, new Label
        {
            Text = "The fallback pastes over a verified selection and then restores your clipboard.",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
        });
        Controls.Add(table);
    }

    private void ShortcutKeyDown(object? sender, KeyEventArgs e)
    {
        e.SuppressKeyPress = true;
        e.Handled = true;
        var candidate = HotKey.FromKeyEvent(e.KeyData);
        if (!candidate.IsValid) return;

        if (hotKeys.Register(candidate))
        {
            // Registration proved the combination is free; release it again until
            // the box loses focus so further presses keep reaching this window.
            hotKeys.Unregister();
            activeHotKey = candidate;
            shortcutBox.Text = candidate.ToString();
            shortcutStatus.ForeColor = SystemColors.GrayText;
            shortcutStatus.Text = $"Shortcut set to {candidate}.";
            Apply();
        }
        else
        {
            shortcutStatus.ForeColor = Color.Firebrick;
            shortcutStatus.Text = $"{candidate} is not available. Another app may be using it.";
        }
    }

    private void Apply()
    {
        working.Shortcut = activeHotKey.ToString();
        working.ArabicLayout = ArabicChoices[Math.Max(arabicBox.SelectedIndex, 0)].Id;
        working.DoublePressMs = (int)interval.Value;
        working.SwitchLayout = switchLayout.Checked;
        working.PasteFallback = pasteFallback.Checked;
        Applied?.Invoke(AppSettings.Parse(working.Serialize()));
    }
}

/// <summary>About box with the copyright and license notice.</summary>
internal sealed class AboutForm : Form
{
    private static AboutForm? open;

    public static void ShowSingle()
    {
        if (open is { IsDisposed: false })
        {
            open.Activate();
            return;
        }
        open = new AboutForm();
        open.Show();
        open.Activate();
    }

    private AboutForm()
    {
        Text = "About Baddel";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoScaleMode = AutoScaleMode.Dpi;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(18);

        var panel = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            WrapContents = false,
            Dock = DockStyle.Fill,
        };
        panel.Controls.Add(new Label { Text = $"Baddel {Program.Version}", AutoSize = true, Font = new Font("Segoe UI", 13, FontStyle.Bold) });
        panel.Controls.Add(new Label
        {
            Text = "Fixes text typed with the wrong keyboard layout (Arabic / English).",
            AutoSize = true,
            Margin = new Padding(3, 6, 3, 10),
        });
        panel.Controls.Add(new Label { Text = Program.Copyright, AutoSize = true });
        panel.Controls.Add(new Label
        {
            Text = "Released under the MIT License. The full license text is in the LICENSE\n"
                   + "file distributed with this program. Copies and forks that redistribute\n"
                   + "Baddel must keep this copyright notice and the license notice.",
            AutoSize = true,
            Margin = new Padding(3, 6, 3, 10),
        });
        var link = new LinkLabel { Text = Program.ProjectUrl, AutoSize = true };
        link.LinkClicked += (_, _) =>
        {
            try
            {
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(Program.ProjectUrl) { UseShellExecute = true });
            }
            catch (Exception)
            {
            }
        };
        panel.Controls.Add(link);
        Controls.Add(panel);
    }
}
