#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
project_root=$(pwd)
. scripts/version.sh
(cd cli && go build -trimpath -ldflags "-X main.version=$release_version -X main.buildNumber=$release_build" -o "$project_root/build/keeb-clock" ./cmd/keeb-clock)
codesign --force --sign - build/keeb-clock
printf 'Built independent Go CLI: %s/build/keeb-clock\n' "$project_root"
