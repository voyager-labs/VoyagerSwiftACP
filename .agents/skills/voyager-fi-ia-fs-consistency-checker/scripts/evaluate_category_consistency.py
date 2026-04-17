#!/usr/bin/env python3
"""Run contract + feature bundle consistency checks for one category."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_MARKERS = [
    Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv"),
    Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"),
    Path("PRODUCT/05_FEATURE_SPECS"),
]

FEATURES_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv")


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    path: str
    source: str
    target: str


def find_repo_root(start: Path) -> Path:
    for candidate in [start.resolve(), *start.resolve().parents]:
        if all((candidate / marker).exists() for marker in REPO_MARKERS):
            return candidate
    raise RuntimeError("Could not locate voyager-documentation repo root")


def normalize(value: str | None, default: str = "") -> str:
    if value is None:
        return default
    stripped = value.strip()
    return stripped if stripped else default


def read_tsv_rows(path: Path) -> list[tuple[int, dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows: list[tuple[int, dict[str, str]]] = []
        for line_no, row in enumerate(reader, start=2):
            rows.append((line_no, {key: (value if value is not None else "") for key, value in row.items()}))
        return rows


def collect_feature_ids(repo_root: Path, category_key: str) -> list[str]:
    feature_ids = [
        normalize(row.get("feature_id"), "")
        for _line_no, row in read_tsv_rows(repo_root / FEATURES_TSV)
        if normalize(row.get("category_key"), "") == category_key and normalize(row.get("feature_id"), "")
    ]
    return sorted(feature_ids)


def run_json_script(script_path: Path, target: str, repo_root: Path | None = None) -> dict[str, Any]:
    command = [sys.executable, str(script_path), target, "--json"]
    if repo_root is not None:
        command.extend(["--repo-root", str(repo_root)])
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(f"Script failed: {' '.join(command)}\n{result.stderr or result.stdout}")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Script did not return JSON: {' '.join(command)}\n{result.stdout}") from exc
    payload["_returncode"] = result.returncode
    return payload


def collect_issues(payload: dict[str, Any], source: str, target: str) -> list[Issue]:
    return [
        Issue(
            severity=issue["severity"],
            code=issue["code"],
            message=issue["message"],
            path=issue.get("path", "-"),
            source=source,
            target=target,
        )
        for issue in payload.get("issues", [])
    ]


def summarize(category: str, feature_ids: list[str], issues: list[Issue]) -> str:
    fail_count = sum(1 for issue in issues if issue.severity == "FAIL")
    warn_count = sum(1 for issue in issues if issue.severity == "WARN")
    info_count = sum(1 for issue in issues if issue.severity == "INFO")
    result = "PASS" if fail_count == 0 else "FAIL"
    lines = [
        f"CATEGORY: {category}",
        f"FEATURES: {len(feature_ids)}",
        f"RESULT: {result}",
        "",
        "COUNTS",
        f"FAIL: {fail_count}",
        f"WARN: {warn_count}",
        f"INFO: {info_count}",
    ]
    for severity in ("FAIL", "WARN", "INFO"):
        matching = [issue for issue in issues if issue.severity == severity]
        if not matching:
            continue
        lines.extend(["", severity])
        for issue in matching:
            lines.append(f"- [{issue.source}:{issue.code}] {issue.target}: {issue.message} ({issue.path})")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate category contract + bundle consistency")
    parser.add_argument("category_key", help="Category key such as CBW")
    parser.add_argument("--json", action="store_true", help="Emit JSON result")
    parser.add_argument("--repo-root", type=Path, default=None, help="Override repo root detection")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve() if args.repo_root else find_repo_root(Path(__file__).resolve().parent)
    category_key = args.category_key.upper()
    feature_ids = collect_feature_ids(repo_root, category_key)
    if not feature_ids:
        raise SystemExit(f"No feature ids found for category: {category_key}")

    scripts_dir = Path(__file__).resolve().parent
    contract_payload = run_json_script(scripts_dir / "check_contract_consistency.py", category_key, repo_root=repo_root)
    bundle_payloads = {
        feature_id: run_json_script(scripts_dir / "check_feature_bundle.py", feature_id, repo_root=repo_root)
        for feature_id in feature_ids
    }

    issues = collect_issues(contract_payload, "contract", category_key)
    for feature_id, payload in bundle_payloads.items():
        issues.extend(collect_issues(payload, "bundle", feature_id))

    ok = contract_payload.get("ok", False) and all(payload.get("ok", False) for payload in bundle_payloads.values())
    if args.json:
        print(
            json.dumps(
                {
                    "category": category_key,
                    "repo_root": str(repo_root),
                    "feature_ids": feature_ids,
                    "ok": ok,
                    "issues": [issue.__dict__ for issue in issues],
                },
                ensure_ascii=False,
                indent=2,
            )
        )
    else:
        print(summarize(category_key, feature_ids, issues))

    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
