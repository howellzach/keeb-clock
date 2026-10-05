#!/bin/sh
# Source from the project root; parse data rather than evaluating config as code.
release_version=$(awk '$1 == "MARKETING_VERSION" && $2 == "=" { print $3 }' Config/Version.xcconfig)
release_build=$(awk '$1 == "CURRENT_PROJECT_VERSION" && $2 == "=" { print $3 }' Config/Version.xcconfig)
printf '%s\n' "$release_version" | LC_ALL=C awk '/^[0-9]+\.[0-9]+(\.[0-9]+)?$/ { n++; next } { exit 1 } END { if (n != 1) exit 1 }' || {
  printf 'Invalid MARKETING_VERSION in Config/Version.xcconfig\n' >&2; exit 1;
}
printf '%s\n' "$release_build" | LC_ALL=C awk '/^[1-9][0-9]*$/ { n++; next } { exit 1 } END { if (n != 1) exit 1 }' || {
  printf 'Invalid CURRENT_PROJECT_VERSION in Config/Version.xcconfig\n' >&2; exit 1;
}
