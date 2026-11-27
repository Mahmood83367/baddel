# Testing record for 0.1.0

This page records what was actually run, where, and what was not. "Passed"
means the check produced the expected text or the expected refusal; nothing
here is inferred.

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
