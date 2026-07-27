#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

label="${1:-$(cut -c1-12 sync/state/commit)}"
safe_label="$(printf '%s' "$label" | tr -cs 'A-Za-z0-9._-' '-')"
safe_label="${safe_label%-}"
host="$(rustc -vV | sed -n 's/^host: //p')"

if [[ -z "$host" ]]; then
  echo "could not determine the Rust host target" >&2
  exit 1
fi
if ! cargo about --version >/dev/null 2>&1; then
  echo "cargo-about is required to package third-party license texts" >&2
  exit 1
fi

cargo build --locked --release --bin apply_patch

rm -rf dist
mkdir -p dist
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

install -m 0755 target/release/apply_patch "$stage/apply_patch"
install -m 0644 LICENSE NOTICE "$stage/"
{
  printf 'Upstream repository: https://github.com/openai/codex\n'
  printf 'Upstream path: codex-rs/apply-patch\n'
  printf 'Upstream ref: %s\n' "$(tr -d '\n' < sync/state/ref)"
  printf 'Upstream commit: %s\n' "$(tr -d '\n' < sync/state/commit)"
} > "$stage/SOURCE"

cargo about generate --locked --fail \
  --output-file "$stage/THIRD_PARTY_LICENSES.html" \
  -c sync/cargo-about/about.toml \
  sync/cargo-about/about.hbs

chmod 0755 "$stage"
chmod 0644 "$stage/SOURCE" "$stage/THIRD_PARTY_LICENSES.html"

archive="dist/apply-patch-${safe_label}-${host}.tar.gz"
tar -C "$stage" -czf "$archive" .
(
  cd dist
  sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
)
printf 'packaged %s\n' "$archive"
