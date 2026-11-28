#!/bin/sh
# Installs Baddel for the current user only, from this unpacked folder. No root.
#
#   ./install.sh
#
# It copies this folder to   ~/.local/opt/baddel
# links the program at       ~/.local/bin/baddel
# and adds a menu entry at   ~/.local/share/applications/app.baddel.Baddel.desktop
#
# Running it again from a newer folder upgrades. Settings (~/.config/baddel) and
# Start at login are never touched. If any of the three places already holds
# something this installer did not put there, it stops before changing anything. Use ./uninstall.sh, or the copy it leaves in
# ~/.local/opt/baddel, to remove Baddel again.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TARGET="$HOME/.local/opt/baddel"
BIN="$HOME/.local/bin"
LINK="$BIN/baddel"
ENTRY="$DATA/applications/app.baddel.Baddel.desktop"
[ -x "$HERE/baddel" ] || { echo "install.sh must stay next to the baddel program." >&2; exit 1; }

# Everything this installer will write is checked first. Until all three
# destinations are known to be free or its own, nothing is written and nothing
# is run.
refuse() { echo "$1; nothing was changed." >&2; exit 1; }
exists() { [ -e "$1" ] || [ -L "$1" ]; }

# 1. The installation folder: absent, or a real folder carrying this installer's marker.
if exists "$TARGET"; then
  [ ! -L "$TARGET" ] && [ -d "$TARGET" ] && [ -f "$TARGET/.baddel-user-install" ] && [ ! -L "$TARGET/.baddel-user-install" ] \
    || refuse "$TARGET exists and was not created by this installer"
fi
# 2. The launcher: absent, or the link this installer made, pointing into that folder.
if exists "$LINK"; then
  [ -L "$LINK" ] && [ "$(readlink "$LINK")" = "$TARGET/baddel" ] \
    || refuse "$LINK exists and is not the link this installer made"
fi
# 3. The menu entry: absent, or a regular file carrying this installer's marker.
if exists "$ENTRY"; then
  [ ! -L "$ENTRY" ] && [ -f "$ENTRY" ] && grep -q '^X-Baddel-User-Install=true$' "$ENTRY" \
    || refuse "$ENTRY exists and was not written by this installer"
fi
# The folders the three live in must be folders, if they exist at all.
for folder in "$HOME/.local/opt" "$BIN" "$DATA/applications"; do
  if exists "$folder" && [ ! -d "$folder" ]; then refuse "$folder is not a folder"; fi
done

# Only a Baddel this installer put there, inside its own folder, is ever run.
if [ -f "$TARGET/.baddel-user-install" ] && [ -f "$TARGET/baddel" ] && [ ! -L "$TARGET/baddel" ] && [ -x "$TARGET/baddel" ]; then
  "$TARGET/baddel" --quit >/dev/null 2>&1 || true
fi

mkdir -p "$TARGET" "$BIN" "$DATA/applications"
rm -rf "$TARGET/shell"
cp "$HERE/baddel" "$TARGET/baddel.new" && mv -f "$TARGET/baddel.new" "$TARGET/baddel"
cp -r "$HERE/shell" "$TARGET/shell"
for file in LICENSE README.txt uninstall.sh; do cp "$HERE/$file" "$TARGET/$file"; done
chmod 755 "$TARGET/baddel" "$TARGET/uninstall.sh"
: > "$TARGET/.baddel-user-install"
# The link was checked above to be absent or this installer's own.
rm -f "$LINK"
ln -s "$TARGET/baddel" "$LINK"
cat > "$ENTRY.new" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Baddel
GenericName=Keyboard layout correction
Comment=Fix text typed with the wrong keyboard layout
Exec="$TARGET/baddel"
TryExec=$TARGET/baddel
Terminal=false
Categories=Utility;Accessibility;
X-Baddel-User-Install=true
DESKTOP
mv -f "$ENTRY.new" "$ENTRY"

echo "Baddel $("$TARGET/baddel" --version | head -1 | cut -d' ' -f2) is installed in $TARGET."
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not on your PATH; run $LINK, or add it to PATH." ;; esac
echo "Start it:              $LINK"
echo "Start it at login:     $LINK --autostart enable"
echo "Remove it:             $TARGET/uninstall.sh"
