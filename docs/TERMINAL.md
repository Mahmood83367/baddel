# Baddel in a terminal

Baddel's shortcut (`⌥⇧Space`, `Ctrl+Alt+Space`) works on text fields that the
operating system's accessibility interface can edit. A terminal is not such a
field: the text on a prompt belongs to the shell or to the program running in
it. So in a terminal Baddel works the other way round. The shell's line editor,
or Claude Code, hands Baddel the text it is holding and puts the corrected text
back itself.

Two things follow from that:

- Nothing is typed, pasted or read off the screen, and Baddel never presses
  Enter. The corrected command line or draft stays where it was for you to
  review.
- The correction is one ordinary edit for the shell or for Claude Code, so
  their own undo takes it back.

Both integrations are **opt-in**: Baddel changes nothing in your shell or in
Claude Code until you add the line shown below yourself. They use the same
correction rules and the same English and Arabic layouts as the rest of
Baddel, and they do not need the Baddel app to be running or to have
Accessibility access.

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
| `Ctrl+T` once | The selected text. With no selection, the last word before the cursor. | zsh and Bash: `Ctrl+_`. PowerShell: `Ctrl+Z`. |
| `Ctrl+T` twice quickly | The whole command line. | The same key; in Bash press it twice. |

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
- **`Ctrl+T`** replaces the shell's "transpose characters" on that key. To use
  another key, set `BADDEL_KEY` before the line above: `BADDEL_KEY='^B'` (zsh),
  `BADDEL_KEY='\C-b'` (Bash), `$env:BADDEL_KEY = 'Ctrl+b'` (PowerShell).

Other settings, all optional and set the same way: `BADDEL_BIN` (path of the
Baddel executable, if the script is not in its packaged place),
`BADDEL_DOUBLE_PRESS_MS`, and `BADDEL_HINT` (`latin`, `arabic` or `none`: the
layout to assume instead of reading the active one).

## Claude Code's message box

Claude Code opens the draft you are writing in an external editor when you
press `Ctrl+G`, and reads the edited text back. Baddel can be that editor: it
corrects the draft and returns at once.

Set `VISUAL` for Claude Code to Baddel with `--fix-draft`. The path must not
contain spaces; Claude Code splits the value at spaces and does not accept
quotes.

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

Then, in Claude Code:

| Press | What happens |
| --- | --- |
| `Ctrl+G` | The whole unsent draft is corrected and stays in the message box. |
| `Ctrl+_` | Claude Code's undo restores the draft as it was. |

What to expect:

- **The whole draft, every time.** Claude Code passes the complete draft and
  no cursor position, so there is no last-word or selection mode here.
- **`Ctrl+G` no longer opens a text editor** in Claude Code while `VISUAL` is
  set this way.
- **Attachments.** Markers such as `[Image #1]` are kept exactly as they are
  and do not count as English text.
- **Pasted text.** A long paste shows in the message box as
  `[Pasted text #1 +30 lines]`, but Claude Code gives the editor the pasted
  text itself. Baddel therefore sees it as part of the draft. If you typed in
  Arabic by mistake after pasting English, the active Arabic layout tells
  Baddel to convert only the Arabic part, and the paste comes back unchanged
  (as full text, no longer folded). If you typed English letters by mistake,
  the paste is in the same script as your typing and is converted with it:
  press `Ctrl+_`, or correct before you paste.
- **Mixed drafts** follow the same rule as mixed command lines above.
- **Other files.** `--fix-draft` only rewrites files named the way Claude Code
  names its drafts (`claude-prompt-…`). If `VISUAL` or `EDITOR` reaches another
  program, such as `git commit`, Baddel leaves that file alone and says so.

## Limits

- Baddel does not switch the keyboard layout after a correction in a terminal.
  Switch it yourself before you continue typing.
- Supported and tested are the shells in the table above. Other shells and
  line editors (fish, Bash on macOS, which is version 3.2, `cmd.exe`, vi mode
  in zsh) have no integration.
- A program running inside the terminal, other than Claude Code, owns its own
  input; Baddel has no way to correct it.
- On Windows each press starts `Baddel.exe`, which takes about 0.4 seconds.
- Reading the active layout: on macOS the current input source; on Windows the
  layout of the foreground window; on Linux the X11 keyboard group. On Wayland
  and over SSH there is none, and the text alone decides.

What was run, and where, is in the [testing record](TESTING.md#terminal-shell-command-line-and-claude-code).

## For developers

The shells call one command and Claude Code calls another; both are the
packaged executable.

```text
baddel --fix-text [--mode word|line] [--cursor N] [--selection START LENGTH]
       [--unit utf16|scalars|bytes] [--hint latin|arabic|none]
    Reads the buffer from standard input (UTF-8). Writes "ok CURSOR" and a
    line break followed by the corrected buffer, or "no CODE".
baddel --fix-draft [--any-file] [--hint latin|arabic|none] FILE
    Corrects a draft file in place. The file is rewritten only when a
    correction was made.
```

Exit codes: 0 corrected, 1 left unchanged, 2 wrong usage. `CODE` is one of the
refusal codes in [the correction rules](CORRECTION_RULES.md); messages never
contain the text. `--unit` says what the cursor is counted in: code points for
zsh and Bash 5, UTF-8 bytes for Bash 4, UTF-16 units for PSReadLine. The logic
is `TextFix` in both cores and runs `shared/fixtures/text-fix.json`.

`tools/terminal-check.py` runs the end-to-end checks: it starts a separate
shell or Claude Code in its own pseudo-terminal with a throwaway configuration,
types synthetic text, presses the keys, and reads the buffer back.
