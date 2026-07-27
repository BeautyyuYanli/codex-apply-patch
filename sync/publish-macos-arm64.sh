#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name the mirror repository}"
: "${GH_TOKEN:?GH_TOKEN is required}"
: "${RELEASE_PLAN:?RELEASE_PLAN must contain the releases to publish}"

jq -e '
  type == "array"
  and length > 0
  and all(.[];
    (.id | type == "number")
    and (.tag | type == "string" and length > 0)
  )
' <<<"$RELEASE_PLAN" >/dev/null

host="$(rustc -vV | sed -n 's/^host: //p')"
if [[ "$host" != "aarch64-apple-darwin" ]]; then
  echo "expected an aarch64-apple-darwin runner, found $host" >&2
  exit 1
fi

while IFS= read -r tag; do
  git checkout --detach "$tag"
  ./sync/package.sh "$tag" aarch64-apple-darwin
  assets=(dist/*)
  gh release upload "$tag" \
    --repo "$GITHUB_REPOSITORY" \
    --clobber \
    "${assets[@]}"
done < <(jq -r '.[].tag' <<<"$RELEASE_PLAN")

git checkout main
git pull --ff-only origin main

latest_release_id="$(jq -r 'last.id' <<<"$RELEASE_PLAN")"
latest_release_tag="$(jq -r 'last.tag' <<<"$RELEASE_PLAN")"
printf '%s\n' "$latest_release_id" > sync/state/release-id
git add sync/state/release-id
if ! git diff --cached --quiet; then
  git commit -m "Record upstream release ${latest_release_tag}"
  git push origin HEAD:main
fi
