# apply-patch

A standalone distribution of OpenAI Codex's
[`apply_patch`](https://github.com/openai/codex/tree/main/codex-rs/apply-patch)
tool, with prebuilt binaries and an optional agent skill.

Supported platforms:

- Linux x86-64
- Linux ARM64
- macOS Apple Silicon
- Windows x64

For the patch format and usage rules, see [`SKILL.md`](SKILL.md).

## Install

Download the latest bundle from
[GitHub Releases](https://github.com/BeautyyuYanli/codex-apply-patch/releases):

| Platform | Asset suffix |
| --- | --- |
| Linux x86-64 | `x86_64-unknown-linux-gnu.tar.gz` |
| Linux ARM64 | `aarch64-unknown-linux-gnu.tar.gz` |
| macOS Apple Silicon | `aarch64-apple-darwin.tar.gz` |
| Windows x64 | `x86_64-pc-windows-msvc.zip` |

Each archive has a matching `.sha256` checksum and extracts to:

```text
apply-patch/
├── apply_patch          # apply_patch.exe on Windows
├── SKILL.md
├── LICENSE
├── NOTICE
├── SOURCE
└── THIRD_PARTY_LICENSES.html
```

To download the newest published release, including prereleases, install
`curl` and `jq`, then run this from a POSIX shell. The asset suffix is detected
from the operating system and CPU architecture:

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

### Install the binary on `PATH`

#### Linux

```sh
sha256sum -c apply-patch-*.tar.gz.sha256
tar -xzf apply-patch-*.tar.gz
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

Ensure `~/.local/bin` is on `PATH`.

#### macOS

```sh
shasum -a 256 -c apply-patch-*.tar.gz.sha256
tar -xzf apply-patch-*.tar.gz
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

Ensure `~/.local/bin` is on `PATH`.

#### Windows

Extract the zip archive, then either copy
`apply-patch\apply_patch.exe` to a directory on `PATH` or add the extracted
`apply-patch` directory to `PATH`.

### Install as an agent skill

This is independent of installing the binary on `PATH`. Extract the complete
bundle directly into the shared agents skill directory.

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

The installed skill is at `~/.agents/skills/apply-patch/SKILL.md`; the bundled
binary stays inside that skill directory and does not need to be added to
`PATH`.

## Sync locally

Install Git, Rust, Cargo, and
[`uv`](https://docs.astral.sh/uv/getting-started/installation/), then run:

```sh
git clone https://github.com/BeautyyuYanli/codex-apply-patch.git
cd codex-apply-patch
uv run --script sync/sync.py \
  --ref main \
  --repository https://github.com/BeautyyuYanli/codex-apply-patch
```

Replace `main` with an upstream tag or commit to synchronize that revision.

## Build locally

```sh
git clone https://github.com/BeautyyuYanli/codex-apply-patch.git
cd codex-apply-patch
cargo build --locked --release --bin apply_patch
cargo test --locked
```

The binary is written to `target/release/apply_patch` or
`target/release/apply_patch.exe`.

## Updates

The [sync workflow](https://github.com/BeautyyuYanli/codex-apply-patch/actions)
runs daily and can also be started manually.

- New upstream releases are mirrored with Linux x86-64, Linux ARM64, macOS
  ARM64, and Windows x64 bundles.
- When there is no new release, upstream `main` is synchronized and Linux
  artifacts are built only when the `codex-rs/apply-patch` tree changes.

The generated source, package metadata, lockfile, and provenance state should
be updated through [`sync/sync.py`](sync/sync.py), not edited manually.

## License

The synchronized source is from OpenAI Codex and is licensed under
Apache-2.0. See [`LICENSE`](LICENSE), [`NOTICE`](NOTICE), and
[`sync/state`](sync/state). This repository is an unofficial standalone mirror
and is not affiliated with or endorsed by OpenAI.
