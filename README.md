# apply-patch

A standalone distribution of OpenAI Codex's
[`apply_patch`](https://github.com/openai/codex/tree/main/codex-rs/apply-patch)
tool.

This repository provides:

- a small `apply_patch` command-line program that applies structured patches
  to files in the current working directory;
- ready-to-use binaries for Linux x86-64, Linux ARM64, macOS Apple Silicon,
  and Windows x64; and
- an `apply-patch` Codex skill containing the patch format, safety rules, and
  verification workflow.

The source is synchronized from OpenAI Codex automatically. This is an
unofficial standalone mirror and is not affiliated with or endorsed by OpenAI.

## Download

Download the bundle for your platform from
[GitHub Releases](https://github.com/BeautyyuYanli/codex-apply-patch/releases):

| Platform | Release asset suffix | Binary |
| --- | --- | --- |
| Linux x86-64 | `x86_64-unknown-linux-gnu.tar.gz` | `apply_patch` |
| Linux ARM64 | `aarch64-unknown-linux-gnu.tar.gz` | `apply_patch` |
| macOS Apple Silicon | `aarch64-apple-darwin.tar.gz` | `apply_patch` |
| Windows x64 | `x86_64-pc-windows-msvc.zip` | `apply_patch.exe` |

Each archive has a matching `.sha256` file. Verify it before extracting:

```sh
sha256sum -c <archive>.sha256
```

On macOS, use:

```sh
shasum -a 256 -c <archive>.sha256
```

Every archive extracts to one top-level directory:

```text
apply-patch/
├── apply_patch          # apply_patch.exe on Windows
├── SKILL.md
├── LICENSE
├── NOTICE
├── SOURCE
└── THIRD_PARTY_LICENSES.html
```

## Install the command

### Linux and macOS

Extract the archive, then place the binary in a directory on `PATH`:

```sh
tar -xzf <archive>
mkdir -p ~/.local/bin
install -m 0755 apply-patch/apply_patch ~/.local/bin/apply_patch
```

Ensure `~/.local/bin` is included in your `PATH`.

### Windows

Extract the zip archive and copy `apply-patch\apply_patch.exe` to a directory
on `PATH`, or add the extracted `apply-patch` directory to `PATH`.

## Use the command

Run `apply_patch` from the root of the project you want to modify. Pass one
complete patch as an argument or through standard input.

The standard-input form is convenient for multiline patches:

```sh
cd path/to/project

apply_patch <<'PATCH'
*** Begin Patch
*** Update File: README.md
@@
-Old text
+New text
*** End Patch
PATCH
```

The same patch can be passed as one argument:

```sh
apply_patch '*** Begin Patch
*** Add File: hello.txt
+Hello, world!
*** End Patch'
```

Paths in the patch are resolved relative to the current working directory.
The command exits with status `0` after a successful patch, `1` after an
application error, and `2` for invalid command usage.

See [`SKILL.md`](SKILL.md) for the complete patch grammar, operation examples,
safety constraints, failure handling, and verification checklist.

## Install the Codex skill

The skill documents how Codex should construct and apply patches. It is
separate from installing the standalone command.

Copy `SKILL.md` into an `apply-patch` directory under your Codex skills
directory:

```sh
mkdir -p ~/.codex/skills/apply-patch
cp apply-patch/SKILL.md ~/.codex/skills/apply-patch/SKILL.md
```

If `CODEX_HOME` is configured, use `$CODEX_HOME/skills/apply-patch` instead.
You can then explicitly invoke it in Codex with a request such as:

```text
Use $apply-patch to update src/config.rs.
```

## Build from source

This repository is a standalone Cargo package:

```sh
cargo build --locked --release --bin apply_patch
```

The binary is written to `target/release/apply_patch` (or
`apply_patch.exe` on Windows).

## Source synchronization

Run the generator manually with:

```sh
uv run --script sync/sync.py --ref main
```

The generator:

- fetches the requested OpenAI Codex branch, tag, or commit;
- replaces the root `src`, `tests`, and `BUILD.bazel` with upstream files;
- expands inherited workspace metadata into a standalone `Cargo.toml`;
- pins internal Codex crates to the synchronized upstream commit;
- copies the upstream Apache-2.0 `LICENSE` and `NOTICE`;
- records the upstream ref, commit, and tree hash; and
- regenerates `Cargo.lock`.

`Cargo.toml`, `Cargo.lock`, `LICENSE`, `NOTICE`, `src`, `tests`, `BUILD.bazel`,
and the commit/ref/tree files under `sync/state` are generated. Modify the
generator rather than editing those files manually.

## Release automation

The [sync workflow](https://github.com/BeautyyuYanli/codex-apply-patch/actions)
runs daily and can also be started manually.

- New upstream releases take priority. The workflow synchronizes each release
  tag, builds all four supported platforms, mirrors the upstream tag, title,
  and prerelease status, and links back to the upstream release.
- When there is no new release, it synchronizes upstream `main`. It builds
  Linux artifacts only when the `codex-rs/apply-patch` tree hash changed.
- Linux ARM64 and Windows x64 are cross-compiled on Linux. macOS ARM64 is
  built on a native Apple Silicon runner.
- The release checkpoint advances only after every platform bundle has been
  published.

## License and provenance

The synchronized source is from OpenAI Codex and is licensed under
Apache-2.0. See [`LICENSE`](LICENSE), [`NOTICE`](NOTICE), and
[`sync/state`](sync/state) for provenance. Release bundles also contain
`SOURCE` and the third-party license report generated by
[`cargo-about`](https://github.com/EmbarkStudios/cargo-about).
