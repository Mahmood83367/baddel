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
# Start at login are never touched. Use ./uninstall.sh, or the copy it leaves in
# ~/.local/opt/baddel, to remove Baddel again.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
TARGET="$HOME/.local/opt/baddel"
BIN="$HOME/.local/bin"
[ -x "$HERE/baddel" ] || { echo "install.sh must stay next to the baddel program." >&2; exit 1; }
if [ -e "$TARGET" ] && [ ! -f "$TARGET/.baddel-user-install" ]; then
  echo "$TARGET exists and was not created by this installer; nothing was changed." >&2
  exit 1
fi

if [ -x "$BIN/baddel" ]; then "$BIN/baddel" --quit >/dev/null 2>&1 || true; fi
mkdir -p "$TARGET" "$BIN" "$DATA/applications"
rm -rf "$TARGET/shell"
cp "$HERE/baddel" "$TARGET/baddel.new" && mv -f "$TARGET/baddel.new" "$TARGET/baddel"
cp -r "$HERE/shell" "$TARGET/shell"
for file in LICENSE README.txt uninstall.sh; do cp "$HERE/$file" "$TARGET/$file"; done
chmod 755 "$TARGET/baddel" "$TARGET/uninstall.sh"
: > "$TARGET/.baddel-user-install"
ln -sfn "$TARGET/baddel" "$BIN/baddel"
cat > "$DATA/applications/app.baddel.Baddel.desktop" <<DESKTOP
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

echo "Baddel $("$TARGET/baddel" --version | head -1 | cut -d' ' -f2) is installed in $TARGET."
case ":$PATH:" in *":$BIN:"*) ;; *) echo "Note: $BIN is not on your PATH; run $BIN/baddel, or add it to PATH." ;; esac
echo "Start it:              $BIN/baddel"
echo "Start it at login:     $BIN/baddel --autostart enable"
echo "Remove it:             $TARGET/uninstall.sh"
