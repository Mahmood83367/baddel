# Baddel in a terminal

Baddel's shortcut works on text fields that the operating system's
accessibility interface can edit. A terminal is not such a field: the text on a
prompt belongs to the shell or to the program running in it. So in a terminal
Baddel works the other way round. The shell's line editor, or Claude Code,
hands Baddel the text it is holding and puts the corrected text back itself.

Two things follow from that:

- Nothing is typed, pasted or read off the screen, and Baddel never presses
  Enter. The corrected command line or draft stays where it was for you to
  review.
- The correction is one ordinary edit for the shell or for Claude Code, so
  their own undo takes it back.

Both integrations are **opt-in**: Baddel changes nothing in your shell or in
Claude Code until you add the lines shown below yourself. They use the same
correction rules and the same English and Arabic layouts as the rest of
Baddel.

## One shortcut

The shortcut is the one set in Baddel: `⌥⇧Space` on macOS and
`Ctrl+Alt+Space` on Windows and Linux unless you changed it (Settings on macOS
and Windows, `settings.json` on Linux). The terminal integrations use that
same combination; there is no second one to remember where the terminal can
deliver it.

Two facts decide whether it can:

1. **A global shortcut is consumed before the window in front sees it.** While
   Baddel holds the combination, a terminal never receives it. Baddel
   therefore lets go of it whenever a terminal window is in front and takes it
   back when another window is. This starts by itself the first time a shell
   or Claude Code integration asks Baddel for its key; it can be forced on or
   off (**In terminals** in macOS Settings, `"TerminalSharing"` in
   `settings.json` on Windows and Linux: `automatic`, `on` or `off`).
2. **A terminal passes on bytes, not key combinations.** A combination with
   Control arrives as a control character and one with Alt or Option as Escape
   plus the key; one with Command or the Windows key does not arrive at all.

To see what is active on your computer:

```bash
/Applications/Baddel.app/Contents/MacOS/Baddel --terminal-key status
```

(`baddel --terminal-key status` on Linux, `Baddel.exe --terminal-key status`
on Windows.) What it means per system:

| System | Shell | Claude Code |
| --- | --- | --- |
| macOS, `⌥⇧Space` | zsh receives it with Terminal's default settings, as the no-break space that Option-Space types, under the English and the Arabic layouts alike. | Claude Code cannot be given a typed character as a shortcut. It needs **Use Option as Meta key** in Terminal's profile (Settings → Profiles → Keyboard), or a terminal that reports modifier keys. Otherwise use `Ctrl+G`. |
| Linux, `Ctrl+Alt+Space` | Bash receives it in GNOME Terminal and xfce4-terminal as they come. xterm needs `XTerm*metaSendsEscape: true`. | Bound as `ctrl+alt+space`. |
| Windows, `Ctrl+Alt+Space` | **PowerShell cannot use it.** PSReadLine reads Ctrl+Alt as AltGr and would bind Ctrl+Alt+Space as plain Space. The integration uses `Ctrl+T` instead. To share one shortcut, choose one such as `Ctrl+Shift+Space` in Baddel's Settings. | Bound as `ctrl+alt+space`. |

A shortcut made of Control and a letter (for example `⌃]` or `Ctrl+]`) reaches
every shell and Claude Code in every terminal, with either layout active. A
shortcut with Command or the Windows key reaches none; the integrations then
fall back to `Ctrl+T` in the shell and `Ctrl+G` in Claude Code, and the status
command says so.

## Shell command line

| System | Shell | Add this line to | Line |
| --- | --- | --- | --- |
| macOS | zsh (the default in Terminal) | `~/.zshrc` | `source /Applications/Baddel.app/Contents/Resources/shell/baddel.zsh` |
| Windows | PowerShell with PSReadLine (Windows PowerShell 5.1 or PowerShell 7) | your profile, `notepad $PROFILE` | `. "C:\path\to\Baddel\shell\baddel.ps1"` |
| Linux | Bash 4.0 or later | `~/.bashrc` | `source /path/to/Baddel/shell/baddel.bash` |

Open a new terminal afterwards. Then, on a command line you have typed but not
run:

| Press | What is corrected | Undo |
| --- | --- | --- |
| The shortcut once | The selected text. With no selection, the last word before the cursor. | zsh and Bash: `Ctrl+_`. PowerShell: `Ctrl+Z`. |
| The shortcut twice quickly | The whole command line. | The same key; in Bash press it twice. |

Details that differ between shells:

- **Selection.** zsh corrects the active region (set the mark with
  `Ctrl+Space`, then move). PowerShell corrects the selection (`Shift` with the
  arrow keys). Bash has no visible selection, so there it is always the last
  word or the whole line.
- **The second press** must come within 300 ms of the first one finishing, and
  the line must still be what the first press left.
- **Mixed lines.** On a whole-line correction of text in both scripts, such as
  `git commit -m "اثممخ"`, the keyboard layout that is active decides which part
  was typed wrongly: the Arabic part if Arabic is active. Where Baddel cannot
  read the active layout it converts the script with more letters, which is
  often the wrong one for a command line. Use the single press there.
- **Undo with the Arabic layout active.** The undo keys are Control
  combinations of the shell; whether they arrive while an Arabic layout is
  active depends on the terminal. The macOS layout tables say they do there.

Settings, all optional and set before the line above:

- `BADDEL_KEY`: a key of your own instead of Baddel's shortcut, in the shell's
  notation: `BADDEL_KEY='^B'` (zsh), `BADDEL_KEY='\C-b'` (Bash),
  `$env:BADDEL_KEY = 'Ctrl+b'` (PowerShell).
- `BADDEL_BIN`: the path of the Baddel executable, if the script is not in its
  packaged place.
- `BADDEL_DOUBLE_PRESS_MS`, and `BADDEL_HINT` (`latin`, `arabic` or `none`: the
  layout to assume instead of reading the active one).

## Claude Code's message box

Claude Code opens the draft you are writing in an external editor and reads
the edited text back. Baddel can be that editor: it corrects the draft and
returns at once.

**1. Make Baddel the editor.** Set `VISUAL` for Claude Code to Baddel with
`--fix-draft`. The path must not contain spaces; Claude Code splits the value
at spaces and does not accept quotes.

| System | Value of `VISUAL` |
| --- | --- |
| macOS | `/Applications/Baddel.app/Contents/MacOS/Baddel --fix-draft` |
| Windows | `C:\path\to\Baddel\Baddel.exe --fix-draft` |
| Linux | `/path/to/Baddel/baddel --fix-draft` |

To set it for Claude Code only, put it in `~/.claude/settings.json`:

```json
{ "env": { "VISUAL": "/Applications/Baddel.app/Contents/MacOS/Baddel --fix-draft" } }
```

or start Claude Code with it: `VISUAL="…/Baddel --fix-draft" claude`.

**2. Press `Ctrl+G`**, Claude Code's own key for the external editor. That
works at once, in every terminal.

**3. To use Baddel's shortcut as well**, add the entry that Baddel prints to
the `bindings` list of `~/.claude/keybindings.json`. Baddel does not write
that file.

```bash
/Applications/Baddel.app/Contents/MacOS/Baddel --terminal-key claude
```

Then, in Claude Code:

| Press | What happens |
| --- | --- |
| `Ctrl+G`, or Baddel's shortcut once bound | The whole unsent draft is corrected and stays in the message box. |
| `Ctrl+_` | Claude Code's undo restores the draft as it was. |

What the external-editor hand-over can and cannot do:

- **The whole draft, every time.** Claude Code passes the complete draft to an
  editor it does not know, without a cursor position or a selection. There is
  no last-word or selection mode here, and one press and two presses do the
  same.
- **`Ctrl+G` no longer opens a text editor** in Claude Code while `VISUAL` is
  set this way.
- **Attachments.** Markers such as `[Image #1]` are kept exactly as they are
  and do not count as English text.
- **Claude's previous reply.** With "Show last response in external editor"
  on, Claude Code puts its last reply above your draft as `#` comment lines,
  down to a line reading "Write your reply below this line". Baddel leaves
  that block alone: it does not count towards the direction and comes back
  unchanged, so Claude Code can remove it again.
- **Pasted text.** A long paste shows in the message box as
  `[Pasted text #1 +30 lines]`, but Claude Code gives the editor the pasted
  text itself, so Baddel sees it as part of the draft. If you typed in Arabic
  by mistake after pasting English, the active Arabic layout tells Baddel to
  convert only the Arabic part, and the paste comes back unchanged. If you typed English letters by mistake, the paste is in the
  same script as your typing and is converted with it: press `Ctrl+_`, or
  correct before you paste.
- **Mixed drafts** follow the same rule as mixed command lines above.
- **Other files.** `--fix-draft` only rewrites files named the way Claude Code
  names its drafts (`claude-prompt-…`). If `VISUAL` or `EDITOR` reaches another
  program, such as `git commit`, Baddel leaves that file alone and exits with
  an error, so that program stops instead of carrying on.

## Limits

- **Keyboard layout.** Baddel does not switch the keyboard layout after a
  correction in a terminal on any system; switch it yourself before you
  continue typing. (In ordinary fields it switches where the system lets it:
  on macOS and Windows, and on Linux in an X11 session with both layouts
  configured as XKB groups, not on Wayland.)
- **Which terminals.** The shortcut is left to Terminal, iTerm2, Ghostty,
  kitty, Alacritty, WezTerm and Warp on macOS; Windows Terminal and the classic
  console on Windows; and the common X11 terminals on Linux. On Wayland Baddel
  holds no shortcut of its own, so there is nothing to release. Others can be
  added (`terminalBundleIDs` on macOS, `"TerminalWindowClasses"` on Linux).
- **Other programs in the terminal.** While a terminal is in front the
  shortcut goes to whatever runs in it. A program without an integration
  receives it as a key press; in macOS Terminal with default settings that
  types a no-break space.
- Supported and tested are the shells in the table above. Other shells and
  line editors (fish, Bash on macOS, which is version 3.2, `cmd.exe`, vi
  editing modes) have no integration.
- On Windows each press starts `Baddel.exe`, which takes about 0.4 seconds,
  and opening PowerShell takes about 0.2 seconds longer because the script
  asks for its key.
- Reading the active layout: on macOS the current input source; on Windows the
  layout of the foreground window; on Linux the X11 keyboard group. On Wayland
  and over SSH there is none, and the text alone decides.

What was run, and where, is in the [testing record](TESTING.md#terminal-shell-command-line-and-claude-code).

## For developers

The shells and Claude Code call the packaged executable in a run-and-exit
mode.

```text
baddel --fix-text [--mode word|line] [--cursor N] [--selection START LENGTH]
       [--unit utf16|scalars|bytes] [--hint latin|arabic|none]
    Reads the buffer from standard input (UTF-8). Writes "ok CURSOR" and a
    line break followed by the corrected buffer, or "no CODE".
    Exit codes: 0 corrected, 1 left unchanged, 2 wrong usage.
baddel --fix-draft [--any-file] [--hint latin|arabic|none] FILE
    Corrects a draft file in place. The file is rewritten only when a
    correction was made.
    Exit codes: 0 corrected or left unchanged, 1 not a Claude Code draft,
    2 wrong usage. (Claude Code reports an editor that exits with an error.)
baddel --terminal-key zsh|bash|pwsh|claude|status
    How the shortcut in the settings reaches a terminal: "ok" and the key
    sequences or chord to bind, or "no REASON"; the keybindings.json entry
    for Claude Code; or a description in words.
```

`CODE` is one of the refusal codes in
[the correction rules](CORRECTION_RULES.md); messages never contain the text.
`--unit` says what the cursor is counted in: code points for zsh and Bash 5,
UTF-8 bytes for Bash 4, UTF-16 units for PSReadLine. The logic is `TextFix`
and `TerminalKey` in both cores, with the fixtures
`shared/fixtures/text-fix.json` and `shared/fixtures/terminal-keys.json`.

`tools/terminal-check.py` runs the end-to-end checks in a pseudo-terminal: it
starts a separate shell or Claude Code with a throwaway configuration, types
synthetic text, presses the keys, and reads the buffer back.
`linux/scripts/terminal-window-check.sh` does the same in real terminal
windows on X11, with the app running and both layouts.
