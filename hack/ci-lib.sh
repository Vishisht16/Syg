# shellcheck shell=bash
# ci-lib.sh, sourced by the CI's scripts: the private source's repository, and
# git and GitHub's API for it, with CORE_READ_TOKEN. The token is passed per
# command, never stored, and masked in the log in each form it is sent in.
CORE=Vishisht16/Syg-Core
# shellcheck disable=SC2034  # used by the scripts that source this
CORE_URL=https://github.com/$CORE.git
: "${CORE_READ_TOKEN:?the CORE_ACCESS_TOKEN secret is not set}"
core_basic=$(printf 'x-access-token:%s' "$CORE_READ_TOKEN" | base64 | tr -d '\n')
echo "::add-mask::$core_basic"
core_git() { git -c "http.extraheader=AUTHORIZATION: basic $core_basic" "$@"; }
core_api() {
  curl -fsS -H "Authorization: Bearer $CORE_READ_TOKEN" -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}
