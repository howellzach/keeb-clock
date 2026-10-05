#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/version.sh
. scripts/xcode-env.sh
project_root=$(pwd)
mkdir -p build
xcrun xcodebuild -quiet \
  -project KeebClock.xcodeproj -scheme KeebClock \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$project_root/build/xcode" \
  CONFIGURATION_BUILD_DIR="$project_root/build" CODE_SIGNING_ALLOWED=NO build
app="$project_root/build/Keeb Clock.app"
# Remove linker debug records containing local source/object paths before signing.
xcrun strip -S "$app/Contents/MacOS/KeebClock"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
. scripts/check-app.sh
printf 'Built Swift app %s (build %s): %s\n' "$release_version" "$release_build" "$app"
