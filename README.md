<img src="docs/media/baddel-logo.png" alt="Baddel logo" width="96">

# Baddel | بدّل

**Fix text typed with the wrong keyboard layout with a shortcut.**

Baddel is an open-source utility for typing in Arabic and English. If you meant to type `عليكم` and got `ugd;l`, press the shortcut to fix the text in place and keep typing.

[Download Baddel](https://mahmoood.com/baddel/) · [Watch the quick-start video](https://mahmoood.com/baddel/#demo) · [GitHub releases](https://github.com/Mahmood83367/baddel/releases) · [العربية](README.ar.md)

## Quick start

1. Try an editable field in TextEdit or Notepad with the other language’s keyboard layout active.
2. **Press the shortcut once** to correct the selected text. With no selection, Baddel corrects the last word before the cursor.
3. **Press twice quickly** to correct the whole field. After a successful correction, Baddel can switch to the matching keyboard layout when that layout is enabled in your operating system and switching is enabled in Baddel.
4. **Click Undo** to restore the previous text and keyboard layout while the same field is active and the corrected text is intact.

| Platform | Default shortcut | Where to find Baddel |
| --- | --- | --- |
| macOS 13 or later, Apple silicon and Intel | `⌥⇧Space` | Menu bar |
| Windows 10 or 11 (x64) | `Ctrl+Alt+Space` | Notification area by the clock |
| Linux (x64), X11 prototype | `Ctrl+Alt+Space` | After starting `baddel` in your desktop session |

Baddel skips password fields and fields it cannot edit safely. [Tested environments](docs/TESTING.md) · [Correction rules](docs/CORRECTION_RULES.md)

## Download and install

Choose the package for your platform from the download page. The current release is `0.2.1`, for macOS, Windows and Linux. Each release lists its signing status and SHA-256 checksums: the macOS app is ad-hoc signed and not notarized by Apple, and the Windows app is not code-signed, so both systems warn before the first start. A signed, notarized macOS build will follow as a later, higher version. [Download page](https://mahmoood.com/baddel/) · [Release notes](https://github.com/Mahmood83367/baddel/releases/tag/v0.2.1)

### macOS

1. Extract the macOS ZIP and move `Baddel.app` to **Applications**. Run it from there: a copy started from **Downloads** is run by macOS from a temporary location, and its Accessibility permission does not stick.
2. Open Baddel from **Applications**. Its icon appears in the menu bar.
3. Enable Baddel in **System Settings → Privacy & Security → Accessibility**. Baddel needs this permission to edit the focused field.

If upgrading from an older preview leaves you with a stale Accessibility entry, select Baddel in the **Accessibility** list, press **−**, then add and allow the copy in **Applications**. The permission window also has a **Remove Old Entry…** button. macOS warns when opening Baddel because this release has no Apple notarization. Verify the published checksum and follow Apple's instructions if you choose to open it. [Apple's instructions](https://support.apple.com/en-us/102445)

In Claude, ChatGPT and other Chromium-based apps, the first press can take about a second: those apps describe their text fields only when asked, and Baddel asks then. If a field is refused, the message says why. (Version `0.2.0` answered "This field isn't supported" there after a restart.) [Details](docs/MACOS.md#claude-chatgpt-and-other-web-based-apps)

**Open Baddel at login** is in Settings. It works for the copy in **Applications**. Turn it on or off there or under **System Settings → General → Login Items**. [macOS guide](docs/MACOS.md)

### Windows

Extract the whole ZIP to a permanent folder and run `Baddel.exe`. The package includes the .NET runtime. Right-click the Baddel icon by the clock for Settings. The app is not code-signed, so SmartScreen may warn before it opens. [Release notes](https://github.com/Mahmood83367/baddel/releases/tag/v0.2.1)

### Linux

The Linux build is a prototype for 64-bit x86, tested by automation on Ubuntu 24.04 only.

**Debian, Ubuntu and derivatives:**

```bash
sudo apt install ./baddel_0.2.1_amd64.deb
```

**Any other distribution, for your user only, without root:** unpack the `x64` archive and run its installer.

```bash
./install.sh
```

Then:

1. Start Baddel from the application menu, or run `baddel`. On X11 it holds the shortcut `Ctrl+Alt+Space` itself. On Wayland it cannot: bind a shortcut in your desktop's keyboard settings to `baddel --trigger`, and switch the layout yourself.
2. To start it at every login, run `baddel --autostart enable`. It is off until you do; `baddel --autostart disable` turns it off again.
3. To remove Baddel: `sudo apt remove baddel`, or `~/.local/opt/baddel/uninstall.sh` for the per-user install. Your settings in `~/.config/baddel` are kept either way.

Baddel edits fields through the desktop's accessibility service. GTK 3 and GTK 4 fields are tested. Qt and KDE applications describe their fields only while the desktop's accessibility switch is on, so Baddel turns that switch on when it starts and leaves it on until you log out; set `"EnableDesktopAccessibility": false` in `~/.config/baddel/settings.json` to prevent that. If a field is refused, `baddel --focus-report 3` says what Baddel can see in the field you click into. Testing so far is automated, on Ubuntu 24.04; no real desktop session has been tried. [Linux guide, limits and what was tested](linux/README.md)

## In a terminal

The shortcut above does not reach a terminal prompt, so Baddel offers two opt-in integrations there. Neither runs a command or sends a message for you, and Baddel does not switch the keyboard layout in a terminal.

**Shell command line.** Add one line to your shell's start-up file, then open a new terminal:

| System and shell | File | Line to add |
| --- | --- | --- |
| macOS, zsh | `~/.zshrc` | `source /Applications/Baddel.app/Contents/Resources/shell/baddel.zsh` |
| Windows, PowerShell | `$PROFILE` | `. "C:\path\to\Baddel\shell\baddel.ps1"` |
| Linux, Bash | `~/.bashrc` | `source /path/to/Baddel/shell/baddel.bash` |

1. Type a command without running it.
2. **Press Baddel's shortcut once**, the same one as everywhere else, to correct the selected text, or the last word before the cursor. In Bash it is always the last word.
3. **Press it twice quickly** to correct the whole command line.
4. **Undo** with the shell's own key: `Ctrl+_` in zsh and Bash (twice in Bash after a double press), `Ctrl+Z` in PowerShell.

Baddel lets go of its shortcut while a terminal window is in front, so the shell receives it. Two exceptions: PowerShell cannot be given `Ctrl+Alt+Space` (it reads it as Space), so there the key is `Ctrl+T` unless you choose a shortcut such as `Ctrl+Shift+Space` in Baddel's Settings; and stock xterm needs `metaSendsEscape`. `Baddel --terminal-key status` says what is active on your computer.

**Claude Code's message box.** Set `VISUAL` for Claude Code to Baddel's draft command, for example in `~/.claude/settings.json`:

```json
{ "env": { "VISUAL": "/Applications/Baddel.app/Contents/MacOS/Baddel --fix-draft" } }
```

On Windows use `C:\path\to\Baddel\Baddel.exe --fix-draft`, on Linux `/path/to/Baddel/baddel --fix-draft`; the path must not contain spaces. Then press **`Ctrl+G`** in Claude Code to correct the whole unsent draft, and **`Ctrl+_`** to restore it. To use Baddel's own shortcut there too, add the entry printed by `Baddel --terminal-key claude` to `~/.claude/keybindings.json`; in macOS Terminal that also needs **Use Option as Meta key**. Claude Code hands over the whole draft only, so there is no last-word mode. Image markers such as `[Image #1]` and Claude's previous reply, when Claude Code shows it in the editor, are left as they are. Long pasted text reaches Baddel as part of the draft and can be converted with it. While this is set, `Ctrl+G` no longer opens a text editor.

[Terminal guide, settings and limits](docs/TERMINAL.md)

## Clipboard history on macOS

1. Open **Clipboard History** from the menu bar or press `⌥⇧V`. Enable **Keep clipboard history on this Mac**.
2. Copy text, images, or files as usual. To retrieve an entry, open the history and choose **Copy**, then paste it in your app with `⌘V`.
3. To keep a standalone copy of a file even if you delete the original, choose **Keep File Copy**.

History stays on your Mac and holds up to 100 recent items. Use **Clear Recent** to clear those items and **Delete** to remove a saved file copy. [Clipboard history guide](docs/CLIPBOARD_HISTORY.md)

## Layouts, updates, and privacy

- **Layouts.** Settings support common Arabic and English layouts, including Arabic–PC and British on macOS and Arabic (101), Arabic (102), US and United Kingdom on Windows. You can also add a custom JSON layout file, which Baddel checks before using it. [Layout guide](docs/LAYOUTS.md)
- **Updates.** Choose **Check for Updates** from the menu on macOS or Windows, or run `./baddel --check-updates stable` on Linux. macOS and Windows can check once a day if you enable it. Choose **Stable releases and previews** in Settings to include pre-releases. The current version lets you download and install new releases manually. [Updates guide](docs/UPDATES.md)
- **Privacy.** Corrections run on your computer when you press the shortcut. Optional clipboard history stays on your Mac. Update checks contact GitHub for release information.

## Contribute and license

When you fork the repository, start from `main` and open pull requests against it. See the contributing guide for building, running the checks, and keeping the two language guides current. [Contributing](CONTRIBUTING.md) · [Packaging releases](docs/RELEASING.md)

**Copyright © 2026 Mahmood.** Baddel uses the [MIT License](LICENSE). Keep the copyright and license notices when distributing copies or substantial portions of the software.
