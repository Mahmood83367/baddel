# Testing record

This page records what was actually run, where, and what was not. "Passed"
means the check produced the expected text or the expected refusal; nothing
here is inferred. The first part covers what 0.2.0 added; the sections after
it are the 0.1.0 record, which still applies.

## Added in 0.2.1

### Linux: exact text in fields, installing, Start at login

All on GitHub-hosted Ubuntu 24.04 runners, with the binary from the packaged
archive.

**The report**: typing `hndv hnmp` gave the right Arabic words followed by many
square characters.

| Finding | How it was established |
|---|---|
| The inserted text was passed to `atspi_editable_text_insert_text` without a terminating NUL, although the function takes a C string | Read from the code and the API; fixed, with a unit test that every text handed over ends in exactly one NUL |
| .NET pads a byte array with zeros to a multiple of eight, so only text whose UTF-8 length is a multiple of eight was exposed. Each four-letter Arabic word is eight bytes | Unit test asserts the reported words are eight bytes |
| The trailing characters themselves | **Not reproduced.** In CI the bytes after the array happened to be zero in every run, in GTK 3 and GTK 4. What follows an array in memory varies from run to run, which fits a fault seen on one machine and not another |
| GTK 4 fields were refused as "disabled" (GTK 4 reports the sensitive state, not enabled) | Reproduced in CI, fixed, GTK 4 entry and text view now pass every case |
| Qt applications are not on the accessibility bus unless the desktop's accessibility switch is on | The new `--focus-report` showed `applications=0` for a Qt window. Baddel now turns the switch on. In CI a Qt application still did not appear with the switch on, so Qt fields remain unverified |

**Byte-exact check** (`linux/scripts/text-fidelity-check.sh`, X11 under Xvfb):
after a correction the field must equal the engine's own result in every byte,
and after Undo the original in every byte. Cases: the reported phrase (whole
field and last word), a second phrase, Arabic typed for English with Arabic
punctuation and Arabic-Indic digits, a right-to-left mark, emoji with a
skin-tone modifier, last word after emoji, a combining mark, and for
multi-line fields three lines (whole field, and last word on the last line).

| Field | Result |
|---|---|
| GTK 3 entry, GTK 3 text view | Passed, every case and every Undo |
| GTK 4 entry, GTK 4 text view | Passed, every case and every Undo |
| Qt 5 line edit, plain text edit, text edit | Skipped: the application was not on the accessibility bus |
| An application that accepts the deletion and refuses the insertion | The deleted text is put back byte for byte; reported as `WriteFailed` |
| New text arriving while the correction is being verified | Nothing is deleted, the new text stays; reported as `VerificationFailed` |

Unit tests: text for native calls ends in one NUL; a string with a NUL or an
unpaired surrogate is refused before anything is deleted; text read from an
application is decoded strictly, so bytes that are not UTF-8 are refused
instead of becoming U+FFFD, while a real U+FFFD in the text is kept.

**Install check** (`linux/scripts/install-check.sh`, 36 checks, all passed):

| Scenario | Result |
|---|---|
| The `.deb` has no installation scripts and installs only under `/opt/baddel`, `/usr/bin` and `/usr/share` | Passed |
| Clean `apt install`: program on the PATH, menu entry valid, icon and Bash integration present, nothing started, Start at login off, nothing in `/etc/xdg/autostart` | Passed |
| `--autostart enable` and `disable`; the entry is valid and names `/usr/bin/baddel`; a same-named file Baddel did not write is neither replaced nor removed | Passed |
| A login-style start: `dex --autostart` runs exactly that entry, Baddel is running, answers `--quit` and stops | Passed |
| Upgrade to a higher-versioned package: settings and the Start at login entry are byte-identical, the settings are still read, nothing is started | Passed |
| `apt remove`: package, program, `/opt/baddel` and menu entry are gone; settings are kept; a leftover Start at login entry starts nothing | Passed |
| Per-user `install.sh` from the archive, run again as an upgrade, `uninstall.sh`; a `~/.local/opt/baddel` it did not create is refused and left alone | Passed |

Not verified:

- **Any real desktop session, and a real logout and login.** The login step
  runs the autostart entry the way a session does; no session was logged into.
- **Wayland.** The check was run inside a headless Weston session: Baddel
  started in trigger-only mode, but no field counted as focused there (a
  headless compositor has no keyboard), so nothing was learned about fields.
- **Qt and KDE fields**, browsers, Electron apps, LibreOffice.
- **The reporter's own layout.** `hndv hnmp` gives `اريد اروح` on their
  machine; with the stock `ara` layout it gives other letters. The check keeps
  the phrase as reported and compares against the engine's result for the
  layout in use.
- "Some symbols do not paste": the Linux build has no clipboard or paste path,
  so this needs the application and the steps from the reporter.
- Other distributions and package formats, and ARM.

### Terminal: shell command line and Claude Code

Run by `tools/terminal-check.py`. Each check starts its **own** shell or its
own Claude Code in a new pseudo-terminal, with a throwaway home, start-up file
and configuration; types synthetic text; presses the keys; and reads the edit
buffer back through the program's own hooks (a test-only key binding in the
shells, the same `Ctrl+G` hand-over in Claude Code). Enter is never pressed on
a command or a draft, and each check confirms that nothing was run or
submitted. No personal shell configuration, history or running session was
used.

**Shell command line** — the same cases in every shell. The key pressed is
Baddel's own shortcut as a terminal delivers it (zsh: the no-break space of
`⌥⇧Space`, and Escape-Space for Option as Meta; Bash: Escape-NUL for
`Ctrl+Alt+Space`), and `Ctrl+T` in the fallback and `BADDEL_KEY` runs and in
PowerShell:

| Case | zsh | Bash | PowerShell |
|---|---|---|---|
| One press corrects the last word (`echo ugd;l` → `echo عليكم`) | Passed | Passed | Passed |
| The shell's undo restores it (`Ctrl+_`, `Ctrl+Z`) | Passed | Passed | Passed |
| Two quick presses correct the whole line | Passed | Passed | Passed |
| Undo after a double press returns to the typed text | Passed (1 step) | Passed (2 steps) | Passed (1 step) |
| Arabic typed for English (`git سفشفعس` → `git status`) | Passed | Passed | Passed |
| One press on a mixed line changes only the last word | Passed | Passed | Passed |
| A slow second press is a new single press, not a whole-line correction | Passed | Passed | Passed |
| Nothing to correct: the line is left alone | Passed | Passed | Passed |
| Cursor in the middle: the word before it, cursor placed after it | Passed | Passed | Passed |
| A selection of two words is corrected instead of the last word | Passed | Not applicable | Passed |
| No command line was run | Passed | Passed | Passed |

| System | What ran | Build under test |
|---|---|---|
| macOS 26, Apple silicon | zsh 5.9 in a pseudo-terminal | The packaged `Baddel.app` (ad-hoc signed local build) and the script inside it |
| GitHub-hosted macOS 15 | The same check, in CI | The packaged universal app from the ZIP |
| Linux, Ubuntu 24.04, 22.04, 20.04 and 18.04 containers | Bash 5.2, 5.1, 5.0 and 4.4 in a pseudo-terminal | The packaged `baddel` built for arm64 with the release options, and `shell/baddel.bash` |
| GitHub-hosted Ubuntu 24.04 | The same check with Bash 5.2, in CI | The packaged x64 binary from the archive |
| Windows 11 (26200), a separate temporary folder | Windows PowerShell 5.1 with PSReadLine 2.0.0, and PowerShell 7.7 with PSReadLine 2.4.5, each in an SSH terminal (ConPTY) | `Baddel.exe` published with the release options (cross-built), and `shell\baddel.ps1` |

Bash 4.4 reports the cursor in bytes and Bash 5 in characters; both were
exercised with Arabic text before the cursor. CI on Windows runs the
`--fix-text` and `--fix-draft` commands of the packaged ZIP with redirected
UTF-8 input and output, but not PSReadLine itself, which needs a console.

**Claude Code's message box** — Claude Code 2.1.332, started with an empty
configuration directory and a placeholder key; nothing was sent:

| Case | macOS | Linux | Windows |
|---|---|---|---|
| The draft is handed to the editor and read back unchanged | Passed | Passed | Passed |
| `Ctrl+G` corrects the whole draft (`ugd;l hgsghl` → `عليكم السلام`) | Passed | Passed | Passed |
| `Ctrl+_` restores the draft | Passed | Passed | Passed |
| Arabic typed for English (`اثممخ صخقمي` → `hello world`) | Passed | Passed | Passed |
| An `[Image #1]` marker, typed as text, is kept | Passed | Passed | Passed |
| A draft of two lines keeps its line break | Passed | Passed | Passed |
| A draft with nothing to convert is left alone | Passed | Passed | Passed |
| A folded 30-line paste reaches the editor as its full text | Passed | Passed | Passed |
| Pasted English stays when Arabic was the active layout (layout given to the command explicitly) | Passed | Passed | Not run |
| `VISUAL=<Baddel> --fix-draft`, as documented, without the check's editor script | Passed | Passed | Passed |
| Nothing was submitted (no transcript was created) | Passed | Passed | Not checked |

macOS: in a pseudo-terminal, with the packaged app. Linux: Ubuntu 24.04
container with Node 18 and the packaged arm64 build. Windows: Windows 11 in an
SSH terminal, Claude Code installed into the temporary folder with npm.
Setting `VISUAL` through the `env` block of Claude Code's `settings.json` was
tried on macOS only.

**One shortcut** — how Baddel's own combination reaches each host:

| Check | Result |
|---|---|
| zsh binds what `--terminal-key zsh` reports for `⌥⇧Space`; all shell cases pass with the no-break space and with Escape-Space (pseudo-terminal, and in CI on macOS 15) | Passed |
| A stored shortcut with Command: the script falls back to `Ctrl+T`, and the status command says the shortcut cannot reach a terminal | Passed (zsh), Passed (Bash, `Super+space`) |
| `BADDEL_KEY` overrides the shortcut | Passed (zsh, Bash, PowerShell) |
| Loading a script switches automatic pass-through on (macOS preference, Linux marker file) | Passed |
| macOS layout tables: Option-Space and Option-Shift-Space give U+00A0 under ABC, British, Arabic, Arabic – PC and Arabic – QWERTY | Observed |
| Claude Code with the entry from `--terminal-key claude` in its `keybindings.json`: Escape-Space corrects the draft, `Ctrl+_` restores it (macOS, pseudo-terminal) | Passed |
| **Real terminal windows on Linux** (`linux/scripts/terminal-window-check.sh`, GitHub-hosted Ubuntu 24.04, X11 under Xvfb with openbox, the packaged app running, keys sent as raw key codes through XTEST): | |
| – with sharing off, `Ctrl+Alt+Space` never reaches the terminal (the grab consumes it) | Passed in xterm, xfce4-terminal, GNOME Terminal |
| – with sharing on (automatic), English layout: one press, `Ctrl+_`, two presses | Passed in all three |
| – with the **Arabic layout active**, the same physical keys type Arabic, and the shortcut pressed under that layout corrects the last word and the whole line | Passed in all three |
| – xterm with stock settings | Not corrected: it does not send Alt as Escape; `metaSendsEscape` is needed (the passing xterm run sets it) |
| PSReadLine 2.0.0 and 2.4.5 record the chord `Ctrl+Alt+Spacebar` as `Spacebar` (Windows 11) | Observed; Baddel never offers that chord, and the script removes any binding that ends up without a modifier |
| PowerShell with the default shortcut: the handler is bound to `Ctrl+t` only, and all shell cases pass with it (CI-built ZIP, SSH terminal) | Passed |

Not verified:

- **Key presses in a Terminal.app window and in a Windows Terminal window.**
  I may not type into terminal applications on the Mac this was developed on,
  and the Windows machine had no interactive desktop session. What stands in
  for them: on macOS the layout tables and the pseudo-terminal runs with the
  exact bytes; on Windows the PSReadLine chord table above. That Terminal
  passes `⌥⇧Space` on as U+00A0 with its default settings, and that Baddel's
  release of the shortcut takes effect when Terminal comes to the front, were
  not observed in a window. On Windows nothing about the shortcut was observed
  in a window: not the release for Windows Terminal, not `Ctrl+Shift+Space` in
  PSReadLine, not `Ctrl+Alt+Space` in Claude Code (an SSH terminal cannot send
  it as a key event).
- Claude Code on Linux and Windows with Baddel's shortcut in
  `keybindings.json` (on Linux only because the container host was not
  available for this round; `Ctrl+G` was verified on both earlier).
- That `Ctrl+G` and `Ctrl+_` arrive while an Arabic layout is active was
  checked on macOS only against the layout tables (Arabic, Arabic – PC and
  Arabic – QWERTY produce the same control characters as ABC), not by typing.
- Claude Code's "Show last response in external editor" in a live session
  with a real reply. The block's format was taken from Claude Code 2.1.332
  itself and is covered by the shared fixtures and the command tests.
- Reading the active layout. On macOS the command read the active input
  source correctly with an English layout active; Arabic active was not
  tried, and the checks pass the layout explicitly. On Windows and Linux it
  was not exercised at all (an SSH session and a container have no layout).
- A real attached image or file in Claude Code. Only the marker text was
  tested.
- Shells and versions other than those listed, vi editing modes, and Claude
  Code versions other than 2.1.332.

### macOS installer, upgrade and Open at Login

Run by `macos/scripts/pkg-install-check.sh` on a **throwaway GitHub-hosted
macOS runner** (macOS 15, Apple silicon), with a real `installer` run as
administrator. The package under test is the **unsigned test build**, because
CI has no signing identity; it is never published. All 28 checks passed.

| Scenario | Result |
|---|---|
| Package metadata: Installer is told to close Baddel by bundle identifier; the package contains no scripts | Passed |
| Fresh install: `Baddel.app` is in `/Applications`, version, bundle identifier and icon are right, the signature verifies, the app starts | Passed |
| The package installed only `Applications/Baddel.app`; no launch agent or daemon exists afterwards | Passed |
| Installing did not turn on Open at Login | Passed |
| Open at Login: turning it on from `/Applications` is accepted and macOS reports it enabled | Passed |
| Open at Login: turning it off returns it to off; on and off again is repeatable | Passed |
| Upgrade over the published 0.1.0 preview (downloaded and hash-checked): `/Applications` holds the new version, which verifies and starts | Passed |
| A second old copy elsewhere on the disk was not touched (the package is not relocated to it) | Passed |
| The new build's code identity differs from the old preview's, so the old Accessibility entry cannot apply | Passed |
| "Remove Old Entry…": the app's own code clears Baddel's Accessibility entry (run through the installed app; the button itself was not clicked) | Passed |
| Upgrade over the published 0.2.0, and installing the same version again | Passed |
| Uninstall as documented: app and receipt are gone | Passed |

On the development Mac, without installing anything: the package was built and
expanded to confirm its payload, metadata and bilingual Installer pages; Open
at Login reports its state and **refuses to turn on from a copy outside
`/Applications`**; the app signs correctly with the Developer ID Application
identity.

**Not done:**

- **A real logout and login.** The checks confirm registration with macOS and
  its removal, not that Baddel actually opens at the next login.
- **The Installer window.** The package was installed with the command-line
  `installer`, which does not show the "quit Baddel" prompt or the welcome and
  conclusion pages; those were inspected as files only.
- **A signed and notarized installer.** No Developer ID Installer identity and
  no notarization profile were available, so the endorsed installer has not
  been built, and Gatekeeper's acceptance of it has not been observed.
- **Granting Accessibility after an upgrade by hand**, including clicking
  "Remove Old Entry…" in the window: CI cannot grant Accessibility.
- **Intel Macs.**

### Other

The app icon appears in the macOS bundle and the Windows executable; the
Windows tray icon now uses the executable's icon. The Windows and Linux jobs
pass unchanged.

## Added in 0.2.0

### Automated tests

| Suite | Count | Where it ran |
|---|---|---|
| Swift (`cd macos && swift test`) | 39 | macOS 26.5 (Apple silicon), local |
| C# core | 24 | Windows 11 (x64), self-hosted |
| C# Windows layer | 23 | Windows 11 (x64), self-hosted |
| C# Linux layer | 4 | compiled and run with the .NET SDK on Windows; runs on Ubuntu in CI |

New in these suites:

- **Layouts:** every built-in table passes validation; the committed Windows
  tables (US, UK, Arabic 101, Arabic 102) equal the tables inside that
  machine's layout DLLs; the macOS British table equals a fresh dump from
  macOS; Windows offers only Windows tables and falls back to the 0.1.0
  defaults for a missing, unknown or wrong-script choice.
- **Custom layouts:** each validation rule; a folder with one valid and four
  invalid files adds exactly the valid one and leaves the built-in layouts
  untouched.
- **Updates** (shared fixture, run by Swift and C#): version ordering; channel
  selection in eleven situations; a signed manifest accepted with the right
  key and refused with no key, another key, a changed byte, a damaged or empty
  signature, the wrong channel, or a version that is not newer; package
  selection by platform, architecture and OS version; the SHA-256 check; and
  that no update key is trusted.
- **Clipboard history** (macOS): six tests — three against a test double and
  three against **real macOS pasteboards**. Each real-pasteboard test creates
  its own uniquely named pasteboard and releases it afterwards; the system
  clipboard is never read or written. They cover: text captured and restored;
  entries marked concealed, transient or auto-generated not stored (and absent
  from the file on disk); the history surviving a restart; the storage folder
  having owner-only permissions; a PNG round trip; a file reference; Keep File
  Copy surviving deletion of the original; and an unpinned reference to a
  deleted file refusing to restore.

### macOS checks

| Check | Result |
|---|---|
| The correction and clipboard hot keys registered together; three presses each reached only their own handler (`--hotkey-coexistence-check`, on throwaway key combinations) | Passed |
| The correction shortcut is still ⌥⇧Space and registers | Passed |
| Live update check, preview channel: reports 0.1.0, no update for 0.2.0 | Passed |
| Live update check, stable channel: reports that no stable release exists | Passed |
| A failed request (GitHub answered 502 once) is reported as a failed check, not as "up to date" | Observed |
| Layout resolution: British + Arabic – PC chosen; a valid custom layout chosen; an invalid custom layout falls back to US English | Passed |
| `Baddel-0.2.0-macos-universal.zip` built, extracted, hashes verified, both architectures present, self-check run | Passed |

**Not run:** the macOS end-to-end script (`hotkey-e2e-check.sh`, real shortcut
presses against TextEdit), including its new cases for the British and US
choice. A released copy of Baddel was running on the test Mac, and the script
refuses to start next to another instance, because two instances would both
act on the same key press. The clipboard window (⌥⇧V, search, the buttons) and
the update dialogs were not operated by hand.

### Windows desktop checks

Same machine and method as below (Windows 11 build 26200, x64, interactive
Remote Desktop session, the self-contained `Baddel.exe` from the 0.2.0 ZIP).
Installed layouts: US English and Arabic (101) only. **48 checks passed.**
New ones:

| Scenario | Result |
|---|---|
| After English→Arabic, Windows' active layout is `00000401`, the layout used for conversion | Passed |
| After Arabic→English, Windows' active layout is `00000409` | Passed |
| Arabic (102) chosen, not installed: converted with the 102 table; keyboard left as it was | Passed |
| UK English chosen: converted with the UK table (`#` handled as the UK key) | Passed |
| UK English chosen, not installed: switching back to English leaves the keyboard as it was | Passed |
| US English chosen: converted with the US table | Passed |
| Settings file from 0.1.0 with no English choice: US English | Passed |
| Custom layout file: loaded, converted with its table, keyboard not switched | Passed |
| Invalid custom layout file: ignored, Arabic (101) used | Passed |
| Live update check from the packaged app, both channels | Passed |

Switching to an *installed* UK or Arabic (102) layout was not run on this
machine, which has neither. The `windows-app` CI job adds them to its
throwaway runner account; see that job's output for each run.

A correction to the 0.1.0 record: the layout-dump tool used then loaded
keyboard layouts into the test session as a side effect. That has been
removed (the tool now only reads layout DLLs), and the stray entries were
unloaded from that session.

## Automated tests

| Suite | Command | Count | Where it ran |
|---|---|---|---|
| Swift core | `cd macos && swift test` | 26 | macOS 26.5 (Apple silicon), local; GitHub-hosted `macos-15` |
| C# core | `dotnet test windows/tests/Baddel.Core.Tests/…` | 17 | Windows 11 (x64), self-hosted; GitHub-hosted `windows-latest` |
| C# Windows layer | `dotnet test windows/tests/Baddel.Windows.Tests/…` | 21 | same as above |

The Swift and C# core suites both run [`shared/fixtures/cases.json`](../shared/fixtures/cases.json):
24 conversions, 36 planning cases (selections, last word, mixed script and
right-to-left, punctuation that stands for letters, trailing whitespace, UTF-16
offsets and surrogate pairs, safe rejections) and 9 double-press sequences.
Both also test the engine against simulated fields: verified writes, stale or
shortened fields, focus changes, secure and unsupported fields, and the undo
conditions.

The Windows layer suite additionally checks that the committed Windows layout
data equals the tables inside the layout DLLs of the machine running the test
(US, Arabic 101, Arabic 102), and that Arabic 101 and 102 are different data.

## macOS desktop checks

Machine: macOS 26.5, Apple silicon, a real logged-in desktop. Target app:
TextEdit with throwaway documents. Scripts: `macos/scripts/ax-integration-check.sh`
and `macos/scripts/hotkey-e2e-check.sh`.

Through the running app, with real shortcut presses and a real mouse click:

| Scenario | Result |
|---|---|
| One press fixes only the last word | Passed |
| Two presses 120 ms apart fix the whole field once | Passed |
| Undo by mouse click restores the text; TextEdit stays frontmost | Passed |
| Undo panel sits directly under the edited word | Passed |
| Arabic typed as English: layout switches Arabic → ABC, Undo switches it back | Passed |
| Arabic layout set to Arabic – PC: a key that differs between the two layouts converts as Arabic – PC | Passed |
| Arabic layout set to Arabic (macOS): the same key converts as macOS Arabic | Passed |

With the engine driving TextEdit through Accessibility (no key presses):

| Scenario | Result |
|---|---|
| Whole field, then undo | Passed |
| Last word with trailing spaces in right-to-left text, then undo | Passed |
| Exact selection; undo refused after the text was edited | Passed |
| UTF-16 offsets after an emoji | Passed |
| Arabic typed instead of English, then undo | Passed |
| Nothing before the caret: refused, field unchanged | Passed |

Package: `Baddel-0.1.0-macos-universal.zip` was built, extracted, its
`SHA256SUMS.txt` verified, the signature verified, both architectures
(`arm64`, `x86_64`) confirmed, and `Baddel --self-check` run from the extracted
app on Apple silicon. The Intel slice was built but **not run** (no Intel Mac).

## Windows desktop checks

Machine: a self-hosted Windows 11 PC (build 26200, x64) in a real interactive
Remote Desktop session, with English (US) and Arabic (101) layouts installed
and **no .NET runtime installed** system-wide. Tool:
`baddel-wincheck --engine --e2e <Baddel.exe> --notepad`. The app under test was
the self-contained `Baddel.exe` extracted from the release ZIP.

Through the running app, with real key presses (`SendInput`) and real mouse
clicks:

| Scenario | Result |
|---|---|
| App starts and keeps running | Passed |
| One press fixes only the last word | Passed |
| Two presses 120 ms apart fix the whole field once | Passed |
| English typed as Arabic: text fixed, layout switches English → Arabic | Passed |
| …Undo popup appears 6 px below the caret | Passed |
| …clicking Undo restores the text, focus stays in the field, layout returns to English | Passed |
| Arabic typed as English: text fixed, layout switches Arabic → English | Passed |
| …Undo popup next to the caret; Undo restores text, focus and layout | Passed |
| Notepad (Windows 11, `RichEditD2DPT`): one press fixes the last word | Passed |
| Notepad: clicking Undo restores the text | Passed |
| Settings file selecting Arabic (102) and a custom shortcut: both are used | Passed |
| Settings file selecting Arabic (101): it is used | Passed |

With the engine driving a real control in another process (no key presses):

| Scenario | Control | Result |
|---|---|---|
| Whole field, then undo | Edit | Passed |
| Last word, trailing spaces, right-to-left context | Edit | Passed |
| Exact selection; undo refused after an edit | Edit | Passed |
| UTF-16 offsets after an emoji | Edit | Passed |
| Arabic typed instead of English | Edit | Passed |
| Nothing before the caret: refused, unchanged | Edit | Passed |
| Last word on the second line | Multi-line Edit | Passed |
| Whole field keeps line breaks | Multi-line Edit | Passed |
| Password field: refused as secure, never read | Password Edit | Passed |
| Read-only field: refused as unsupported | Read-only Edit | Passed |
| Last word | Rich edit, single line | Passed |
| Arabic (101) selected: variant-specific key | Edit | Passed |
| Arabic (102) selected: variant-specific key | Edit | Passed |
| Multi-line content reached through UI Automation: refused, text untouched | Rich edit, multi-line | Passed |

Package: `Baddel-0.1.0-windows-x64.zip` was built on that machine, extracted,
every hash in `SHA256SUMS.txt` and the ZIP's own `.sha256` verified, the
version and copyright resource checked, and `Baddel.exe --self-check` run.

### GitHub-hosted Windows runner

The `windows-app` CI job builds the same package on GitHub-hosted
`windows-latest` and runs the same tool against it. That runner has only an
English layout, so **layout switching is not exercised there**; the tool says
so in its output. Its result for each run is in the job log and in the
`windows-desktop-check-results` artifact. A hosted runner's desktop is not a
person's desktop: treat it as a regression check, not as proof of interactive
behaviour.

## Linux prototype checks

Environment: **Ubuntu 24.04 on a GitHub-hosted runner; an X11 session under
Xvfb with the openbox window manager; a GTK 3 text entry; English and Arabic
configured as XKB groups.** The binary under test is the one extracted from
the packaged `tar.gz`. Script: `linux/scripts/x11-smoke.sh`. This is the only
Linux environment anything has been run in. It is a CI session, not a person's
desktop, and it is not Wayland.

| Scenario | Result |
|---|---|
| App starts with an X11 key grab | Passed |
| One press fixes only the last word | Passed |
| Two presses 120 ms apart fix the whole field once | Passed |
| Exact selection only | Passed |
| Character offsets after an emoji | Passed |
| One / two `baddel --trigger` calls (desktop-bound shortcut path) | Passed |
| Password entry: refused as secure, unchanged | Passed |
| Read-only entry: refused as unsupported, unchanged | Passed |
| Nothing before the caret: nothing changes | Passed |
| Arabic typed as English: fixed, XKB group switches to English | Passed |
| Clicking the Undo window restores text and Arabic group; the entry keeps focus | Passed |
| English typed as Arabic: fixed, group switches to Arabic; `baddel --undo` restores both | Passed |
| Undo refused after the text was edited | Passed |
| `ara` and `ara(digits)` are read as separate tables | Passed |
| Configured Arabic variant is loaded and used for conversion | Passed |
| With two Arabic groups, switching selects the group with the exact variant | Passed |
| Configured variant not among the session's groups: text fixed, layout left alone | Passed |
| Variant not configured: the session's variant is used | Passed |
| Configured Latin variant is loaded | Passed |
| Socket is in the private runtime directory when there is one | Passed |
| Without it, the per-user fallback is created as a real directory with mode 700, and the trigger works through it | Passed |
| A non-private runtime directory is not used | Passed |
| World-writable fallback directory: refused, app does not start a channel, no socket created | Passed |
| Symbolic link at the fallback path: refused, client refuses to send, nothing created behind it | Passed |

The result of each run is in the `linux-x11-smoke-results` artifact of the
`linux` CI job.

Not verified on Linux: any real desktop session (GNOME, KDE Plasma or others);
any Wayland session, including the trigger path there; Qt, browsers, Electron,
LibreOffice, terminals and multi-line text views; other distributions; ARM.

## Not verified

- **Other applications**, on both platforms: browsers, Electron apps, Microsoft
  Office, terminals, and other custom text surfaces. Baddel refuses fields it
  cannot read and verify, but which apps work has not been established.
- **Multi-line text reached only through UI Automation** on Windows is refused
  in this release (see the last row above). It needs the paste fallback.
- **The paste fallback** on both platforms: implemented with clipboard
  preservation and a focus check immediately before pasting, off by default,
  and not exercised end to end.
- **The settings windows as a person uses them** (recording a shortcut by
  pressing keys, changing options with the mouse). Settings were verified by
  starting the app with the corresponding stored values.
- **The macOS permission window on a Mac without Accessibility access**, and a
  real password field on macOS (covered by unit tests with a simulated field).
- **Windows on ARM**, Windows 10, and elevated (administrator) target windows.
- **Gatekeeper and SmartScreen prompts** on a machine that downloaded the ZIP
  from the internet.
