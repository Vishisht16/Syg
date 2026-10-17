#!/bin/sh
# Tests install.sh against a fake release served from a directory (file://):
# a good install, a checksum mismatch, a version pin, and a missing archive.
#   sh hack/test-install.sh PATH-TO-A-SYG-BINARY
set -eu
bin="$1"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
os=linux; [ "$(uname -s)" = Darwin ] && os=darwin
arch=amd64; case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; esac

release() { # release VERSION: a fake release directory for VERSION
  d="$work/rel/v$1"; mkdir -p "$d/pkg"
  cp "$bin" "$d/pkg/syg"
  (cd "$d/pkg" && tar -czf "../syg_${1}_${os}_${arch}.tar.gz" syg)
  rm -rf "$d/pkg"
  (cd "$d" && if command -v sha256sum >/dev/null; then sha256sum ./*.tar.gz; else shasum -a 256 ./*.tar.gz; fi | sed 's| \./| |' > SHA256SUMS)
}
fail() { echo "test-install: FAIL: $*" >&2; exit 1; }

release 9.9.9
printf '{"tag_name": "v9.9.9"}' > "$work/latest.json"
export SYG_DOWNLOAD_BASE="file://$work/rel" SYG_API="file://$work/latest.json"

SYG_INSTALL_DIR="$work/a" sh "$here/install.sh" 2>"$work/log" || { cat "$work/log"; fail "a good install failed"; }
[ -x "$work/a/syg" ] || fail "no binary installed"
grep -q "checksum verified" "$work/log" || fail "the checksum was not verified"

release 1.2.3
SYG_VERSION=1.2.3 SYG_INSTALL_DIR="$work/b" sh "$here/install.sh" 2>"$work/log" || fail "a pinned version failed"
grep -q "downloading syg 1.2.3" "$work/log" || fail "the pinned version was not the one downloaded"

sed -i.bak 's/^[0-9a-f]\{8\}/00000000/' "$work/rel/v1.2.3/SHA256SUMS"
if SYG_VERSION=1.2.3 SYG_INSTALL_DIR="$work/c" sh "$here/install.sh" 2>"$work/log"; then fail "a checksum mismatch installed"; fi
grep -q "checksum mismatch" "$work/log" || fail "a mismatch was not reported as one"
[ ! -e "$work/c/syg" ] || fail "a mismatched binary was left installed"

if SYG_VERSION=4.5.6 SYG_INSTALL_DIR="$work/d" sh "$here/install.sh" 2>"$work/log"; then fail "a missing release installed"; fi
grep -q "no release archive" "$work/log" || fail "a missing release was not reported"

echo "test-install: PASS: install, version pin, checksum mismatch, missing release"
