# apply-patch

A standalone distribution of OpenAI Codex's
[`apply_patch`](https://github.com/openai/codex/tree/main/codex-rs/apply-patch)
utility. This repository mirrors the upstream Rust crate and publishes
ready-to-install bundles containing both a binary and an agent skill.

For the patch format and tool instructions, see [`SKILL.md`](SKILL.md).

## Download

Prebuilt bundles are available from
[GitHub Releases](https://github.com/BeautyyuYanli/codex-apply-patch/releases):

| Platform | Release asset suffix |
| --- | --- |
| Linux x86-64 | `x86_64-unknown-linux-gnu.tar.gz` |
| Linux ARM64 | `aarch64-unknown-linux-gnu.tar.gz` |
| macOS Apple Silicon | `aarch64-apple-darwin.tar.gz` |
| Windows x64 | `x86_64-pc-windows-msvc.zip` |

Every archive has a matching `.sha256` checksum and contains one top-level
directory:

```text
apply-patch/
├── apply_patch          # apply_patch.exe on Windows
├── SKILL.md
├── LICENSE
├── NOTICE
├── SOURCE
└── THIRD_PARTY_LICENSES.html
```

### Download the latest release from a shell

The following command downloads the newest published release, including
prereleases. It requires `curl` and `jq`, and automatically selects the asset
for the current platform:

```sh
set -eu

case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64)
    asset_suffix="x86_64-unknown-linux-gnu.tar.gz"
    ;;
  Linux:aarch64|Linux:arm64)
    asset_suffix="aarch64-unknown-linux-gnu.tar.gz"
    ;;
  Darwin:arm64|Darwin:aarch64)
    asset_suffix="aarch64-apple-darwin.tar.gz"
    ;;
  MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64)
    asset_suffix="x86_64-pc-windows-msvc.zip"
    ;;
  *)
    echo "Unsupported platform: $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

asset_url="$(
  curl -fsSL \
    "https://api.github.com/repos/BeautyyuYanli/codex-apply-patch/releases?per_page=10" |
    jq -er --arg suffix "$asset_suffix" '
      first(
        .[] | select(.draft == false) | .assets[]
        | select(.name | endswith($suffix))
        | .browser_download_url
      )
    '
)"
curl -fLO "$asset_url"
curl -fLO "${asset_url}.sha256"
```

## Install

Install the command-line binary, the agent skill, or both.

### Install the binary on `PATH`

#### Linux

```sh
sha256sum -c apply-patch-*.tar.gz.sha256
tar -xzf apply-patch-*.tar.gz
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

#### macOS

```sh
shasum -a 256 -c apply-patch-*.tar.gz.sha256
tar -xzf apply-patch-*.tar.gz
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

On Linux and macOS, ensure `~/.local/bin` is on `PATH`.

#### Windows

Extract the zip archive, then copy `apply-patch\apply_patch.exe` to a directory
you already manage on `PATH`, or add the extracted `apply-patch` directory to
the user `PATH`.

### Install as an agent skill

Extract the complete bundle directly into the shared agents skill directory.
This installation does not require adding the binary to `PATH`.

On Linux or macOS:

```sh
mkdir -p ~/.agents/skills
tar -xzf apply-patch-*.tar.gz -C ~/.agents/skills
```

On Windows PowerShell:

```powershell
New-Item -ItemType Directory -Force "$HOME/.agents/skills" | Out-Null
Expand-Archive -Force -Path apply-patch-*.zip -DestinationPath "$HOME/.agents/skills"
```

The installed skill entry point is
`~/.agents/skills/apply-patch/SKILL.md`.

For command-line access on Linux or macOS, we recommend linking the bundled
binary into a directory on `PATH` instead of copying it:

```sh
mkdir -p ~/.local/bin
ln -sfn "$HOME/.agents/skills/apply-patch/apply_patch" \
  "$HOME/.local/bin/apply_patch"
```

Ensure `~/.local/bin` is on `PATH`.

## Work locally

Local synchronization and builds require Git, Rust, Cargo, and
[`uv`](https://docs.astral.sh/uv/getting-started/installation/).

### Synchronize from upstream

```sh
git clone https://github.com/BeautyyuYanli/codex-apply-patch.git
cd codex-apply-patch
uv run --script sync/sync.py \
  --ref main \
  --repository https://github.com/BeautyyuYanli/codex-apply-patch
```

Replace `main` with an upstream tag or commit to synchronize that revision.
The script regenerates the source tree, Cargo metadata, lockfile, licenses, and
provenance state.

### Build and test

```sh
git clone https://github.com/BeautyyuYanli/codex-apply-patch.git
cd codex-apply-patch
cargo build --locked --release --bin apply_patch
cargo test --locked
```

The resulting binary is written to `target/release/apply_patch` or
`target/release/apply_patch.exe`.

## Automation

The [sync workflow](https://github.com/BeautyyuYanli/codex-apply-patch/actions)
runs daily and can also be started manually.

- When a new upstream release is available, the workflow synchronizes that
  release instead of upstream `main`, builds all four platform bundles, and
  publishes a matching release whose notes link back to the upstream release.
- When there is no new release, the workflow synchronizes upstream `main`.
  Linux bundles are built only when the `codex-rs/apply-patch` source tree has
  changed.

Generated source, package metadata, lockfiles, licenses, and provenance state
must be updated through [`sync/sync.py`](sync/sync.py), not edited manually.

## License and provenance

The synchronized OpenAI source is licensed under Apache-2.0. The repository
tracks the upstream [`LICENSE`](LICENSE), [`NOTICE`](NOTICE), commit, ref, and
tree hash in [`sync/state`](sync/state). Release bundles also include source
provenance and generated third-party license notices.

This is an unofficial standalone mirror and is not affiliated with or endorsed
by OpenAI.
