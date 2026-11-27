# Baddel for Linux — prototype

A .NET 8 app on the same C# core as the Windows app
(`windows/src/Baddel.Core`). **It is a prototype: it has been run only in CI,
in an X11 session, and on no real desktop.** See [What was tested](#what-was-tested).

| Part | How |
|---|---|
| Shortcut on X11 | A passive `XGrabKey` of one combination on the root window. X delivers only that combination. |
| Shortcut elsewhere | The desktop's own shortcut settings run `baddel --trigger`, which signals the running app over a private Unix socket. |
| Text | AT-SPI (`libatspi`): read text, caret and selection; write by deleting exactly the target range and inserting the replacement, after re-checking the planned snapshot; verify afterwards. |
| Layout tables | Read at start from this system's XKB data with `libxkbcommon`. Nothing is copied from another platform. |
| Layout switching | XKB group of the X11 session, matched by exact layout **and variant**. |
| Undo | On X11, a small override-redirect window next to the caret that never takes focus. Everywhere: `baddel --undo`. |

No privileged key capture: no `/dev/input`, no `uinput`, no root, no `input`
group. No display security setting is changed.

## Build, test, package

```bash
dotnet test windows/tests/Baddel.Core.Tests/Baddel.Core.Tests.csproj   # shared core, on Linux
dotnet test linux/tests/Baddel.Linux.Tests/Baddel.Linux.Tests.csproj
linux/scripts/package-release.sh
```

creates `dist/Baddel-<version>-linux-x64-prototype.tar.gz` and its `.sha256`.
The archive contains the self-contained `baddel` binary, `LICENSE`,
`README.txt` (prerequisites and usage) and `SHA256SUMS.txt`. CI uploads it as
the `baddel-linux-prototype` artifact.

## Prerequisites

64-bit x86 Linux with glibc; `libx11-6`, `libxkbcommon0`, `xkb-data`,
`libatspi2.0-0`, `at-spi2-core`, and `setxkbmap` (`x11-xkb-utils`);
accessibility enabled in the desktop. For layout switching, English and Arabic
configured as XKB groups of the session (`setxkbmap -layout us,ara`).

## Settings

`~/.config/baddel/settings.json`, all optional:

```json
{
  "Shortcut": "Ctrl+Alt+space",
  "LatinXkbLayout": "us",   "LatinXkbVariant": null,
  "ArabicXkbLayout": "ara", "ArabicXkbVariant": null,
  "DoublePressMs": 300,
  "SwitchLayout": true
}
```

Both sides have a manually selectable variant. `null` means "the variant of
this session's group with that layout", `""` means the layout's default
variant, and any other value (`"digits"`, `"dvorak"`, …) is that exact
variant. Layout switching selects the session group whose layout and variant
both match; if no group matches exactly, the text is corrected and the layout
is left alone rather than switched to a different variant.

## The trigger socket

`baddel --trigger`, `--undo` and `--quit` talk to the running app through a
Unix socket. It is created only in a directory no other user can enter:

1. `XDG_RUNTIME_DIR`, if it is a real directory with mode `0700`;
2. otherwise `/tmp/baddel-<uid>`, created with mode `0700`, which must be a
   real directory (not a symbolic link) with exactly that mode.

If neither holds — the fallback path is a symbolic link, or a directory with
any group or other permission — the app refuses to open the channel and exits,
and clients refuse to send. The socket is never placed directly in `/tmp`.

## Wayland

A Wayland client cannot grab keys or position its own window, and that is by
design. On Wayland the app does not try: it starts in trigger-only mode, the
shortcut is bound by the user in the desktop's keyboard settings to
`baddel --trigger`, there is no popup, and Undo is `baddel --undo`. Layout
switching is not implemented there (there is no cross-desktop API), so the
text is corrected and the layout is reported as not switched.

**None of this has been run in a Wayland session.** The trigger mechanism
itself is exercised in CI, under X11. The GlobalShortcuts portal, per-desktop
layout switching and a positioned Undo on Wayland are described in
[docs/LINUX.md](../docs/LINUX.md) and are not implemented.

## What was tested

One environment only: **Ubuntu 24.04 on a GitHub-hosted runner, X11 under Xvfb
with the openbox window manager, against a GTK 3 text entry**, using the binary
extracted from the packaged archive. Script: `linux/scripts/x11-smoke.sh`.
The scenarios and results are listed in [docs/TESTING.md](../docs/TESTING.md).

Not tested: any real desktop session (GNOME, KDE Plasma or any other), any
Wayland session, Qt and other toolkits, browsers, Electron apps, LibreOffice,
terminals, multi-line text views, other distributions, and ARM.
