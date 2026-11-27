# Baddel — بدّل

Baddel fixes text typed with the wrong keyboard layout. You meant to write
`عليكم` but the keyboard was on English and you got `ugd;l` — press the
shortcut and Baddel rewrites it in place and switches the layout for you.

It is an original, open-source utility for Arabic and English. Everything runs
locally on your computer.

| Status | |
|---|---|
| macOS | Working prototype (menu bar app) |
| Windows | Core logic and shared tests only; no app yet — see the [roadmap](docs/ROADMAP.md) |

## What it does

- **Press the shortcut once** (default **⌥⇧Space**): fixes exactly the selected
  text. With no selection, fixes the last word before the caret.
- **Press it twice within about 300 ms**: fixes the entire focused text field in
  one operation. Baddel waits for the second press before changing anything,
  ignores a held key, and checks that the same field still has focus.
- **Switches the active keyboard layout** to match, once the edit is verified.
- **Shows a small Undo button** next to the edited text. Undo restores the
  original text and the previous layout, but only while the same field still
  holds exactly the corrected text.
- **Skips what it should not touch**: password fields, fields it cannot read or
  write reliably, and text that changed between reading and writing.

Supported layouts: **US English** (also "ABC"), **Arabic** (the macOS layout)
and **Arabic – PC**. The mapping data is generated from the system layout
tables, not typed by hand; see [`shared/layouts`](shared/layouts).

## Privacy

- No keystroke logging. Baddel registers a single system hot key
  (`RegisterEventHotKey`) and is only told when that combination is pressed. It
  installs no event tap and no global key monitor.
- No network access. Text is read from the focused field only when you press
  the shortcut, converted in memory, and written back.
- Diagnostics contain outcome codes, lengths, the app's bundle identifier and
  the element's accessibility role. They never contain the text itself; the
  diagnostic record type has no field that could hold it.
- The original text is kept in memory only while the Undo button is on screen
  (about six seconds).

## Build and run (macOS)

Requires macOS 13 or later and Xcode 15 or later (Swift 5.9+).

```bash
cd macos
swift test                 # unit tests, including the shared fixtures
./scripts/build-app.sh     # builds macos/build/Baddel.app
open build/Baddel.app
```

Baddel appears as a keyboard icon in the menu bar.

### Accessibility permission

Reading and replacing text in other apps requires macOS Accessibility access.
On first launch Baddel opens a window that explains this and offers two
buttons: one shows the system's own permission dialog, the other opens
**System Settings → Privacy & Security → Accessibility**. You enable Baddel
there yourself; Baddel never changes that setting. Until access is granted the
shortcut only re-opens that window.

The build script signs the app ad hoc, so macOS treats every rebuild as a new
app. After rebuilding, remove the old Baddel entry from the Accessibility list
and add the new build.

### Settings

Menu bar icon → **Settings…**

- **Shortcut** — click the button and press a new combination (it must include
  ⌃, ⌥ or ⌘). If another app already owns the combination, Baddel says so and
  keeps the previous one.
- **Arabic layout** — automatic (from your enabled input sources), Arabic
  (macOS) or Arabic – PC.
- **Double-press window** — 150–600 ms, 300 ms by default.
- **Switch the keyboard layout after a correction** — on by default.
- **Paste fallback (experimental)** — off by default. See
  [Architecture](docs/ARCHITECTURE.md#writing-text).

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

## Checks

| Check | How | What it covers |
|---|---|---|
| Unit tests | `cd macos && swift test` | Layout mappings, selections, last word, mixed script and RTL, punctuation-as-letters, trailing whitespace, UTF-16 offsets and surrogate pairs, double-press state, safe rejections, stale-field protection, undo conditions |
| Shared fixtures on .NET | `dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj` | The same fixture file against the C# port |
| Real Accessibility edits | `macos/scripts/ax-integration-check.sh` | Runs the engine against a throwaway TextEdit document |
| Real hot key | `macos/scripts/hotkey-e2e-check.sh` | Starts the app, posts the shortcut, clicks Undo |

The two scripts need a terminal that already has Accessibility access, and
refuse to run if TextEdit is open so they cannot touch your documents.

### Verified and not verified

Verified on macOS 26.5 (Apple silicon) against TextEdit, through the running
app with real shortcut presses and a real mouse click: single press, double
press, undo without stealing focus, the Undo panel placed directly under the
edited word, and the layout switching from Arabic to ABC and back on Undo.
Verified with the engine driving TextEdit through Accessibility: exact
selection, UTF-16 offsets after an emoji, trailing whitespace in right-to-left
text, undo refused after the text changed, and rejection with the field left
unchanged.

Not yet verified: other apps. Browsers and Electron apps expose text through
Accessibility differently and may refuse direct edits; Baddel is designed to
reject those safely rather than guess, but that behaviour has only been
exercised in unit tests with simulated fields. The paste fallback, skipping a
real password field, the Settings window (including recording a new shortcut)
and the permission window on a Mac without access have not been exercised end
to end. The C# port has not been compiled locally; it is built and tested by
CI.

## Repository layout

```
shared/     Layout data and test fixtures used by both platforms
macos/      Swift package: BaddelCore (pure logic), BaddelMacKit (system APIs), the app
windows/    C# port of the core logic and its tests
tools/      Script that generates shared/layouts from the macOS layout tables
docs/       Rules, architecture, roadmap, clipboard-history design
```

## Roadmap

- Windows correction (hot key, UI Automation, layout switching, Undo).
- A local, searchable clipboard history for macOS (text, images and files) —
  see the [design](docs/CLIPBOARD_HISTORY.md).

Details in [docs/ROADMAP.md](docs/ROADMAP.md).

## License

[MIT](LICENSE)
