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

## Added in 0.2.1

- A macOS installer package for `/Applications/Baddel.app`, published only
  when it is signed and notarized. See [MACOS.md](MACOS.md).
- Opt-in "Open Baddel at login" on macOS.
- "Remove Old Entry…" in the Accessibility window, for upgrades from the
  ad-hoc previews.
- The app icon on macOS and Windows.

## Added in 0.2.0

- A choice of English layout: Automatic / US / British on macOS, US / UK on
  Windows, each from the system's own table.
- Layout switching selects exactly the layout used for conversion, and leaves
  the keyboard alone when that layout is not installed.
- Custom layouts from a file, validated before use.
  See [LAYOUTS.md](LAYOUTS.md).
- Opt-in clipboard history on macOS: text, images and file references, search,
  and Keep File Copy. See [CLIPBOARD_HISTORY.md](CLIPBOARD_HISTORY.md).
- Check for Updates with stable and preview channels, and the verification
  half of signed updates. See [UPDATES.md](UPDATES.md).
- A rule and a CI check that every published version is new and higher.

## Upcoming

### Linux desktop version

A prototype is in [`linux/`](../linux/README.md): X11 shortcut, AT-SPI text
access, layout tables from the system's XKB data with manual variants, XKB
group switching, an Undo window, and a private trigger socket for desktops
where the shortcut is bound by the desktop. It passes a smoke test in an X11
CI session and has not been run on a real desktop or under Wayland.

Next, in order: run and fix it on real Ubuntu GNOME sessions (X11 and
Wayland); the Wayland GlobalShortcuts portal; layout switching through each
desktop's own interface; an Undo that can be positioned on Wayland; packaging
beyond a tarball. Support will be claimed only for desktop environments it has
actually been tested on. Design: [LINUX.md](LINUX.md).

### Keyboard layouts

- The extra key of ISO keyboards, which UK and many European layouts need for
  `\` and `|`; the table format gains that key first.
- More layouts, each generated from the operating system's own table and
  tested on its own.
- On Windows, an "Automatic" choice that follows the installed layouts, as
  macOS has.
- A way to import and check a custom layout from Settings, instead of placing
  a file by hand.

### Updates

Today: a manual check, an opt-in daily check, two channels, and tested
verification of signed manifests with no trusted key configured, so nothing
can be installed. Remaining, in order: an update signing key; platform code
signing (Developer ID with notarization, Authenticode); signed manifests
attached to releases; an installer with staging and rollback per platform;
real update and rollback tests. Automatic installation stays opt-in and is not
shipped before all of that exists. See [UPDATES.md](UPDATES.md).

### Clipboard history

Excluding apps, bookmarks so file references survive moves, a configurable
shortcut and limits, and versions for Windows and Linux.
See [CLIPBOARD_HISTORY.md](CLIPBOARD_HISTORY.md).

### Smaller items

- macOS and Windows: verify and tune behaviour in browsers, Electron apps and
  office suites; decide per app whether the paste fallback is needed.
- Windows: multi-line fields that are reachable only through UI Automation;
  an installer and a "start with Windows" option; an ARM64 build.
- macOS: the signed, notarized installer. A Developer ID Application identity exists; a Developer ID Installer identity and a notarization profile are still needed.
- Arabic localisation of the interface.
- An optional word list to resolve the `لا` ambiguity on Arabic-PC and
  Arabic (101).
