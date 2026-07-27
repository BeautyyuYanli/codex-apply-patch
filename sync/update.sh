#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must name the mirror repository}"
: "${GH_TOKEN:?GH_TOKEN is required}"

upstream_repository="openai/codex"
mirror_repository_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY}"
main_targets=(
  x86_64-unknown-linux-gnu
  aarch64-unknown-linux-gnu
)
release_targets=(
  "${main_targets[@]}"
  x86_64-pc-windows-msvc
)
baseline_file="sync/state/release-id"
release_page_size=20
baseline="$(tr -d '\n' < "$baseline_file")"
if [[ ! "$baseline" =~ ^[0-9]+$ ]]; then
  echo "$baseline_file must contain a GitHub release ID" >&2
  exit 1
fi

gh_api_retry() {
  local output_file="$1"
  shift
  local attempt
  local delay
  for attempt in 1 2 3 4 5; do
    if gh api "$@" > "$output_file"; then
      return 0
    fi
    if (( attempt == 5 )); then
      return 1
    fi
    delay=$((2 ** attempt))
    echo "GitHub API request failed; retrying in ${delay}s" >&2
    sleep "$delay"
  done
}

api_temp="$(mktemp -d)"
trap 'rm -rf "$api_temp"' EXIT
releases_file="$api_temp/releases.json"
page_file="$api_temp/page.json"
merged_file="$api_temp/merged.json"
published_file="$api_temp/published.json"
new_releases_file="$api_temp/new-releases.json"
printf '[]\n' > "$releases_file"

page=1
while :; do
  gh_api_retry "$page_file" -X GET \
    "repos/${upstream_repository}/releases?per_page=${release_page_size}&page=${page}"
  jq -e 'type == "array"' "$page_file" >/dev/null
  jq -s '.[0] + .[1]' "$releases_file" "$page_file" > "$merged_file"
  mv "$merged_file" "$releases_file"
  if jq -e --argjson baseline "$baseline" \
    'any(.id == $baseline)' "$page_file" >/dev/null; then
    break
  fi
  if (( $(jq 'length' "$page_file") < release_page_size )); then
    echo "release baseline $baseline was not found upstream; refusing to skip history" >&2
    exit 1
  fi
  ((page += 1))
done
jq 'map(select(.draft == false))' "$releases_file" > "$published_file"
baseline_index="$(
  jq --argjson baseline "$baseline" \
    'map(.id) | index($baseline)' "$published_file"
)"
jq --argjson end "$baseline_index" \
  '.[0:$end] | reverse' "$published_file" > "$new_releases_file"
release_count="$(jq 'length' "$new_releases_file")"
release_plan="$(jq -c '[.[] | {id, tag: .tag_name}]' "$new_releases_file")"
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

if (( release_count > 0 )); then
  mode=release
  built=true
  while IFS= read -r encoded; do
    release_json="$(base64 --decode <<<"$encoded")"
    tag="$(jq -r '.tag_name' <<<"$release_json")"
    title="$(jq -r '.name // .tag_name' <<<"$release_json")"
    prerelease="$(jq -r '.prerelease' <<<"$release_json")"

    ./sync/sync.py --ref "$tag" --repository "$mirror_repository_url"

    if gh release view "$tag" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
      echo "release $tag already exists; retaining it for asset reconciliation"
      commit_generated_files "Sync apply-patch for OpenAI Codex ${tag}"
      continue
    fi

    ./sync/package.sh "$tag" "${release_targets[@]}"
    commit_generated_files "Sync apply-patch for OpenAI Codex ${tag}"

    if ! git ls-remote --exit-code --tags origin "refs/tags/${tag}" >/dev/null 2>&1; then
      git tag -a "$tag" -m "$title"
      git push origin "refs/tags/${tag}"
    fi

    notes_file="$(mktemp)"
    upstream_release_url="$(jq -r '.html_url' <<<"$release_json")"
    printf 'Upstream release: %s\n' "$upstream_release_url" > "$notes_file"
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
  done < <(jq -r '.[] | @base64' "$new_releases_file")
else
  previous_commit=""
  if [[ -f sync/state/commit ]]; then
    previous_commit="$(tr -d '\n' < sync/state/commit)"
  fi
  ./sync/sync.py --ref main --repository "$mirror_repository_url"
  current_commit="$(tr -d '\n' < sync/state/commit)"

  if [[ "$current_commit" != "$previous_commit" ]]; then
    ./sync/package.sh \
      "$(cut -c1-12 sync/state/commit)" \
      "${main_targets[@]}"
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
    printf 'release_plan=%s\n' "$release_plan"
  } >> "$GITHUB_OUTPUT"
fi
