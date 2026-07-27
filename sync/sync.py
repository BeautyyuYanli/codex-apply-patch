#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Synchronize OpenAI Codex's apply-patch crate into this standalone crate."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import tempfile
import tomllib
from pathlib import Path
from typing import Any


DEFAULT_UPSTREAM = "https://github.com/openai/codex.git"
DEFAULT_REPOSITORY = "https://github.com/BeautyyuYanli/codex-apply-patch"
UPSTREAM_CRATE = Path("codex-rs/apply-patch")
GENERATED_FILES = {
    "Cargo.toml": Path("Cargo.toml"),
    "Cargo.lock": Path("Cargo.lock"),
    "LICENSE": Path("LICENSE"),
    "NOTICE": Path("NOTICE"),
    "UPSTREAM_COMMIT": Path("sync/state/commit"),
    "UPSTREAM_REF": Path("sync/state/ref"),
    "UPSTREAM_TREE": Path("sync/state/tree"),
}
LEGACY_GENERATED_FILES = ("UPSTREAM_COMMIT", "UPSTREAM_REF", "UPSTREAM_TREE")
GENERATED_CRATE_ENTRIES = (
    "src",
    "tests",
    "benches",
    "examples",
    "build.rs",
    "BUILD.bazel",
)


def run(*args: str, cwd: Path, capture: bool = False) -> str:
    result = subprocess.run(
        args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout.strip() if capture else ""


def validate_ref(ref: str) -> None:
    if (
        not ref
        or ref.startswith("-")
        or ".." in ref
        or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]*", ref)
    ):
        raise ValueError(f"unsafe upstream ref: {ref!r}")


def quote_key(key: str) -> str:
    if re.fullmatch(r"[A-Za-z0-9_-]+", key):
        return key
    return json.dumps(key)


def toml_value(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    if isinstance(value, dict):
        fields = ", ".join(
            f"{quote_key(key)} = {toml_value(item)}" for key, item in value.items()
        )
        return "{ " + fields + " }"
    raise TypeError(f"unsupported TOML value: {value!r}")


def resolve_dependency(
    name: str,
    specification: Any,
    workspace_dependencies: dict[str, Any],
    commit: str,
    upstream_url: str,
) -> Any:
    if not isinstance(specification, dict) or not specification.get("workspace"):
        if isinstance(specification, dict) and "path" in specification:
            result = dict(specification)
            result.pop("path")
            result["git"] = upstream_url
            result["rev"] = commit
            return result
        return specification

    if name not in workspace_dependencies:
        raise KeyError(f"{name!r} is absent from [workspace.dependencies]")

    inherited = workspace_dependencies[name]
    if isinstance(inherited, str):
        resolved: dict[str, Any] = {"version": inherited}
    else:
        resolved = dict(inherited)

    if "path" in resolved:
        resolved.pop("path")
        resolved.pop("version", None)
        resolved["git"] = upstream_url
        resolved["rev"] = commit

    overrides = {
        key: value for key, value in specification.items() if key != "workspace"
    }
    if "features" in overrides and "features" in resolved:
        resolved["features"] = list(
            dict.fromkeys([*resolved["features"], *overrides.pop("features")])
        )
    resolved.update(overrides)

    if set(resolved) == {"version"}:
        return resolved["version"]
    return resolved


def resolve_dependencies(
    dependencies: dict[str, Any],
    workspace_dependencies: dict[str, Any],
    commit: str,
    upstream_url: str,
) -> dict[str, Any]:
    return {
        name: resolve_dependency(
            name, specification, workspace_dependencies, commit, upstream_url
        )
        for name, specification in dependencies.items()
    }


def adjust_source_path(value: str) -> str:
    return value


def write_table(lines: list[str], name: str, values: dict[str, Any]) -> None:
    if not values:
        return
    lines.append(f"[{name}]")
    for key, value in values.items():
        lines.append(f"{quote_key(key)} = {toml_value(value)}")
    lines.append("")


def write_array_table(
    lines: list[str], name: str, entries: list[dict[str, Any]]
) -> None:
    for entry in entries:
        lines.append(f"[[{name}]]")
        for key, value in entry.items():
            lines.append(f"{quote_key(key)} = {toml_value(value)}")
        lines.append("")


def render_manifest(
    crate_manifest: dict[str, Any],
    workspace_manifest: dict[str, Any],
    commit: str,
    ref: str,
    tree: str,
    upstream_url: str,
    repository: str,
    crate_dir: Path,
) -> str:
    workspace = workspace_manifest["workspace"]
    workspace_package = workspace["package"]
    workspace_dependencies = workspace["dependencies"]

    package: dict[str, Any] = {}
    for key, value in crate_manifest["package"].items():
        if isinstance(value, dict) and value.get("workspace"):
            package[key] = workspace_package[key]
        else:
            package[key] = value
    package.update(
        {
            "description": "Standalone mirror of OpenAI Codex's apply_patch binary",
            "repository": repository,
            "publish": False,
        }
    )
    package.pop("readme", None)
    if "build" in package:
        package["build"] = adjust_source_path(package["build"])

    library = dict(crate_manifest.get("lib", {}))
    if "path" in library:
        library["path"] = adjust_source_path(library["path"])

    binaries = []
    for binary in crate_manifest.get("bin", []):
        adjusted = dict(binary)
        if "path" in adjusted:
            adjusted["path"] = adjust_source_path(adjusted["path"])
        binaries.append(adjusted)

    tests = []
    for test_path in sorted((crate_dir / "tests").glob("*.rs")):
        tests.append(
            {
                "name": test_path.stem,
                "path": adjust_source_path(str(test_path.relative_to(crate_dir))),
            }
        )

    lines = [
        "# @generated by sync/sync.py; do not edit by hand.",
        f"# Upstream: {upstream_url.removesuffix('.git')}/tree/{commit}/codex-rs/apply-patch",
        "",
    ]
    write_table(lines, "package", package)
    write_table(lines, "lib", library)
    write_array_table(lines, "bin", binaries)
    write_array_table(lines, "test", tests)

    for section in ("dependencies", "dev-dependencies", "build-dependencies"):
        resolved = resolve_dependencies(
            crate_manifest.get(section, {}),
            workspace_dependencies,
            commit,
            upstream_url,
        )
        write_table(lines, section, resolved)

    for target, target_values in crate_manifest.get("target", {}).items():
        for section in ("dependencies", "dev-dependencies", "build-dependencies"):
            resolved = resolve_dependencies(
                target_values.get(section, {}),
                workspace_dependencies,
                commit,
                upstream_url,
            )
            write_table(
                lines,
                f"target.{json.dumps(target)}.{section}",
                resolved,
            )

    write_table(lines, "features", crate_manifest.get("features", {}))
    write_table(
        lines,
        "package.metadata.upstream",
        {
            "repository": upstream_url.removesuffix(".git"),
            "path": "codex-rs/apply-patch",
            "reference": ref,
            "commit": commit,
            "tree": tree,
        },
    )
    for source, patches in workspace_manifest.get("patch", {}).items():
        write_table(lines, f"patch.{quote_key(source)}", patches)
    write_table(lines, "profile.release", {"lto": "thin", "strip": "symbols"})
    return "\n".join(lines).rstrip() + "\n"


def checkout_upstream(remote: str, ref: str, destination: Path) -> Path:
    run("git", "init", "--quiet", str(destination), cwd=destination.parent)
    run("git", "remote", "add", "origin", remote, cwd=destination)
    run(
        "git",
        "fetch",
        "--quiet",
        "--depth=1",
        "--filter=blob:none",
        "origin",
        ref,
        cwd=destination,
    )
    run("git", "sparse-checkout", "init", "--cone", cwd=destination)
    run(
        "git",
        "sparse-checkout",
        "set",
        str(UPSTREAM_CRATE),
        cwd=destination,
    )
    run("git", "checkout", "--quiet", "--detach", "FETCH_HEAD", cwd=destination)
    return destination


def synchronize(
    root: Path,
    ref: str,
    upstream_url: str,
    repository: str,
    source: str | None,
    skip_lock: bool,
) -> None:
    validate_ref(ref)
    with tempfile.TemporaryDirectory(prefix="codex-apply-patch-sync-") as temp:
        temporary = Path(temp)
        upstream = checkout_upstream(source or upstream_url, ref, temporary / "codex")
        commit = run("git", "rev-parse", "HEAD", cwd=upstream, capture=True)
        tree = run(
            "git",
            "rev-parse",
            f"HEAD:{UPSTREAM_CRATE}",
            cwd=upstream,
            capture=True,
        )

        crate_dir = upstream / UPSTREAM_CRATE
        workspace_path = upstream / "codex-rs/Cargo.toml"
        if not crate_dir.is_dir() or not workspace_path.is_file():
            raise RuntimeError("upstream checkout does not contain the expected Codex crate")

        crate_manifest = tomllib.loads((crate_dir / "Cargo.toml").read_text())
        workspace_manifest = tomllib.loads(workspace_path.read_text())

        stage = temporary / "stage"
        for name in GENERATED_CRATE_ENTRIES:
            source_entry = crate_dir / name
            staged_entry = stage / name
            if source_entry.is_dir():
                shutil.copytree(source_entry, staged_entry)
            elif source_entry.is_file():
                shutil.copy2(source_entry, staged_entry)

        manifest = render_manifest(
            crate_manifest,
            workspace_manifest,
            commit,
            ref,
            tree,
            upstream_url,
            repository,
            crate_dir,
        )
        (stage / "Cargo.toml").write_text(manifest)
        for name, value in (
            ("UPSTREAM_COMMIT", commit),
            ("UPSTREAM_REF", ref),
            ("UPSTREAM_TREE", tree),
        ):
            (stage / name).write_text(value + "\n")

        for name in ("LICENSE", "NOTICE"):
            source_file = upstream / name
            if source_file.is_file():
                shutil.copy2(source_file, stage / name)

        if not skip_lock:
            workspace_lock = upstream / "codex-rs/Cargo.lock"
            if not workspace_lock.is_file():
                raise RuntimeError("upstream checkout does not contain codex-rs/Cargo.lock")
            shutil.copy2(workspace_lock, stage / "Cargo.lock")
            run("cargo", "metadata", "--format-version", "1", cwd=stage, capture=True)

        for name in GENERATED_CRATE_ENTRIES:
            staged_entry = stage / name
            destination_entry = root / name
            if destination_entry.is_dir():
                shutil.rmtree(destination_entry)
            elif destination_entry.exists():
                destination_entry.unlink()
            if staged_entry.is_dir():
                shutil.copytree(staged_entry, destination_entry)
            elif staged_entry.is_file():
                shutil.copy2(staged_entry, destination_entry)

        legacy_crate = root / "upstream/apply-patch"
        if legacy_crate.exists():
            shutil.rmtree(legacy_crate)

        for name, relative_destination in GENERATED_FILES.items():
            staged_file = stage / name
            destination_file = root / relative_destination
            if staged_file.exists():
                destination_file.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(staged_file, destination_file)
            elif destination_file.exists():
                destination_file.unlink()
        for name in LEGACY_GENERATED_FILES:
            legacy_file = root / name
            if legacy_file.exists():
                legacy_file.unlink()
        legacy_state = root / "upstream/state"
        if legacy_state.exists():
            shutil.rmtree(legacy_state)
        legacy_upstream = root / "upstream"
        if legacy_upstream.exists() and not any(legacy_upstream.iterdir()):
            legacy_upstream.rmdir()

    print(f"synced {UPSTREAM_CRATE} at {commit} ({ref})")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="main", help="upstream branch, tag, or commit")
    parser.add_argument("--upstream", default=DEFAULT_UPSTREAM, help="upstream Git URL")
    parser.add_argument(
        "--repository",
        default=DEFAULT_REPOSITORY,
        help="repository URL written to Cargo package metadata",
    )
    parser.add_argument(
        "--source",
        help="optional local Codex Git checkout to use instead of the network",
    )
    parser.add_argument(
        "--skip-lock",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    root = Path(__file__).resolve().parent.parent
    synchronize(
        root=root,
        ref=args.ref,
        upstream_url=args.upstream,
        repository=args.repository,
        source=args.source,
        skip_lock=args.skip_lock,
    )


if __name__ == "__main__":
    main()
