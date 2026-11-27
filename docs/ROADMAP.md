# Roadmap

## Released in 0.1.0 — correction on macOS and Windows

- Shared layout data generated from the operating systems' own tables: US
  English, Arabic (macOS), Arabic – PC, Arabic (101), Arabic (102).
- Platform-independent conversion, direction detection and planning, in Swift
  and C#, held to the same fixtures.
- macOS menu bar app and Windows notification-area app: configurable global
  shortcut, single press (selection or last word), double press (whole field),
  verified edits, layout switching, guarded non-activating Undo, safe refusal
  of secure and unsupported fields.
- Manual choice of the Arabic layout variant on both platforms.

What was and was not tested is in [TESTING.md](TESTING.md).

## Upcoming

### Clipboard history (macOS)

A local, searchable history of copied text, images and files, with file
references and an explicit pin that keeps a copy. Designed in
[CLIPBOARD_HISTORY.md](CLIPBOARD_HISTORY.md). **Not implemented; not part of
0.1.0.**

### Linux desktop version

Its own app on the shared C# core, using AT-SPI for text and the standard X11
and Wayland shortcut mechanisms. Plan and constraints in [LINUX.md](LINUX.md).
It will be developed in its own pull request, and support will be claimed only
for desktop environments it has actually been tested on.

### More keyboard layouts, with manual control

Today: one English layout (US) and two Arabic variants per platform, chosen
manually. Planned:

- An **English layout selector** next to the Arabic one. The first additions
  (UK English, for example) need the extra ISO key that the current 47-key
  table does not describe, so the data format gains that key first.
- **Detection of installed layouts**, offered as the default while keeping the
  manual choice.
- **User-entered custom mappings**, validated before use: every key present
  exactly once, no empty base output, and a round-trip check against the other
  layout, with a clear report of what is ambiguous.
- Every new layout is generated from the operating system's own table and
  tested on its own. Two layouts are never treated as identical because their
  names match.

### Updates

There is no updater in 0.1.0 and the app makes no network connections.
Planned, in this order:

1. **"Check for Updates…"**, a manual action that compares the running version
   with the latest official release published from `main`, and opens the
   release page. It downloads and installs nothing.
2. **Release and channel compatibility**: a small signed manifest per channel
   (stable first) stating version, minimum OS, and the package hashes, so an
   app only offers updates that fit it.
3. **Opt-in automatic installation**, off by default, shipped only when all of
   the following exist: a dedicated update signing key whose public half is
   compiled into the app; platform code signing (Developer ID with
   notarization, Authenticode) for the packages; and real update *and
   rollback* tests on each platform.

Rules that will not change: updates come only from official release assets
built from `main`; the signature and hash are verified before anything is
unpacked; unsigned or unverifiable update code is never executed; a failed
update leaves the installed version working.

### Smaller items

- macOS and Windows: verify and tune behaviour in browsers, Electron apps and
  office suites; decide per app whether the paste fallback is needed.
- Windows: multi-line fields that are reachable only through UI Automation;
  an installer and a "start with Windows" option; an ARM64 build.
- macOS: Developer ID signing with notarization; launch at login.
- Arabic localisation of the interface.
- An optional word list to resolve the `لا` ambiguity on Arabic-PC and
  Arabic (101).
