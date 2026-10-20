#!/usr/bin/env bash
# A final release's package-manager manifests, rendered from its SHA256SUMS
# and pushed: by release.yml, to main, and by rehearse.yml, to a branch that is
# deleted again at once, since what it rehearses is the push.
#
#   bash hack/channels.sh scoop VERSION SHA256SUMS BRANCH
#   TAP_TOKEN=... bash hack/channels.sh brew VERSION SHA256SUMS BRANCH
#
# scoop: bucket/syg.json in this repository, with the checkout's credentials.
# brew: Formula/syg.rb in vishisht16/homebrew-tap, cloned to tap/, with
# TAP_TOKEN, which is used for that repository alone, and not kept.
set -euo pipefail
usage="usage: channels.sh scoop|brew VERSION SHA256SUMS BRANCH"
kind=${1:?$usage} version=${2:?$usage} sums=${3:?$usage} branch=${4:?$usage}

# commit MESSAGE FILE...: commit the files, as the release, if they changed.
commit() {
  local message=$1
  shift
  git config user.name "syg-release"
  git config user.email "syg-release@users.noreply.github.com"
  git add "$@"
  git diff --cached --quiet || git commit -q -m "$message"
}

# push [GIT-OPTION...]: HEAD to the branch. Main is pushed to by the docs job at
# the same time: rebase onto it and retry.
push() {
  if [ "$branch" != main ]; then
    git "$@" push -q origin "HEAD:refs/heads/$branch"
    git "$@" push -q origin --delete "$branch"
    echo "pushed to $branch, and deleted it"
    return
  fi
  for _ in 1 2 3; do
    if git "$@" pull --rebase -q origin main && git "$@" push -q origin HEAD:main; then return 0; fi
    sleep 5
  done
  return 1
}

case $kind in
  scoop)
    python3 hack/render.py scoop "$version" "$sums" > bucket/syg.json
    commit "Scoop: syg $version" bucket/syg.json
    push
    ;;
  brew)
    : "${TAP_TOKEN:?the TAP_TOKEN secret is not set}"
    basic=$(printf 'x-access-token:%s' "$TAP_TOKEN" | base64 | tr -d '\n')
    echo "::add-mask::$basic"
    auth=(-c "http.extraheader=AUTHORIZATION: basic $basic")
    git "${auth[@]}" clone -q https://github.com/vishisht16/homebrew-tap.git tap
    mkdir -p tap/Formula
    python3 hack/render.py brew "$version" "$sums" > tap/Formula/syg.rb
    cd tap
    commit "syg $version" Formula/syg.rb
    push "${auth[@]}"
    ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac
