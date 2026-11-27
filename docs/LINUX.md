# Linux desktop version — plan (not implemented)

Baddel for Linux will be its own independently runnable app. It is planned as a
separate pull request after the 0.1.0 release. This document fixes the approach
and the constraints.

## Requirements

The same behaviour as macOS and Windows: a configurable shortcut; one press
fixes the selection or the last word; two presses within the window fix the
whole focused field; the layout is switched after a verified edit; a guarded
Undo is offered near the field without taking focus; secure and unsupported
fields are refused untouched; nothing is logged.

Two hard limits:

- **No privileged key capture.** No reading of `/dev/input`, no `uinput`
  device, no root helper, no membership in the `input` group.
- **No weakening of display security.** No disabling of Wayland isolation, no
  compositor-specific back doors, no X11 access-control changes.

## Reuse

- `windows/src/Baddel.Core` is plain .NET 8 with no Windows dependency. It will
  move to a neutral location (for example `core/dotnet/Baddel.Core`) and be
  referenced by both the Windows and the Linux app, with the shared fixtures
  running on Linux in CI.
- `shared/layouts` gains Linux layout data generated from the system's own XKB
  definitions (`us`, `ara`, `ara(...)` variants) through `libxkbcommon`, never
  copied from another platform's table.
- The engine's three interfaces (`IEditableField`, `IFocusProvider`,
  `ILayoutSwitcher`) are the whole platform boundary, as on Windows.

## Text access: AT-SPI

AT-SPI 2 over D-Bus is the Linux accessibility API and works the same under X11
and Wayland.

| Need | AT-SPI |
|---|---|
| Focused element | focus events / `GetActiveDescendant`, cached on `object:state-changed:focused` |
| Is it secure | role `PASSWORD_TEXT` → refused, never read |
| Is it editable text | `Text` and `EditableText` interfaces, state `EDITABLE` |
| Read text, caret, selection | `Text.GetText`, `CaretOffset`, `GetSelection` |
| Guarded write | re-read and compare with the planned snapshot, then `EditableText.DeleteText` + `InsertText` on the exact range, then re-read and verify |
| Popup position | `Text.GetCharacterExtents` / `GetRangeExtents`, falling back to the component extents |

AT-SPI text offsets are in **characters (code points)**, not UTF-16 units. The
Linux field implementation converts at its boundary and refuses ranges that do
not map cleanly; the core keeps working in UTF-16 so the fixtures stay shared.

Undo follows the existing rule: it runs only if the same accessible object is
still focused and still holds exactly the post-edit text.

Known constraint to verify rather than assume: toolkits differ in how much of
`EditableText` they implement (GTK and Qt are good; Chromium and Electron need
accessibility switched on by the user; some terminals expose nothing). Anything
that cannot be read and verified is refused.

## The shortcut

| Session | Mechanism | Notes |
|---|---|---|
| X11 | `XGrabKey` on the root window for the one configured combination | Standard, unprivileged; delivers only that combination. Auto-repeat is filtered so a held key is one press. |
| Wayland, portal available | `org.freedesktop.portal.GlobalShortcuts` | The desktop shows its own dialog and the user approves and can rebind the shortcut. Activated/Deactivated signals give distinct presses. |
| Wayland, no portal | An explicit desktop-bound shortcut | The user binds a key in their desktop's keyboard settings to `baddel --trigger`, which signals the running app over a session D-Bus name. |

The single/double decision stays in the shared `DoublePressDetector`; each
mechanism only has to report distinct presses.

## Layout switching

There is no cross-desktop API. Per desktop, using each one's documented
interface (for example the input-sources settings on GNOME, the keyboard
layout D-Bus interface on KDE Plasma, IBus or Fcitx5 engines where those manage
layouts). Only layouts the user already configured are selected. Where a
desktop offers no supported way, Baddel corrects the text and reports that the
layout was not switched — it does not simulate key presses to force it.

## Undo popup

A small window that does not take focus. Under X11 an override-redirect or
`_NET_WM_WINDOW_TYPE_NOTIFICATION` window can be placed at the caret. Under
Wayland a client cannot position its own top-level, so the plan is the
layer-shell protocol where the compositor supports it, and a desktop
notification with an Undo action otherwise. The fallback is recorded per
desktop in the testing page.

## Packaging and support claims

- A self-contained build for x64 first (tarball; a Flatpak afterwards, since
  the GlobalShortcuts portal is designed for sandboxed apps).
- The app states at start which mechanisms it found (session type, portal,
  AT-SPI bus) and what it therefore can and cannot do.
- **Support is claimed only for combinations that were actually tested**, named
  precisely: distribution and version, desktop and version, X11 or Wayland.
  The first targets are Ubuntu LTS with GNOME on Wayland and on X11. Everything
  else is "untested" until someone runs the checks there.

## Testing

A check tool equivalent to `baddel-wincheck`: a throwaway GTK window with a
text field, the engine driven through AT-SPI, then the running app triggered
through the session's real shortcut mechanism, with the results recorded in
[TESTING.md](TESTING.md). CI can run the core fixtures and AT-SPI checks under
a headless session; real-desktop behaviour is recorded separately and never
inferred from CI.
