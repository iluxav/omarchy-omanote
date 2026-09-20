#!/bin/bash
# Opened in a terminal by the bar icon when `omanote` is missing.
#
# It installs one specific omanote release, the one named in omanote.pin, and
# only after checking the download against the SHA-256 recorded there. Nothing
# is piped into a shell and nothing unverified is ever run. Nothing happens
# without a yes.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIN="$HERE/omanote.pin"
DIR="${OMANOTE_INSTALL_DIR:-$HOME/.local/bin}"

die() { echo "install-omanote: $*" >&2; exit 1; }

if command -v omanote >/dev/null 2>&1; then
  echo "omanote is already installed: $(command -v omanote)"
  exit 0
fi

[[ -f $PIN ]] || die "missing $PIN"
version=$(awk -F= '$1 == "version" { print $2 }' "$PIN")
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "omanote.pin has no usable version"

case "$(uname -m)" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *) die "unsupported processor: $(uname -m)" ;;
esac
asset="omanote-$arch-unknown-linux-musl.tar.gz"
want=$(awk -v f="$asset" '$1 == "sha256" && $3 == f { print $2 }' "$PIN")
[[ $want =~ ^[0-9a-f]{64}$ ]] || die "omanote.pin has no checksum for $asset"
url="https://github.com/iluxav/omanote/releases/download/$version/$asset"

cat <<MSG
The Omanote plugin is the desktop side only: the bar icon, the search popup and
quick capture. The editor is a separate program, omanote, which is not
installed yet.

This will download omanote $version:

  $url

check it against the checksum this plugin was published with:

  $want

and put the program in $DIR.

MSG

if command -v gum >/dev/null 2>&1; then
  gum confirm "Install omanote $version now?" || { echo "Not installed."; exit 0; }
else
  read -r -p "Install omanote $version now? [y/N] " answer
  [[ $answer == [yY]* ]] || { echo "Not installed."; exit 0; }
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL "$url" -o "$tmp/$asset" || die "download failed"
got=$(sha256sum "$tmp/$asset" | awk '{ print $1 }')
[[ $got == "$want" ]] || die "checksum mismatch — expected $want, got $got. Nothing was installed."
echo "Checksum OK."

tar -xzf "$tmp/$asset" -C "$tmp"
[[ -f $tmp/omanote ]] || die "the archive did not contain omanote"
mkdir -p "$DIR"
install -m755 "$tmp/omanote" "$DIR/omanote"
echo "Installed $DIR/omanote"

echo
# App launcher entry and Omarchy menu entries; safe to run twice.
"$DIR/omanote" --omarchy || true
