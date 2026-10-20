#!/usr/bin/env bash
# The site deployed at BASE is the one built in DIR, and every rule's address
# finds its section there:
#
#   bash hack/check-site.sh https://syg.vishisht.tech built
#
# DIR is the docs artifact: DIR/site, the site as built, and DIR/docs-urls.txt,
# the docs_url of every rule, which each finding and `syg explain` print. A
# page can answer 200 and still be an older build, without a section a newer
# rule links to, so each deployed file is compared with the built one, byte
# for byte (dotfiles aside: Pages does not serve them), and each address's
# section is looked for by its id. The pages the binary and the installers
# name are asked for too, and the install scripts compared with this
# repository's. Pages's CDN keeps a page for up to ten minutes, so each
# attempt asks with a query of its own, and a failure is retried for twelve
# minutes (CHECK_SITE_ATTEMPTS, 30 s apart) before it fails the run.
set -euo pipefail
attempts=${CHECK_SITE_ATTEMPTS:-25}
base=${1:?usage: check-site.sh BASE DIR}
dir=${2:?usage: check-site.sh BASE DIR}
base=${base%/}
if [ ! -d "$dir/site" ] || [ ! -s "$dir/docs-urls.txt" ]; then
  echo "::error::$dir holds no site/ and docs-urls.txt"
  exit 1
fi
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# check ATTEMPT: every problem, one per line, on stdout; none is a pass.
check() {
  local q="?check=${GITHUB_RUN_ID:-local}-$1" f rel url page id p
  while IFS= read -r f; do
    rel=${f#"$dir/site/"}
    if ! curl -fsS --max-time 30 -o "$work/got" "$base/$rel$q" 2>/dev/null; then
      echo "missing: $base/$rel"
    elif ! cmp -s "$work/got" "$f"; then
      echo "not the page built: $base/$rel"
    fi
  done < <(find "$dir/site" -type f -not -path '*/.*' | sort)
  while IFS= read -r url; do
    page=${url%%#*}
    id=${url#*#}
    case "$page" in "$base"/*) ;; *) echo "not on the site: $url"; continue ;; esac
    if ! curl -fsS --max-time 30 -o "$work/got" "$page$q" 2>/dev/null; then
      echo "missing: $page"
    elif [ "$id" != "$url" ] && ! grep -qF "id=\"$id\"" "$work/got"; then
      echo "no section: $url"
    fi
  done < "$dir/docs-urls.txt"
  for p in install privacy eula; do
    curl -fsS --max-time 30 -o /dev/null "$base/$p$q" 2>/dev/null || echo "missing: $base/$p"
  done
  for p in install.sh install.ps1; do
    if ! curl -fsS --max-time 30 -o "$work/got" "$base/$p$q" 2>/dev/null; then
      echo "missing: $base/$p"
    elif [ -f "$p" ] && ! cmp -s "$work/got" "$p"; then
      echo "not this repository's: $base/$p"
    fi
  done
}

files=$(find "$dir/site" -type f -not -path '*/.*' | wc -l)
urls=$(grep -c . "$dir/docs-urls.txt")
for attempt in $(seq 1 "$attempts"); do
  check "$attempt" > "$work/problems"
  if [ ! -s "$work/problems" ]; then
    echo "$base is the site built: $files files, and $urls rules' sections"
    exit 0
  fi
  if [ "$attempt" -lt "$attempts" ]; then sleep 30; fi
done
echo "::error::$base is not the site built: $(wc -l < "$work/problems") problems"
cat "$work/problems"
exit 1
