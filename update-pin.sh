#!/bin/bash
# For the maintainer: point the plugin at an omanote release.
#
#   ./update-pin.sh v0.1.0
#
# Records the version and the release's checksums in omanote.pin, which is what
# install-omanote.sh installs and verifies against. Commit the result.
set -euo pipefail

version="${1:-}"
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 v0.1.0" >&2; exit 1; }
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sums=$(curl -fsSL "https://github.com/iluxav/omanote/releases/download/$version/checksums.txt") \
  || { echo "no checksums.txt for $version — is the release published?" >&2; exit 1; }

{
  echo "# The omanote release this plugin installs, with the SHA-256 of each build."
  echo "# Written by update-pin.sh; install-omanote.sh refuses anything that does not match."
  echo "version=$version"
  awk '$2 ~ /linux/ { print "sha256", $1, $2 }' <<<"$sums"
} > "$here/omanote.pin"
cat "$here/omanote.pin"
