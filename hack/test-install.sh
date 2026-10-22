#!/bin/sh
# Tests install.sh against a fake release served from a directory (file://): a
# good install, a version pin, a checksum mismatch, a missing archive, no final
# release yet, and the signature check with a stand-in cosign (older than the
# script checks with; a signature that verifies; one that does not; none at
# all).
#   sh hack/test-install.sh PATH-TO-A-SYG-BINARY
set -eu
bin="$1"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
os=linux; [ "$(uname -s)" = Darwin ] && os=darwin
arch=amd64; case "$(uname -m)" in arm64|aarch64) arch=arm64 ;; esac

release() { # release VERSION [signed]: a fake release directory for VERSION
  d="$work/rel/v$1"; mkdir -p "$d/pkg"
  cp "$bin" "$d/pkg/syg"
  (cd "$d/pkg" && tar -czf "../syg_${1}_${os}_${arch}.tar.gz" syg)
  rm -rf "$d/pkg"
  (cd "$d" && if command -v sha256sum >/dev/null; then sha256sum ./*.tar.gz; else shasum -a 256 ./*.tar.gz; fi | sed 's| \./| |' > SHA256SUMS)
  if [ "${2:-}" = signed ]; then echo '{}' > "$d/syg_${1}_${os}_${arch}.tar.gz.sigstore.json"; fi
}
fail() { echo "test-install: FAIL: $*" >&2; exit 1; }

# A stand-in cosign, first on PATH, whatever the machine has: the test chooses
# its version and whether a signature verifies.
mkdir -p "$work/stub"
PATH="$work/stub:$PATH"
cosign_stub() { # cosign_stub MAJOR EXIT: cosign MAJOR.x, verify-blob exits EXIT, its arguments in cosign.args
  # shellcheck disable=SC2016 # the $1 and $@ are the stub's own
  printf '#!/bin/sh\ncase "$1" in version) echo "GitVersion:    v%s.0.1" ;; verify-blob) echo "$@" > "%s/cosign.args"; exit %s ;; esac\n' "$1" "$work" "$2" > "$work/stub/cosign"
  chmod +x "$work/stub/cosign"
}
cosign_stub 2 1

release 9.9.9
printf '{"tag_name": "v9.9.9"}' > "$work/latest.json"
export SYG_DOWNLOAD_BASE="file://$work/rel" SYG_API="file://$work/latest.json"

SYG_INSTALL_DIR="$work/a" sh "$here/install.sh" 2>"$work/log" || { cat "$work/log"; fail "a good install failed"; }
[ -x "$work/a/syg" ] || fail "no binary installed"
grep -q "checksum verified" "$work/log" || fail "the checksum was not verified"
grep -q "signature not checked" "$work/log" || fail "cosign 2 was not reported as too old to check the signature"
for f in "$work/a"/.syg.new.*; do [ ! -e "$f" ] || fail "a temporary binary was left behind: $f"; done

release 1.2.3 signed
SYG_VERSION=1.2.3 SYG_INSTALL_DIR="$work/b" sh "$here/install.sh" 2>"$work/log" || fail "a pinned version failed"
grep -q "downloading syg 1.2.3" "$work/log" || fail "the pinned version was not the one downloaded"

cosign_stub 3 0
SYG_VERSION=1.2.3 SYG_INSTALL_DIR="$work/e" sh "$here/install.sh" 2>"$work/log" || { cat "$work/log"; fail "a signed release failed"; }
grep -q "signature verified" "$work/log" || fail "cosign 3 did not check the signature"
grep -qF 'workflows/build\.yml@' "$work/cosign.args" || fail "the signature was not checked against build.yml: $(cat "$work/cosign.args")"

# A release candidate is signed by build.yml too.
release 1.0.0-rc.4 signed
SYG_VERSION=1.0.0-rc.4 SYG_INSTALL_DIR="$work/e4" sh "$here/install.sh" 2>"$work/log" || { cat "$work/log"; fail "rc.4 failed"; }
grep -qF 'workflows/build\.yml@' "$work/cosign.args" || fail "rc.4's signature was not checked against build.yml: $(cat "$work/cosign.args")"

cosign_stub 3 1
if SYG_VERSION=1.2.3 SYG_INSTALL_DIR="$work/f" sh "$here/install.sh" 2>"$work/log"; then fail "a bad signature installed"; fi
grep -q "does not verify" "$work/log" || fail "a bad signature was not reported as one"
[ ! -e "$work/f/syg" ] || fail "a binary with a bad signature was installed"

if SYG_VERSION=9.9.9 SYG_INSTALL_DIR="$work/g" sh "$here/install.sh" 2>"$work/log"; then fail "an unsigned release installed under cosign 3"; fi
grep -q "no signature" "$work/log" || fail "a missing signature was not reported"

cosign_stub 2 1
sed -i.bak 's/^[0-9a-f]\{8\}/00000000/' "$work/rel/v1.2.3/SHA256SUMS"
if SYG_VERSION=1.2.3 SYG_INSTALL_DIR="$work/c" sh "$here/install.sh" 2>"$work/log"; then fail "a checksum mismatch installed"; fi
grep -q "checksum mismatch" "$work/log" || fail "a mismatch was not reported as one"
[ ! -e "$work/c/syg" ] || fail "a mismatched binary was left installed"

if SYG_VERSION=4.5.6 SYG_INSTALL_DIR="$work/d" sh "$here/install.sh" 2>"$work/log"; then fail "a missing release installed"; fi
grep -q "no release archive" "$work/log" || fail "a missing release was not reported"

# Only release candidates: GitHub's latest release is none, and the installer
# says how to install a candidate instead.
printf '{"message": "Not Found"}' > "$work/none.json"
if SYG_API="file://$work/none.json" SYG_INSTALL_DIR="$work/h" sh "$here/install.sh" 2>"$work/log"; then fail "an install with no release succeeded"; fi
if ! grep -q "no final release yet.*SYG_VERSION" "$work/log"; then cat "$work/log"; fail "no release was not explained"; fi

echo "test-install: PASS: install, version pin, signature (old cosign, verified, bad, missing), checksum mismatch, missing release, no final release yet"
