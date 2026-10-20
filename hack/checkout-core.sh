#!/usr/bin/env bash
# The private source at REF, in core/, for the release and docs workflows:
#
#   CORE_READ_TOKEN=... bash hack/checkout-core.sh REF [tags]
#
# REF is a branch, a tag (refs/tags/v1.0.0), a commit, or HEAD for the default
# branch. Only that commit is fetched, unless "tags" asks for its history and
# the tags too (the docs show the latest release tag). Quietly: git's
# detached-HEAD message would print the commit's subject in the public log.
# The token is used for this fetch alone, and not kept.
set -euo pipefail
ref=${1:?usage: checkout-core.sh REF [tags]}
: "${CORE_READ_TOKEN:?the CORE_READ_TOKEN secret is not set}"
printf '%s\n' "$ref" | grep -Eqx '[A-Za-z0-9][A-Za-z0-9_./+-]*' \
  || { echo "::error::$ref is not a branch, tag or commit"; exit 1; }
basic=$(printf 'x-access-token:%s' "$CORE_READ_TOKEN" | base64 | tr -d '\n')
echo "::add-mask::$basic"
what=(--depth 1 --no-tags)
if [ "${2:-}" = tags ]; then what=(--tags); fi
git -c init.defaultBranch=main init -q core
git -C core -c "http.extraheader=AUTHORIZATION: basic $basic" \
  fetch -q "${what[@]}" -- https://github.com/Vishisht16/Syg-Core.git "$ref"
git -C core -c advice.detachedHead=false checkout -q FETCH_HEAD
