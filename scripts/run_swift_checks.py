#!/usr/bin/env python3
"""Run read-only Swift checks against an explicit Git snapshot.

The index is exported through a private index, never by stashing or checking out
user files. stdout is a receipt; child output goes to stderr. This is not a
compiler, a semantic ownership proof, or an agent-behavior evaluation.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from dataclasses import asdict, dataclass
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from collections.abc import Iterator, Sequence


@dataclass(frozen=True)
class CheckResult:
    name: str
    status: str
    returncode: int | None = None
    reason: str | None = None


def git(root: Path, *args: str, env: dict[str, str] | None = None) -> bytes:
    result = subprocess.run(
        ["git", *args], cwd=root, env=env, capture_output=True, check=False,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return result.stdout


def paths_from_nul(data: bytes) -> list[str]:
    return [os.fsdecode(value) for value in data.split(b"\0") if value]


def changed_paths(root: Path, mode: str, base: str | None) -> list[str]:
    if mode == "all":
        return paths_from_nul(git(root, "ls-files", "-z"))
    if mode == "staged":
        return paths_from_nul(git(root, "diff", "--cached", "--name-only", "-z", "--diff-filter=ACMRD"))
    if mode == "base-ref":
        base_sha = git(root, "rev-parse", "--verify", f"{base}^{{commit}}").decode().strip()
        ancestor = git(root, "merge-base", base_sha, "HEAD").decode().strip()
        return paths_from_nul(git(root, "diff", "--name-only", "-z", "--diff-filter=ACMRD", ancestor, "HEAD"))
    unstaged = paths_from_nul(git(root, "diff", "--name-only", "-z", "--diff-filter=ACMRD", "HEAD"))
    untracked = paths_from_nul(git(root, "ls-files", "--others", "--exclude-standard", "-z"))
    return sorted(set(unstaged + untracked))


@contextmanager
def snapshot(root: Path, mode: str) -> Iterator[tuple[Path, str | None]]:
    if mode in {"working-tree", "all"}:
        yield root, None
        return
    tree = git(root, "write-tree") if mode == "staged" else git(root, "rev-parse", "HEAD^{tree}")
    tree_sha = tree.decode().strip()
    with tempfile.TemporaryDirectory(prefix="voyager-swift-check-") as directory:
        temporary = Path(directory)
        content_root = temporary / "content"
        content_root.mkdir()
        environment = os.environ.copy()
        environment["GIT_INDEX_FILE"] = str(temporary / "index")
        git(root, "read-tree", tree_sha, env=environment)
        git(root, "checkout-index", "--all", f"--prefix={content_root}/", env=environment)
        yield content_root, tree_sha


def is_test(path: str) -> bool:
    return any(part == "Tests" or part.endswith("Tests") for part in Path(path).parts[:-1])


def is_swift_source(path: str) -> bool:
    return path.startswith("apps/macos/") and path.endswith(".swift") and not any(
        part.lower() in {"build", ".build", "deriveddata", "pods"} for part in Path(path).parts
    )


def safe_file(root: Path, relative: str) -> Path:
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()) or path.is_symlink():
        raise RuntimeError(f"check input escapes snapshot or is a symlink: {relative}")
    if not path.is_file():
        raise RuntimeError(f"required check input is missing: {relative}")
    return path


def run_check(name: str, args: Sequence[str], root: Path) -> CheckResult:
    try:
        completed = subprocess.run(
            list(args), cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, errors="replace", timeout=300, check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return CheckResult(name, "blocked", reason=str(error))
    if completed.stdout:
        print(completed.stdout, file=sys.stderr, end="")
    return CheckResult(name, "passed" if completed.returncode == 0 else "failed", completed.returncode)


def check_exit(results: Sequence[CheckResult]) -> int:
    if any(result.status == "blocked" for result in results):
        return 2
    return 1 if any(result.status == "failed" for result in results) else 0


def check_sources(root: Path, paths: list[str], checks: list[str]) -> list[CheckResult]:
    files = sorted(path for path in set(paths) if is_swift_source(path) and (root / path).is_file())
    for path in files:
        safe_file(root, path)
    results: list[CheckResult] = []
    tools = {"ast": ("ast-grep", "--version"), "format": ("swiftformat", "--version"), "lint": ("swiftlint", "version")}
    for check in checks:
        if not files:
            results.append(CheckResult(check, "notApplicable", reason="no Swift files in selected source scope"))
            continue
        probe = run_check(f"{check}:tool", ["mise", "exec", "--", *tools[check]], root)
        if probe.status != "passed":
            results.append(CheckResult(check, "blocked", probe.returncode, "required pinned tool unavailable"))
            continue
        if check == "format":
            config = safe_file(root, "apps/macos/.swiftformat")
            commands = [("format", ["mise", "exec", "--", "swiftformat", "--lint", "--config", str(config), *files])]
        elif check == "lint":
            commands = []
            for tests, config_name in [(False, ".swiftlint.yml"), (True, ".swiftlint-tests.yml")]:
                selected = [path for path in files if is_test(path) == tests]
                if selected:
                    config = safe_file(root, f"apps/macos/{config_name}")
                    commands.append((f"lint:{'tests' if tests else 'sources'}", ["mise", "exec", "--", "swiftlint", "--config", str(config), *selected]))
        else:
            commands = []
            rules = sorted((root / ".ast-grep/rules").rglob("*.yaml"))
            if not rules:
                raise RuntimeError("no AST rule files found in snapshot")
            production = [path for path in files if not is_test(path)]
            for rule in rules:
                safe_file(root, rule.relative_to(root).as_posix())
                segment = rule.parent.name
                if segment not in {"model", "reducer", "ui", "common"}:
                    raise RuntimeError(f"unregistered AST rule scope: {segment}")
                selected = [path for path in production if "/Ui/" in path] if segment == "ui" else production
                if selected:
                    commands.append((f"ast:{rule.stem}", ["mise", "exec", "--", "ast-grep", "scan", "--rule", str(rule), *selected]))
            if not commands:
                results.append(CheckResult("ast", "notApplicable", reason="no production Swift sources"))
        for name, command in commands:
            results.append(run_check(name, command, root))
    return results


def policy_changed(paths: list[str], check: str) -> bool:
    if "mise.toml" in paths or "scripts/run_swift_checks.py" in paths:
        return True
    if check == "ast":
        return "sgconfig.yml" in paths or any(path.startswith(".ast-grep/") for path in paths)
    if check == "format":
        return "apps/macos/.swiftformat" in paths
    return any(path in paths for path in ["apps/macos/.swiftlint.yml", "apps/macos/.swiftlint-tests.yml"])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--staged", action="store_true")
    group.add_argument("--base-ref")
    group.add_argument("--all", action="store_true")
    group.add_argument("--working-tree", action="store_true")
    parser.add_argument("--checks", nargs="+", choices=["ast", "format", "lint"], default=["ast", "format", "lint"])
    args = parser.parse_args()
    root = args.root.resolve()
    mode = "staged" if args.staged else "base-ref" if args.base_ref else "all" if args.all else "working-tree"
    tree_sha = None
    try:
        paths = changed_paths(root, mode, args.base_ref)
        with snapshot(root, mode) as (content_root, tree_sha):
            results = []
            all_paths = paths_from_nul(
                git(root, "ls-tree", "-r", "--name-only", "-z", tree_sha)
                if tree_sha else git(root, "ls-files", "-z")
            )
            for check in dict.fromkeys(args.checks):
                selected = sorted(set(all_paths + paths)) if policy_changed(paths, check) else paths
                results.extend(check_sources(content_root, selected, [check]))
                if check == "ast" and (policy_changed(paths, check) or args.all):
                    if not list((content_root / ".ast-grep/rule-tests").glob("*.yaml")):
                        raise RuntimeError("AST rule fixtures are missing")
                    results.append(run_check("ast:fixtures", ["mise", "exec", "--", "ast-grep", "test", "--skip-snapshot-tests"], content_root))
    except (RuntimeError, OSError) as error:
        results = [CheckResult("scope", "blocked", reason=str(error))]
    print(json.dumps({"tool": "swift-checks", "mode": mode, "tree": tree_sha, "checks": [asdict(result) for result in results]}, ensure_ascii=True, sort_keys=True))
    return check_exit(results)


if __name__ == "__main__":
    raise SystemExit(main())
