#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass
from typing import cast


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


def _run_git_head_lines(args: list[str], max_lines: int) -> tuple[bool, list[str], str]:
    p = subprocess.Popen(
        ["git", *args],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert p.stdout is not None
    assert p.stderr is not None

    lines: list[str] = []
    truncated = False
    try:
        for line in p.stdout:
            if len(lines) >= max_lines:
                truncated = True
                break
            lines.append(line.rstrip("\n"))
    finally:
        if truncated:
            p.terminate()
        _ = p.stdout.close()
        err = p.stderr.read()
        _ = p.stderr.close()
        rc = p.wait()
    return (rc == 0, lines, err.strip())


_ISSUE_KEY_PATTERNS: list[re.Pattern[str]] = [
    re.compile(r"\b[A-Z][A-Z0-9]+-\d+\b"),
    re.compile(r"\b[a-z][a-z0-9]+-\d+\b"),
]


def _extract_issue_keys(text: str) -> list[str]:
    keys: set[str] = set()
    for pat in _ISSUE_KEY_PATTERNS:
        matches = cast(list[str], pat.findall(text or ""))
        for m in matches:
            keys.add(m)
    return sorted(keys)


def _branch_type_hint(branch: str) -> str:
    if not branch or "/" not in branch:
        return ""
    prefix = branch.split("/", 1)[0].strip().lower()
    mapping = {
        "feature": "feat",
        "feat": "feat",
        "fix": "fix",
        "hotfix": "fix",
        "refactor": "refactor",
        "docs": "docs",
        "test": "test",
        "ci": "ci",
        "chore": "chore",
        "build": "build",
        "ui": "ui",
    }
    return mapping.get(prefix, "")


def _looks_like_secret(line: str) -> bool:
    s = line.lower()
    needles = [
        "begin private key",
        "api_key",
        "apikey",
        "secret",
        "token",
        "authorization:",
        "x-api-key",
        "password",
    ]
    return any(n in s for n in needles)


def _subject_style_stats(subjects: list[str]) -> str:
    if not subjects:
        return "(no commits)"

    conventional_re = re.compile(r"^(?P<type>[a-zA-Z]+)(\((?P<scope>[^)]+)\))?:\s+")

    type_counts: Counter[str] = Counter()
    scope_counts: Counter[str] = Counter()
    conventional = 0
    has_issue_key = 0
    non_ascii = 0

    for s in subjects:
        if any(ord(ch) > 127 for ch in s):
            non_ascii += 1
        if _extract_issue_keys(s):
            has_issue_key += 1
        m = conventional_re.match(s)
        if m:
            conventional += 1
            type_counts[m.group("type").lower()] += 1
            scope = m.group("scope")
            if scope:
                scope_counts[scope] += 1

    lines: list[str] = []
    lines.append(f"conventional_subjects: {conventional}/{len(subjects)}")
    lines.append(f"subjects_with_issue_key: {has_issue_key}/{len(subjects)}")
    lines.append(f"subjects_with_non_ascii: {non_ascii}/{len(subjects)}")

    if type_counts:
        top_types = ", ".join([f"{k}({v})" for k, v in type_counts.most_common(8)])
        lines.append(f"top_types: {top_types}")
    if scope_counts:
        top_scopes = ", ".join([f"{k}({v})" for k, v in scope_counts.most_common(10)])
        lines.append(f"top_scopes: {top_scopes}")

    return "\n".join(lines)


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
    _ = parser.add_argument(
        "--head-lines",
        type=int,
        default=1200,
        help="How many patch lines to include from the start.",
    )
    _ = parser.add_argument(
        "--tail-lines",
        type=int,
        default=1200,
        help="How many patch lines to include from the end.",
    )
    _ = parser.add_argument(
        "--max-commit-docs",
        type=int,
        default=12,
        help="How many *commit*.md files to excerpt.",
    )
    _ = parser.add_argument(
        "--recent-subjects",
        type=int,
        default=120,
        help="How many recent non-merge commit subjects to include.",
    )
    _ = parser.add_argument(
        "--recent-full-messages",
        type=int,
        default=8,
        help="How many recent non-merge full commit messages to include (truncated).",
    )
    _ = parser.add_argument(
        "--recent-full-max-lines",
        type=int,
        default=60,
        help="Max lines per full commit message excerpt.",
    )
    _ = parser.add_argument(
        "--dir-sample-limit",
        type=int,
        default=20,
        help="How many sample tracked paths to show per touched directory.",
    )
    _ = parser.add_argument(
        "--touched-dir-limit",
        type=int,
        default=10,
        help="How many touched directories to sample (deepest first).",
    )
    args = parser.parse_args()

    head_lines = int(cast(int, args.head_lines))
    tail_lines = int(cast(int, args.tail_lines))
    max_commit_docs = int(cast(int, args.max_commit_docs))
    recent_subjects = int(cast(int, args.recent_subjects))
    recent_full_messages = int(cast(int, args.recent_full_messages))
    recent_full_max_lines = int(cast(int, args.recent_full_max_lines))
    dir_sample_limit = int(cast(int, args.dir_sample_limit))
    touched_dir_limit = int(cast(int, args.touched_dir_limit))

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

    _print_section("Branch hints (best-effort)")
    issue_keys = _extract_issue_keys(branch)
    if issue_keys:
        print("issue_keys_from_branch:")
        for k in issue_keys:
            print(f"- {k}")
    else:
        print("issue_keys_from_branch: (none detected)")

    type_hint = _branch_type_hint(branch)
    print(f"type_hint_from_branch_prefix: {type_hint or '(none)'}")

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
    shortstat = _run_git(["diff", "--cached", "--shortstat"]).rstrip("\n")
    _print_cmd("git diff --cached --shortstat", shortstat)
    stat = _run_git(["diff", "--cached", "--stat"]).rstrip("\n")
    _print_cmd("git diff --cached --stat", stat)
    numstat_raw = _run_git(["diff", "--cached", "--numstat"]).rstrip("\n")
    _print_cmd("git diff --cached --numstat", numstat_raw)

    _print_section("Staged distribution (dirstat)")
    dirstat = _run_git(["diff", "--cached", "--dirstat=files,0"]).rstrip("\n")
    _print_cmd("git diff --cached --dirstat=files,0", dirstat)

    _print_section("Staged compact summary")
    compact_summary = _run_git(["diff", "--cached", "--compact-summary"]).rstrip("\n")
    _print_cmd("git diff --cached --compact-summary", compact_summary)
    summary = _run_git(["diff", "--cached", "--summary"]).rstrip("\n")
    _print_cmd("git diff --cached --summary", summary)
    check = _run_git(["diff", "--cached", "--check"], check=False).rstrip("\n")
    _print_cmd("git diff --cached --check", check)

    rows = _parse_numstat(numstat_raw)
    rows_sorted = sorted(
        rows, key=lambda r: (-(r.added + r.deleted), -r.added, -r.deleted, r.path)
    )

    _print_section("Staged file extensions (top)")
    ext_counts: Counter[str] = Counter()
    for p in staged_paths:
        base = p.rsplit("/", 1)[-1]
        if "." in base and not base.startswith("."):
            ext = base.rsplit(".", 1)[-1].lower()
        else:
            ext = "(none)"
        ext_counts[ext] += 1
    print("count  ext")
    for ext, c in ext_counts.most_common(15):
        print(f"{c:>5}  {ext}")

    _print_section("Scope candidates (heuristic)")
    scope_candidates: list[str] = []
    for p in staged_paths:
        if p.startswith("apps/backend/"):
            scope_candidates.append("backend")
        elif p.startswith("apps/macos/"):
            scope_candidates.append("macos")
        elif p.startswith("docs/"):
            scope_candidates.append("docs")
        elif p.startswith(".github/"):
            scope_candidates.append("ci")
        elif p.startswith("infra/"):
            scope_candidates.append("infra")

    if scope_candidates:
        for s, c in Counter(scope_candidates).most_common(8):
            print(f"{c:>3}  {s}")
        print("note: omit scope if ambiguous")
    else:
        print("(no obvious scope from paths)")

    _print_section("Repo top-level entries (HEAD)")
    top_entries = _run_git(["ls-tree", "--name-only", "HEAD"]).rstrip("\n")
    _print_cmd("git ls-tree --name-only HEAD", top_entries)

    _print_section("Touched directories (tracked samples)")
    touched_dirs: list[str] = []
    for p in staged_paths:
        d = os.path.dirname(p)
        touched_dirs.append(d if d else ".")
    uniq_dirs = sorted(set(touched_dirs), key=lambda d: (-d.count("/"), d))
    for d in uniq_dirs[: max(0, touched_dir_limit)]:
        print(f"----- {d}")
        ok, sample, err = _run_git_head_lines(
            ["ls-files", "--", d],
            max_lines=max(0, dir_sample_limit + 1),
        )
        if not ok:
            print(f"(git ls-files failed: {err or 'unknown error'})")
            print()
            continue
        if not sample:
            print("(no tracked files found)")
            print()
            continue
        clipped = sample[: max(0, dir_sample_limit)]
        for p in clipped:
            print(p)
        if len(sample) > dir_sample_limit:
            print("... (truncated) ...")
        print()

    _print_section("Staged files (top changes by lines, from numstat)")
    print("total  +  -  path")
    for r in rows_sorted[:20]:
        total = r.added + r.deleted
        print(f"{total:>5} {r.added:>3} {r.deleted:>3}  {r.path}")

    patch = _run_git(
        ["diff", "--cached", "--patch", "-U0", "--color=never"]
    )  # keep newlines
    patch_lines = _lines(patch)

    _print_section("Staged patch secret scan (best-effort)")
    suspicious = [ln for ln in patch_lines if _looks_like_secret(ln)]
    if suspicious:
        print(f"suspicious_lines: {len(suspicious)}")
        for ln in _clamp_lines(suspicious, 30, 10):
            print(ln)
    else:
        print("suspicious_lines: 0")

    _print_section("Staged patch (compact)")
    clamped = _clamp_lines(patch_lines, head_lines, tail_lines)
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
        f"Excerpts (first 200 lines) of up to {max_commit_docs} matched files"
    )
    for p in commit_md_files[:max_commit_docs]:
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
    subjects_raw = _run_git(
        ["log", "--no-merges", "-n", str(recent_subjects), "--pretty=format:%s"]
    ).rstrip("\n")
    subjects_list = [s for s in _lines(subjects_raw) if s]
    _print_cmd(
        f"git log --no-merges -n {recent_subjects} --pretty=format:%s",
        subjects_raw,
    )

    _print_section("Recent commit subject style stats (best-effort)")
    print(_subject_style_stats(subjects_list))

    _print_section("Recent full commit messages (truncated, for inference)")
    if recent_full_messages > 0:
        raw_full = _run_git(
            [
                "log",
                "--no-merges",
                "-n",
                str(recent_full_messages),
                "--pretty=format:----- %h%n%B",
            ]
        )
        full_lines = _lines(raw_full)
        current: list[str] = []
        emitted = 0
        for ln in full_lines:
            if ln.startswith("----- "):
                if current:
                    emitted += 1
                    for out_ln in _head(current, recent_full_max_lines):
                        print(out_ln)
                    if len(current) > recent_full_max_lines:
                        print("... (truncated) ...")
                    print()
                current = [ln]
                continue
            current.append(ln)
        if current and emitted < recent_full_messages:
            for out_ln in _head(current, recent_full_max_lines):
                print(out_ln)
            if len(current) > recent_full_max_lines:
                print("... (truncated) ...")
            print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
