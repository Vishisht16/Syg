#!/bin/sh
# Installs syg: https://syg.vishisht.tech/install.html
#
#   curl -fsSL https://syg.vishisht.tech/install.sh | sh
#
# Downloads the release archive for this OS and CPU, checks it against the
# release's SHA256SUMS (and its cosign signature, when cosign is installed),
# and puts syg in $SYG_INSTALL_DIR (default ~/.local/bin). No sudo.
#
#   SYG_VERSION=1.0.0       a version instead of the latest
#   SYG_INSTALL_DIR=DIR     where to put the binary
set -eu

REPO="vishisht16/syg"
BASE="${SYG_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download}"
API="${SYG_API:-https://api.github.com/repos/$REPO/releases/latest}"
DIR="${SYG_INSTALL_DIR:-$HOME/.local/bin}"

say() { printf 'syg-install: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

fetch() { # fetch URL FILE
  if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else die "needs curl or wget"; fi
}

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) die "unsupported OS $(uname -s): on Windows, use install.ps1 or scoop (https://syg.vishisht.tech/install.html)" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  arm64 | aarch64) arch=arm64 ;;
  *) die "unsupported CPU $(uname -m)" ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT INT TERM

version="${SYG_VERSION:-}"
if [ -z "$version" ]; then
  fetch "$API" "$tmp/latest.json" || die "could not find the latest release"
  version="$(sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' "$tmp/latest.json" | head -n 1)"
  [ -n "$version" ] || die "could not read the latest release's version"
fi
version="${version#v}"

archive="syg_${version}_${os}_${arch}.tar.gz"
say "downloading syg $version for $os/$arch"
fetch "$BASE/v$version/$archive" "$tmp/$archive" || die "no release archive $archive for v$version"
fetch "$BASE/v$version/SHA256SUMS" "$tmp/SHA256SUMS" || die "no SHA256SUMS for v$version"

want="$(awk -v f="$archive" '$2 == f || $2 == "*"f { print $1 }' "$tmp/SHA256SUMS")"
[ -n "$want" ] || die "$archive is not listed in SHA256SUMS"
if command -v sha256sum >/dev/null 2>&1; then got="$(sha256sum "$tmp/$archive" | awk '{print $1}')"
else got="$(shasum -a 256 "$tmp/$archive" | awk '{print $1}')"; fi
[ "$got" = "$want" ] || die "checksum mismatch for $archive: expected $want, got $got"
say "checksum verified"

if command -v cosign >/dev/null 2>&1 && fetch "$BASE/v$version/$archive.sigstore.json" "$tmp/bundle.json" 2>/dev/null; then
  cosign verify-blob "$tmp/$archive" --bundle "$tmp/bundle.json" \
    --certificate-identity-regexp "^https://github.com/$REPO/" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1 \
    || die "the signature of $archive does not verify"
  say "signature verified"
fi

tar -xzf "$tmp/$archive" -C "$tmp" syg || die "$archive holds no syg binary"
mkdir -p "$DIR"
mv "$tmp/syg" "$DIR/syg"
chmod 755 "$DIR/syg"
say "installed $DIR/syg"
case ":$PATH:" in
  *":$DIR:"*) ;;
  *) say "$DIR is not on your PATH; add it, e.g. export PATH=\"$DIR:\$PATH\"" ;;
esac
"$DIR/syg" version >&2 || true
