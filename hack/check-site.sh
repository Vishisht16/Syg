#!/usr/bin/env bash
# The site at BASE serves the docs of this repository's commit COMMIT, or of a
# later one, and every rule's address finds its section there:
#
#   bash hack/check-site.sh https://syg.vishisht.tech built/docs-urls.txt COMMIT
#
# Vishisht16/syg-site builds the site from docs/ here, and names the commit it
# built from in BASE/build.json. Run it in a checkout of this repository with
# its history. DOCS-URLS holds the docs_url of every rule, which each finding
# and `syg explain` print; each must find its section by id. The pages the
# binary and the installers name are asked for too, the install scripts
# compared with those of the commit served, and security.txt must name a
# contact and not have expired. A deploy and Pages's CDN take some minutes,
# so each attempt asks with a query of its own, and a failure is retried for
# 25 minutes (CHECK_SITE_ATTEMPTS, 30 s apart) before it fails the run.
set -euo pipefail
attempts=${CHECK_SITE_ATTEMPTS:-50}
base=${1:?usage: check-site.sh BASE DOCS-URLS COMMIT}
urls=${2:?usage: check-site.sh BASE DOCS-URLS COMMIT}
commit=${3:?usage: check-site.sh BASE DOCS-URLS COMMIT}
base=${base%/}
if [ ! -s "$urls" ]; then
  echo "::error::$urls names no rules"
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# get URL FILE: the body at URL into FILE; prints the status, 000 for none.
get() { curl -sS --max-time 30 -o "$2" -w '%{http_code}' "$1" 2>/dev/null || echo 000; }

# check ATTEMPT: every problem, one per line, on stdout; none is a pass.
check() {
  local q="?check=${GITHUB_RUN_ID:-local}-$1" url page id p code served
  code=$(get "$base/build.json$q" "$work/build.json")
  served=$(sed -n 's/.*"syg":"\([0-9a-f]\{40\}\)".*/\1/p' "$work/build.json" 2>/dev/null || true)
  if [ "$code" != 200 ] || [ -z "$served" ]; then
    echo "$code, names no commit: $base/build.json"
    return
  fi
  git cat-file -e "$served^{commit}" 2>/dev/null || git fetch -q origin main 2>/dev/null || true
  if [ "$served" != "$commit" ] && ! git merge-base --is-ancestor "$commit" "$served" 2>/dev/null; then
    echo "the docs of $served, not of $commit or later: $base"
    return
  fi
  while IFS= read -r url; do
    page=${url%%#*}
    id=${url#*#}
    case "$page" in "$base"/*) ;; *) echo "not on the site: $url"; continue ;; esac
    code=$(get "$page$q" "$work/got")
    if [ "$code" != 200 ]; then
      echo "$code: $page"
    elif [ "$id" != "$url" ] && ! grep -aqF "id=\"$id\"" "$work/got"; then
      echo "no section: $url"
    fi
  done < "$urls"
  for p in install privacy eula; do
    code=$(get "$base/$p$q" "$work/got")
    [ "$code" = 200 ] || echo "$code: $base/$p"
  done
  for p in install.sh install.ps1; do
    code=$(get "$base/$p$q" "$work/got")
    if [ "$code" != 200 ]; then
      echo "$code: $base/$p"
    elif ! git show "$served:$p" | cmp -s "$work/got" -; then
      echo "not $p of $served: $base/$p"
    fi
  done
  code=$(get "$base/.well-known/security.txt$q" "$work/security.txt")
  if [ "$code" != 200 ]; then
    echo "$code: $base/.well-known/security.txt"
  elif ! grep -q '^Contact: https://' "$work/security.txt"; then
    echo "names no Contact: $base/.well-known/security.txt"
  else
    expires=$(sed -n 's/^Expires: //p' "$work/security.txt")
    if [ -z "$expires" ] || [ "$(date -u -d "$expires" +%s 2>/dev/null || echo 0)" -le "$(date -u +%s)" ]; then
      echo "expired, or no Expires: $base/.well-known/security.txt"
    fi
  fi
}

rules=$(grep -c . "$urls")
for attempt in $(seq 1 "$attempts"); do
  check "$attempt" > "$work/problems"
  if [ ! -s "$work/problems" ]; then
    echo "$base serves the docs of $commit or later, with $rules rules' sections"
    exit 0
  fi
  if [ "$attempt" -lt "$attempts" ]; then sleep 30; fi
done
echo "::error::$base does not serve these docs: $(wc -l < "$work/problems") problems"
cat "$work/problems"
exit 1
