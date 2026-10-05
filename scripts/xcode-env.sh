#!/bin/sh
# Respect an explicit toolchain; use full Xcode when only Command Line Tools is selected.
if test -z "${DEVELOPER_DIR:-}"; then
  selected_developer=$(xcode-select -p)
  if test ! -d "$selected_developer/Platforms/MacOSX.platform"; then
    if test -d /Applications/Xcode.app/Contents/Developer; then
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
      export DEVELOPER_DIR
    else
      printf 'Full Xcode is required. Set DEVELOPER_DIR to its Contents/Developer directory.\n' >&2
      exit 1
    fi
  fi
fi
