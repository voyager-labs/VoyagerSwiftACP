#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import cast

ROOT_DIR = Path(__file__).resolve().parents[2]
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from scripts.dev.voyager_contexts import (
    CONTEXTS,
    DERIVED_DATA_PATH,
    context_to_json,
    normalize_paths,
    primary_lsp_context,
    print_json,
)


def cli_args() -> list[str]:
    args = sys.argv[1:]
    if args and args[0] == "--":
        return args[1:]
    return args


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Switch SourceKit-LSP/xcode-build-server to the Voyager macOS context that matches a scope or path."
    )
    parser.add_argument(
        "--scope", choices=sorted(CONTEXTS), help="Explicit LSP context to select."
    )
    parser.add_argument(
        "--path",
        action="append",
        default=[],
        help="Repo-relative or absolute path used to infer context. Can be repeated.",
    )
    parser.add_argument(
        "--json", action="store_true", help="Print the selected context as JSON."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Only print the selected context; do not generate buildServer.json.",
    )
    return parser.parse_args(cli_args())


def setup_context(
    context_name: str, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    context = CONTEXTS[context_name]
    env = os.environ.copy()
    env.update(
        {
            "PROJECT_PATH": context.project_path,
            "SCHEME": context.scheme,
            "DERIVED_DATA_PATH": str(DERIVED_DATA_PATH),
        }
    )
    return subprocess.run(
        [sys.executable, "scripts/dev/setup_sourcekit_lsp.py"],
        cwd=ROOT_DIR,
        env=env,
        check=False,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def main() -> None:
    args = parse_args()
    input_paths = cast(list[str], args.path)
    scope = cast(str | None, args.scope)
    dry_run = cast(bool, args.dry_run)
    json_output = cast(bool, args.json)

    paths = normalize_paths(input_paths)
    context = CONTEXTS[scope] if scope else primary_lsp_context(paths)[0]
    payload: dict[str, object] = {
        "context": context_to_json(context),
        "input_paths": [str(path) for path in paths],
        "dry_run": dry_run,
    }

    if dry_run:
        print_json(payload)
        return

    if not json_output:
        print(f"Selected LSP context: {context.name} ({context.scheme})", flush=True)
        print(f"Project: {context.project_path}", flush=True)
        print(f"DerivedData: {DERIVED_DATA_PATH}", flush=True)

    completed = setup_context(context.name, capture=json_output)
    if json_output:
        payload["result"] = {
            "returncode": completed.returncode,
            "stdout": completed.stdout,
            "stderr": completed.stderr,
        }
        print_json(payload)
    raise SystemExit(completed.returncode)


if __name__ == "__main__":
    main()
