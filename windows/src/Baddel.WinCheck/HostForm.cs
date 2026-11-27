using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace Baddel.WinCheck;

/// <summary>
/// A throwaway window with one text control holding fixture text. The checks only
/// ever edit this window.
/// </summary>
internal sealed class HostForm : Form
{
    internal const string Title = "Baddel Check Host";

    public HostForm(string kind, string text, int? caret, (int Start, int Length)? selection, string? layout, string readyFile)
    {
        Text = Title;
        StartPosition = FormStartPosition.Manual;
        Location = new System.Drawing.Point(120, 120);
        ClientSize = new System.Drawing.Size(560, 240);
        TopMost = true;

        TextBoxBase box = kind == "rich" ? new RichTextBox() : new TextBox();
        box.Dock = DockStyle.Fill;
        box.Font = new System.Drawing.Font("Segoe UI", 12);
        if (box is TextBox plain)
        {
            plain.Multiline = kind == "multi";
            plain.UseSystemPasswordChar = kind == "password";
            plain.ReadOnly = kind == "readonly";
        }
        else if (box is RichTextBox rich)
        {
            rich.Multiline = true;
        }
        box.Text = text;
        Controls.Add(box);

        Shown += (_, _) =>
        {
            Activate();
            box.Focus();
            if (selection is { } range) box.Select(range.Start, range.Length);
            else box.Select(caret ?? box.TextLength, 0);
            if (layout is not null)
            {
                var wanted = InputLanguage.InstalledInputLanguages.Cast<InputLanguage>()
                    .FirstOrDefault(l => l.Culture.TwoLetterISOLanguageName == layout);
                if (wanted is not null) InputLanguage.CurrentInputLanguage = wanted;
            }
            var timer = new Timer { Interval = 400 };
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                File.WriteAllText(readyFile, Handle.ToInt64().ToString(CultureInfo.InvariantCulture));
            };
            timer.Start();
        };
    }
}
