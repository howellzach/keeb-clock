#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
. scripts/xcode-env.sh
# CI and default local tests must never opt into USB writes.
unset CIDOO_LIVE_TEST
xcrun swift test --package-path CidooCore --scratch-path "$(pwd)/build/swift-tests"
