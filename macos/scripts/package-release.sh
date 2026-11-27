#!/bin/bash
# Builds the macOS download from the current source tree:
#
#   dist/Baddel-<version>-macos-universal.zip
#   dist/Baddel-<version>-macos-universal.zip.sha256
#
# The ZIP holds one folder with Baddel.app, LICENSE, README.txt and
# SHA256SUMS.txt (hashes of the files in that folder and of the app's
# executable).
#
# Signing and notarization are opt-in and use only credentials you already
# have; nothing is requested, created or bypassed:
#   BADDEL_SIGN_IDENTITY   Developer ID Application identity to sign with
#   BADDEL_NOTARY_PROFILE  notarytool keychain profile; when set (and signed),
#                          the app is submitted to Apple and the ticket stapled
# Without them the app is ad-hoc signed and not notarized, and README.txt in
# the ZIP says so.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < ../VERSION)
NAME="Baddel-$VERSION-macos-universal"
DIST="$(cd .. && pwd)/dist"
STAGE="$DIST/$NAME"

UNIVERSAL=1 ./scripts/build-app.sh
rm -rf "$STAGE" "$DIST/$NAME.zip" "$DIST/$NAME.zip.sha256"
mkdir -p "$STAGE"
cp -R build/Baddel.app "$STAGE/Baddel.app"
cp ../LICENSE "$STAGE/LICENSE"

SIGNING="ad-hoc signed (no developer identity) and not notarized"
if [ -n "${BADDEL_SIGN_IDENTITY:-}" ]; then
  SIGNING="signed with a Developer ID and not notarized"
  if [ -n "${BADDEL_NOTARY_PROFILE:-}" ]; then
    ditto -c -k --keepParent "$STAGE/Baddel.app" "$DIST/notarize.zip"
    xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$BADDEL_NOTARY_PROFILE" --wait
    rm -f "$DIST/notarize.zip"
    xcrun stapler staple "$STAGE/Baddel.app"
    SIGNING="signed with a Developer ID and notarized by Apple"
  fi
fi

cat > "$STAGE/README.txt" <<TXT
Baddel $VERSION for macOS
Copyright (c) 2026 Mahmood. Released under the MIT License (see LICENSE).
https://github.com/Mahmood83367/baddel

Requirements: macOS 13 or later, Apple silicon or Intel.

This build is $SIGNING.

Install
  1. Move Baddel.app to your Applications folder and open it. Keep one copy,
     in Applications. It appears as a keyboard icon in the menu bar.
  2. If macOS refuses to open it because it cannot check the developer, that
     is Gatekeeper doing its job for software that is not notarized. Only if
     you trust this download: open System Settings > Privacy & Security, find
     the message about Baddel and choose "Open Anyway". Baddel never changes
     this setting for you.
  3. Baddel asks for Accessibility access, which it needs to read and replace
     text in other apps. Enable it yourself in System Settings > Privacy &
     Security > Accessibility.
  4. Upgrading from an earlier preview: if Baddel is already listed and
     switched on there but its window still says access is not granted, click
     "Remove Old Entry..." in that window, then turn Baddel on again. Delete
     old copies kept outside Applications.

Open at login (optional, off by default)
  Menu bar icon > Settings > "Open Baddel at login". Turn it off in the same
  place or in System Settings > General > Login Items.

Uninstall
  Turn off "Open Baddel at login", quit Baddel, and move it to the Trash.
  Settings:  defaults delete app.baddel.Baddel
  Stored data: ~/Library/Application Support/Baddel

Use
  Shortcut (default Option-Shift-Space):
    once   fixes the selected text, or the last word before the caret
    twice  fixes the whole focused field
  An Undo button appears next to the text for a few seconds.

In a terminal  (opt-in)
  zsh command line: add this line to ~/.zshrc, then open a new terminal:
    source /Applications/Baddel.app/Contents/Resources/shell/baddel.zsh
  Ctrl+T once fixes the selected text or the last word before the cursor,
  twice quickly the whole command line. Ctrl+_ undoes. Nothing is run for you.
  Claude Code message box: set VISUAL for Claude Code to
    /Applications/Baddel.app/Contents/MacOS/Baddel --fix-draft
  and press Ctrl+G to fix the whole unsent draft; Ctrl+_ undoes. Nothing is
  sent for you.
  Baddel does not switch the keyboard layout in a terminal.
  Settings and About are in the keyboard icon in the menu bar.

Verify this download
  shasum -a 256 -c SHA256SUMS.txt      (run inside this folder)

Redistribution
  Copies and forks that redistribute Baddel must keep the copyright notice
  and the license notice in LICENSE.
TXT

(
  cd "$STAGE"
  shasum -a 256 LICENSE README.txt Baddel.app/Contents/MacOS/Baddel Baddel.app/Contents/Info.plist \
    Baddel.app/Contents/Resources/LICENSE Baddel.app/Contents/Resources/layouts/*.json > SHA256SUMS.txt
)
(cd "$DIST" && ditto -c -k --keepParent "$NAME" "$NAME.zip" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")
rm -rf "$STAGE"
echo "Created dist/$NAME.zip"
cat "$DIST/$NAME.zip.sha256"
