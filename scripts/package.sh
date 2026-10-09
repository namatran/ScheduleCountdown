#!/bin/bash
# Builds a Release copy of the app, ad-hoc signs it, and packages it as
# dist/ScheduleCountdown.zip (what Sparkle updates download) and dist/ScheduleCountdown.dmg
# (drag-to-install, for new installs).
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

# Disk image: the app, an Applications shortcut, and a background with an arrow between them.
volume=ScheduleCountdown
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/stage/.background"
ditto "$app" "$work/stage/ScheduleCountdown.app"
ln -s /Applications "$work/stage/Applications"
swift scripts/dmg-background.swift "$work/background.png" 1
swift scripts/dmg-background.swift "$work/background@2x.png" 2
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" \
    -out "$work/stage/.background/background.tiff" 2>/dev/null

# A copy left mounted from an earlier run would make the new one mount as "ScheduleCountdown 1".
[[ -d /Volumes/$volume ]] && hdiutil detach "/Volumes/$volume" -quiet
hdiutil create -quiet -srcfolder "$work/stage" -volname "$volume" -fs HFS+ -format UDRW "$work/rw.dmg"
mount=$(hdiutil attach -readwrite -noverify -noautoopen "$work/rw.dmg" \
    | awk -F'\t' '/\/Volumes\// { print $NF }')

# Finder saves the window layout into the image's .DS_Store. It needs permission to control
# Finder the first time; without it the image still works, just without the layout.
if ! osascript - "$volume" <<'EOF'
on run argv
    tell application "Finder"
        tell disk (item 1 of argv)
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            -- 660×400 content, plus the title bar.
            set bounds of container window to {200, 120, 860, 548}
            set options to icon view options of container window
            set arrangement of options to not arranged
            set icon size of options to 128
            set text size of options to 13
            set background picture of options to file ".background:background.tiff"
            set position of item "ScheduleCountdown.app" of container window to {170, 180}
            set position of item "Applications" of container window to {490, 180}
            update without registering applications
            delay 1
            close
        end tell
    end tell
end run
EOF
then
    echo "warning: couldn't lay out the disk image window (allow Terminal to control Finder)" >&2
fi
rm -rf "$mount/.fseventsd"
sync
hdiutil detach "$mount" -quiet
rm -f dist/ScheduleCountdown.dmg
hdiutil convert "$work/rw.dmg" -quiet -format UDZO -imagekey zlib-level=9 -o dist/ScheduleCountdown.dmg
echo "Built dist/ScheduleCountdown.dmg"
