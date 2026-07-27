#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name the mirror repository}"
: "${GH_TOKEN:?GH_TOKEN is required}"

upstream_repository="openai/codex"
baseline_file="sync/state/release-id"
baseline="$(tr -d '\n' < "$baseline_file")"
if [[ ! "$baseline" =~ ^[0-9]+$ ]]; then
  echo "$baseline_file must contain a GitHub release ID" >&2
  exit 1
fi

releases="[]"
page=1
while :; do
  page_releases="$(
    gh api -X GET "repos/${upstream_repository}/releases" \
      -f per_page=100 \
      -f page="$page"
  )"
  jq -e 'type == "array"' >/dev/null <<<"$page_releases"
  releases="$(
    jq -cn \
      --argjson previous "$releases" \
      --argjson current "$page_releases" \
      '$previous + $current'
  )"
  if jq -e --argjson baseline "$baseline" \
    'any(.id == $baseline)' >/dev/null <<<"$page_releases"; then
    break
  fi
  if (( $(jq 'length' <<<"$page_releases") < 100 )); then
    echo "release baseline $baseline was not found upstream; refusing to skip history" >&2
    exit 1
  fi
  ((page += 1))
done
releases="$(jq 'map(select(.draft == false))' <<<"$releases")"
baseline_index="$(
  jq --argjson baseline "$baseline" \
    'map(.id) | index($baseline)' <<<"$releases"
)"
new_releases="$(
  jq --argjson end "$baseline_index" '.[0:$end] | reverse' <<<"$releases"
)"
release_count="$(jq 'length' <<<"$new_releases")"
built=false
mode=noop

commit_generated_files() {
  local message="$1"
  git add \
    Cargo.toml Cargo.lock LICENSE NOTICE BUILD.bazel src tests \
    sync/state/commit sync/state/ref sync/state/tree
  if ! git diff --cached --quiet; then
    git commit -m "$message"
    git push origin HEAD:main
  fi
}

record_release() {
  local release_id="$1"
  local tag="$2"
  printf '%s\n' "$release_id" > "$baseline_file"
  git add "$baseline_file"
  if ! git diff --cached --quiet; then
    git commit -m "Record upstream release ${tag}"
    git push origin HEAD:main
  fi
}

if (( release_count > 0 )); then
  mode=release
  built=true
  while IFS= read -r encoded; do
    release_json="$(base64 --decode <<<"$encoded")"
    release_id="$(jq -r '.id' <<<"$release_json")"
    tag="$(jq -r '.tag_name' <<<"$release_json")"
    title="$(jq -r '.name // .tag_name' <<<"$release_json")"
    prerelease="$(jq -r '.prerelease' <<<"$release_json")"

    ./sync/sync.py --ref "$tag"

    if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
      echo "release $tag already exists; advancing the release baseline"
      commit_generated_files "Sync apply-patch for OpenAI Codex ${tag}"
      record_release "$release_id" "$tag"
      continue
    fi

    ./sync/package.sh "$tag"
    commit_generated_files "Sync apply-patch for OpenAI Codex ${tag}"

    if ! git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
      git tag -a "$tag" -m "$title"
      git push origin "refs/tags/${tag}"
    fi

    notes_file="$(mktemp)"
    jq -r '.body // ""' <<<"$release_json" > "$notes_file"
    mapfile -t assets < <(find dist -maxdepth 1 -type f -print | sort)
    release_args=(
      release create "$tag"
      --repo "$GITHUB_REPOSITORY"
      --verify-tag
      --title "$title"
      --notes-file "$notes_file"
    )
    if [[ "$prerelease" == "true" ]]; then
      release_args+=(--prerelease)
    fi
    gh "${release_args[@]}" "${assets[@]}"
    rm -f "$notes_file"

    record_release "$release_id" "$tag"
  done < <(jq -r '.[] | @base64' <<<"$new_releases")
else
  previous_commit=""
  if [[ -f sync/state/commit ]]; then
    previous_commit="$(tr -d '\n' < sync/state/commit)"
  fi
  ./sync/sync.py --ref main
  current_commit="$(tr -d '\n' < sync/state/commit)"

  if [[ "$current_commit" != "$previous_commit" ]]; then
    ./sync/package.sh "$(cut -c1-12 sync/state/commit)"
    built=true
    mode=main
  fi
  commit_generated_files "Sync apply-patch from OpenAI Codex ${current_commit:0:12}"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'built=%s\n' "$built"
    printf 'mode=%s\n' "$mode"
    printf 'release_count=%s\n' "$release_count"
  } >> "$GITHUB_OUTPUT"
fi
