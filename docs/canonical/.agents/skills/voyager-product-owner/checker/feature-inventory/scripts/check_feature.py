#!/usr/bin/env python3
"""Voyager Feature Inventory Checker.

Deterministic lookup and lightweight validation for FEATURE_INVENTORY TSV tables.

This script is intentionally dependency-free (stdlib only).
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections.abc import Iterable, Sequence
from pathlib import Path


FEATURES_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv")
FEATURES_SCHEMA = Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/schema.json")
FEATURE_CATEGORIES_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv")
WINDOW_STRUCTURE_TSV = Path("PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv")
INTERACTIONS_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")


def _try_set_csv_field_limit() -> None:
    # INTERACTIONS rows can be long; avoid csv.Error: field larger than field limit.
    try:
        _ = csv.field_size_limit(10 * 1024 * 1024)
    except Exception:
        pass


def find_repo_root(start: Path) -> Path:
    """Find repo root by walking upward until a .git directory is found."""
    start = start.resolve()
    candidates = [start] + list(start.parents)
    for p in candidates:
        if (p / ".git").is_dir():
            return p
    return start


def read_json(path: Path) -> dict[str, object]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            raise ValueError(f"Expected JSON object at top-level: {path}")
        return data
    except FileNotFoundError:
        raise
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON: {path}: {e}")


def normalize_row_len(row: list[str], header_len: int) -> tuple[list[str], list[str]]:
    """Pad or truncate a TSV row to header length.

    Returns: (normalized_row, issues)
    """
    issues: list[str] = []
    if len(row) < header_len:
        issues.append(
            f"row has {len(row)} columns; expected {header_len} (padding missing cells)"
        )
        row = row + ([""] * (header_len - len(row)))
    elif len(row) > header_len:
        issues.append(
            f"row has {len(row)} columns; expected {header_len} (truncating extra cells)"
        )
        row = row[:header_len]
    return row, issues


def iter_tsv(
    path: Path,
) -> tuple[list[str], Iterable[tuple[int, dict[str, str], list[str], list[str]]]]:
    """Yield TSV rows as dicts.

    Returns: (header, iterator yielding (line_no, row_dict, raw_row, issues))
    """
    f = path.open("r", encoding="utf-8", newline="")
    reader = csv.reader(f, delimiter="\t")
    try:
        header = next(reader)
    except StopIteration:
        f.close()
        raise ValueError(f"Empty TSV file: {path}")

    header_len = len(header)

    def _iter() -> Iterable[tuple[int, dict[str, str], list[str], list[str]]]:
        with f:
            for idx, row in enumerate(reader, start=2):
                row_list = list(row)
                normalized, issues = normalize_row_len(row_list, header_len)
                row_dict = dict(zip(header, normalized))
                yield idx, row_dict, normalized, issues

    return header, _iter()


def load_schema_columns(schema: dict[str, object]) -> list[str]:
    cols = schema.get("columns")
    if not isinstance(cols, list):
        raise ValueError("schema.json missing columns[]")
    names: list[str] = []
    for c in cols:
        if not isinstance(c, dict) or "name" not in c:
            raise ValueError("schema.json columns[] entry missing name")
        names.append(str(c["name"]))
    return names


def schema_required_columns(schema: dict[str, object]) -> set[str]:
    required: set[str] = set()
    cols = schema.get("columns")
    if not isinstance(cols, list):
        return required

    for c in cols:
        if isinstance(c, dict) and c.get("required") is True:
            required.add(str(c.get("name")))
    return required


def is_empty_value(value: str) -> bool:
    v = value.strip()
    return v == "" or v == "-"


def is_tbd_value(value: str) -> bool:
    return value.strip() == "TBD"


def is_ai_draft_value(value: str) -> bool:
    return value.startswith("<<AI>> ")


def print_kv(key: str, value: str) -> None:
    print(f"{key}: {value}")


def summarize_values(values: Sequence[str]) -> str:
    # Keep output stable and short.
    joined = ", ".join(values)
    return joined if len(joined) <= 120 else (joined[:117] + "...")


def load_category_maps(
    repo_root: Path,
) -> tuple[dict[str, dict[str, str]], dict[str, dict[str, str]]]:
    path = repo_root / FEATURE_CATEGORIES_TSV
    if not path.exists():
        return {}, {}
    _header, it = iter_tsv(path)
    by_key: dict[str, dict[str, str]] = {}
    by_title: dict[str, dict[str, str]] = {}
    for _line, row, _raw, _issues in it:
        key = row.get("category_key", "").strip()
        title = row.get("category_title", "").strip()
        if key:
            by_key[key] = row
        if title:
            by_title[title] = row
    return by_key, by_title


def load_window_structure_keys(repo_root: Path) -> set[str]:
    path = repo_root / WINDOW_STRUCTURE_TSV
    if not path.exists():
        return set()
    header, it = iter_tsv(path)
    if "structure_key" not in header:
        return set()
    keys: set[str] = set()
    for _line, row, _raw, _issues in it:
        k = row.get("structure_key", "").strip()
        if k:
            keys.add(k)
    return keys


def load_interactions_for_feature(
    repo_root: Path, feature_id: str
) -> list[tuple[int, dict[str, str]]]:
    path = repo_root / INTERACTIONS_TSV
    if not path.exists():
        return []
    header, it = iter_tsv(path)
    if "feature_id" not in header:
        return []
    rows: list[tuple[int, dict[str, str]]] = []
    for line_no, row, _raw, _issues in it:
        if row.get("feature_id", "").strip() == feature_id:
            rows.append((line_no, row))
    return rows


def pick_match_mode(query: str) -> str:
    # Heuristic: feature_id pattern like FMW-001 / EIX-012.
    if re.match(r"^[A-Z0-9]{2,10}-\d{3,}$", query.strip()):
        return "id"
    return "contains"


def find_features(
    repo_root: Path, query: str, match: str
) -> list[tuple[int, dict[str, str]]]:
    tsv_path = repo_root / FEATURES_TSV
    _header, it = iter_tsv(tsv_path)
    matches: list[tuple[int, dict[str, str]]] = []
    q = query.strip()

    for line_no, row, _raw, _issues in it:
        fid = row.get("feature_id", "")
        title = row.get("feature_title", "")
        if match == "id":
            if fid.strip() == q:
                matches.append((line_no, row))
        elif match == "title":
            if title.strip().lower() == q.lower():
                matches.append((line_no, row))
        elif match == "contains":
            hay = f"{fid}\n{title}\n{row.get('description', '')}".lower()
            if q.lower() in hay:
                matches.append((line_no, row))
        else:
            raise ValueError(f"Unknown match mode: {match}")

    return matches


def main(argv: Sequence[str] | None = None) -> int:
    _try_set_csv_field_limit()

    parser = argparse.ArgumentParser(
        description="Check a FEATURE entry in Voyager FEATURE_INVENTORY"
    )
    _ = parser.add_argument("query", help="feature_id (ex: FMW-001) or a search string")
    _ = parser.add_argument(
        "--match",
        choices=["auto", "id", "title", "contains"],
        default="auto",
        help="Matching mode (default: auto)",
    )
    _ = parser.add_argument(
        "--no-interactions",
        action="store_true",
        help="Do not load/print INTERACTIONS referencing the feature",
    )
    _ = parser.add_argument(
        "--max-interactions",
        type=int,
        default=50,
        help="Max interactions to print (0 = print all)",
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

    features_schema_path = repo_root / FEATURES_SCHEMA
    features_tsv_path = repo_root / FEATURES_TSV

    if not features_tsv_path.exists():
        print(f"ERROR: Missing TSV: {FEATURES_TSV}")
        print(f"Repo root: {repo_root}")
        return 2

    schema: dict[str, object] = {}
    if features_schema_path.exists():
        try:
            schema = read_json(features_schema_path)
        except Exception as e:
            print(f"WARN: Failed to read schema: {FEATURES_SCHEMA}: {e}")
            schema = {}
    else:
        print(f"WARN: Missing schema: {FEATURES_SCHEMA}")

    schema_cols: list[str] = []
    required_cols: set[str] = set()
    if schema:
        try:
            schema_cols = load_schema_columns(schema)
            required_cols = schema_required_columns(schema)
        except Exception as e:
            print(f"WARN: Bad schema format: {FEATURES_SCHEMA}: {e}")

    match_mode = args.match
    if match_mode == "auto":
        match_mode = pick_match_mode(args.query)

    try:
        matches = find_features(repo_root, args.query, match_mode)
    except Exception as e:
        print(f"ERROR: Failed to search FEATURES: {e}")
        return 2

    if not matches:
        print(f"NOT FOUND: {args.query}")
        print_kv("match", match_mode)
        print_kv("table", str(FEATURES_TSV))
        return 1

    if len(matches) > 1:
        print(f"AMBIGUOUS: {args.query}")
        print_kv("match", match_mode)
        print(f"candidates: {len(matches)}")
        for line_no, row in matches[:25]:
            fid = row.get("feature_id", "").strip()
            title = row.get("feature_title", "").strip()
            status = row.get("status", "").strip()
            print(f"- line {line_no}: {fid} | {title} | {status}")
        if len(matches) > 25:
            print(f"(truncated; total candidates: {len(matches)})")
        print("Hint: use --match id with an exact feature_id")
        return 1

    line_no, feature = matches[0]
    feature_id = feature.get("feature_id", "").strip()

    print("FOUND")
    print_kv("line", str(line_no))
    print_kv("feature_id", feature_id)
    print_kv("feature_title", feature.get("feature_title", "").strip())
    print_kv("feature_category", feature.get("feature_category", "").strip())
    if "category_key" in feature:
        print_kv("category_key", feature.get("category_key", "").strip())
    print_kv("release_phase", feature.get("release_phase", "").strip())
    print_kv("status", feature.get("status", "").strip())
    print_kv("related_ui", feature.get("related_ui", "").strip())
    print_kv("description", feature.get("description", "").strip())
    if "objects" in feature:
        print_kv("objects", feature.get("objects", "").strip())

    print("\nCHECKS")
    problems: list[str] = []

    # Validate schema/header alignment (best-effort).
    try:
        header, _it = iter_tsv(features_tsv_path)
        if schema_cols and header != schema_cols:
            problems.append(
                "WARN: TSV header does not match schema.columns[].name order"
            )
            problems.append(f"  header: {summarize_values(header)}")
            problems.append(f"  schema:  {summarize_values(schema_cols)}")
    except Exception as e:
        problems.append(f"WARN: Could not read TSV header: {FEATURES_TSV}: {e}")

    # Required fields.
    if required_cols:
        for col in sorted(required_cols):
            v = feature.get(col, "")
            if is_empty_value(v):
                problems.append(
                    f"ERROR: required column '{col}' is empty ('{v.strip()}')"
                )
    else:
        # Fallback to known required columns for this table.
        for col in ["feature_category", "feature_title", "feature_id"]:
            v = feature.get(col, "")
            if is_empty_value(v):
                problems.append(
                    f"ERROR: required column '{col}' is empty ('{v.strip()}')"
                )

    # Empty cells: prefer the repo-standard '-' sentinel for readability.
    empty_cells = [k for k, v in feature.items() if v.strip() == ""]
    if empty_cells:
        problems.append(
            f"WARN: empty cells (prefer '-' sentinel): {', '.join(sorted(empty_cells))}"
        )

    # AI drafts.
    ai_cols = [k for k, v in feature.items() if is_ai_draft_value(v)]
    if ai_cols:
        problems.append(
            f"WARN: AI draft markers present in: {', '.join(sorted(ai_cols))}"
        )

    # Category consistency.
    cat_by_key, cat_by_title = load_category_maps(repo_root)
    prefix = feature_id.split("-", 1)[0] if "-" in feature_id else ""
    feature_category = feature.get("feature_category", "").strip()

    feature_category_key = (
        feature.get("category_key", "").strip() if "category_key" in feature else ""
    )

    if feature_category_key and feature_category_key not in ("-", "TBD"):
        if feature_category_key not in cat_by_key:
            problems.append(
                f"WARN: FEATURES.category_key '{feature_category_key}' not found in FEATURE_CATEGORIES.category_key"
            )
        else:
            cat_title = (
                cat_by_key[feature_category_key].get("category_title", "").strip()
            )
            if cat_title and feature_category and cat_title != feature_category:
                problems.append(
                    f"WARN: feature_category does not match FEATURE_CATEGORIES.category_title for category_key ('{feature_category}' != '{cat_title}')"
                )

        if prefix and feature_category_key != prefix:
            problems.append(
                f"WARN: category_key '{feature_category_key}' does not match feature_id prefix '{prefix}'"
            )
    elif prefix:
        # Backward-compatible fallback when FEATURES.category_key is absent.
        if prefix not in cat_by_key:
            problems.append(
                f"WARN: feature_id prefix '{prefix}' not found in FEATURE_CATEGORIES.category_key"
            )
        else:
            cat_title = cat_by_key[prefix].get("category_title", "").strip()
            if cat_title and feature_category and cat_title != feature_category:
                problems.append(
                    f"WARN: feature_category does not match FEATURE_CATEGORIES.category_title for the same prefix ('{feature_category}' != '{cat_title}')"
                )
    if feature_category and feature_category not in cat_by_title:
        problems.append(
            f"WARN: feature_category '{feature_category}' not found in FEATURE_CATEGORIES.category_title"
        )

    # UI reference.
    related_ui = feature.get("related_ui", "").strip()
    if related_ui and related_ui != "-":
        structure_keys = load_window_structure_keys(repo_root)
        if structure_keys and related_ui not in structure_keys:
            problems.append(
                f"WARN: related_ui '{related_ui}' not found in WINDOW_STRUCTURE.structure_key"
            )
        elif not structure_keys:
            problems.append(
                "WARN: WINDOW_STRUCTURE keys not loaded; cannot validate related_ui"
            )

    # Print checks.
    if problems:
        for p in problems:
            print(p)
    else:
        print("OK: no issues found")

    # Interactions.
    if not args.no_interactions and feature_id:
        interactions = load_interactions_for_feature(repo_root, feature_id)
        print("\nINTERACTIONS")
        print_kv("count", str(len(interactions)))
        if interactions:
            by_status: dict[str, int] = {}
            for _line_no, it in interactions:
                s = it.get("status", "").strip() or "(empty)"
                by_status[s] = by_status.get(s, 0) + 1
            status_summary = ", ".join(f"{k}={v}" for k, v in sorted(by_status.items()))
            print_kv("by_status", status_summary)

            # Cross-table sanity checks (best-effort).
            structure_keys = load_window_structure_keys(repo_root)
            if not structure_keys:
                print(
                    "WARN: WINDOW_STRUCTURE keys not loaded; cannot validate related_region"
                )
            else:
                invalid_regions = {
                    it.get("related_region", "").strip()
                    for _line_no, it in interactions
                    if it.get("related_region", "").strip()
                    and it.get("related_region", "").strip() != "-"
                    and it.get("related_region", "").strip() not in structure_keys
                }
                if invalid_regions:
                    invalid_list = sorted(invalid_regions)
                    print_kv(
                        "warn_unknown_related_region",
                        f"{len(invalid_list)}: {summarize_values(invalid_list)}",
                    )

            desired_category_key = ""
            if feature_category_key not in ("", "-", "TBD"):
                desired_category_key = feature_category_key
            elif prefix:
                desired_category_key = prefix

            if desired_category_key:
                mismatched = {
                    it.get("category_key", "").strip()
                    for _line_no, it in interactions
                    if it.get("category_key", "").strip()
                    and it.get("category_key", "").strip() != desired_category_key
                }
                if mismatched:
                    mismatched_list = sorted(mismatched)
                    print_kv(
                        "warn_mismatched_category_key",
                        f"{len(mismatched_list)}: {summarize_values(mismatched_list)}",
                    )

            max_n = args.max_interactions
            if max_n < 0:
                max_n = 50
            to_show = interactions if max_n == 0 else interactions[:max_n]
            for _line_no, it in to_show:
                title = it.get("interaction_title", "").strip()
                iid = it.get("interaction_id", "").strip()
                itype = it.get("interaction_type", "").strip()
                status = it.get("status", "").strip()
                region = it.get("related_region", "").strip()
                if iid:
                    print(
                        f"- {title} | {iid} | {itype} | {status} | related_region={region}"
                    )
                else:
                    print(f"- {title} | {itype} | {status} | related_region={region}")
            if max_n != 0 and len(interactions) > max_n:
                print(f"(truncated; use --max-interactions 0 to print all)")
        else:
            print("WARN: no interactions reference this feature_id")

    # Exit code: not-found handled earlier; treat ERROR lines as non-zero.
    has_error = any(p.startswith("ERROR:") for p in problems)
    return 2 if has_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
