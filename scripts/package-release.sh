#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/version.sh
. scripts/check-app.sh
architecture=$(uname -m)
case "$architecture" in arm64|x86_64) ;; *) printf 'Unsupported architecture: %s\n' "$architecture" >&2; exit 1 ;; esac
app_architectures=$(xcrun lipo -archs "$app/Contents/MacOS/KeebClock")
case " $app_architectures " in *' arm64 '*) ;; *) exit 1 ;; esac
case " $app_architectures " in *' x86_64 '*) ;; *) exit 1 ;; esac
codesign --verify --strict "$app"
test "$(./build/keeb-clock --version)" = "keeb-clock $release_version (build $release_build)"
codesign --verify --strict build/keeb-clock
staging=$(mktemp -d "$PWD/build/release-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT HUP INT TERM
mkdir -p dist "$staging/app" "$staging/cli"
ditto --norsrc --noextattr "$app" "$staging/app/Keeb Clock.app"
cp LICENSE THIRD_PARTY_NOTICES.md "$staging/app/"
cp build/keeb-clock LICENSE THIRD_PARTY_NOTICES.md "$staging/cli/"
cat > "$staging/app/INSTALL.txt" <<'TEXT'
Move Keeb Clock.app to Applications and open it.
Connect a CIDOO ABM066 over USB, then use the clock-keycap menu bar icon.
Requires macOS 13 or later. Only tested on Apple Silicon.
This build is ad-hoc signed and is not notarized. macOS may block its first launch.
Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
cat > "$staging/cli/INSTALL.txt" <<'TEXT'
Run ./keeb-clock devices to list connected keyboards.
Run ./keeb-clock sync-time to update the clock; add --utc for UTC.
Requires macOS and a CIDOO ABM066 connected over USB.
Only tested on Apple Silicon. This build is ad-hoc signed and not notarized.
Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
app_archive="KeebClock-$release_version-macos-universal.zip"
cli_archive="keeb-clock-$release_version-macos-$architecture.zip"
ditto -c -k --norsrc --noextattr "$staging/app" "dist/$app_archive"
ditto -c -k --norsrc --noextattr "$staging/cli" "dist/$cli_archive"
(cd dist && shasum -a 256 "$app_archive" "$cli_archive" > SHA256SUMS.txt)
cat > build/release-notes.md <<TEXT
Keeb Clock $release_version (build $release_build)

- Menu bar app: Apple Silicon and Intel build; only tested on Apple Silicon.
- CLI: macOS $architecture build.
- Connect a CIDOO ABM066 over USB. Bluetooth syncing is not supported.
- These builds are ad-hoc signed and are **not notarized**. macOS may block first launch.

Unzip the app download, move Keeb Clock.app into Applications, then open it.
The CLI archive includes usage instructions. Both archives include licence notices.
Use SHA256SUMS.txt to check downloaded archive checksums.

Unofficial project. Not affiliated with or endorsed by CIDOO.
TEXT
printf 'Packaged app and %s CLI in dist/\n' "$architecture"
