#!/bin/sh
# Installs syg: https://syg.vishisht.tech/install.html
#
#   curl -fsSL https://syg.vishisht.tech/install.sh | sh
#
# Downloads the release archive for this OS and CPU, checks it against the
# release's SHA256SUMS (and its cosign signature, when cosign 3 or newer is
# installed), and puts syg in $SYG_INSTALL_DIR (default ~/.local/bin). No sudo.
#
#   SYG_VERSION=1.0.0       a version instead of the latest
#   SYG_INSTALL_DIR=DIR     where to put the binary
#
# Everything runs from main, on the last line, so a download cut short runs
# nothing.
set -eu

REPO="vishisht16/syg"
BASE="${SYG_DOWNLOAD_BASE:-https://github.com/$REPO/releases/download}"
DIR="${SYG_INSTALL_DIR:-$HOME/.local/bin}"
# The certificate a release's signature must carry: this repository's release
# workflow, and nothing else.
IDENTITY='(?i)^https://github\.com/vishisht16/syg/\.github/workflows/release\.yml@refs/(heads/main|tags/v.+)$'

say() { printf 'syg-install: %s\n' "$*" >&2; }
die() { say "$*"; exit 1; }

fetch() { # fetch URL FILE
  if command -v curl >/dev/null 2>&1; then curl -fsSL -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then wget -q -O "$2" "$1"
  else die "needs curl or wget"; fi
}

# latest prints the newest release's version. It reads where
# github.com/REPO/releases/latest redirects to, which, unlike GitHub's API,
# has no hourly limit per address; SYG_API names an API response instead (the
# tests use one).
latest() {
  if [ -n "${SYG_API:-}" ]; then
    fetch "$SYG_API" "$tmp/latest.json" || return 1
    sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' "$tmp/latest.json" | head -n 1
    return 0
  fi
  url="https://github.com/$REPO/releases/latest"
  if command -v curl >/dev/null 2>&1; then
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$url")" || return 1
  else
    url="$(wget -S --spider "$url" 2>&1 | sed -n 's/^ *[Ll]ocation: *//p' | tail -n 1 | tr -d '\r')"
  fi
  case "$url" in */releases/tag/v*) printf '%s\n' "${url##*/releases/tag/v}" ;; esac
}

# verify_signature checks the archive's cosign signature when cosign 3 or newer
# is installed. Releases are signed with cosign 3, whose bundles older versions
# cannot read; without it, the checksum stands alone, as it does without cosign.
verify_signature() {
  command -v cosign >/dev/null 2>&1 || return 0
  major="$(cosign version 2>/dev/null | sed -n 's/^GitVersion: *v\{0,1\}\([0-9][0-9]*\).*/\1/p' | head -n 1)"
  if [ -z "$major" ] || [ "$major" -lt 3 ]; then
    say "the installed cosign cannot read this release's signature (cosign 3 or newer can): signature not checked"
    return 0
  fi
  fetch "$BASE/v$version/$archive.sigstore.json" "$tmp/bundle.json" || die "no signature for $archive"
  cosign verify-blob "$tmp/$archive" --bundle "$tmp/bundle.json" \
    --certificate-identity-regexp "$IDENTITY" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com >/dev/null 2>&1 \
    || die "the signature of $archive does not verify"
  say "signature verified"
}

main() {
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
  new="$DIR/.syg.new.$$"
  trap 'rm -rf "$tmp"; rm -f "$new"' EXIT INT TERM

  version="${SYG_VERSION:-}"
  if [ -z "$version" ]; then
    version="$(latest)" || version=""
    [ -n "$version" ] || die "could not find the latest release"
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

  verify_signature

  tar -xzf "$tmp/$archive" -C "$tmp" syg || die "$archive holds no syg binary"
  mkdir -p "$DIR"
  # A copy beside the old binary, then a rename: syg is never half written.
  cp "$tmp/syg" "$new"
  chmod 755 "$new"
  mv -f "$new" "$DIR/syg"
  say "installed $DIR/syg"
  case ":$PATH:" in
    *":$DIR:"*) ;;
    *) say "$DIR is not on your PATH; add it, e.g. export PATH=\"$DIR:\$PATH\"" ;;
  esac
  # Installing is not using Syg: this check sends no usage statistics.
  SYG_TELEMETRY=off "$DIR/syg" version >&2 || true
}

main "$@"
