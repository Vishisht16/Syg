#!/usr/bin/env bash
# A release's files, checked the way the documentation tells users to check
# them: by release.yml's smoke job before the release is published, and by
# rehearse.yml for one already out.
#
#   GH_TOKEN=... bash hack/check-release.sh DIR VERSION [DOCS]
#
# DIR holds the release's files. DOCS is a directory of the documentation's
# Markdown: every verification command it shows must name the identity this
# script checks. Needs cosign 3, gh, jq and sudo (for a namespace with no
# network). Releases up to 1.0.0-rc.3 were signed by release.yml and carry
# fewer files; the checks of what they lack are skipped for them.
set -euo pipefail
dir=$(cd "${1:?usage: check-release.sh DIR VERSION [DOCS]}" && pwd)
version=${2:?usage: check-release.sh DIR VERSION [DOCS]}
docs=${3:-}
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "::error::$*"; exit 1; }
ok() { echo "ok: $*"; }

repo=Vishisht16/Syg
workflow=build.yml strict=1
case "$version" in 1.0.0-rc.[123]) workflow=release.yml strict="" ;; esac
signer="$repo/.github/workflows/$workflow"
identity="(?i)^https://github\\.com/vishisht16/syg/\\.github/workflows/${workflow%.yml}\\.yml@refs/(heads/main|tags/v.+)\$"
issuer=https://token.actions.githubusercontent.com
archive="syg_${version}_linux_amd64.tar.gz"

# Every file the checksums name is here, and is what they say. (Up to rc.3,
# SHA256SUMS named the packages with the "~" GitHub renames to ".".)
missing=--strict; [ -z "$strict" ] && missing=--ignore-missing
(cd "$dir" && sha256sum --check --quiet "$missing" SHA256SUMS) || fail "SHA256SUMS does not check"
ok "SHA256SUMS: $(wc -l < "$dir/SHA256SUMS") files"

# What every archive holds.
want="README.md EULA.md PRIVACY.md"
[ -n "$strict" ] && want="$want THIRD_PARTY_NOTICES.txt completions/syg.bash completions/_syg completions/syg.fish completions/syg.ps1 man/syg.1"
for a in "$dir"/syg_"$version"_*.tar.gz "$dir"/syg_"$version"_*.zip; do
  case "$a" in *.zip) list=$(unzip -Z1 "$a") ;; *) list=$(tar tzf "$a") ;; esac
  for f in $want; do
    grep -qx "$f" <<<"$list" || fail "$f is not in $(basename "$a")"
  done
done
ok "each archive holds $want"

# install.sh, as a user runs it, with cosign 3 on the PATH: the checksum and
# the signature, from a mirror of the release.
mkdir -p "$work/mirror" "$work/bin"
ln -s "$dir" "$work/mirror/v$version"
SYG_DOWNLOAD_BASE="file://$work/mirror" SYG_VERSION="$version" SYG_INSTALL_DIR="$work/bin" \
  sh "$here/install.sh" 2> "$work/install.log" || { cat "$work/install.log"; fail "install.sh failed"; }
grep -q "checksum verified" "$work/install.log" || fail "install.sh did not check the checksum"
grep -q "signature verified" "$work/install.log" || { cat "$work/install.log"; fail "install.sh did not check the signature"; }
grep -qF "$identity" "$here/install.sh" || fail "install.sh does not name $identity"
ok "install.sh: checksum and signature verified"
syg=$work/bin/syg

# The signature of SHA256SUMS, and the provenance of an archive and a package.
cosign verify-blob "$dir/SHA256SUMS" --bundle "$dir/SHA256SUMS.sigstore.json" \
  --certificate-identity-regexp "$identity" --certificate-oidc-issuer "$issuer" > /dev/null 2>&1 \
  || fail "the signature of SHA256SUMS does not verify against $identity"
ok "SHA256SUMS signed by $workflow"
deb=$(find "$dir" -maxdepth 1 -name 'syg_*_amd64.deb' -printf '%f\n' | head -n 1)
[ -n "$deb" ] || fail "no amd64 .deb in $dir"
for f in "$archive" "$deb"; do
  gh attestation verify "$dir/$f" --repo "$repo" --signer-workflow "$signer" > /dev/null \
    || fail "the provenance of $f does not verify against $signer"
done
ok "provenance of $archive and $deb, signed by $workflow"

if [ -n "$strict" ]; then
  # Offline, from the release's .intoto.jsonl and a trusted root fetched
  # here: in a namespace with no network at all.
  gh attestation trusted-root > "$work/trusted_root.jsonl"
  sudo unshare --net -- env -u GH_TOKEN HOME="$work" PATH="$PATH" \
    gh attestation verify "$dir/$archive" --repo "$repo" --signer-workflow "$signer" \
    --bundle "$dir/syg_$version.intoto.jsonl" --custom-trusted-root "$work/trusted_root.jsonl" > /dev/null \
    || fail "$archive does not verify offline from syg_$version.intoto.jsonl"
  ok "provenance verified offline, from syg_$version.intoto.jsonl"

  # The source statement: which tag and commit the archive was built from.
  gh attestation verify "$dir/$archive" --repo "$repo" --signer-workflow "$signer" \
    --predicate-type https://syg.vishisht.tech/attestations/source/v1 --format json > "$work/source.json" \
    || fail "$archive has no source statement signed by $workflow"
  jq -e --arg tag "v$version" '.[0].verificationResult.statement.predicate | .tag == $tag and (.commit | test("^[0-9a-f]{40}$"))' \
    "$work/source.json" > /dev/null || fail "the source statement does not name v$version and a commit"
  ok "source statement: $(jq -r '.[0].verificationResult.statement.predicate | .tag + " at " + .commit' "$work/source.json")"

  # Two SBOMs per archive.
  for a in "$dir"/syg_"$version"_*.tar.gz "$dir"/syg_"$version"_*.zip; do
    jq -e '.spdxVersion' "$a.spdx.json" > /dev/null || fail "$(basename "$a").spdx.json is not SPDX"
    jq -e '.bomFormat == "CycloneDX"' "$a.cdx.json" > /dev/null || fail "$(basename "$a").cdx.json is not CycloneDX"
  done
  ok "SPDX and CycloneDX SBOMs for each archive"

  # The JSON output names its schema; the bash completion loads.
  "$syg" init "$work/m" --service api > /dev/null 2>&1
  "$syg" check --format json "$work/m" | jq -e '."$schema" == "https://syg.vishisht.tech/schemas/diagnostics-v1.json"' > /dev/null \
    || fail "--format json does not name its schema"
  bash -c 'source <("$1" completion bash) && complete -p syg' _ "$syg" > /dev/null || fail "the bash completion does not load"
  ok "--format json names its schema; the bash completion loads"
fi

# With no network at all, and statistics on, as in CI and on a laptop:
# check, build and version exit as they would, and soon.
[ -d "$work/m" ] || "$syg" init "$work/m" --service api > /dev/null 2>&1
for ci in true ""; do
  for args in "check $work/m" "build $work/m -o $work/out" "version"; do
    start=$(date +%s%N)
    # shellcheck disable=SC2086 # the arguments are words
    sudo unshare --net -- env -i PATH=/usr/bin:/bin HOME="$work/home" GITHUB_ACTIONS="$ci" \
      SYG_CONFIG_DIR="$work/config" "$syg" $args > /dev/null 2>&1 || fail "syg $args failed with no network (CI: ${ci:-no})"
    ms=$(( ($(date +%s%N) - start) / 1000000 ))
    [ "$ms" -lt 3000 ] || fail "syg $args took ${ms} ms with no network (CI: ${ci:-no})"
  done
done
code=0
sudo unshare --net -- env -i PATH=/usr/bin:/bin HOME="$work/home" "$syg" schema vendor --from https://example.com/crds.yaml "$work/m" > /dev/null 2>&1 || code=$?
[ "$code" = 2 ] || fail "schema vendor with no network exited $code, not 2"
ok "with no network: check, build and version as usual, schema vendor exits 2"

# Every verification command the documentation shows names this identity.
if [ -n "$docs" ] && [ -n "$strict" ]; then
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *--certificate-identity-regexp*) got=$(sed -n "s/.*--certificate-identity-regexp '\\([^']*\\)'.*/\\1/p" <<<"$line") ; [ "$got" = "$identity" ] || fail "the documentation names the identity $got: $line" ;;
      *--signer-workflow*) got=$(sed -n 's/.*--signer-workflow \([^ ]*\).*/\1/p' <<<"$line") ; [ "$got" = "$signer" ] || fail "the documentation names the signer $got: $line" ;;
    esac
  done < <(cat "$docs"/*.md "$here/SECURITY.md" | grep -E -e "--certificate-identity-regexp '|--signer-workflow ")
  [ "$n" -ge 6 ] || fail "only $n verification commands found in the documentation"
  ok "the documentation's $n verification commands name $workflow"
fi
echo "release $version: every check passed"
