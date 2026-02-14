#!/usr/bin/env python3
"""Draft a new FEATURES row (no file writes).

This helper is intentionally minimal and deterministic:
- Reads existing IDs from FEATURES/data.tsv
- Suggests next feature_id for a given category_key
- Emits a single TSV line matching current FEATURES header

It does NOT modify any TSV file.
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path


def find_repo_root(start: Path) -> Path:
    start = start.resolve()
    for p in [start] + list(start.parents):
        if (p / ".git").is_dir():
            return p
    return start


def read_header_and_rows(path: Path) -> tuple[list[str], list[list[str]]]:
    with path.open("r", encoding="utf-8", newline="") as f:
        r = csv.reader(f, delimiter="\t")
        header = next(r)
        rows = [row for row in r]
    return header, rows


def next_feature_id(category_key: str, existing_ids: list[str]) -> str:
    prefix = category_key.strip()
    pat = re.compile(rf"^{re.escape(prefix)}-(\d+)$")
    max_n = 0
    for fid in existing_ids:
        m = pat.match(fid.strip())
        if not m:
            continue
        try:
            n = int(m.group(1))
        except ValueError:
            continue
        if n > max_n:
            max_n = n
    return f"{prefix}-{max_n + 1:03d}"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Draft a new FEATURES TSV row")
    ap.add_argument("category_key", help="Category key (ex: FMW)")
    ap.add_argument("feature_category", help="Korean category title (display)")
    ap.add_argument("feature_title", help="English feature title")
    ap.add_argument(
        "--release-phase",
        default="TBD",
        help="release_phase value (default: TBD)",
    )
    ap.add_argument(
        "--status",
        default="드래프트",
        help="status value (default: 드래프트)",
    )
    ap.add_argument(
        "--description",
        default="",
        help="Korean one-liner. If empty, uses '<<AI>> TBD'",
    )
    ap.add_argument(
        "--related-ui",
        default="-",
        help="WINDOW_STRUCTURE.structure_key (default: -)",
    )
    ap.add_argument(
        "--objects",
        default="-",
        help="objects cell (default: -)",
    )
    args = ap.parse_args(argv)

    repo_root = find_repo_root(Path(__file__))
    if not (repo_root / ".git").is_dir():
        repo_root = find_repo_root(Path.cwd())

    features_path = repo_root / "04_FEATURE_INVENTORY/FEATURES/data.tsv"
    header, rows = read_header_and_rows(features_path)

    if "feature_id" not in header:
        print("ERROR: FEATURES header missing feature_id")
        return 2

    idx_feature_id = header.index("feature_id")
    existing_ids = []
    for row in rows:
        if len(row) <= idx_feature_id:
            continue
        existing_ids.append(row[idx_feature_id])

    fid = next_feature_id(args.category_key, existing_ids)
    description = args.description.strip() or "<<AI>> TBD"
    if not description.startswith("<<AI>> "):
        description = "<<AI>> " + description

    # Build row matching known v2 header.
    # Current header in this repo: feature_category, category_key, feature_title, feature_id,
    # release_phase, status, description, related_ui, objects
    col_map = {
        "feature_category": args.feature_category.strip(),
        "category_key": args.category_key.strip(),
        "feature_title": args.feature_title.strip(),
        "feature_id": fid,
        "release_phase": args.release_phase.strip(),
        "status": args.status.strip(),
        "description": description,
        "related_ui": args.related_ui.strip() or "-",
        "objects": args.objects.strip() or "-",
    }

    out = [col_map.get(col, "-") for col in header]
    print("\t".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
