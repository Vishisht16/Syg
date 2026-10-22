#!/usr/bin/env bash
# The image a release publishes, checked as a user runs it: by release.yml
# before the release is out, and by rehearse.yml.
#
#   GH_TOKEN=... bash hack/check-image.sh IMAGE@DIGEST VERSION WORKFLOW [DIST]
#
# Its signature and attestations name WORKFLOW (build.yml for a release), and
# it holds linux/amd64 and linux/arm64. On this machine's platform, which is
# one of the two, it runs as user 65532, is syg VERSION, and checks and
# builds a module with no capabilities and a read-only file system. With
# DIST, a directory that holds the release's Linux archives, its binary is
# the archive's, byte for byte. Run it on amd64 and on arm64; it emulates
# neither. Needs docker, jq, cosign 3 and gh.
set -euo pipefail
usage="usage: check-image.sh IMAGE@DIGEST VERSION WORKFLOW [DIST]"
image=${1:?$usage}
version=${2:?$usage}
workflow=${3:?$usage}
dist=${4:-}
fail() { echo "::error::$*"; exit 1; }
ok() { echo "ok: $*"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) fail "the image has no platform for $(uname -m)" ;;
esac
platform=linux/$arch

identity="(?i)^https://github\\.com/vishisht16/syg/\\.github/workflows/${workflow%.yml}\\.yml@refs/(heads/main|tags/v.+)\$"
signer="Vishisht16/Syg/.github/workflows/$workflow"
cosign verify "$image" --certificate-identity-regexp "$identity" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com > /dev/null 2>&1 \
  || fail "the image's signature does not verify against $identity"
ok "signed by $workflow"
gh attestation verify "oci://$image" --repo Vishisht16/Syg --signer-workflow "$signer" > /dev/null \
  || fail "the image's provenance does not verify against $signer"
gh attestation verify "oci://$image" --repo Vishisht16/Syg --signer-workflow "$signer" \
  --predicate-type https://spdx.dev/Document/v2.3 > /dev/null \
  || fail "the image's SBOM does not verify against $signer"
ok "provenance and SBOM attested by $workflow"

platforms=$(docker manifest inspect "$image" | jq -r '[.manifests[].platform | .os + "/" + .architecture] | sort | join(" ")')
[ "$platforms" = "linux/amd64 linux/arm64" ] || fail "the image holds ${platforms:-no platform}, not linux/amd64 and linux/arm64"
# Docker's classic image store keeps one platform per digest: one pulled
# before, for another platform, would refuse this pull.
docker image rm -f "$image" > /dev/null 2>&1 || true
docker pull -q --platform "$platform" "$image" > /dev/null
got=$(docker inspect --format '{{.Os}}/{{.Architecture}} {{.Config.User}}' "$image")
[ "$got" = "$platform 65532:65532" ] || fail "the image pulled is $got, not $platform running as 65532:65532"
docker run --rm -e SYG_TELEMETRY=off "$image" version | grep -q "^syg $version " \
  || fail "the $platform image is not syg $version"
ok "linux/amd64 and linux/arm64; on $platform, user 65532:65532 and syg $version"

# As the documentation runs it: init and build as the directory's owner,
# check as the image's own user, from a read-only mount.
run=(docker run --rm --read-only --cap-drop ALL -e SYG_TELEMETRY=off)
mkdir "$work/src"
chmod 755 "$work/src"
"${run[@]}" --user "$(id -u):$(id -g)" -v "$work/src:/src" "$image" init app --service api > /dev/null 2>&1 \
  || fail "init failed in the image"
"${run[@]}" -v "$work/src:/src:ro" "$image" check app > /dev/null 2>&1 || fail "check failed in the image"
"${run[@]}" --user "$(id -u):$(id -g)" -v "$work/src:/src" "$image" build app -o out > /dev/null 2>&1 \
  || fail "build failed in the image"
[ -n "$(find "$work/src/out" -name '*.yaml' -print -quit)" ] || fail "build wrote no manifests"
ok "init, check and build, read-only, with no capabilities"

# What comes with the binary.
docs="EULA.md PRIVACY.md THIRD_PARTY_NOTICES.txt"
files=/usr/local/bin/syg
for f in $docs; do files="$files /usr/share/doc/syg/$f"; done
cid=$(docker create "$image")
mkdir "$work/image"
for f in $files; do
  if ! docker cp -q "$cid:$f" "$work/image/" || [ ! -s "$work/image/$(basename "$f")" ]; then
    docker rm -f "$cid" > /dev/null
    fail "$f is not in the image"
  fi
done
docker rm -f "$cid" > /dev/null
ok "$docs in /usr/share/doc/syg"
if [ -n "$dist" ]; then
  mkdir "$work/archive"
  tar xzf "$dist/syg_${version}_linux_${arch}.tar.gz" -C "$work/archive" syg
  cmp -s "$work/archive/syg" "$work/image/syg" || fail "the $platform image's syg is not the one in syg_${version}_linux_${arch}.tar.gz"
  ok "the $platform image's syg is the archive's, byte for byte"
fi
echo "image $image on $platform: every check passed"
