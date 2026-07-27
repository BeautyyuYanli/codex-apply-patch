#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

label="${1:-$(cut -c1-12 sync/state/commit)}"
safe_label="$(printf '%s' "$label" | tr -cs 'A-Za-z0-9._-' '-')"
safe_label="${safe_label%-}"
host="$(rustc -vV | sed -n 's/^host: //p')"
if (( $# > 0 )); then
  shift
fi
targets=("$@")

if [[ -z "$host" ]]; then
  echo "could not determine the Rust host target" >&2
  exit 1
fi
if (( ${#targets[@]} == 0 )); then
  targets=("$host")
fi
if ! cargo about --version >/dev/null 2>&1; then
  echo "cargo-about is required to package third-party license texts" >&2
  exit 1
fi

rm -rf dist
mkdir -p dist
stage_root="$(mktemp -d)"
trap 'rm -rf "$stage_root"' EXIT
common="$stage_root/common"
mkdir "$common"

install -m 0644 LICENSE NOTICE "$common/"
{
  printf 'Upstream repository: https://github.com/openai/codex\n'
  printf 'Upstream path: codex-rs/apply-patch\n'
  printf 'Upstream ref: %s\n' "$(tr -d '\n' < sync/state/ref)"
  printf 'Upstream commit: %s\n' "$(tr -d '\n' < sync/state/commit)"
} > "$common/SOURCE"

cargo about generate --locked --fail \
  --output-file "$common/THIRD_PARTY_LICENSES.html" \
  -c sync/cargo-about/about.toml \
  sync/cargo-about/about.hbs

chmod 0644 "$common/SOURCE" "$common/THIRD_PARTY_LICENSES.html"

for target in "${targets[@]}"; do
  binary_name="apply_patch"
  case "$target" in
    "$host")
      cargo build --locked --release --target "$target" --bin apply_patch
      ;;
    aarch64-unknown-linux-gnu)
      if ! cross --version >/dev/null 2>&1; then
        echo "cross is required to build $target" >&2
        exit 1
      fi
      CROSS_CONFIG=sync/cross/Cross.toml \
        cross build --locked --release --target "$target" --bin apply_patch
      ;;
    x86_64-pc-windows-msvc)
      if ! cargo xwin --version >/dev/null 2>&1; then
        echo "cargo-xwin is required to build $target" >&2
        exit 1
      fi
      cargo xwin build --locked --release --target "$target" --bin apply_patch
      binary_name="apply_patch.exe"
      ;;
    *)
      echo "cannot build $target from host $host" >&2
      exit 1
      ;;
  esac

  stage="$stage_root/$target"
  mkdir "$stage"
  install -m 0755 "target/$target/release/$binary_name" "$stage/$binary_name"
  install -m 0644 "$common/LICENSE" "$common/NOTICE" \
    "$common/SOURCE" "$common/THIRD_PARTY_LICENSES.html" "$stage/"

  archive_stem="apply-patch-${safe_label}-${target}"
  if [[ "$target" == *-windows-* ]]; then
    if ! command -v zip >/dev/null 2>&1; then
      echo "zip is required to package $target" >&2
      exit 1
    fi
    archive="$repo_root/dist/${archive_stem}.zip"
    (
      cd "$stage"
      zip -q "$archive" ./*
    )
  else
    archive="$repo_root/dist/${archive_stem}.tar.gz"
    tar -C "$stage" -czf "$archive" .
  fi

  archive_name="$(basename "$archive")"
  if command -v sha256sum >/dev/null 2>&1; then
    (
      cd dist
      sha256sum "$archive_name" > "${archive_name}.sha256"
    )
  else
    digest="$(shasum -a 256 "$archive" | awk '{print $1}')"
    printf '%s  %s\n' "$digest" "$archive_name" > "${archive}.sha256"
  fi
  printf 'packaged %s\n' "$archive"
done
