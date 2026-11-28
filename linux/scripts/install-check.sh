#!/bin/bash
# Checks installing, upgrading, Start at login and removing Baddel on a throwaway
# Debian or Ubuntu machine (a CI runner). It installs and removes a system
# package with sudo, so do not run it on a computer you use.
#
#   linux/scripts/install-check.sh <deb> <newer deb for the upgrade> <tarball>
#
# Home, settings and autostart folders are throwaway directories throughout.
# For the login step it needs an X11 session with a session D-Bus:
#   dbus-run-session -- xvfb-run -a linux/scripts/install-check.sh …
set -u
DEB=$(realpath "$1"); NEWER=$(realpath "$2"); TARBALL=$(realpath "$3")
WORK=$(mktemp -d)
RESULTS="${RESULTS_FILE:-$WORK/results.txt}"
failures=0
: > "$RESULTS"
say() { echo "$1" | tee -a "$RESULTS"; }
check() { if [ "$2" = "$3" ]; then say "PASS $1"; else say "FAIL $1 [expected: $3] [actual: $2]"; failures=$((failures + 1)); fi; }
yes_no() { if "$@" >/dev/null 2>&1; then echo yes; else echo no; fi; }
trap 'baddel --quit >/dev/null 2>&1; sudo apt-get remove -y -qq baddel >/dev/null 2>&1; rm -rf "$WORK"' EXIT

export HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/home/.config" XDG_DATA_HOME="$WORK/home/.local/share"
mkdir -p "$XDG_CONFIG_HOME/baddel"
unset BADDEL_SETTINGS_DIR
VERSION=$(dpkg-deb -f "$DEB" Version); NEW_VERSION=$(dpkg-deb -f "$NEWER" Version)

say "-- Debian package --"
check "the package has no installation scripts" "$(dpkg-deb --ctrl-tarfile "$DEB" | tar -t | grep -cE 'preinst|postinst|prerm|postrm')" 0
check "it installs only under /opt/baddel, /usr/bin and /usr/share" \
  "$(dpkg-deb -c "$DEB" | awk '{print $6}' | grep -vE '^\./$|^\./(opt|usr)/$|^\./opt/baddel|^\./usr/(bin|share)/' | wc -l)" 0
check "baddel is not installed before the check" "$(yes_no dpkg -s baddel)" no
sudo apt-get install -y -qq "$DEB" >/dev/null 2>&1
check "clean install: the package is installed" "$(dpkg-query -W -f='${Status} ${Version}' baddel 2>/dev/null)" "install ok installed $VERSION"
check "clean install: baddel is on the PATH and runs" "$(baddel --version | head -1)" "Baddel ${VERSION%%~*} (Linux prototype)"
check "clean install: menu entry, icon and Bash integration are in place" \
  "$(yes_no test -f /usr/share/applications/app.baddel.Baddel.desktop)$(yes_no test -f /usr/share/icons/hicolor/256x256/apps/baddel.png)$(yes_no test -f /opt/baddel/shell/baddel.bash)" yesyesyes
check "the menu entry is valid" "$(desktop-file-validate /usr/share/applications/app.baddel.Baddel.desktop 2>&1 | grep -c error)" 0
check "installing started nothing" "$(pgrep -x baddel | wc -l)" 0
check "installing did not turn Start at login on" "$(baddel --autostart status | head -1)" "startAtLogin=off"
check "no system-wide autostart entry was installed" "$(ls /etc/xdg/autostart 2>/dev/null | grep -ci baddel)" 0

say "-- Start at login --"
AUTOSTART="$XDG_CONFIG_HOME/autostart/app.baddel.Baddel.desktop"
check "enable" "$(baddel --autostart enable | head -1)" "startAtLogin=on"
check "the entry is in the user's own autostart folder and points at the installed launcher" \
  "$(grep '^Exec=' "$AUTOSTART")" "Exec=/usr/bin/baddel"
check "the autostart entry is valid" "$(desktop-file-validate "$AUTOSTART" 2>&1 | grep -c error)" 0
check "disable removes it" "$(baddel --autostart disable | head -1; yes_no test -e "$AUTOSTART")" "startAtLogin=off
no"
mkdir -p "$(dirname "$AUTOSTART")"; printf '[Desktop Entry]\nType=Application\nName=Other\nExec=/usr/bin/true\n' > "$AUTOSTART"
cp "$AUTOSTART" "$WORK/foreign"
baddel --autostart enable >/dev/null; baddel --autostart disable >/dev/null
check "a file of the same name that Baddel did not write is neither replaced nor removed" "$(yes_no cmp -s "$AUTOSTART" "$WORK/foreign")" yes
rm -f "$AUTOSTART"
baddel --autostart enable >/dev/null

# What a desktop does at login: run the entries in the autostart folder.
if command -v dex >/dev/null && [ -n "${DISPLAY:-}" ]; then
  openbox >/dev/null 2>&1 & sleep 1; setxkbmap -layout us,ara
  check "the login step would run exactly this entry" "$(dex --autostart --dry-run --search-paths "$XDG_CONFIG_HOME/autostart" 2>&1 | grep -c '/usr/bin/baddel')" 1
  dex --autostart --search-paths "$XDG_CONFIG_HOME/autostart" >/dev/null 2>&1
  for _ in $(seq 1 50); do pgrep -x baddel >/dev/null && break; sleep 0.1; done
  sleep 1.5
  check "started the way a login starts it: Baddel is running" "$(yes_no pgrep -x baddel)" yes
  check "and it answers its own commands" "$(yes_no baddel --quit)" yes
  sleep 0.5
  check "it stops when asked" "$(yes_no pgrep -x baddel)" no
else
  say "SKIP the login step: needs dex and an X11 session"
fi

say "-- Upgrade --"
printf '{ "Shortcut": "Ctrl+Alt+b", "SwitchLayout": false }' > "$XDG_CONFIG_HOME/baddel/settings.json"
BEFORE=$(sha256sum "$XDG_CONFIG_HOME/baddel/settings.json" "$AUTOSTART" | sha256sum)
sudo apt-get install -y -qq "$NEWER" >/dev/null 2>&1
check "upgrade: the newer version is installed" "$(dpkg-query -W -f='${Version}' baddel)" "$NEW_VERSION"
check "upgrade: settings and the Start at login entry are untouched" "$(sha256sum "$XDG_CONFIG_HOME/baddel/settings.json" "$AUTOSTART" | sha256sum)" "$BEFORE"
check "upgrade: the settings are still read" "$(baddel --terminal-key status | head -1 | cut -d' ' -f2)" "Ctrl+Alt+b"
check "upgrade: Start at login is still on" "$(baddel --autostart status | head -1)" "startAtLogin=on"
check "upgrade started nothing" "$(pgrep -x baddel | wc -l)" 0

say "-- Removal --"
sudo apt-get remove -y -qq baddel >/dev/null 2>&1
check "removed: no package, no program, no /opt/baddel, no menu entry" \
  "$(yes_no dpkg -s baddel)$(yes_no test -e /usr/bin/baddel)$(yes_no test -e /opt/baddel)$(yes_no test -e /usr/share/applications/app.baddel.Baddel.desktop)" nononono
check "removed: the user's settings are kept" "$(yes_no test -f "$XDG_CONFIG_HOME/baddel/settings.json")" yes
if command -v dex >/dev/null; then
  check "removed: a leftover Start at login entry starts nothing (the desktop skips it)" \
    "$(dex --autostart --dry-run --search-paths "$XDG_CONFIG_HOME/autostart" 2>&1 | grep -c 'baddel')" 0
fi
rm -f "$AUTOSTART"

say "-- Per-user install from the archive (no root) --"
mkdir "$WORK/unpacked" && tar -xzf "$TARBALL" -C "$WORK/unpacked"
FOLDER=$(echo "$WORK"/unpacked/*)
(cd "$FOLDER" && sha256sum -c SHA256SUMS.txt >/dev/null 2>&1); check "the archive's checksums hold" "$?" 0
rm -f "$XDG_CONFIG_HOME/baddel/settings.json"
"$FOLDER/install.sh" > "$WORK/install.log" 2>&1
check "install.sh: installed for this user only" \
  "$(yes_no test -x "$HOME/.local/opt/baddel/baddel")$(yes_no test -L "$HOME/.local/bin/baddel")$(yes_no test -f "$XDG_DATA_HOME/applications/app.baddel.Baddel.desktop")" yesyesyes
check "install.sh: it runs" "$(yes_no "$HOME/.local/bin/baddel" --version)" yes
check "install.sh: did not turn Start at login on" "$("$HOME/.local/bin/baddel" --autostart status | head -1)" "startAtLogin=off"
"$HOME/.local/bin/baddel" --autostart enable >/dev/null
check "Start at login points at the per-user launcher" "$(grep '^Exec=' "$AUTOSTART")" "Exec=$HOME/.local/bin/baddel"
printf '{ "SwitchLayout": false }' > "$XDG_CONFIG_HOME/baddel/settings.json"
BEFORE=$(sha256sum "$XDG_CONFIG_HOME/baddel/settings.json" "$AUTOSTART" | sha256sum)
"$FOLDER/install.sh" >/dev/null 2>&1
check "install.sh again (upgrade): settings and Start at login are untouched" "$(sha256sum "$XDG_CONFIG_HOME/baddel/settings.json" "$AUTOSTART" | sha256sum)" "$BEFORE"
"$HOME/.local/opt/baddel/uninstall.sh" >/dev/null 2>&1
check "uninstall.sh: program, link, menu entry and Start at login are gone" \
  "$(yes_no test -e "$HOME/.local/opt/baddel")$(yes_no test -e "$HOME/.local/bin/baddel")$(yes_no test -e "$XDG_DATA_HOME/applications/app.baddel.Baddel.desktop")$(yes_no test -e "$AUTOSTART")" nononono
check "uninstall.sh: settings are kept" "$(yes_no test -f "$XDG_CONFIG_HOME/baddel/settings.json")" yes
mkdir -p "$HOME/.local/opt/baddel"; echo mine > "$HOME/.local/opt/baddel/notes.txt"
"$FOLDER/install.sh" >/dev/null 2>&1
check "install.sh refuses a folder it did not create, and leaves it alone" "$?$(cat "$HOME/.local/opt/baddel/notes.txt")" "1mine"

say "RESULT $([ "$failures" -eq 0 ] && echo pass || echo "fail ($failures)")"
exit "$failures"
