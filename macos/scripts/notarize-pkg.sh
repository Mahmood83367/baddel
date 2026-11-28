#!/bin/bash
# Notarizes an installer package that is already signed with a Developer ID
# Installer identity, staples the ticket, and gives it its publishable name.
# Use it when the package was built before a notarytool profile existed, so the
# exact file that was verified is the one that gets notarized:
#
#   BADDEL_NOTARY_PROFILE=<profile> macos/scripts/notarize-pkg.sh \
#     dist/Baddel-<version>-macos-universal-TEST-ONLY-not-notarized.pkg
#
# The profile is a notarytool keychain profile, created once by the account
# holder with `xcrun notarytool store-credentials`. This script reads no
# credential itself and stores nothing.
#
# Output, next to the input and only after Apple has accepted the package:
#   Baddel-<version>-macos-universal.pkg
#   Baddel-<version>-macos-universal.pkg.sha256
set -euo pipefail
INPUT=${1:?usage: notarize-pkg.sh <signed package>}
: "${BADDEL_NOTARY_PROFILE:?set BADDEL_NOTARY_PROFILE to a notarytool keychain profile}"
[ -f "$INPUT" ] || { echo "$INPUT does not exist"; exit 1; }
case "$(basename "$INPUT")" in
  Baddel-*-macos-universal-TEST-ONLY-not-notarized.pkg) ;;
  *) echo "expected Baddel-<version>-macos-universal-TEST-ONLY-not-notarized.pkg"; exit 1 ;;
esac
pkgutil --check-signature "$INPUT" | grep -q "Developer ID Installer" || { echo "the package is not signed with a Developer ID Installer identity"; exit 1; }

DIR=$(cd "$(dirname "$INPUT")" && pwd)
FINAL="$DIR/$(basename "$INPUT" | sed 's/-TEST-ONLY-not-notarized//')"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cp "$INPUT" "$WORK/Baddel.pkg"

xcrun notarytool submit "$WORK/Baddel.pkg" --keychain-profile "$BADDEL_NOTARY_PROFILE" --wait | tee "$WORK/submit.log"
grep -q "status: Accepted" "$WORK/submit.log" || { echo "Apple did not accept the package; nothing was renamed."; exit 1; }
xcrun stapler staple "$WORK/Baddel.pkg"
xcrun stapler validate "$WORK/Baddel.pkg"
# The final word is the system's own assessment of an installer package.
spctl --assess --type install -vv "$WORK/Baddel.pkg"

cp "$WORK/Baddel.pkg" "$FINAL"
(cd "$DIR" && shasum -a 256 "$(basename "$FINAL")" > "$(basename "$FINAL").sha256")
echo "Created $FINAL"
echo "This package is signed, notarized and stapled, and may be published."
cat "$FINAL.sha256"
