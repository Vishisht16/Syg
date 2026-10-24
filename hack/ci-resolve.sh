#!/usr/bin/env bash
# ci-resolve.sh REF: the commit a CI run tests, so that a push during the run
# changes nothing. Checks the source out at REF (a branch, tag or commit, or
# HEAD for its default branch), sets the commit status there to pending, and
# writes the job's output, sha.
set -euo pipefail
here=$(dirname "$0")
bash "$here/checkout-core.sh" "${1:?usage: ci-resolve.sh REF}"
sha=$(git -C core rev-parse HEAD)
echo "testing $sha"
echo "sha=$sha" >> "$GITHUB_OUTPUT"
bash "$here/ci-status.sh" "$sha" pending
