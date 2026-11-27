#!/bin/bash
# Installs the package for real and checks the result. It changes
# /Applications, the package receipts and login items, so it is meant for a
# THROWAWAY machine (CI). It refuses to run anywhere else unless
# BADDEL_ALLOW_INSTALL_CHECK=1 is set.
#
#   macos/scripts/pkg-install-check.sh <package.pkg> [results file]
set -u
PKG=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
RESULTS=${2:-/dev/null}
if [ "${CI:-}" != "true" ] && [ "${BADDEL_ALLOW_INSTALL_CHECK:-}" != "1" ]; then
  echo "Refusing to install on a machine that is not CI. Set BADDEL_ALLOW_INSTALL_CHECK=1 to override."; exit 2
fi
APP=/Applications/Baddel.app
BIN=$APP/Contents/MacOS/Baddel
VERSION=$(tr -d '[:space:]' < "$(dirname "$0")/../../VERSION")
RELEASES=https://github.com/Mahmood83367/baddel/releases/download
WORK=$(mktemp -d)
failures=0
: > "$RESULTS" 2>/dev/null || true

say() { echo "$1" | tee -a "$RESULTS"; }
check() { if [ "$2" = "true" ]; then say "PASS $1${3:+ [$3]}"; else say "FAIL $1${3:+ [$3]}"; failures=$((failures + 1)); fi; }
yes_no() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }
version_of() { /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null; }
cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }
install_pkg() { sudo installer -pkg "$PKG" -target / >/dev/null 2>&1; }
remove_all() {
  pkill -x Baddel 2>/dev/null; sleep 0.5
  sudo rm -rf "$APP"; sudo pkgutil --forget app.baddel.Baddel.pkg >/dev/null 2>&1
}
old_preview() {  # version -> path of an extracted Baddel.app from that published release
  local v=$1 dir="$WORK/old-$1"
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    curl -sSL -o "$dir/a.zip" "$RELEASES/v$v/Baddel-$v-macos-universal.zip" || return 1
    curl -sSL -o "$dir/a.zip.sha256" "$RELEASES/v$v/Baddel-$v-macos-universal.zip.sha256" || return 1
    [ "$(shasum -a 256 "$dir/a.zip" | cut -d' ' -f1)" = "$(cut -d' ' -f1 "$dir/a.zip.sha256")" ] || return 1
    ditto -x -k "$dir/a.zip" "$dir" || return 1
  fi
  echo "$dir/Baddel-$v-macos-universal/Baddel.app"
}

say "machine: macOS $(sw_vers -productVersion) $(uname -m); package: $(basename "$PKG")"
say "package signature: $(pkgutil --check-signature "$PKG" 2>&1 | sed -n 's/^ *Status: //p' | head -1)"
pkgutil --expand "$PKG" "$WORK/expanded"
check "Installer is told to close Baddel by bundle identifier" "$(grep -q '<app id="app.baddel.Baddel"/>' "$WORK/expanded/Distribution" && grep -q '<must-close>' "$WORK/expanded/Distribution" && echo true || echo false)"
check "the package contains no scripts" "$([ ! -e "$WORK/expanded/component.pkg/Scripts" ] && ! grep -q -E '<(pre|post)install' "$WORK/expanded/component.pkg/PackageInfo" && echo true || echo false)"

say "-- fresh install --"
remove_all
check "nothing installed before" "$([ ! -e "$APP" ] && echo true || echo false)"
check "installer runs" "$(yes_no install_pkg)"
check "Baddel.app is in /Applications" "$([ -d "$APP" ] && echo true || echo false)"
check "installed version is $VERSION" "$([ "$(version_of "$APP")" = "$VERSION" ] && echo true || echo false)" "found=$(version_of "$APP")"
check "bundle identifier is unchanged" "$([ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "app.baddel.Baddel" ] && echo true || echo false)"
check "icon is declared and present" "$([ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist")" = "Baddel" ] && [ -f "$APP/Contents/Resources/Baddel.icns" ] && echo true || echo false)"
check "app signature verifies after install" "$(yes_no codesign --verify --strict "$APP")"
check "app starts (self-check)" "$(yes_no "$BIN" --self-check)"
FILES=$(pkgutil --files app.baddel.Baddel.pkg 2>/dev/null)
check "the package installed only Applications/Baddel.app" "$([ -n "$FILES" ] && ! grep -v -E '^Applications(/Baddel\.app(/.*)?)?$' <<<"$FILES" | grep -q . && echo true || echo false)"
check "no launch agent or daemon was installed" "$(! ls /Library/LaunchAgents /Library/LaunchDaemons "$HOME/Library/LaunchAgents" 2>/dev/null | grep -qi baddel && echo true || echo false)"
check "installing did not turn on Open at Login" "$("$BIN" --login-item status | grep -q -E 'state=(disabled|notFound)' && echo true || echo false)" "$("$BIN" --login-item status | tail -1)"

say "-- Open at Login toggle --"
ON=$("$BIN" --login-item enable | tail -1)
AFTER_ON=$("$BIN" --login-item status | tail -1)
check "turning it on is accepted from /Applications" "$(grep -q -E 'state=(enabled|requiresApproval)' <<<"$ON" && echo true || echo false)" "$ON; then $AFTER_ON"
BTM=$(sudo sfltool dumpbtm 2>/dev/null | grep -c -i "app.baddel.Baddel" || true)
say "NOTE login items database mentions Baddel $BTM time(s) while on"
OFF=$("$BIN" --login-item disable | tail -1)
AFTER_OFF=$("$BIN" --login-item status | tail -1)
check "turning it off returns it to off" "$(grep -q 'state=disabled' <<<"$AFTER_OFF" && echo true || echo false)" "$OFF; then $AFTER_OFF"
"$BIN" --login-item enable >/dev/null; "$BIN" --login-item disable >/dev/null
check "on and off again is repeatable" "$("$BIN" --login-item status | grep -q 'state=disabled' && echo true || echo false)"
say "NOTE a real logout and login was not performed; this checks registration with macOS only"

say "-- upgrade from the 0.1.0 preview (ad-hoc identity) --"
remove_all
OLD=$(old_preview 0.1.0)
if [ -n "$OLD" ] && [ -d "$OLD" ]; then
  sudo ditto "$OLD" "$APP"
  mkdir -p "$HOME/Downloads/OldBaddel" && ditto "$OLD" "$HOME/Downloads/OldBaddel/Baddel.app"
  OLD_HASH=$(cdhash "$APP")
  check "old preview is in place" "$([ "$(version_of "$APP")" = "0.1.0" ] && echo true || echo false)"
  # The package runs no script. In the Installer window macOS asks the user to
  # quit Baddel (must-close); that prompt does not exist for the command-line
  # installer used here, so the old copy is not started for this check.
  check "installer runs over the old preview" "$(yes_no install_pkg)"
  check "/Applications now holds $VERSION" "$([ "$(version_of "$APP")" = "$VERSION" ] && echo true || echo false)" "found=$(version_of "$APP")"
  check "the copy elsewhere was not touched (not relocated)" "$([ "$(version_of "$HOME/Downloads/OldBaddel/Baddel.app")" = "0.1.0" ] && echo true || echo false)"
  check "new app verifies and starts" "$(codesign --verify --strict "$APP" >/dev/null 2>&1 && "$BIN" --self-check >/dev/null 2>&1 && echo true || echo false)"
  NEW_HASH=$(cdhash "$APP")
  check "the code identity differs from the old preview's" "$([ -n "$OLD_HASH" ] && [ "$OLD_HASH" != "$NEW_HASH" ] && echo true || echo false)"
  say "NOTE because the identity differs, the old copy's Accessibility entry does not apply to the new one; the app offers Remove Old Entry"
  check "the command behind Remove Old Entry succeeds" "$(yes_no tccutil reset Accessibility app.baddel.Baddel)"
  rm -rf "$HOME/Downloads/OldBaddel"
else
  check "0.1.0 preview could be downloaded and verified" false
fi

say "-- upgrade from 0.2.0 --"
remove_all
OLD=$(old_preview 0.2.0)
if [ -n "$OLD" ] && [ -d "$OLD" ]; then
  sudo ditto "$OLD" "$APP"
  check "installer runs over 0.2.0" "$(yes_no install_pkg)"
  check "/Applications now holds $VERSION" "$([ "$(version_of "$APP")" = "$VERSION" ] && echo true || echo false)"
  check "installing the same version again works" "$(yes_no install_pkg)"
  check "still $VERSION and starts" "$([ "$(version_of "$APP")" = "$VERSION" ] && "$BIN" --self-check >/dev/null 2>&1 && echo true || echo false)"
else
  check "0.2.0 could be downloaded and verified" false
fi

say "-- uninstall as documented --"
"$BIN" --login-item disable >/dev/null 2>&1
pkill -x Baddel 2>/dev/null
sudo rm -rf "$APP"
sudo pkgutil --forget app.baddel.Baddel.pkg >/dev/null 2>&1
check "app and receipt are gone" "$([ ! -e "$APP" ] && ! pkgutil --pkg-info app.baddel.Baddel.pkg >/dev/null 2>&1 && echo true || echo false)"

rm -rf "$WORK"
if [ "$failures" -eq 0 ]; then say "RESULT all checks passed"; else say "RESULT $failures check(s) failed"; fi
[ "$failures" -eq 0 ]
