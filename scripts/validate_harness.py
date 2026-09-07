#!/usr/bin/env python3
"""Validate harness structure; optionally compose the Xcode matrix gate."""
from __future__ import annotations

import argparse
import json
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

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--with-build-matrix", action="store_true",
        help="also run the required Xcode matrix gate in the same content root",
    )
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
    matrix_exit = None
    try:
        with validation_root(args.root.resolve(), mode) as content_root:
            paths = set(args.paths) if args.paths else git_paths(
                args.root.resolve(), mode, args.base_ref, content_root,
            )
            diagnostics = validate_harness(content_root, paths, mode)
            # The pure validator remains reusable for harness-only fixtures.
            # Hook and CI explicitly request the composite gate; absence of an
            # Xcode project or validator must never silently skip that request.
            if args.with_build_matrix:
                matrix_exit = _run_build_matrix_validator(content_root)
    except RuntimeError as error:
        parser.error(str(error))
    payload = json.loads(json_result("validate-harness", diagnostics, mode))
    payload["buildMatrix"] = {
        "status": "notRun" if matrix_exit is None else
        "passed" if matrix_exit == 0 else
        "blocked" if matrix_exit == 2 else "failed",
        "returncode": matrix_exit,
    }
    print(json.dumps(payload, ensure_ascii=True, sort_keys=True))
    print(f"validate-harness: {len(diagnostics)} diagnostic(s) in {mode} scope", file=sys.stderr)
    if matrix_exit == 2:
        return 2
    return 1 if diagnostics or matrix_exit else 0


if __name__ == "__main__":
    raise SystemExit(main())
