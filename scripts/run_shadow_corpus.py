#!/usr/bin/env python3
"""Run repeatable source-contract v1/v2 shadow evaluation outside validators."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from typing import Any


REQUIRED_CASE_FIELDS = {
    "id",
    "prompt",
    "fixtures",
    "relevant_files",
    "expected_constraints",
    "expected_tool_choice",
    "expected_stop_or_escalation",
    "old_result",
    "v2_result",
    "score",
    "failure_class",
    "class",
    "rubric",
}
SIGNALS = ("constraints", "tool_choice", "stop_or_escalation")
STRICT_PREFIX = "strict-"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--corpus", type=Path, default=Path("scripts/evals/shadow-corpus.json")
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--inject-missing-approval-boundary", action="store_true")
    return parser.parse_args()


def baseline_text(root: Path, path: str, ref: str) -> str | None:
    completed = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        cwd=root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return completed.stdout if completed.returncode == 0 else None


def apply_overlays(text: str, path: str, overlays: list[dict[str, Any]]) -> str:
    for overlay in overlays:
        if overlay["path"] != path:
            continue
        if overlay["operation"] != "replace":
            raise ValueError(f"unsupported overlay operation: {overlay['operation']}")
        if text.count(overlay["from"]) < overlay["count"]:
            raise ValueError(f"overlay source not found enough times in {path}")
        text = text.replace(overlay["from"], overlay["to"], overlay["count"])
    return text


def source_text(
    root: Path,
    path: str,
    version: str,
    baseline_ref: str,
    overlays: list[dict[str, Any]],
) -> str | None:
    text = (
        baseline_text(root, path, baseline_ref)
        if version == "v1"
        else ((root / path).read_text() if (root / path).is_file() else None)
    )
    return (
        None
        if text is None
        else apply_overlays(text, path, overlays if version == "v2" else [])
    )


def evaluate_assertion(
    root: Path,
    assertion: dict[str, Any],
    version: str,
    baseline_ref: str,
    overlays: list[dict[str, Any]],
) -> dict[str, Any]:
    path = assertion.get("path")
    if not isinstance(path, str):
        raise ValueError("assertion path must be a string")
    text = source_text(root, path, version, baseline_ref, overlays)
    if "path_exists" in assertion:
        passed = (text is not None) is assertion["path_exists"]
        operation, expected = "path_exists", assertion["path_exists"]
    elif "contains" in assertion:
        passed = text is not None and assertion["contains"] in text
        operation, expected = "contains", assertion["contains"]
    elif "not_contains" in assertion:
        passed = text is not None and assertion["not_contains"] not in text
        operation, expected = "not_contains", assertion["not_contains"]
    elif "regex" in assertion:
        passed = (
            text is not None
            and re.search(assertion["regex"], text, re.MULTILINE) is not None
        )
        operation, expected = "regex", assertion["regex"]
    else:
        raise ValueError(f"assertion for {path} has no supported operation")
    return {"path": path, "operation": operation, "expected": expected, "pass": passed}


def evaluate_version(
    root: Path,
    case: dict[str, Any],
    version: str,
    baseline_ref: str,
    overlays: list[dict[str, Any]],
) -> dict[str, Any]:
    signals = {}
    for signal in SIGNALS:
        assertions = case["rubric"][signal]
        checks = [
            evaluate_assertion(root, assertion, version, baseline_ref, overlays)
            for assertion in assertions
        ]
        signals[signal] = {
            "pass": all(check["pass"] for check in checks),
            "assertions": checks,
        }
    passed = all(signal["pass"] for signal in signals.values())
    return {
        "pass": passed,
        "signals": signals,
        "failure_class": None if passed else "source-contract-regression",
    }


def snapshot(
    root: Path,
    paths: list[str],
    version: str,
    baseline_ref: str,
    overlays: list[dict[str, Any]],
) -> dict[str, str | None]:
    return {
        path: None
        if (text := source_text(root, path, version, baseline_ref, overlays)) is None
        else hashlib.sha256(text.encode()).hexdigest()
        for path in paths
    }


def validate_case(case: dict[str, Any]) -> list[str]:
    errors = sorted(REQUIRED_CASE_FIELDS - case.keys())
    if errors:
        return [f"{case.get('id', '<missing-id>')}: missing {', '.join(errors)}"]
    if not case["id"].startswith("E") or not all(
        isinstance(case[field], list)
        for field in (
            "fixtures",
            "relevant_files",
            "expected_constraints",
            "expected_tool_choice",
            "expected_stop_or_escalation",
        )
    ):
        return [f"{case['id']}: invalid case shape"]
    if set(case["rubric"]) != set(SIGNALS) or not all(
        case["rubric"][signal] for signal in SIGNALS
    ):
        return [
            f"{case['id']}: rubric must have non-empty assertions for {', '.join(SIGNALS)}"
        ]
    return []


def summarize(results: list[dict[str, Any]]) -> dict[str, Any]:
    strict = [result for result in results if result["class"].startswith(STRICT_PREFIX)]
    general = [
        result for result in results if not result["class"].startswith(STRICT_PREFIX)
    ]
    strict_failures = [
        result["id"] for result in strict if result["passes"] != result["trials"]
    ]
    general_failures = [result["id"] for result in general if result["passes"] < 2]
    old_rate = sum(result["old_result"]["passes"] for result in results) / (
        len(results) * results[0]["trials"]
    )
    v2_rate = sum(result["v2_result"]["passes"] for result in results) / (
        len(results) * results[0]["trials"]
    )
    regression = old_rate - v2_rate
    deletion_blocked = (
        bool(strict_failures) or bool(general_failures) or regression > 0.03
    )
    return {
        "strict_cases": len(strict),
        "general_cases": len(general),
        "strict_failures": strict_failures,
        "general_failures": general_failures,
        "old_pass_rate": old_rate,
        "v2_pass_rate": v2_rate,
        "aggregate_regression": regression,
        "regression_budget": 0.03,
        "deletion_blocked": deletion_blocked,
        "verdict": "revise" if deletion_blocked else "defer",
        "deletion_action": "retain-all-v1-canonical-text",
    }


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    corpus = json.loads((root / args.corpus).read_text())
    cases = corpus.get("cases", [])
    errors = [error for case in cases for error in validate_case(case)]
    expected_ids = {f"E{number:02d}" for number in range(1, 19)}
    case_ids = [case.get("id") for case in cases]
    if len(case_ids) != len(expected_ids) or set(case_ids) != expected_ids:
        errors.append("corpus must contain E01 through E18 exactly once")
    if args.trials < 3:
        errors.append("adoption gate requires at least three trials")
    if errors:
        raise SystemExit("\n".join(errors))

    injection = (
        "missing-approval-boundary" if args.inject_missing_approval_boundary else None
    )
    overlays = corpus["failure_injections"][injection]["overlays"] if injection else []
    baseline_ref = corpus["fixed_settings"]["baseline_ref"]
    results = []
    for case in cases:
        old_trial = evaluate_version(root, case, "v1", baseline_ref, [])
        v2_trial = evaluate_version(root, case, "v2", baseline_ref, overlays)
        old_trials, v2_trials = [old_trial] * args.trials, [v2_trial] * args.trials
        results.append(
            {
                "id": case["id"],
                "class": case["class"],
                "prompt": case["prompt"],
                "fixtures": case["fixtures"],
                "relevant_files": case["relevant_files"],
                "expected_constraints": case["expected_constraints"],
                "expected_tool_choice": case["expected_tool_choice"],
                "expected_stop_or_escalation": case["expected_stop_or_escalation"],
                "old_result": {
                    "passes": old_trial["pass"] * args.trials,
                    "trials": old_trials,
                },
                "v2_result": {
                    "passes": v2_trial["pass"] * args.trials,
                    "trials": v2_trials,
                },
                "passes": v2_trial["pass"] * args.trials,
                "trials": args.trials,
                "score": sum(signal["pass"] for signal in v2_trial["signals"].values())
                / len(SIGNALS),
                "failure_class": v2_trial["failure_class"],
                "source_snapshots": {
                    "v1": snapshot(
                        root, case["relevant_files"], "v1", baseline_ref, []
                    ),
                    "v2": snapshot(
                        root, case["relevant_files"], "v2", baseline_ref, overlays
                    ),
                },
            }
        )
    evidence = {
        "task": 8,
        "runner": "scripts/run_shadow_corpus.py",
        "schema": str(args.corpus),
        "fixed_settings": {**corpus["fixed_settings"], "trials": args.trials},
        "failure_injection": injection,
        "source_contract_scope": "contains, not_contains, regex, and path_exists assertions against v1 baseline-ref and v2 working-tree content",
        "results": results,
        "summary": summarize(results),
        "limitations": "No live model executor is configured; static source-contract success must not authorize deletion.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
