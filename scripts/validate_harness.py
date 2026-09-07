#!/usr/bin/env python3
"""Validate structural agent-harness contracts without model evaluations."""
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


def _run_build_matrix_validator(root: Path) -> int:
    """Run the snapshot's validator in the same snapshot, not the caller's cwd."""
    try:
        completed = subprocess.run(
            [sys.executable, "-m", "scripts.validate_build_matrix"],
            cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=120, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"build-matrix: blocked: {error}", file=sys.stderr)
        return 2
    if completed.stdout:
        print(completed.stdout, file=sys.stderr, end="")
    return completed.returncode


def main() -> int:
    from scripts.agent_validation import (
        git_paths, json_result, validate_harness, validation_root,
    )

    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--working-tree", action="store_true")
    scope.add_argument("--staged", action="store_true")
    scope.add_argument("--base-ref")
    scope.add_argument("--all", action="store_true")
    parser.add_argument("paths", nargs="*")
    args = parser.parse_args()
    mode = (
        "base-ref" if args.base_ref else "staged" if args.staged
        else "all" if args.all else "working-tree"
    )
    try:
        with validation_root(args.root.resolve(), mode) as content_root:
            paths = set(args.paths) if args.paths else git_paths(
                args.root.resolve(), mode, args.base_ref, content_root,
            )
            diagnostics = validate_harness(content_root, paths, mode)
            # Keep the temporary index export alive for every constituent check.
            build_matrix_exit = _run_build_matrix_validator(content_root)
    except RuntimeError as error:
        parser.error(str(error))
    print(json_result("validate-harness", diagnostics, mode))
    print(f"validate-harness: {len(diagnostics)} diagnostic(s) in {mode} scope", file=sys.stderr)
    if build_matrix_exit == 2:
        return 2
    return 1 if diagnostics or build_matrix_exit else 0


if __name__ == "__main__":
    raise SystemExit(main())
