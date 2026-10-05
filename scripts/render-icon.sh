#!/bin/sh
# Generate macOS icon sizes from the master image.
set -eu
cd "$(dirname "$0")/.."
master="assets/keeb-clock-icon.png"
output="KeebClock/Assets.xcassets/AppIcon.appiconset"
test -f "$master"
mkdir -p "$output"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$master" --out "$output/icon-$size.png" >/dev/null
done
python3 scripts/clean-png.py "$output"/*.png
printf 'Regenerated all macOS icon sizes from %s\n' "$master"
