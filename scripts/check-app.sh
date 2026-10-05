#!/bin/sh
# Source from the project root after loading scripts/version.sh.
app="$(pwd)/build/Keeb Clock.app"
actual_version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
actual_build=$(plutil -extract CFBundleVersion raw -o - "$app/Contents/Info.plist")
test "$actual_version" = "$release_version" && test "$actual_build" = "$release_build" || {
  printf 'App version does not match Config/Version.xcconfig.\n' >&2; exit 1;
}
test -x "$app/Contents/MacOS/KeebClock"
test "$(plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" = 'howellza.ch.keeb-clock'
test ! -e "$app/Contents/Resources/cidoo-screen"
test ! -e "$app/Contents/Resources/keeb-clock"
test -f "$app/Contents/Resources/AppIcon.icns"
test "$(plutil -extract CFBundleDisplayName raw -o - "$app/Contents/Info.plist")" = 'Keeb Clock'
if LC_ALL=C grep -a -q -E '/Users/|/Volumes/' "$app/Contents/MacOS/KeebClock"; then
  printf 'Release executable contains local build paths.\n' >&2
  exit 1
fi
