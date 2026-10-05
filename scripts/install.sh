#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
project_root=$(pwd)
source_app="$project_root/build/Keeb Clock.app"
install_directory="${KEEB_CLOCK_INSTALL_DIR:-/Applications}"
destination="$install_directory/Keeb Clock.app"
staging="$install_directory/.Keeb Clock.installing.app"
test -d "$source_app" || { printf 'Build the Swift app first.\n' >&2; exit 1; }
test ! -e "$staging" || { printf 'Installation staging folder already exists.\n' >&2; exit 1; }
codesign --verify --strict "$source_app"
source_identifier=$(plutil -extract CFBundleIdentifier raw -o - "$source_app/Contents/Info.plist")
if test -e "$destination"; then
  identifier=$(plutil -extract CFBundleIdentifier raw -o - "$destination/Contents/Info.plist")
  if test "$identifier" != "$source_identifier" && test "${KEEB_CLOCK_REPLACE_IDENTITY:-0}" != 1; then
    printf 'Existing app has a different identity: %s. Set KEEB_CLOCK_REPLACE_IDENTITY=1 to replace it.\n' "$destination" >&2
    exit 1
  fi
fi
mkdir -p "$install_directory"
ditto "$source_app" "$staging"
codesign --verify --strict "$staging"
if test -e "$destination"; then
  # Stop only the matching installed app and preserve a rollback copy.
  installed_executable=$(plutil -extract CFBundleExecutable raw -o - "$destination/Contents/Info.plist")
  case "$installed_executable" in ''|*/*) printf 'Invalid installed executable name.\n' >&2; exit 1 ;; esac
  app_pid=$(pgrep -f "^$destination/Contents/MacOS/$installed_executable$" || true)
  if test -n "$app_pid"; then kill -TERM "$app_pid"; fi
  backup="$project_root/build/Previous Keeb Clock-$(date +%Y%m%d-%H%M%S).app"
  test ! -e "$backup" || { printf 'Backup already exists: %s\n' "$backup" >&2; exit 1; }
  mv "$destination" "$backup"
  printf 'Previous app preserved: %s\n' "$backup"
fi
mv "$staging" "$destination"
codesign --verify --strict "$destination"
printf 'Installed standalone Swift app: %s\n' "$destination"
