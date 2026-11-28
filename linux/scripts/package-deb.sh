#!/bin/bash
# Builds a Debian package from the tarball that package-release.sh produced:
#
#   dist/baddel_<version>_amd64.deb
#   dist/baddel_<version>_amd64.deb.sha256
#
# For Debian, Ubuntu and their derivatives. It installs:
#   /opt/baddel/                 the program, the Bash integration, the license
#   /usr/bin/baddel              a link to the program
#   /usr/share/applications/     a menu entry
#   /usr/share/icons/hicolor/    the icon
#   /usr/share/doc/baddel/       copyright and README
# It has no installation scripts: nothing runs as root at install or removal,
# nothing is started, and Start at login stays off until a user enables it.
#
# BADDEL_DEB_VERSION overrides the version, for upgrade checks only.
set -euo pipefail
cd "$(dirname "$0")/../.."
VERSION=$(tr -d '[:space:]' < VERSION)
DEB_VERSION="${BADDEL_DEB_VERSION:-$VERSION}"
TARBALL="dist/Baddel-$VERSION-linux-x64-prototype.tar.gz"
[ -f "$TARBALL" ] || { echo "Run linux/scripts/package-release.sh first: $TARBALL is missing." >&2; exit 1; }

ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
PKG="$ROOT/baddel"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/baddel" "$PKG/usr/bin" "$PKG/usr/share/applications" \
  "$PKG/usr/share/icons/hicolor/256x256/apps" "$PKG/usr/share/doc/baddel"
tar -xzf "$TARBALL" -C "$ROOT"
SOURCE="$ROOT/Baddel-$VERSION-linux-x64-prototype"
cp "$SOURCE/baddel" "$PKG/opt/baddel/baddel"
cp -r "$SOURCE/shell" "$PKG/opt/baddel/shell"
cp "$SOURCE/LICENSE" "$PKG/opt/baddel/LICENSE"
ln -s /opt/baddel/baddel "$PKG/usr/bin/baddel"
cp docs/media/baddel-logo.png "$PKG/usr/share/icons/hicolor/256x256/apps/baddel.png"
cp "$SOURCE/README.txt" "$PKG/usr/share/doc/baddel/README"

cat > "$PKG/usr/share/applications/app.baddel.Baddel.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Baddel
GenericName=Keyboard layout correction
Comment=Fix text typed with the wrong keyboard layout
Exec=baddel
TryExec=baddel
Icon=baddel
Terminal=false
Categories=Utility;Accessibility;
Keywords=keyboard;layout;Arabic;English;
DESKTOP

cat > "$PKG/usr/share/doc/baddel/copyright" <<COPYRIGHT
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Baddel
Source: https://github.com/Mahmood83367/baddel

Files: *
Copyright: 2026 Mahmood
License: Expat

License: Expat
$(sed 's/^$/./; s/^/ /' LICENSE)
COPYRIGHT

SIZE=$(du -sk "$PKG" | cut -f1)
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: baddel
Version: $DEB_VERSION
Section: utils
Priority: optional
Architecture: amd64
Installed-Size: $SIZE
Depends: libc6, libx11-6, libxkbcommon0, xkb-data, libatspi2.0-0, at-spi2-core, libglib2.0-bin, x11-xkb-utils
Recommends: bash (>= 4.0)
Maintainer: Mahmood <84744874+Mahmood83367@users.noreply.github.com>
Homepage: https://github.com/Mahmood83367/baddel
Description: Fix text typed with the wrong keyboard layout (Arabic and English)
 Baddel corrects text that was typed with the wrong keyboard layout: press its
 shortcut and the last word, the selection or the whole field is converted
 between the Arabic and the English layout in place.
 .
 This is a prototype. On X11 it holds its shortcut itself; on Wayland a desktop
 shortcut has to be bound to "baddel --trigger". It edits text fields through
 the accessibility bus (AT-SPI) and includes an opt-in Bash integration.
CONTROL

find "$PKG" -type d -exec chmod 755 {} +
chmod 755 "$PKG/opt/baddel/baddel"
chmod 644 "$PKG/opt/baddel/LICENSE" "$PKG/opt/baddel/shell/baddel.bash" "$PKG/usr/share/applications/"*.desktop \
  "$PKG/usr/share/icons/hicolor/256x256/apps/baddel.png" "$PKG/usr/share/doc/baddel/"* "$PKG/DEBIAN/control"
OUT="dist/baddel_${DEB_VERSION}_amd64.deb"
rm -f "$OUT" "$OUT.sha256"
dpkg-deb --root-owner-group --build "$PKG" "$OUT" >/dev/null
(cd dist && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
echo "Created $OUT"
cat "$OUT.sha256"
