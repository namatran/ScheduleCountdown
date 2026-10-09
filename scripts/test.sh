#!/bin/bash
# Regenerates the Xcode project and runs the unit tests.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project ScheduleCountdown.xcodeproj -scheme ScheduleCountdown \
    -derivedDataPath build test 2>&1 \
    | grep -v "\[Connection\]" \
    | grep -E "error:|warning: .*\.swift|✘|Test run|issue|TEST (SUCCEEDED|FAILED)|BUILD FAILED" || true
