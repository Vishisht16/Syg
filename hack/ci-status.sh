#!/usr/bin/env bash
# ci-status.sh SHA pending | ci-status.sh SHA NEEDS: sets the commit status
# "ci" (or STATUS_CONTEXT, for a run on another image) on SHA in the source,
# linking this run; a pull request there shows it. NEEDS is the jobs'
# results, toJSON(needs): success when every job passed or was skipped,
# failure when one failed, error when one was cancelled. Without "Commit
# statuses: read and write" on the source, the token earns a warning.
set -euo pipefail
sha=${1:?usage: ci-status.sh SHA pending|NEEDS}
# shellcheck source=hack/ci-lib.sh
. "$(dirname "$0")/ci-lib.sh"
if [ "${2:?usage: ci-status.sh SHA pending|NEEDS}" = pending ]; then
  state=pending desc="running"
else
  failed=$(jq -r '[to_entries[] | select(.value.result == "failure") | .key] | join(", ")' <<< "$2")
  cancelled=$(jq -r '[to_entries[] | select(.value.result == "cancelled") | .key] | join(", ")' <<< "$2")
  if [ -n "$failed" ]; then state=failure desc="failed: $failed"
  elif [ -n "$cancelled" ]; then state=error desc="cancelled: $cancelled"
  else state=success desc="every job passed"
  fi
fi
context=${STATUS_CONTEXT:-ci}
body=$(jq -n --arg state "$state" --arg desc "$desc" \
  --arg url "$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID" \
  --arg context "$context" \
  '{state: $state, description: $desc, target_url: $url, context: $context}')
if core_api -X POST "https://api.github.com/repos/$CORE/statuses/$sha" -d "$body" > /dev/null; then
  echo "$context: $state ($desc)"
else
  echo "::warning::the commit status was not set: the token needs Commit statuses: read and write on the source"
fi
