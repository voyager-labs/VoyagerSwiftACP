from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any


def _default_runs_path() -> Path:
    return (
        Path(__file__).resolve().parents[2]
        / "tests"
        / "evals"
        / "runs"
        / "collection_query_expected_dsl_runs.jsonl"
    )


def _iter_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        raise FileNotFoundError(str(path))
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        rows.append(json.loads(line))
    return rows


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Pretty-print eval runs JSONL.")
    parser.add_argument("--path", type=Path, default=_default_runs_path())
    parser.add_argument("--last", type=int, default=10, help="Print last N rows (default: 10).")
    parser.add_argument("--case", dest="case_id", type=str, default="", help="Filter by case_id.")
    parser.add_argument("--fail-only", action="store_true", help="Show only failed rows.")
    args = parser.parse_args(argv)

    rows = _iter_jsonl(args.path)

    if args.case_id:
        rows = [row for row in rows if row.get("case_id") == args.case_id]
    if args.fail_only:
        rows = [row for row in rows if not row.get("passed", False)]

    rows = rows[-max(args.last, 0) :] if args.last > 0 else rows

    for row in rows:
        sys.stdout.write(json.dumps(row, ensure_ascii=False, indent=2))
        sys.stdout.write("\n---\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
