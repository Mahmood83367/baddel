using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using Baddel.Core;
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
    private readonly ComboBox arabicBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
    private readonly ComboBox englishBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
    private readonly Label layoutStatus = new() { AutoSize = true, ForeColor = SystemColors.GrayText };
    private readonly NumericUpDown interval = new() { Minimum = 150, Maximum = 600, Increment = 25, Width = 80 };
    private readonly CheckBox switchLayout = new() { Text = "Switch the keyboard layout after a correction", AutoSize = true };
    private readonly CheckBox pasteFallback = new() { Text = "Paste fallback for controls that refuse direct edits (experimental)", AutoSize = true };
    private readonly ComboBox channelBox = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 260 };
    private readonly CheckBox autoCheck = new() { Text = "Check for updates once a day (never downloads or installs)", AutoSize = true };
    private readonly AppSettings working;
    private HotKey activeHotKey;

    private readonly KeyboardLayout[] arabicChoices;
    private readonly KeyboardLayout[] englishChoices;

    /// <summary>Raised with the updated settings each time something is applied.</summary>
    public event Action<AppSettings>? Applied;

    public SettingsForm(AppSettings settings, HotKeyListener hotKeys, LayoutStore store)
    {
        this.hotKeys = hotKeys;
        arabicChoices = EmbeddedLayouts.Choices(store, Script.Arabic).ToArray();
        englishChoices = EmbeddedLayouts.Choices(store, Script.Latin).ToArray();
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

        foreach (var choice in arabicChoices) arabicBox.Items.Add(choice.Name);
        foreach (var choice in englishChoices) englishBox.Items.Add(choice.Name);
        arabicBox.SelectedIndex = Math.Max(Array.FindIndex(arabicChoices, c => c.Id == working.ArabicLayout), 0);
        englishBox.SelectedIndex = Math.Max(Array.FindIndex(englishChoices, c => c.Id == working.EnglishLayout), 0);
        englishBox.SelectedIndexChanged += (_, _) => Apply();
        interval.Value = working.ClampedDoublePressMs;
        switchLayout.Checked = working.SwitchLayout;
        pasteFallback.Checked = working.PasteFallback;

        channelBox.Items.Add("Stable releases only");
        channelBox.Items.Add("Stable releases and previews");
        channelBox.SelectedIndex = working.Channel == UpdateChannel.Preview ? 1 : 0;
        autoCheck.Checked = working.CheckForUpdatesAutomatically;
        channelBox.SelectedIndexChanged += (_, _) => Apply();
        autoCheck.CheckedChanged += (_, _) => Apply();
        arabicBox.SelectedIndexChanged += (_, _) => Apply();
        interval.ValueChanged += (_, _) => Apply();
        switchLayout.CheckedChanged += (_, _) => Apply();
        pasteFallback.CheckedChanged += (_, _) => Apply();

        UpdateLayoutStatus();
        var table = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, AutoSizeMode = AutoSizeMode.GrowAndShrink, Dock = DockStyle.Fill };
        void Row(string label, Control control)
        {
            table.Controls.Add(new Label { Text = label, AutoSize = true, Margin = new Padding(0, 6, 8, 6) });
            table.Controls.Add(control);
        }
        Row("Shortcut:", shortcutBox);
        Row(string.Empty, shortcutStatus);
        Row("English layout:", englishBox);
        Row("Arabic layout:", arabicBox);
        Row(string.Empty, layoutStatus);
        Row("Double-press window (ms):", interval);
        Row(string.Empty, switchLayout);
        Row(string.Empty, pasteFallback);
        Row(string.Empty, new Label
        {
            Text = "The fallback pastes over a verified selection and then restores your clipboard.",
            AutoSize = true,
            ForeColor = SystemColors.GrayText,
        });
        Row("Updates:", channelBox);
        Row(string.Empty, autoCheck);
        Controls.Add(table);
    }

    /// <summary>Says plainly when a chosen layout is not installed, since Baddel will then not switch to it.</summary>
    private void UpdateLayoutStatus()
    {
        var missing = new[] { englishChoices[Math.Max(englishBox.SelectedIndex, 0)], arabicChoices[Math.Max(arabicBox.SelectedIndex, 0)] }
            .Where(layout => EmbeddedLayouts.Klid(layout) is not { } klid || !InputLanguageSwitcher.IsInstalled(klid))
            .Select(layout => layout.Name)
            .ToArray();
        layoutStatus.Text = missing.Length == 0
            ? "Both layouts are installed; Baddel switches to exactly these."
            : $"Not installed in Windows: {string.Join(", ", missing)}. Text is still converted with it, but the keyboard is not switched.";
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
        working.ArabicLayout = arabicChoices[Math.Max(arabicBox.SelectedIndex, 0)].Id;
        working.EnglishLayout = englishChoices[Math.Max(englishBox.SelectedIndex, 0)].Id;
        UpdateLayoutStatus();
        working.DoublePressMs = (int)interval.Value;
        working.SwitchLayout = switchLayout.Checked;
        working.PasteFallback = pasteFallback.Checked;
        working.UpdateChannel = channelBox.SelectedIndex == 1 ? "preview" : "stable";
        working.CheckForUpdatesAutomatically = autoCheck.Checked;
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
