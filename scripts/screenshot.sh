#!/bin/sh
# Render the app's real SwiftUI view with sample data, without USB access.
set -eu
cd "$(dirname "$0")/.."
. scripts/xcode-env.sh
project_root=$(pwd)
mkdir -p assets
xcrun xcodebuild -quiet -project KeebClock.xcodeproj -scheme KeebClock \
  -configuration Debug -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$project_root/build/screenshot-xcode" \
  CONFIGURATION_BUILD_DIR="$project_root/build/screenshot" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG SCREENSHOT' CODE_SIGNING_ALLOWED=NO build
app="$project_root/build/screenshot/Keeb Clock.app"
codesign --force --sign - "$app"
"$app/Contents/MacOS/KeebClock" --screenshot "$project_root/assets/menu.png"
python3 scripts/clean-png.py "$project_root/assets/menu.png"
