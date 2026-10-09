#!/usr/bin/env python3
"""Run the toolchain's swift-format on changed, existing Swift files in src/."""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / ".swift-format"
ZERO_SHA = "0" * 40


def git(*args):
    return subprocess.run(
        ["git", *args], cwd=ROOT, capture_output=True, check=True
    ).stdout


def commit(ref):
    if not ref:
        raise ValueError("Swift format requires a non-empty Git reference")

    return git("rev-parse", "--verify", "--end-of-options", ref + "^{commit}").decode().strip()


def committed_paths(base, head):
    head_commit = commit(head)
    if base == ZERO_SHA:
        return git("ls-tree", "-r", "--name-only", "-z", head_commit, "--", "src")

    base_commit = commit(base)
    merge_base = git("merge-base", base_commit, head_commit).decode().strip()
    return git("diff", "--name-only", "--diff-filter=ACMRT", "-z", merge_base, head_commit, "--", "src")


def changed_paths():
    base = os.environ.get("HARNESS_FORMAT_BASE")
    head = os.environ.get("HARNESS_FORMAT_HEAD")
    if (base is None) != (head is None):
        raise ValueError("Set HARNESS_FORMAT_BASE and HARNESS_FORMAT_HEAD together")

    if base is not None:
        changes = committed_paths(base, head)
        return [os.fsdecode(path) for path in changes.split(b"\0") if path]

    changes = committed_paths("origin/master", "HEAD")
    changes += git("diff", "--cached", "--name-only", "--diff-filter=ACMRT", "-z", "--", "src")
    changes += git("diff", "--name-only", "--diff-filter=ACMRT", "-z", "--", "src")
    changes += git("ls-files", "--others", "--exclude-standard", "-z", "--", "src")
    return [os.fsdecode(path) for path in changes.split(b"\0") if path]


def source_path(name):
    # Allow aliases outside the repository, but not links within its sources.
    path = Path(os.path.abspath(ROOT / name))
    try:
        resolved = path.resolve()
        relative = resolved.relative_to(ROOT)
        ancestors = (path, *path.parents)
        boundaries = [parent for parent in ancestors if parent.resolve() == ROOT]
    except (OSError, RuntimeError, ValueError):
        return None

    if not relative.parts:
        return None
    if relative.parts[0] != "src":
        return None
    if resolved.suffix != ".swift":
        return None
    if not boundaries:
        return None
    # Choose the outermost root alias so a src/ link back to ROOT cannot bypass this check.
    boundary = boundaries[-1]
    for parent in ancestors:
        if parent == boundary:
            break
        if parent.is_symlink():
            return None

    if not resolved.is_file():
        return None

    return relative.as_posix()


def targets(names):
    explicit = bool(names)
    if not explicit:
        names = changed_paths()

    selected = set()
    for name in names:
        path = source_path(name)
        if path is None:
            if explicit:
                raise ValueError(f"Not an existing regular src/**/*.swift file: {name!r}")
            continue

        selected.add(path)

    return sorted(selected)


def post_edit_targets():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError as error:
        raise ValueError(f"Invalid PostToolUse JSON: {error}") from error

    if not isinstance(payload, dict):
        raise ValueError("PostToolUse input must be an object")
    if payload.get("tool_name") not in ("Edit", "Write"):
        raise ValueError("PostToolUse requires tool_name Edit or Write")

    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        raise ValueError("PostToolUse requires a tool_input object")

    name = tool_input.get("file_path")
    if not isinstance(name, str):
        raise ValueError("PostToolUse requires a string file_path")
    if not name:
        raise ValueError("PostToolUse file_path must not be empty")
    if "\0" in name:
        raise ValueError("PostToolUse file_path must not contain NUL")
    if not Path(name).is_absolute():
        raise ValueError("PostToolUse file_path must be absolute")

    path = source_path(name)
    if path is None:
        return []

    return [path]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("lint", "format"))
    parser.add_argument("files", nargs="*", help="Paths relative to the repository root (or absolute paths)")
    parser.add_argument("--post-edit", action="store_true", help="Lint the edited file from PostToolUse JSON on stdin")
    args = parser.parse_args()

    try:
        if args.post_edit:
            if args.mode != "lint":
                raise ValueError("--post-edit requires lint")
            if args.files:
                raise ValueError("--post-edit cannot be combined with explicit files")
            files = post_edit_targets()
        else:
            files = targets(args.files)

        if not files:
            print("Swift format: no eligible src/**/*.swift files; tool not run")
            return 0

        if not CONFIG.is_file():
            raise ValueError(f"Missing Swift format configuration: {CONFIG}")
        if shutil.which("swift") is None:
            raise ValueError("Swift format not run: swift is unavailable; use the Xcode 16.4 toolchain")

        command = ["swift", "format", args.mode]
        if args.mode == "lint":
            command.append("--strict")
        else:
            command.append("--in-place")

        command.extend(["--configuration", str(CONFIG), *files])
        print(f"Swift format: {args.mode} {len(files)} file(s)", flush=True)
        return subprocess.run(command, cwd=ROOT).returncode
    except subprocess.CalledProcessError as error:
        print("Swift format Git selection failed: " + os.fsdecode(error.stderr).strip(), file=sys.stderr)
        return error.returncode
    except (OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
