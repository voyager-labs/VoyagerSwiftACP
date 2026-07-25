#!/usr/bin/env python3
"""Validate structural agent-harness contracts without running model evaluations."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from scripts.agent_validation import (
    git_paths,
    json_result,
    validate_harness,
    validation_root,
)

from scripts.validate_build_matrix import main as validate_build_matrix_main


def _run_build_matrix_validator() -> int:
    """Run the build matrix validator, sending its output to stderr."""
    import io

    old_stdout = sys.stdout
    sys.stdout = io.StringIO()
    try:
        exit_code = validate_build_matrix_main()
    finally:
        output = sys.stdout.getvalue()
        sys.stdout = old_stdout
        if output.strip():
            print(output.strip(), file=sys.stderr)
    return exit_code


def main() -> int:
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
        "base-ref"
        if args.base_ref
        else "staged"
        if args.staged
        else "all"
        if args.all
        else "working-tree"
    )
    try:
        with validation_root(args.root, mode) as content_root:
            paths = (
                set(args.paths)
                if args.paths
                else git_paths(args.root, mode, args.base_ref, content_root)
            )
            diagnostics = validate_harness(content_root, paths, mode)
    except RuntimeError as error:
        parser.error(str(error))
    print(json_result("validate-harness", diagnostics, mode))
    print(
        f"validate-harness: {len(diagnostics)} diagnostic(s) in {mode} scope",
        file=sys.stderr,
    )
    harness_exit = 1 if diagnostics else 0
    build_matrix_exit = _run_build_matrix_validator()
    return 1 if (harness_exit or build_matrix_exit) else 0


if __name__ == "__main__":
    raise SystemExit(main())
