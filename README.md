# Baddel — بدّل

Baddel fixes text typed with the wrong keyboard layout. You meant to write
`عليكم` but the keyboard was on English and you got `ugd;l` — press the
shortcut and Baddel rewrites it in place and switches the layout for you.

It is an original, open-source utility for Arabic and English. Everything runs
locally on your computer.

| Platform | Status in 0.1.0 |
|---|---|
| macOS 13+ (Apple silicon and Intel) | Menu bar app |
| Windows 10 / 11 (x64) | Notification-area app |
| Linux | Planned — see [docs/LINUX.md](docs/LINUX.md) |

This first release is about correction only. The clipboard history described
in [docs/CLIPBOARD_HISTORY.md](docs/CLIPBOARD_HISTORY.md) is **upcoming and not
part of this release**.

## What it does

- **Press the shortcut once**: fixes exactly the selected text. With no
  selection, fixes the last word before the caret.
- **Press it twice within about 300 ms**: fixes the entire focused text field in
  one operation. Baddel waits for the second press before changing anything,
  ignores a held key, and checks that the same field still has focus.
- **Switches the active keyboard layout** to match, once the edit is verified.
- **Shows a small Undo button** next to the edited text. Undo restores the
  original text and the previous layout, but only while the same field still
  holds exactly the corrected text. Clicking it does not take focus away from
  the field.
- **Skips what it should not touch**: password fields, read-only fields, fields
  it cannot read or write reliably, and text that changed between reading and
  writing.

| | macOS | Windows |
|---|---|---|
| Default shortcut | ⌥⇧Space | Ctrl+Alt+Space |
| Where it lives | Keyboard icon in the menu bar | Blue icon in the notification area |
| Settings and About | Menu bar icon | Right-click the icon |

## Download and install

Packages are attached to the [releases](https://github.com/Mahmood83367/baddel/releases)
of this repository. Each ZIP contains the app, `LICENSE`, a `README.txt` with
these instructions, and `SHA256SUMS.txt`; a `.sha256` file for the ZIP itself
is published next to it.

**Signing status of 0.1.0, stated plainly:** the macOS app is ad-hoc signed and
**not notarized** by Apple; the Windows executable is **not code-signed**. Both
systems will warn you before running software they cannot identify. Those
warnings are the operating system protecting you. Baddel does not, and will
not, switch them off for you; whether to proceed is your decision.

### macOS

1. Download `Baddel-<version>-macos-universal.zip` and extract it.
2. Optional: run `shasum -a 256 -c SHA256SUMS.txt` inside the folder.
3. Move `Baddel.app` to Applications and open it. If macOS refuses because it
   cannot check the developer, and you trust the download, use
   **System Settings → Privacy & Security → Open Anyway**.
4. Baddel explains why it needs **Accessibility** access and opens the right
   settings pane. You enable it there yourself.

### Windows

1. Download `Baddel-<version>-windows-x64.zip` and extract the whole folder,
   for example to `%LOCALAPPDATA%\Programs\Baddel`.
2. Optional: compare `Get-FileHash Baddel.exe -Algorithm SHA256` with
   `SHA256SUMS.txt`.
3. Run `Baddel.exe`. If SmartScreen warns, and you trust the download, choose
   **More info → Run anyway**.

It is a portable app: no installer, no administrator rights, no .NET install.
Settings are stored in `%APPDATA%\Baddel\settings.json`. To start it with
Windows, put a shortcut to `Baddel.exe` in the folder opened by `shell:startup`.
To remove it, exit Baddel and delete the folder.

Baddel does not run elevated, so it cannot edit windows of programs that run as
administrator.

## Keyboard layouts

The mapping data in [`shared/layouts`](shared/layouts) is generated from each
operating system's own layout tables, never typed by hand, and two layouts are
never assumed to be the same because their names are similar.

| | Arabic (choose in Settings) | English |
|---|---|---|
| macOS | Arabic, Arabic – PC | US English ("U.S." and "ABC") |
| Windows | Arabic (101), Arabic (102) | US English |

**Current limit: US English is the only English layout.** Other English
layouts (UK, for example), detection of the layouts you have installed, and
custom mappings are on the [roadmap](docs/ROADMAP.md).

## Privacy

- No keystroke logging. Baddel registers a single system hot key
  (`RegisterEventHotKey` on macOS, `RegisterHotKey` on Windows) and is only told
  when that combination is pressed. It installs no event tap, no keyboard hook
  and no global key monitor.
- No network access. There is no updater in this release; text is read from the
  focused field only when you press the shortcut, converted in memory, and
  written back.
- Diagnostics contain outcome codes and lengths. They never contain the text;
  the diagnostic record type has no field that could hold it.
- The original text is kept in memory only while the Undo button is on screen
  (about six seconds).
- The optional paste fallback (off by default) saves your clipboard, pastes
  over a verified selection, and restores the clipboard afterwards.

## How the text is decided

The full rules, including the **whole-field rule for mixed-script text**, are in
[docs/CORRECTION_RULES.md](docs/CORRECTION_RULES.md). In short:

- The direction comes from the text itself: Latin letters mean it was typed on
  the English layout, Arabic letters mean the Arabic layout. The active layout
  is only a tie-breaker.
- Conversion is by physical key, so punctuation that stands for a letter is
  handled: `ugd;l` → `عليكم`.
- In a whole field with both scripts, the script with more letters is treated
  as the mistyped one and is converted; words already in the other script are
  left exactly as they are.
- Whitespace is never changed. The last-word fix skips spaces between the word
  and the caret and keeps them.

## What has been tested

Exactly which scenarios were run, on which machine, and what has **not** been
verified is recorded in [docs/TESTING.md](docs/TESTING.md). In brief: on macOS
against TextEdit; on Windows 11 against standard edit controls, rich-edit
controls and Notepad, in a real desktop session. Browsers, Electron apps,
Microsoft Office and other custom text surfaces have not been verified on
either platform; Baddel is built to refuse those safely rather than guess.

## Build from source

```bash
# macOS (Xcode 15 or later)
cd macos && swift test && ./scripts/build-app.sh
```

```powershell
# Windows (.NET 8 SDK)
dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj
dotnet test windows/tests/Baddel.Windows.Tests/Baddel.Windows.Tests.csproj
dotnet run --project windows/src/Baddel.App
```

Release packaging is described in [docs/RELEASING.md](docs/RELEASING.md).

## Repository layout

```
shared/     Layout data and test fixtures used by every platform
macos/      Swift package: BaddelCore (pure logic), BaddelMacKit (system APIs), the app
windows/    C#: Baddel.Core (pure logic), Baddel.Windows (system APIs), the app, check tool
tools/      Script that generates the macOS layout data from the system tables
docs/       Rules, architecture, testing record, releasing, roadmap, designs
```

## Roadmap

Clipboard history for macOS, a Linux desktop version, more keyboard layouts
with manual and automatic selection, and opt-in signed updates. Details in
[docs/ROADMAP.md](docs/ROADMAP.md).

## License, copies and forks

Baddel is released under the [MIT License](LICENSE).
Copyright (c) 2026 Mahmood.

The MIT License lets you use, copy, modify and redistribute the software.
Its one condition is that **the copyright notice and the license notice are
kept in all copies or substantial portions of the software** — so a fork or
copy that redistributes Baddel, in source or binary form, must retain the
`LICENSE` file with the original copyright line. This paragraph only restates
the license; it adds no terms.

If you fork the repository on GitHub, we recommend leaving **"Copy the `main`
branch only"** selected, and opening pull requests against `main`. That is a
recommendation for keeping contributions simple, not a restriction: a public
repository cannot limit which branches are forked. See
[CONTRIBUTING.md](CONTRIBUTING.md).
