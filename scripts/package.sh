#!/bin/bash
# Builds a Release copy of the app, ad-hoc signs it, and zips it to dist/ScheduleCountdown.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project ScheduleCountdown.xcodeproj -scheme ScheduleCountdown \
    -configuration Release -derivedDataPath build build -quiet

app=build/Build/Products/Release/ScheduleCountdown.app
# No paid developer account: ad-hoc sign so macOS will run it after a one-time "Open Anyway".
# Sign inside-out instead of --deep, which would strip the entitlements of Sparkle's helpers.
sign() { codesign --force --sign - --preserve-metadata=entitlements "$@"; }
sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign "$sparkle"/XPCServices/*.xpc
sign "$sparkle/Autoupdate"
sign "$sparkle/Updater.app"
sign "$app/Contents/Frameworks/Sparkle.framework"
sign "$app"
codesign --verify --deep --strict "$app"

mkdir -p dist
rm -f dist/ScheduleCountdown.zip
ditto -c -k --keepParent "$app" dist/ScheduleCountdown.zip
echo "Built dist/ScheduleCountdown.zip"
