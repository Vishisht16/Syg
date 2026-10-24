#!/usr/bin/env bash
# ci-watch.sh: starts ci.yml for each commit of the source without the commit
# status "ci" (the CI sets it as it starts): the head of the default branch,
# and of each Dependabot branch, which is a pull request's. It never fails: it
# runs every hour, and a failing run sends an email.
set -uo pipefail
here=$(dirname "$0")
if [ -z "${CORE_READ_TOKEN:-}" ]; then
  echo "::warning::the ci environment's CORE_ACCESS_TOKEN is not set: nothing to watch"
  exit 0
fi
# shellcheck source=hack/ci-lib.sh
. "$here/ci-lib.sh"
if ! heads=$(core_git ls-remote "$CORE_URL" HEAD 'refs/heads/dependabot/*'); then
  echo "::warning::could not list the source's branches: is CORE_ACCESS_TOKEN still valid?"
  exit 0
fi
while read -r sha ref; do
  [ -n "$sha" ] || continue
  if ! statuses=$(core_api "https://api.github.com/repos/$CORE/commits/$sha/statuses?per_page=100"); then
    echo "::warning::the token cannot read the source's commit statuses (it needs Commit statuses: read and write), so nothing was started"
    exit 0
  fi
  if jq -e 'any(.[]; .context == "ci")' <<< "$statuses" > /dev/null; then
    continue
  fi
  echo "starting the CI for $sha ($ref)"
  gh workflow run ci.yml --repo "$GITHUB_REPOSITORY" -f ref="$sha" ||
    echo "::warning::could not start the CI for $sha"
done <<< "$heads"
