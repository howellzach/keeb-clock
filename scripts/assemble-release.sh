#!/bin/sh
# Combine macOS and Linux release archives into dist/ and write one checksum file.
set -eu
cd "$(dirname "$0")/.."
. scripts/version.sh
artifacts=${1:?artifact directory}
rm -rf dist
mkdir -p dist build
find "$artifacts" -type f -name '*.zip' -exec cp {} dist/ \;
notes=$(find "$artifacts" -type f -name release-notes.md)
test -n "$notes"
test "$(printf '%s\n' "$notes" | grep -c .)" -eq 1
cp "$notes" build/release-notes.md
grep -q "Keeb Clock $release_version" build/release-notes.md
test -f "dist/KeebClock-$release_version-macos-universal.zip"
test -f "dist/keeb-clock-$release_version-macos-arm64.zip"
test -f "dist/keeb-clock-$release_version-macos-x86_64.zip"
test -f "dist/keeb-clock-$release_version-linux-x86_64.zip"
test -f "dist/keeb-clock-$release_version-linux-arm64.zip"
set -- dist/*.zip
test "$#" -eq 5
(cd dist && sha256sum -- *.zip | LC_ALL=C sort -k 2 > SHA256SUMS.txt)
printf 'Assembled %s release archives in dist/\n' "$release_version"
