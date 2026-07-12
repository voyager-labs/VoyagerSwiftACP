#!/usr/bin/env python3
"""Validate plan structure only; model evaluation belongs to the separate eval runner."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from scripts.agent_validation import git_paths, json_result, verify_plans


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
        paths = (
            set(args.paths) if args.paths else git_paths(args.root, mode, args.base_ref)
        )
    except RuntimeError as error:
        parser.error(str(error))
    diagnostics = verify_plans(args.root, paths)
    print(json_result("verify-plan", diagnostics, mode))
    print(
        f"verify-plan: {len(diagnostics)} diagnostic(s) in {mode} scope",
        file=sys.stderr,
    )
    return 1 if diagnostics else 0


if __name__ == "__main__":
    raise SystemExit(main())
