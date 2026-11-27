#!/bin/bash
# Builds the Linux x64 prototype download from the current source tree:
#
#   dist/Baddel-<version>-linux-x64-prototype.tar.gz
#   dist/Baddel-<version>-linux-x64-prototype.tar.gz.sha256
#
# The archive holds one folder with the self-contained `baddel` binary,
# the opt-in Bash integration (shell/baddel.bash), LICENSE, README.txt and
# SHA256SUMS.txt. Needs the .NET 8 SDK.
#
# BADDEL_RID=linux-arm64 builds for another architecture, for local checks only;
# the published download is x64.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(tr -d '[:space:]' < VERSION)
RID="${BADDEL_RID:-linux-x64}"
NAME="Baddel-$VERSION-$RID-prototype"
STAGE="dist/$NAME"

rm -rf "$STAGE" "dist/$NAME.tar.gz" "dist/$NAME.tar.gz.sha256" dist/linux-publish
mkdir -p "$STAGE"
dotnet publish linux/src/Baddel.Linux/Baddel.Linux.csproj -c Release -r "$RID" --self-contained true \
  -p:PublishSingleFile=true -p:DebugType=none -o dist/linux-publish --nologo -v q
cp dist/linux-publish/baddel "$STAGE/baddel"
chmod 755 "$STAGE/baddel"
rm -rf dist/linux-publish
mkdir -p "$STAGE/shell"
cp shared/shell/baddel.bash "$STAGE/shell/baddel.bash"
cp LICENSE "$STAGE/LICENSE"

cat > "$STAGE/README.txt" <<TXT
Baddel $VERSION for Linux (x64) - PROTOTYPE
Copyright (c) 2026 Mahmood. Released under the MIT License (see LICENSE).
https://github.com/Mahmood83367/baddel

This is a prototype, not a supported release. Read "What was tested" before
relying on it.

Prerequisites
  - 64-bit x86 Linux with glibc. .NET does not need to be installed.
  - An X11 session for the built-in shortcut and the Undo popup.
  - These libraries and tools (Debian/Ubuntu package names):
      libx11-6  libxkbcommon0  xkb-data  libatspi2.0-0  at-spi2-core
      x11-xkb-utils (for setxkbmap, used to read the session's layouts)
  - Accessibility (AT-SPI) enabled in your desktop, and applications that
    expose editable text through it.
  - For layout switching: the English and Arabic layouts configured as XKB
    groups of the session, for example:  setxkbmap -layout us,ara

Run
  ./baddel               run in the foreground (Ctrl+C or: ./baddel --quit)
  ./baddel --self-check  report what this session supports
  ./baddel --help

Use
  Shortcut (default Ctrl+Alt+space, set in settings.json):
    once   fixes the selected text, or the last word before the caret
    twice  fixes the whole focused field
  On X11 a small "click to Undo" window appears next to the text.
  ./baddel --undo undoes the last correction from a terminal or a key binding.

  On Wayland the app cannot grab keys or place its own window. Bind a key in
  your desktop's keyboard settings to:  /path/to/baddel --trigger
  and, if you want, another to:         /path/to/baddel --undo

In a terminal  (opt-in; works without the desktop parts above)
  Bash command line: add this line to ~/.bashrc, with the folder you unpacked:
    source /path/to/shell/baddel.bash
  Ctrl+T once fixes the last word before the cursor, twice quickly the whole
  command line. Ctrl+_ undoes (twice after a double press). Nothing is run for
  you. Needs Bash 4.0 or later and libxkbcommon0 with xkb-data.
  Claude Code composer: start Claude Code with
    VISUAL="/path/to/baddel --fix-draft" claude
  and press Ctrl+G to fix the whole unsent draft; Ctrl+_ undoes. Nothing is
  sent for you.
  Baddel does not switch the keyboard layout in a terminal.

Settings  (~/.config/baddel/settings.json, all optional)
  {
    "Shortcut": "Ctrl+Alt+space",
    "LatinXkbLayout": "us",   "LatinXkbVariant": null,
    "ArabicXkbLayout": "ara", "ArabicXkbVariant": null,
    "DoublePressMs": 300,
    "SwitchLayout": true
  }
  A variant of null means "use the variant of this session's group with that
  layout"; "" means the layout's default variant; any other value, such as
  "digits", is that exact variant. The key tables are read from the XKB data
  installed on this computer.

What was tested
  Only this: Ubuntu 24.04 on a GitHub-hosted runner, in an X11 session under
  Xvfb with the openbox window manager, against a GTK 3 text entry.
  Not tested: any real desktop (GNOME, KDE Plasma, others), any Wayland
  session, the trigger path on Wayland, other toolkits and applications
  (Qt, browsers, Electron, LibreOffice, terminals), and other distributions.

Privacy and safety
  Baddel grabs only its one shortcut combination. It reads no input devices,
  needs no root, and changes no display security setting. Password fields are
  skipped. Nothing is sent anywhere and no text is logged.

Verify this download
  sha256sum -c SHA256SUMS.txt      (run inside this folder)

Redistribution
  Copies and forks that redistribute Baddel must keep the copyright notice
  and the license notice in LICENSE.
TXT

(cd "$STAGE" && sha256sum baddel shell/baddel.bash LICENSE README.txt > SHA256SUMS.txt)
tar -C dist --owner=0 --group=0 -czf "dist/$NAME.tar.gz" "$NAME"
rm -rf "$STAGE"
(cd dist && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
echo "Created dist/$NAME.tar.gz"
cat "dist/$NAME.tar.gz.sha256"
