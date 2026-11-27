#!/bin/bash
# Builds macos/build/Baddel.app (release, ad-hoc signed).
#
# Ad-hoc signatures change with every build, so macOS treats each rebuild as a
# new app for Accessibility: remove the old Baddel entry in System Settings →
# Privacy & Security → Accessibility and add the new build again.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Baddel
APP=build/Baddel.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/layouts"
cp .build/release/Baddel "$APP/Contents/MacOS/Baddel"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp ../shared/layouts/*.json "$APP/Contents/Resources/layouts/"
codesign --force --sign - "$APP"
echo "Built $APP"
