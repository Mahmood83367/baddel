#!/bin/bash
# Builds the macOS installer package from the app in macos/build/Baddel.app
# (run scripts/build-app.sh or scripts/package-release.sh first).
#
# The package installs exactly one thing: /Applications/Baddel.app. It carries
# no scripts at all: nothing runs as root. A running Baddel is handled by
# Installer itself, which asks the user to quit the app with Baddel's bundle
# identifier (the must-close entry in pkg/distribution.xml). It installs no
# launch agent or daemon and changes no permission or login item.
#
# Output in dist/, depending on what the build could be signed with:
#
#   Baddel-<version>-macos-universal.pkg
#       ONLY when the package is signed with a Developer ID Installer identity
#       AND notarized by Apple. This is the installer that may be published.
#
#   Baddel-<version>-macos-universal-TEST-ONLY-<state>.pkg
#       Every other case (unsigned, or signed but not notarized). For
#       validation only. It must not be published as the Mac installer:
#       macOS will not open it normally, and that is the correct behaviour.
#
# Signing uses identities already in the keychain, through the system tools.
# Nothing is exported and no credential is read by this script:
#   BADDEL_SIGN_IDENTITY       Developer ID Application identity (signs the app;
#                              set it when running build-app.sh / package-release.sh)
#   BADDEL_INSTALLER_IDENTITY  Developer ID Installer identity (signs the package)
#   BADDEL_NOTARY_PROFILE      notarytool keychain profile (notarizes and staples)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < ../VERSION)
APP=build/Baddel.app
DIST="$(cd .. && pwd)/dist"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
[ -d "$APP" ] || { echo "Build the app first: scripts/build-app.sh"; exit 1; }
mkdir -p "$DIST" "$WORK/root/Applications" "$WORK/pkgs" "$WORK/resources"

ditto "$APP" "$WORK/root/Applications/Baddel.app"

# The component must not be "relocatable". By default Installer looks for an
# existing app with the same bundle identifier anywhere on the disk and
# installs over that copy instead; Baddel has one canonical path.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$WORK/component.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked false" "$WORK/component.plist"
/usr/libexec/PlistBuddy -c "Set :0:BundleHasStrictIdentifier true" "$WORK/component.plist"

pkgbuild --root "$WORK/root" --component-plist "$WORK/component.plist" \
  --identifier app.baddel.Baddel.pkg --version "$VERSION" --install-location / \
  --ownership recommended "$WORK/pkgs/component.pkg" >/dev/null

cp -R pkg/resources/. "$WORK/resources/"
cp ../LICENSE "$WORK/resources/license.txt"
find "$WORK/resources" -name '*.html' -exec sed -i '' "s/__VERSION__/$VERSION/g" {} +
sed "s/__VERSION__/$VERSION/g" pkg/distribution.xml > "$WORK/distribution.xml"

STATE=unsigned
SIGN=()
if [ -n "${BADDEL_INSTALLER_IDENTITY:-}" ]; then
  SIGN=(--sign "$BADDEL_INSTALLER_IDENTITY" --timestamp)
  STATE=not-notarized
fi
productbuild --distribution "$WORK/distribution.xml" --resources "$WORK/resources" \
  --package-path "$WORK/pkgs" ${SIGN[@]+"${SIGN[@]}"} "$WORK/Baddel.pkg" >/dev/null

if [ "$STATE" = "not-notarized" ] && [ -n "${BADDEL_NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$WORK/Baddel.pkg" --keychain-profile "$BADDEL_NOTARY_PROFILE" --wait
  xcrun stapler staple "$WORK/Baddel.pkg"
  # The final word is the system's own assessment of an installer package.
  spctl --assess --type install "$WORK/Baddel.pkg"
  STATE=notarized
fi

rm -f "$DIST"/Baddel-"$VERSION"-macos-universal*.pkg "$DIST"/Baddel-"$VERSION"-macos-universal*.pkg.sha256
if [ "$STATE" = "notarized" ]; then
  NAME="Baddel-$VERSION-macos-universal.pkg"
else
  NAME="Baddel-$VERSION-macos-universal-TEST-ONLY-$STATE.pkg"
fi
cp "$WORK/Baddel.pkg" "$DIST/$NAME"
(cd "$DIST" && shasum -a 256 "$NAME" > "$NAME.sha256")

# Check what was built: the close-first entry is present and no script is.
pkgutil --expand "$DIST/$NAME" "$WORK/expanded"
grep -q '<app id="app.baddel.Baddel"/>' "$WORK/expanded/Distribution" || { echo "must-close entry missing"; exit 1; }
if [ -e "$WORK/expanded/component.pkg/Scripts" ] || grep -q -E '<(pre|post)install' "$WORK/expanded/component.pkg/PackageInfo"; then
  echo "the package must not contain scripts"; exit 1
fi

echo "Created dist/$NAME"
echo "must-close: app.baddel.Baddel; scripts: none"
echo "package signature: $(pkgutil --check-signature "$DIST/$NAME" 2>&1 | sed -n 's/^ *Status: //p' | head -1)"
if [ "$STATE" = "notarized" ]; then
  echo "This package is signed and notarized and may be published."
else
  echo "TEST ONLY ($STATE): do not publish this as the Mac installer."
fi
cat "$DIST/$NAME.sha256"
