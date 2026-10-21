#!/usr/bin/env bash
# Validates the docs.page sources: docs.json parses, every sidebar entry and
# every internal link points to an existing page.
set -euo pipefail

cd "$(dirname "$0")/../.."

jq empty docs.json

page_exists() {
  local path="${1%%#*}"
  path="${path%/}"
  [[ -z "$path" ]] && path="/index"
  [[ -f "docs${path}.mdx" || -f "docs${path}/index.mdx" ]]
}

status=0

while read -r href; do
  if ! page_exists "$href"; then
    echo "docs.json: no page for sidebar entry $href"
    status=1
  fi
done < <(jq -r '.sidebar[].pages[].href' docs.json)

while IFS=: read -r file link; do
  if ! page_exists "$link"; then
    echo "$file: broken internal link $link"
    status=1
  fi
done < <(grep -oE '\]\(/[^)]*\)' -r docs --include='*.mdx' | sed -E 's/\]\((.*)\)$/\1/')

exit $status
