# Roadmap

## Done — milestone 1: macOS prototype

- Shared layout data for US English, Arabic (macOS) and Arabic – PC, generated
  from the system layout tables.
- Platform-independent conversion, direction detection and planning, with
  shared fixtures.
- Configurable global shortcut; single press (selection or last word) and
  double press (whole field).
- Accessibility text-range edits with verification, safe rejection, layout
  switching and a guarded, non-activating Undo.
- Accessibility permission flow.

## Next for macOS

- Verify and tune behaviour in browsers, Electron apps and other non-native
  text fields; decide per app whether the paste fallback is needed.
- More layouts (Arabic – QWERTY, Arabic – AZERTY, other Latin layouts).
- Developer ID signing and notarization, so Accessibility access survives
  updates; launch at login.
- Arabic localisation of the interface.
- An optional word list to resolve the `لا` ambiguity on Arabic-PC.

## Windows correction

`windows/src/Baddel.Core` already ports the core logic and passes the shared
fixtures. Still to build, in C# on .NET:

- Global shortcut with `RegisterHotKey`, feeding the existing
  `DoublePressDetector`.
- Text access through UI Automation (`TextPattern` / `ValuePattern`),
  implementing the same field interface as macOS, with the same snapshot check
  before every write. Password fields (`IsPassword`) are skipped.
- Layout data for the Windows Arabic (101) and Arabic (102) layouts, added to
  `shared/layouts` with `"windows"` platform identifiers, and layout switching
  through the input-language APIs.
- A non-activating Undo popup and a tray icon with settings.

## Clipboard history (macOS)

A local, searchable history of copied text, images and files. The design is in
[CLIPBOARD_HISTORY.md](CLIPBOARD_HISTORY.md). It is not implemented.
