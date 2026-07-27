# apply-patch

A standalone distribution of OpenAI Codex's
[`apply_patch`](https://github.com/openai/codex/tree/main/codex-rs/apply-patch)
tool, with prebuilt binaries and an optional Codex skill.

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

### Linux

```sh
sha256sum -c apply-patch-*.tar.gz.sha256
tar -xzf apply-patch-*.tar.gz
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

Ensure `~/.local/bin` is on `PATH`.

### macOS

```sh
shasum -a 256 -c apply-patch-*.tar.gz.sha256
tar -xzf apply-patch-*.tar.gz
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

Ensure `~/.local/bin` is on `PATH`.

### Windows

Extract the zip archive, then either copy
`apply-patch\apply_patch.exe` to a directory on `PATH` or add the extracted
`apply-patch` directory to `PATH`.

### Optional: install the Codex skill

After extracting any bundle:

```sh
mkdir -p ~/.codex/skills/apply-patch
cp apply-patch/SKILL.md ~/.codex/skills/apply-patch/SKILL.md
```

If `CODEX_HOME` is configured, use `$CODEX_HOME/skills/apply-patch` instead.

## Build from source

```sh
cargo build --locked --release --bin apply_patch
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
