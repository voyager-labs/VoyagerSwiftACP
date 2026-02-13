#!/usr/bin/env python3
"""Voyager Use Cases Checker.

Deterministic linting for `05_USE_CASES/*.md` Markdown docs.

Checks:
- `PREV:` / `NEXT:` link targets and consistency with `05_USE_CASES/index.md`
- Happy Path table references:
  - `Invoked Interaction` column prefers `INTERACTIONS.interaction_id` (`<FEATURE_ID>-<snake_slug>`, legacy `INT.*` tolerated)
  - `UI Surface` prefers `WINDOW_STRUCTURE.structure_key`

This script is intentionally dependency-free (stdlib only).
"""

from __future__ import annotations

import argparse
import csv
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence


USE_CASES_DIR = Path("05_USE_CASES")
USE_CASES_INDEX = USE_CASES_DIR / "index.md"

INTERACTIONS_TSV = Path("04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")
WINDOW_STRUCTURE_TSV = Path("03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv")


LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")

# interaction_id formats
# - Legacy: INT.* (kept for backward-compatible diagnostics)
# - Current: <FEATURE_ID>-<snake_slug> (example: FMW-001-open_new_file_manager_window)
LEGACY_INT_TOKEN_RE = re.compile(r"\bINT\.[A-Za-z0-9][A-Za-z0-9_.-]*\b")
INTERACTION_ID_TOKEN_RE = re.compile(
    r"\b(?:INT\.[A-Za-z0-9][A-Za-z0-9_.-]*|[A-Z]{2,10}-\d{3}-[a-z0-9_]+)\b"
)

IDLIKE_TOKEN_RE = re.compile(r"\b[A-Z]{2,10}\.[A-Za-z0-9][A-Za-z0-9_.-]*\b")

# `structure_key` can be just `file_manager_window` (no dot) or nested keys with dots.
DOT_KEYLIKE_RE = re.compile(r"\b[a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+\b")


def _try_set_csv_field_limit() -> None:
    try:
        _ = csv.field_size_limit(10 * 1024 * 1024)
    except Exception:
        pass


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    candidates = [start] + list(start.parents)
    for p in candidates:
        if (p / ".git").is_dir():
            return p
    return start


def iter_tsv(path: Path) -> tuple[list[str], Iterable[tuple[int, dict[str, str]]]]:
    f = path.open("r", encoding="utf-8", newline="")
    reader = csv.reader(f, delimiter="\t")
    try:
        header = next(reader)
    except StopIteration:
        f.close()
        raise ValueError(f"Empty TSV file: {path}")

    header_len = len(header)

    def _iter() -> Iterable[tuple[int, dict[str, str]]]:
        with f:
            for idx, row in enumerate(reader, start=2):
                r = list(row)
                if len(r) < header_len:
                    r = r + ([""] * (header_len - len(r)))
                elif len(r) > header_len:
                    r = r[:header_len]
                yield idx, dict(zip(header, r))

    return header, _iter()


def load_interaction_ids(repo_root: Path) -> set[str]:
    path = repo_root / INTERACTIONS_TSV
    header, it = iter_tsv(path)
    if "interaction_id" not in header:
        raise ValueError(f"Missing column 'interaction_id' in {INTERACTIONS_TSV}")
    out: set[str] = set()
    for _line, row in it:
        iid = row.get("interaction_id", "").strip()
        if iid and iid != "-":
            out.add(iid)
    return out


def load_structure_keys(repo_root: Path) -> set[str]:
    path = repo_root / WINDOW_STRUCTURE_TSV
    header, it = iter_tsv(path)
    if "structure_key" not in header:
        raise ValueError(f"Missing column 'structure_key' in {WINDOW_STRUCTURE_TSV}")
    out: set[str] = set()
    for _line, row in it:
        k = row.get("structure_key", "").strip()
        if k and k != "-":
            out.add(k)
    return out


def _normalize_md_text(s: str) -> str:
    # Keep this conservative; only normalize things that routinely appear in this repo.
    s = s.strip()
    s = s.replace("\\_", "_")
    s = s.replace("\\-", "-")
    s = s.replace("\\|", "|")
    s = s.replace("`", "")
    s = s.replace("**", "")
    return s.strip()


def _normalize_header_cell(s: str) -> str:
    s = _normalize_md_text(s).lower()
    s = re.sub(r"\s+", "", s)
    return s


def _parse_md_links(line: str) -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    for m in LINK_RE.finditer(line):
        label = m.group(1).strip()
        target = m.group(2).strip()
        out.append((label, target))
    return out


def _parse_md_table_row(line: str) -> list[str] | None:
    s = line.strip()
    if not s.startswith("|"):
        return None
    if s.count("|") < 2:
        return None
    parts = [p.strip() for p in s.strip("|").split("|")]
    return parts


def _is_alignment_row(cells: Sequence[str]) -> bool:
    # Typical Markdown alignment markers: --- / :--- / ---: / :---:
    for c in cells:
        t = c.strip()
        if t == "":
            continue
        if re.fullmatch(r":?-{3,}:?", t) is None:
            return False
    return True


def parse_uc_order_from_index(repo_root: Path) -> list[str]:
    index_path = repo_root / USE_CASES_INDEX
    content = index_path.read_text(encoding="utf-8")
    order: list[str] = []
    seen: set[str] = set()
    for line in content.splitlines():
        for _label, target in _parse_md_links(line):
            target = target.strip()
            if not target.startswith("05_USE_CASES/"):
                continue
            if not target.endswith(".md"):
                continue
            if target in (
                "05_USE_CASES/index.md",
                "05_USE_CASES/templates.md",
            ):
                continue
            if target in seen:
                continue
            order.append(target)
            seen.add(target)
    return order


@dataclass(frozen=True)
class Issue:
    level: str  # ERROR/WARN/INFO
    file: str
    line: int
    message: str


def check_nav(
    *,
    repo_root: Path,
    rel_path: str,
    expected_prev: str | None,
    expected_next: str | None,
    check_against_index: bool,
) -> list[Issue]:
    issues: list[Issue] = []
    path = repo_root / rel_path
    content = path.read_text(encoding="utf-8")

    prev_targets: set[str] = set()
    next_targets: set[str] = set()
    has_index_link = False

    for line_no, line in enumerate(content.splitlines(), start=1):
        for label, target in _parse_md_links(line):
            if target.strip() == "05_USE_CASES/index.md":
                has_index_link = True
            if label.upper().startswith("PREV:"):
                prev_targets.add(target.strip())
            if label.upper().startswith("NEXT:"):
                next_targets.add(target.strip())

    if not has_index_link:
        issues.append(
            Issue(
                level="WARN",
                file=rel_path,
                line=1,
                message="Missing USE_CASES index link to 05_USE_CASES/index.md",
            )
        )

    def _pick_single(kind: str, targets: set[str]) -> str | None:
        if not targets:
            return None
        if len(targets) == 1:
            return next(iter(targets))
        issues.append(
            Issue(
                level="WARN",
                file=rel_path,
                line=1,
                message=f"Multiple distinct {kind} targets found: {', '.join(sorted(targets))}",
            )
        )
        return next(iter(sorted(targets)))

    found_prev = _pick_single("PREV", prev_targets)
    found_next = _pick_single("NEXT", next_targets)

    # Existence checks (if present).
    for kind, target in (("PREV", found_prev), ("NEXT", found_next)):
        if not target:
            continue
        target_path = repo_root / target
        if not target_path.exists():
            issues.append(
                Issue(
                    level="ERROR",
                    file=rel_path,
                    line=1,
                    message=f"{kind} link target does not exist: {target}",
                )
            )

    # Index-order checks.
    if check_against_index:
        if expected_prev and found_prev != expected_prev:
            issues.append(
                Issue(
                    level="WARN",
                    file=rel_path,
                    line=1,
                    message=f"PREV target mismatch vs index.md (expected {expected_prev}, found {found_prev or '-'})",
                )
            )
        if expected_prev is None and found_prev is not None:
            issues.append(
                Issue(
                    level="WARN",
                    file=rel_path,
                    line=1,
                    message=f"Unexpected PREV target for first UC in index order: {found_prev}",
                )
            )

        if expected_next and found_next != expected_next:
            issues.append(
                Issue(
                    level="WARN",
                    file=rel_path,
                    line=1,
                    message=f"NEXT target mismatch vs index.md (expected {expected_next}, found {found_next or '-'})",
                )
            )
        if expected_next is None and found_next is not None:
            issues.append(
                Issue(
                    level="WARN",
                    file=rel_path,
                    line=1,
                    message=f"Unexpected NEXT target for last UC in index order: {found_next}",
                )
            )

    return issues


def check_happy_path_tables(
    *,
    repo_root: Path,
    rel_path: str,
    interaction_ids: set[str],
    structure_keys: set[str],
    strict: bool,
) -> list[Issue]:
    issues: list[Issue] = []
    path = repo_root / rel_path
    lines = path.read_text(encoding="utf-8").splitlines()

    # Collect table blocks.
    blocks: list[list[tuple[int, str]]] = []
    cur: list[tuple[int, str]] = []
    for i, line in enumerate(lines, start=1):
        if line.strip().startswith("|"):
            cur.append((i, line))
        else:
            if cur:
                blocks.append(cur)
                cur = []
    if cur:
        blocks.append(cur)

    for block in blocks:
        rows: list[tuple[int, list[str]]] = []
        for line_no, raw in block:
            parsed = _parse_md_table_row(raw)
            if parsed is None:
                continue
            rows.append((line_no, parsed))
        if not rows:
            continue

        # Find a header row containing both columns.
        header_idx = None
        col_invoked = None
        col_surface = None
        for idx, (_line_no, cells) in enumerate(rows):
            norm = [_normalize_header_cell(c) for c in cells]
            try:
                i_invoked = next(
                    i for i, c in enumerate(norm) if "invokedinteraction" in c
                )
                i_surface = next(i for i, c in enumerate(norm) if "uisurface" in c)
            except StopIteration:
                continue
            header_idx = idx
            col_invoked = i_invoked
            col_surface = i_surface
            break

        if header_idx is None or col_invoked is None or col_surface is None:
            continue

        header_line_no, header_cells = rows[header_idx]
        expected_cols = len(header_cells)
        if expected_cols <= max(col_invoked, col_surface):
            issues.append(
                Issue(
                    level="WARN",
                    file=rel_path,
                    line=header_line_no,
                    message="Happy Path header row has unexpected column layout; cannot validate references reliably",
                )
            )
            continue

        # Iterate data rows after header.
        for line_no, cells in rows[header_idx + 1 :]:
            if _is_alignment_row(cells):
                continue

            if len(cells) != expected_cols:
                issues.append(
                    Issue(
                        level="WARN",
                        file=rel_path,
                        line=line_no,
                        message=f"Table row column count mismatch (expected {expected_cols}, got {len(cells)})",
                    )
                )
                if len(cells) < expected_cols:
                    cells = cells + ([""] * (expected_cols - len(cells)))
                else:
                    cells = cells[:expected_cols]

            invoked_raw = _normalize_md_text(cells[col_invoked])
            surface_raw = _normalize_md_text(cells[col_surface])

            # Invoked Interaction checks
            if invoked_raw == "":
                issues.append(
                    Issue(
                        level="WARN",
                        file=rel_path,
                        line=line_no,
                        message="Invoked Interaction cell is empty (use '-' for not-applicable)",
                    )
                )
            elif invoked_raw != "-":
                tokens = sorted(set(INTERACTION_ID_TOKEN_RE.findall(invoked_raw)))
                if tokens:
                    unknown = [t for t in tokens if t not in interaction_ids]
                    for t in unknown:
                        issues.append(
                            Issue(
                                level="ERROR" if strict else "WARN",
                                file=rel_path,
                                line=line_no,
                                message=f"Unknown interaction_id referenced: {t}",
                            )
                        )

                    legacy = sorted(set(LEGACY_INT_TOKEN_RE.findall(invoked_raw)))
                    if legacy:
                        issues.append(
                            Issue(
                                level="WARN",
                                file=rel_path,
                                line=line_no,
                                message="Legacy INT.* interaction_id detected (prefer <FEATURE_ID>-<snake_slug>)",
                            )
                        )
                else:
                    # Non-interaction identifiers or free text.
                    idlikes = sorted(set(IDLIKE_TOKEN_RE.findall(invoked_raw)))
                    idlikes = [t for t in idlikes if not t.startswith("INT.")]
                    if idlikes:
                        issues.append(
                            Issue(
                                level="WARN",
                                file=rel_path,
                                line=line_no,
                                message=f"Invoked Interaction is not an INTERACTIONS.interaction_id (found: {', '.join(idlikes)})",
                            )
                        )
                    else:
                        issues.append(
                            Issue(
                                level="WARN",
                                file=rel_path,
                                line=line_no,
                                message="Invoked Interaction is free text (prefer <FEATURE_ID>-<snake_slug> interaction_id)",
                            )
                        )

            # UI Surface checks
            if surface_raw == "":
                issues.append(
                    Issue(
                        level="WARN",
                        file=rel_path,
                        line=line_no,
                        message="UI Surface cell is empty (use '-' for not-applicable)",
                    )
                )
            elif surface_raw != "-":
                # Only validate strings that plausibly refer to `structure_key`.
                # - Validate any dotted key-like tokens (e.g. `file_manager_window.content_pane...`).
                # - If the entire cell is a single key-like token (no spaces), validate that token.
                # Otherwise, assume the cell is an intentional human-readable label.

                dot_candidates = sorted(set(DOT_KEYLIKE_RE.findall(surface_raw)))
                for t in dot_candidates:
                    if t not in structure_keys:
                        issues.append(
                            Issue(
                                level="ERROR" if strict else "WARN",
                                file=rel_path,
                                line=line_no,
                                message=f"Unknown WINDOW_STRUCTURE.structure_key referenced: {t}",
                            )
                        )

                token = surface_raw
                looks_like_single_key = re.fullmatch(
                    r"[a-z][a-z0-9_.-]*", token
                ) is not None and ("_" in token or "." in token)
                if (
                    looks_like_single_key
                    and not dot_candidates
                    and token not in structure_keys
                ):
                    issues.append(
                        Issue(
                            level="ERROR" if strict else "WARN",
                            file=rel_path,
                            line=line_no,
                            message=f"Unknown WINDOW_STRUCTURE.structure_key referenced: {token}",
                        )
                    )

    return issues


def main(argv: Sequence[str] | None = None) -> int:
    _try_set_csv_field_limit()

    parser = argparse.ArgumentParser(
        description="Check Voyager USE_CASES markdown consistency"
    )
    _ = parser.add_argument(
        "--file",
        type=str,
        default="",
        help="Check a single use case file (repo-relative path)",
    )
    _ = parser.add_argument(
        "--all-files",
        action="store_true",
        help="Check all .md files under 05_USE_CASES/ (excluding index/templates/AGENTS)",
    )
    _ = parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat unknown interaction_id/structure_key references as errors",
    )
    _ = parser.add_argument(
        "--fail-on-warn",
        action="store_true",
        help="Exit non-zero if any warnings are present",
    )
    _ = parser.add_argument(
        "--repo-root",
        type=str,
        default="",
        help="Override repo root (defaults to searching for .git)",
    )
    args = parser.parse_args(argv)

    if args.repo_root:
        repo_root = Path(args.repo_root).expanduser().resolve()
    else:
        repo_root = find_repo_root(Path(__file__))
        if not (repo_root / ".git").is_dir():
            repo_root = find_repo_root(Path.cwd())

    errors: list[Issue] = []
    warns: list[Issue] = []
    infos: list[Issue] = []

    # Load SSOT keys.
    try:
        interaction_ids = load_interaction_ids(repo_root)
    except Exception as e:
        errors.append(
            Issue(
                level="ERROR",
                file=str(INTERACTIONS_TSV),
                line=1,
                message=f"Failed to load INTERACTIONS interaction_id set: {e}",
            )
        )
        interaction_ids = set()

    try:
        structure_keys = load_structure_keys(repo_root)
    except Exception as e:
        errors.append(
            Issue(
                level="ERROR",
                file=str(WINDOW_STRUCTURE_TSV),
                line=1,
                message=f"Failed to load WINDOW_STRUCTURE structure_key set: {e}",
            )
        )
        structure_keys = set()

    # Choose target files.
    target_files: list[str] = []
    if args.file:
        target_files = [args.file]
    elif args.all_files:
        uc_dir = repo_root / USE_CASES_DIR
        for p in sorted(uc_dir.glob("*.md")):
            if p.name in ("index.md", "templates.md", "AGENTS.md"):
                continue
            target_files.append(str(p.relative_to(repo_root)))
    else:
        try:
            target_files = parse_uc_order_from_index(repo_root)
        except Exception as e:
            errors.append(
                Issue(
                    level="ERROR",
                    file=str(USE_CASES_INDEX),
                    line=1,
                    message=f"Failed to parse use case order from index.md: {e}",
                )
            )
            target_files = []

    # Validate file existence.
    for rel in target_files:
        if not (repo_root / rel).exists():
            errors.append(
                Issue(
                    level="ERROR",
                    file=rel,
                    line=1,
                    message="Use case file referenced by check target list does not exist",
                )
            )

    # Precompute expected nav based on index order when applicable.
    expected_map: dict[str, tuple[str | None, str | None]] = {}
    if not args.file and not args.all_files and target_files:
        for i, rel in enumerate(target_files):
            expected_prev = target_files[i - 1] if i > 0 else None
            expected_next = target_files[i + 1] if i + 1 < len(target_files) else None
            expected_map[rel] = (expected_prev, expected_next)

    # Run checks.
    for rel in target_files:
        check_against_index = not args.file and not args.all_files
        exp_prev, exp_next = expected_map.get(rel, (None, None))
        for issue in check_nav(
            repo_root=repo_root,
            rel_path=rel,
            expected_prev=exp_prev,
            expected_next=exp_next,
            check_against_index=check_against_index,
        ):
            (errors if issue.level == "ERROR" else warns).append(issue)

        for issue in check_happy_path_tables(
            repo_root=repo_root,
            rel_path=rel,
            interaction_ids=interaction_ids,
            structure_keys=structure_keys,
            strict=args.strict,
        ):
            if issue.level == "ERROR":
                errors.append(issue)
            elif issue.level == "INFO":
                infos.append(issue)
            else:
                warns.append(issue)

    # Print issues.
    def _print(issue: Issue) -> None:
        print(f"{issue.level}: {issue.file}:{issue.line}: {issue.message}")

    for issue in errors:
        _print(issue)
    for issue in warns:
        _print(issue)
    for issue in infos:
        _print(issue)

    print(
        f"DONE: files={len(target_files)} errors={len(errors)} warnings={len(warns)} info={len(infos)}"
    )

    if errors:
        return 2
    if args.fail_on_warn and warns:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
