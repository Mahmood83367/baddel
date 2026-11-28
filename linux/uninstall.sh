#!/bin/sh
# Removes a Baddel that ./install.sh installed for the current user.
#
#   ~/.local/opt/baddel/uninstall.sh            keeps your settings
#   ~/.local/opt/baddel/uninstall.sh --purge    also removes ~/.config/baddel
#
# It stops Baddel, turns Start at login off, and removes only what install.sh
# created. Files it does not recognise as its own are left alone.
set -eu
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET="$HOME/.local/opt/baddel"
BIN="$HOME/.local/bin/baddel"
if [ -L "$TARGET" ] || [ ! -d "$TARGET" ] || [ ! -f "$TARGET/.baddel-user-install" ] || [ -L "$TARGET/.baddel-user-install" ]; then
  echo "No per-user Baddel installation was found in $TARGET; nothing was changed." >&2
  exit 1
fi

if [ -f "$TARGET/baddel" ] && [ ! -L "$TARGET/baddel" ] && [ -x "$TARGET/baddel" ]; then
  "$TARGET/baddel" --quit >/dev/null 2>&1 || true
  "$TARGET/baddel" --autostart disable >/dev/null 2>&1 || true
fi
if [ -L "$BIN" ] && [ "$(readlink "$BIN")" = "$TARGET/baddel" ]; then rm -f "$BIN"; fi
ENTRY="$DATA/applications/app.baddel.Baddel.desktop"
if [ ! -L "$ENTRY" ] && [ -f "$ENTRY" ] && grep -q '^X-Baddel-User-Install=true$' "$ENTRY"; then rm -f "$ENTRY"; fi
rm -rf "$TARGET"
rmdir "$HOME/.local/opt" 2>/dev/null || true

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$CONFIG/baddel"
  echo "Baddel and its settings were removed."
else
  echo "Baddel was removed. Your settings are still in $CONFIG/baddel (remove them with --purge next time, or delete that folder)."
fi
