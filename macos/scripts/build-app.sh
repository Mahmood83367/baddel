#!/bin/bash
# Builds macos/build/Baddel.app from the current source tree.
#
#   ./scripts/build-app.sh              release build for this Mac's architecture
#   UNIVERSAL=1 ./scripts/build-app.sh  universal build (arm64 + x86_64)
#
# Signing:
#   default                              ad-hoc signature (no developer identity)
#   BADDEL_SIGN_IDENTITY="Developer ID Application: …"
#                                        sign with that identity and the hardened runtime
#
# An ad-hoc signature changes with every build, so macOS treats each rebuild as
# a new app for Accessibility: remove the old Baddel entry in System Settings →
# Privacy & Security → Accessibility and add the new build again.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < ../VERSION)

if [ "${UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --product Baddel --arch arm64 --arch x86_64
  BINARY=.build/apple/Products/Release/Baddel
else
  swift build -c release --product Baddel
  BINARY=.build/release/Baddel
fi

APP=build/Baddel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/layouts"
cp "$BINARY" "$APP/Contents/MacOS/Baddel"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
# Only the layouts this platform uses; the Windows layout tables stay out.
for layout in us-english uk-english-mac arabic-mac arabic-pc; do
  cp "../shared/layouts/$layout.json" "$APP/Contents/Resources/layouts/"
done
# Opt-in zsh integration; a user sources it from ~/.zshrc (docs/TERMINAL.md).
mkdir -p "$APP/Contents/Resources/shell"
cp ../shared/shell/baddel.zsh "$APP/Contents/Resources/shell/baddel.zsh"
cp ../LICENSE "$APP/Contents/Resources/LICENSE"
cp Resources/Baddel.icns "$APP/Contents/Resources/Baddel.icns"

if [ -n "${BADDEL_SIGN_IDENTITY:-}" ]; then
  # BADDEL_SIGN_TIMESTAMP=none skips the Apple timestamp server (local tests only).
  codesign --force --options runtime --timestamp"${BADDEL_SIGN_TIMESTAMP:+=$BADDEL_SIGN_TIMESTAMP}" \
    --sign "$BADDEL_SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (version $VERSION)"
