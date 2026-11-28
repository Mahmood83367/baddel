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

## Install, start at login, remove

Baddel runs straight from the unpacked archive. Installing it is optional and
comes in two forms.

**Debian, Ubuntu and derivatives** (the one validated here, on Ubuntu 24.04):

```bash
sudo apt install ./baddel_<version>_amd64.deb
sudo apt remove baddel
```

The package installs `/opt/baddel`, a `/usr/bin/baddel` link, a menu entry and
an icon. It has no installation scripts: nothing is started, nothing runs as
root, and upgrading replaces the program only. Build it with
`linux/scripts/package-deb.sh` after `package-release.sh`.

**Any distribution, for one user, without root** (the portable route):

```bash
./install.sh                              # from the unpacked archive
~/.local/opt/baddel/uninstall.sh          # add --purge to remove the settings too
```

`install.sh` copies the folder to `~/.local/opt/baddel`, links
`~/.local/bin/baddel` and adds a menu entry under `~/.local/share`. Running a
newer archive's `install.sh` upgrades. It refuses a `~/.local/opt/baddel` it
did not create. For RPM-based and other distributions this is the supported
route for now; a package for them would be a thin wrapper around the same
layout as the `.deb`, and has not been built or tested.

**Start at login** is off until you turn it on:

```bash
baddel --autostart enable      # or: disable, status
```

It writes one file, `~/.config/autostart/app.baddel.Baddel.desktop`, the
standard per-user autostart entry that GNOME, KDE Plasma, Xfce and others run
at login, on X11 and on Wayland. Baddel only replaces or removes a file it
wrote itself. The entry names the program with `TryExec`, so if Baddel has
been removed the desktop skips it. On Wayland Baddel starts but still needs a
desktop shortcut bound to `baddel --trigger`.

Settings (`~/.config/baddel/settings.json`) and the autostart entry belong to
the user and are never touched by installing, upgrading or removing; the
per-user `uninstall.sh` turns Start at login off, the package cannot (run
`baddel --autostart disable` before `apt remove` if you want the file gone).

## Which fields work, and how to find out why one does not

Baddel edits text through the accessibility bus (AT-SPI).

- **GTK 3 and GTK 4** applications answer on it by themselves. Both are tested,
  single-line and multi-line.
- **Qt and KDE** applications register on it only while the desktop's
  accessibility switch (`org.a11y.Status IsEnabled`, the one screen readers
  set) is on. Baddel turns it on when it starts, if it is off, and never turns
  it off, because another assistive tool may rely on it by then; it lasts
  until you log out. `"EnableDesktopAccessibility": false` in the settings
  keeps Baddel from touching it. Qt fields themselves are **not verified**: in
  the test environment a Qt application did not appear on the bus even with
  the switch on.
- **Browsers and Electron apps** need their own accessibility option and are
  not tested. **Terminals** are not text fields; use the
  [shell integration](../docs/TERMINAL.md).

When a press does nothing, the log line Baddel prints says why, in codes:
`reason=NoFocusedField detail=[applications=0 …]` (nothing on the bus answered),
`reason=UnsupportedField detail=[role=… unsupported=noEditableTextInterface]`
and so on. To look at one field:

```bash
baddel --focus-report 3     # click into the field during the three seconds
```

It lists the applications on the bus, their toolkit, and each focused element
with its role and whether Baddel can edit it. It never reads text.

There is no clipboard or paste path in the Linux build: text is written only
through the accessibility interface, and a field that does not accept that is
refused.

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

## In a terminal

Two opt-in integrations work without the desktop parts (no X11 session, no
accessibility bus): `shell/baddel.bash` for the Bash command line, and
`baddel --fix-draft` as Claude Code's external editor. They need
`libxkbcommon0` and `xkb-data` for the key tables. Usage, shortcuts and limits
are in the [terminal guide](../docs/TERMINAL.md).

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

All of it automated, on **Ubuntu 24.04 GitHub-hosted runners**, with the binary
extracted from the packaged archive. Results are in
[docs/TESTING.md](../docs/TESTING.md).

- X11 under Xvfb with openbox, GTK 3 entry: the shortcut, Undo, layout
  switching (`linux/scripts/x11-smoke.sh`).
- Exact text, byte for byte, in GTK 3 and GTK 4 entries and text views, with
  failed writes (`linux/scripts/text-fidelity-check.sh`).
- The shortcut in xterm, xfce4-terminal and GNOME Terminal windows
  (`linux/scripts/terminal-window-check.sh`).
- The Debian package and the per-user installer: install, Start at login, a
  login-style start, upgrade, removal (`linux/scripts/install-check.sh`).

Not tested: any real desktop session (GNOME, KDE Plasma or any other) and a
real login; Qt and KDE applications; browsers, Electron apps and LibreOffice;
other distributions and package formats; ARM. A Wayland run is attempted in CI
with a headless compositor and recorded as information only.
