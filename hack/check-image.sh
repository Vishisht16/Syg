#!/usr/bin/env bash
# The image a release publishes, checked as a user runs it: by release.yml
# before the release is out, and by rehearse.yml.
#
#   GH_TOKEN=... bash hack/check-image.sh IMAGE@DIGEST VERSION WORKFLOW
#
# Its signature and attestations name WORKFLOW (build.yml for a release), it
# runs as user 65532 on both platforms, and it checks and builds a module
# with no capabilities and a read-only file system. Needs docker, QEMU for
# arm64, cosign 3 and gh.
set -euo pipefail
image=${1:?usage: check-image.sh IMAGE@DIGEST VERSION WORKFLOW}
version=${2:?usage: check-image.sh IMAGE@DIGEST VERSION WORKFLOW}
workflow=${3:?usage: check-image.sh IMAGE@DIGEST VERSION WORKFLOW}
fail() { echo "::error::$*"; exit 1; }
ok() { echo "ok: $*"; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

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

docker pull -q "$image" > /dev/null
user=$(docker inspect --format '{{.Config.User}}' "$image")
[ "$user" = 65532:65532 ] || fail "the image runs as ${user:-root}, not 65532:65532"
for p in linux/amd64 linux/arm64; do
  docker run --rm --platform "$p" -e SYG_TELEMETRY=off "$image" version | grep -q "^syg $version " \
    || fail "the $p image is not syg $version"
done
ok "user 65532:65532, syg $version on amd64 and arm64"

# As the documentation runs it: init and build as the directory's owner,
# check as the image's own user, from a read-only mount.
run=(docker run --rm --read-only --cap-drop ALL -e SYG_TELEMETRY=off)
chmod 755 "$work"
"${run[@]}" --user "$(id -u):$(id -g)" -v "$work:/src" "$image" init app --service api > /dev/null 2>&1 \
  || fail "init failed in the image"
"${run[@]}" -v "$work:/src:ro" "$image" check app > /dev/null 2>&1 || fail "check failed in the image"
"${run[@]}" --user "$(id -u):$(id -g)" -v "$work:/src" "$image" build app -o out > /dev/null 2>&1 \
  || fail "build failed in the image"
[ -n "$(find "$work/out" -name '*.yaml' -print -quit)" ] || fail "build wrote no manifests"
ok "init, check and build, read-only, with no capabilities"

# The notices come with every release from rc.4 on.
docs="EULA.md PRIVACY.md THIRD_PARTY_NOTICES.txt"
case "$version" in 1.0.0-rc.[123]) docs="EULA.md PRIVACY.md" ;; esac
cid=$(docker create "$image")
for f in $docs; do
  if ! docker cp -q "$cid:/usr/share/doc/syg/$f" "$work/$f" || [ ! -s "$work/$f" ]; then
    docker rm -f "$cid" > /dev/null
    fail "/usr/share/doc/syg/$f is not in the image"
  fi
done
docker rm -f "$cid" > /dev/null
ok "$docs in /usr/share/doc/syg"
echo "image $image: every check passed"
