#!/bin/sh
# Package one native CLI binary. The host architecture must match the archive name.
set -eu
cd "$(dirname "$0")/.."
. scripts/version.sh
binary=${1:?binary}
platform=${2:?platform}
arch=${3:?arch}
case "$platform-$arch" in
  macos-arm64|macos-x86_64|linux-arm64|linux-x86_64) ;;
  *) printf 'Unsupported CLI target: %s %s\n' "$platform" "$arch" >&2; exit 1 ;;
esac
host=$(uname -m)
case "$host" in aarch64) host=arm64 ;; esac
if test "$host" != "$arch"; then
  printf 'This machine is %s. %s archives are built on %s.\n' "$host" "$platform $arch" "$arch" >&2
  exit 1
fi
description=$(file -b "$binary")
printf '%s\n' "$description" | grep -q '64-bit'
case "$arch" in
  x86_64) printf '%s\n' "$description" | grep -E -q 'x86_64|x86-64' ;;
  arm64) printf '%s\n' "$description" | grep -E -q 'arm64|aarch64' ;;
esac
if test "$platform" = linux; then
  ldd "$binary" | grep -q libudev
fi
if test "$(uname -s)" = Darwin; then
  codesign --verify --strict "$binary"
fi
test "$("$binary" --version)" = "keeb-clock $release_version (build $release_build)"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT HUP INT TERM
cp "$binary" "$staging/keeb-clock"
cp LICENSE THIRD_PARTY_NOTICES.md "$staging/"
case "$platform-$arch" in
  macos-arm64)
    cat > "$staging/INSTALL.txt" <<'TEXT'
Run ./keeb-clock devices to list connected keyboards.
Run ./keeb-clock sync-time to update the clock; add --utc for UTC.
Requires macOS on Apple Silicon.
This build is ad-hoc signed and not notarized.
Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
    ;;
  macos-x86_64)
    cat > "$staging/INSTALL.txt" <<'TEXT'
Run ./keeb-clock devices to list connected keyboards.
Run ./keeb-clock sync-time to update the clock; add --utc for UTC.
Requires macOS on a 64-bit Intel Mac.
This build is ad-hoc signed and not notarized.
Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
    ;;
  linux-x86_64)
    cat > "$staging/INSTALL.txt" <<'TEXT'
Run ./keeb-clock devices to list connected keyboards.
Run ./keeb-clock sync-time to update the clock; add --utc for UTC.
Requires 64-bit x86 Linux with glibc and libudev, and a CIDOO ABM066 connected over USB.
Your user needs permission to open the keyboard's hidraw device.
Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
    ;;
  linux-arm64)
    cat > "$staging/INSTALL.txt" <<'TEXT'
Run ./keeb-clock devices to list connected keyboards.
Run ./keeb-clock sync-time to update the clock; add --utc for UTC.
Requires 64-bit ARM Linux with glibc and libudev, and a CIDOO ABM066 connected over USB.
Your user needs permission to open the keyboard's hidraw device.
Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
    ;;
esac
mkdir -p dist
archive="keeb-clock-$release_version-$platform-$arch.zip"
case "$(uname -s)" in
  Darwin)
    ditto -c -k --norsrc --noextattr "$staging" "dist/$archive"
    ;;
  Linux)
    archive_path="$PWD/dist/$archive"
    (cd "$staging" && zip -q "$archive_path" keeb-clock LICENSE THIRD_PARTY_NOTICES.md INSTALL.txt)
    ;;
  *) printf 'Package CLI archives on macOS or Linux.\n' >&2; exit 1 ;;
esac
printf 'Packaged %s %s CLI: dist/%s\n' "$platform" "$arch" "$archive"
