#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable


def _run_git(args: list[str], *, check: bool = True) -> str:
    p = subprocess.run(
        ["git", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if check and p.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {p.stderr.strip()}")
    return p.stdout


def _run_git_maybe(args: list[str]) -> tuple[bool, str]:
    p = subprocess.run(
        ["git", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    return (p.returncode == 0, p.stdout)


def _print_section(title: str) -> None:
    print("\n" + "#" * 3 + f" {title}")


def _print_cmd(cmd: str, output: str) -> None:
    print(f"$ {cmd}")
    if output:
        print(output.rstrip("\n"))
    print()


def _lines(s: str) -> list[str]:
    return [line.rstrip("\n") for line in s.splitlines()]


def _head(lines: list[str], n: int) -> list[str]:
    return lines[:n]


def _tail(lines: list[str], n: int) -> list[str]:
    if n <= 0:
        return []
    return lines[-n:]


def _clamp_lines(lines: list[str], head_n: int, tail_n: int) -> list[str]:
    if len(lines) <= head_n + tail_n:
        return lines
    return [*lines[:head_n], "... (truncated) ...", *lines[-tail_n:]]


def _group_by_top_level(paths: Iterable[str]) -> list[tuple[str, int]]:
    counts: dict[str, int] = {}
    for p in paths:
        if not p:
            continue
        top = p.split("/", 1)[0] if "/" in p else "(root)"
        counts[top] = counts.get(top, 0) + 1
    return sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))


@dataclass(frozen=True)
class NumstatRow:
    added: int
    deleted: int
    path: str


def _parse_numstat(raw: str) -> list[NumstatRow]:
    rows: list[NumstatRow] = []
    for line in raw.splitlines():
        # numstat is TAB-delimited; path can contain spaces.
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        add_s, del_s, path = parts[0], parts[1], "\t".join(parts[2:])
        if add_s == "-":
            added = 0
        else:
            try:
                added = int(add_s)
            except ValueError:
                added = 0

        if del_s == "-":
            deleted = 0
        else:
            try:
                deleted = int(del_s)
            except ValueError:
                deleted = 0

        rows.append(NumstatRow(added=added, deleted=deleted, path=path))
    return rows


def _read_git_file(ref: str, path: str) -> tuple[bool, str]:
    # Try index (:) first, then HEAD.
    ok, out = _run_git_maybe(["show", f":{path}"])
    if ok:
        return True, out
    ok, out = _run_git_maybe(["show", f"{ref}:{path}"])
    if ok:
        return True, out
    return False, ""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Collect staged git context for commit-message generation.",
    )
    parser.add_argument(
        "--head-lines",
        type=int,
        default=1200,
        help="How many patch lines to include from the start.",
    )
    parser.add_argument(
        "--tail-lines",
        type=int,
        default=1200,
        help="How many patch lines to include from the end.",
    )
    parser.add_argument(
        "--max-commit-docs",
        type=int,
        default=12,
        help="How many *commit*.md files to excerpt.",
    )
    args = parser.parse_args()

    try:
        repo_root = _run_git(["rev-parse", "--show-toplevel"]).strip()
    except Exception as e:
        print(f"ERROR: not a git repository (or git unavailable): {e}", file=sys.stderr)
        return 2

    os.chdir(repo_root)

    _print_section("Repo root / index path")
    _print_cmd("git rev-parse --show-toplevel", repo_root)
    index_path = _run_git(["rev-parse", "--git-path", "index"]).strip()
    _print_cmd("git rev-parse --git-path index", index_path)

    _print_section("Preflight (refresh index)")
    _ = _run_git(["update-index", "-q", "--refresh"], check=False)
    _print_cmd("git update-index -q --refresh", "(done)")

    _print_section("Branch")
    branch = _run_git(["rev-parse", "--abbrev-ref", "HEAD"]).strip()
    _print_cmd("git rev-parse --abbrev-ref HEAD", branch)

    _print_section("Staged files")
    name_only = _run_git(["diff", "--cached", "--name-only"]).rstrip("\n")
    _print_cmd("git diff --cached --name-only", name_only)
    name_status = _run_git(["diff", "--cached", "--name-status"]).rstrip("\n")
    _print_cmd("git diff --cached --name-status", name_status)

    staged_paths = [p for p in _lines(name_only) if p]
    grouped = _group_by_top_level(staged_paths)
    _print_section("Staged files (grouped by top-level directory)")
    print("count  dir")
    for d, c in grouped:
        print(f"{c:>5}  {d}")

    _print_section("Staged summary (stat + numstat)")
    stat = _run_git(["diff", "--cached", "--stat"]).rstrip("\n")
    _print_cmd("git diff --cached --stat", stat)
    numstat_raw = _run_git(["diff", "--cached", "--numstat"]).rstrip("\n")
    _print_cmd("git diff --cached --numstat", numstat_raw)

    rows = _parse_numstat(numstat_raw)
    rows_sorted = sorted(
        rows, key=lambda r: (-(r.added + r.deleted), -r.added, -r.deleted, r.path)
    )

    _print_section("Staged files (top changes by lines, from numstat)")
    print("total  +  -  path")
    for r in rows_sorted[:20]:
        total = r.added + r.deleted
        print(f"{total:>5} {r.added:>3} {r.deleted:>3}  {r.path}")

    _print_section("Staged patch (compact)")
    patch = _run_git(
        ["diff", "--cached", "--patch", "-U0", "--color=never"]
    )  # keep newlines
    patch_lines = _lines(patch)
    clamped = _clamp_lines(patch_lines, args.head_lines, args.tail_lines)
    for line in clamped:
        print(line)

    _print_section("Commit convention references (best-effort)")
    template = _run_git(["config", "--get", "commit.template"], check=False).strip()
    _print_cmd("git config --get commit.template", template)

    # Find tracked *commit*.md files.
    ok, out = _run_git_maybe(["ls-files", ":(icase,glob)**/*commit*.md"])
    if ok:
        commit_md_files = [p for p in _lines(out) if p]
    else:
        all_files = [p for p in _lines(_run_git(["ls-files"])) if p]
        commit_md_files = [
            p for p in all_files if "commit" in p.lower() and p.lower().endswith(".md")
        ]

    _print_section("Matched *commit*.md files (tracked, up to 120)")
    for p in commit_md_files[:120]:
        print(p)

    _print_section(
        f"Excerpts (first 200 lines) of up to {args.max_commit_docs} matched files"
    )
    for p in commit_md_files[: args.max_commit_docs]:
        print(f"----- {p}")
        ok, content = _read_git_file("HEAD", p)
        if not ok:
            print("(missing in HEAD and index)")
            print()
            continue
        excerpt = _head(_lines(content), 200)
        print("\n".join(excerpt))
        print()

    _print_section("Common convention docs (best-effort)")
    common_docs = [
        "CONTRIBUTING.md",
        ".github/CONTRIBUTING.md",
        ".gitmessage",
        "commitlint.config.js",
        "commitlint.config.cjs",
        ".commitlintrc",
        ".commitlintrc.json",
        ".commitlintrc.yml",
        ".commitlintrc.yaml",
    ]
    for p in common_docs:
        ok, content = _read_git_file("HEAD", p)
        print(f"----- {p}")
        if not ok:
            print("(missing)")
            print()
            continue
        excerpt = _head(_lines(content), 200)
        print("\n".join(excerpt))
        print()

    _print_section("Recent commit subjects (for inference)")
    subjects = _run_git(
        ["log", "--no-merges", "-n", "80", "--pretty=format:%s%n"]
    ).rstrip("\n")
    _print_cmd("git log --no-merges -n 80 --pretty=format:%s%n", subjects)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
