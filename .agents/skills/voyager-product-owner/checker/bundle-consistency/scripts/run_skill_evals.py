#!/usr/bin/env python3
"""Run deterministic eval cases for voyager-fi-ia-fs-consistency-checker."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class EvalResult:
    eval_id: int
    family: str
    prompt: str
    passed: bool
    details: list[str]


def load_evals(skill_root: Path) -> dict:
    path = skill_root / "evals" / "evals.json"
    return json.loads(path.read_text(encoding="utf-8"))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run deterministic evals for voyager-fi-ia-fs-consistency-checker")
    parser.add_argument("--output", type=Path, default=None, help="Optional path to write JSON summary")
    return parser.parse_args()


def run_eval_case(skill_root: Path, eval_case: dict) -> EvalResult:
    runner = eval_case["runner"]
    script = skill_root / "scripts" / runner["script"]
    repo_root = skill_root / runner["repo_root"]
    command = [
        sys.executable,
        str(script),
        runner["target"],
        "--repo-root",
        str(repo_root),
        "--json",
    ]
    proc = subprocess.run(command, capture_output=True, text=True)
    if proc.returncode not in (0, 1):
        return EvalResult(eval_case["id"], eval_case.get("family", "ungrouped"), eval_case["prompt"], False, [proc.stderr or proc.stdout or "script failed"])

    payload = json.loads(proc.stdout)
    issues = payload.get("issues", [])
    codes = [issue["code"] for issue in issues]
    fail_count = sum(1 for issue in issues if issue["severity"] == "FAIL")
    warn_count = sum(1 for issue in issues if issue["severity"] == "WARN")

    passed = True
    details: list[str] = []

    expected_ok = runner.get("expect_ok")
    if expected_ok is not None and payload.get("ok") != expected_ok:
        passed = False
        details.append(f"expected ok={expected_ok}, got ok={payload.get('ok')}")

    if fail_count != runner.get("expect_fail_count", fail_count):
        passed = False
        details.append(f"expected fail_count={runner.get('expect_fail_count')}, got {fail_count}")

    if warn_count != runner.get("expect_warn_count", warn_count):
        passed = False
        details.append(f"expected warn_count={runner.get('expect_warn_count')}, got {warn_count}")

    for code in runner.get("expect_issue_codes_present", []):
        if code not in codes:
            passed = False
            details.append(f"expected issue code missing: {code}")

    for code in runner.get("expect_issue_codes_absent", []):
        if code in codes:
            passed = False
            details.append(f"unexpected issue code present: {code}")

    if passed:
        details.append("all expectations satisfied")

    return EvalResult(eval_case["id"], eval_case.get("family", "ungrouped"), eval_case["prompt"], passed, details)


def main() -> int:
    args = parse_args()
    skill_root = Path(__file__).resolve().parent.parent
    evals = load_evals(skill_root)
    results = [run_eval_case(skill_root, eval_case) for eval_case in evals["evals"]]

    summary = {
        "skill_name": evals["skill_name"],
        "passed": sum(1 for result in results if result.passed),
        "failed": sum(1 for result in results if not result.passed),
        "families": {},
        "results": [
            {
                "eval_id": result.eval_id,
                "family": result.family,
                "prompt": result.prompt,
                "passed": result.passed,
                "details": result.details,
            }
            for result in results
        ],
    }

    for result in results:
        family = summary["families"].setdefault(result.family, {"passed": 0, "failed": 0})
        if result.passed:
            family["passed"] += 1
        else:
            family["failed"] += 1

    if args.output is not None:
        output_path = args.output.resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
