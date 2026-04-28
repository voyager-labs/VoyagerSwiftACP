#!/usr/bin/env python3
"""Audit IA OBJECTS definition quality and contract usage."""

from __future__ import annotations

import argparse
import csv
import json
import re
import tomllib
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any


REPO_MARKERS = [
    Path("PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv"),
    Path("PRODUCT/05_FEATURE_SPECS"),
]
OBJECTS_TSV = Path("PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv")
FEATURE_SPECS_DIR = Path("PRODUCT/05_FEATURE_SPECS")
CATEGORY_ORDER = ["Domain", "Conversation", "State", "Operation", "Rule"]
SEVERITY_ORDER = {"FAIL": 0, "WARN": 1, "INFO": 2}
KEY_PATTERN = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")


@dataclass
class ObjectRow:
    line_no: int
    category: str
    key: str
    label_ko: str
    summary: str


@dataclass
class Usage:
    contract_path: str
    role: str


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    path: str = "-"
    keys: list[str] = field(default_factory=list)


def normalize(value: str | None, default: str = "") -> str:
    if value is None:
        return default
    stripped = value.strip()
    return stripped if stripped else default


def normalize_compact(value: str | None) -> str:
    text = normalize(value, "").lower()
    return re.sub(r"[^0-9a-z가-힣]+", "", text)


def is_placeholder(value: str | None) -> bool:
    return normalize(value, "") in {"", "-"}


def is_tbd(value: str | None) -> bool:
    return normalize(value, "") == "TBD"


def key_tokens(key: str) -> list[str]:
    return [token for token in normalize(key, "").split("_") if token]


def compile_term_pattern(term: str) -> re.Pattern[str]:
    escaped = re.escape(term)
    if " " in term:
        escaped = escaped.replace(r"\ ", r"[\s_]+")
    return re.compile(rf"(?<![A-Za-z0-9_]){escaped}(?![A-Za-z0-9_])")


def find_repo_root(start: Path) -> Path:
    for candidate in [start.resolve(), *start.resolve().parents]:
        if all((candidate / marker).exists() for marker in REPO_MARKERS):
            return candidate
    raise RuntimeError("Could not locate voyager-documentation repo root")


def read_tsv_rows(path: Path) -> list[tuple[int, dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows: list[tuple[int, dict[str, str]]] = []
        for line_no, row in enumerate(reader, start=2):
            rows.append((line_no, {key: value or "" for key, value in row.items()}))
        return rows


def load_objects(path: Path) -> list[ObjectRow]:
    rows: list[ObjectRow] = []
    for line_no, row in read_tsv_rows(path):
        rows.append(
            ObjectRow(
                line_no=line_no,
                category=normalize(row.get("category"), ""),
                key=normalize(row.get("key"), ""),
                label_ko=normalize(row.get("label_ko"), ""),
                summary=normalize(row.get("summary"), ""),
            )
        )
    return rows


def iter_contract_paths(repo_root: Path) -> list[Path]:
    return sorted((repo_root / FEATURE_SPECS_DIR).rglob("contracts/*.toml"))


def normalize_list(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    normalized: list[str] = []
    for value in values:
        text = normalize(str(value), "")
        if text:
            normalized.append(text)
    return normalized


def add_usage(usages: dict[str, list[Usage]], key: str, contract_path: Path, role: str) -> None:
    object_key = normalize(key, "")
    if not object_key:
        return
    usages[object_key].append(Usage(contract_path=str(contract_path), role=role))


def collect_contract_usages(repo_root: Path) -> dict[str, list[Usage]]:
    usages: dict[str, list[Usage]] = defaultdict(list)
    for contract_path in iter_contract_paths(repo_root):
        with contract_path.open("rb") as handle:
            data = tomllib.load(handle)

        contract = data.get("contract", {})
        add_usage(
            usages,
            normalize(contract.get("primary_object_key") or contract.get("primary_object"), ""),
            contract_path,
            "contract.primary_object",
        )
        for key in normalize_list(contract.get("secondary_object_keys") or contract.get("secondary_objects")):
            add_usage(usages, key, contract_path, "contract.secondary_object")

        ownership = data.get("ownership", {})
        if not isinstance(ownership, dict):
            continue
        for ownership_key, ownership_data in ownership.items():
            if not isinstance(ownership_data, dict):
                continue
            add_usage(
                usages,
                normalize(ownership_data.get("target_object"), ""),
                contract_path,
                f"ownership.{ownership_key}.target_object",
            )
            for key in normalize_list(ownership_data.get("creates_objects")):
                add_usage(usages, key, contract_path, f"ownership.{ownership_key}.creates_objects")
            for key in normalize_list(ownership_data.get("preserves_objects")):
                add_usage(usages, key, contract_path, f"ownership.{ownership_key}.preserves_objects")
    return usages


def predict_category(key: str) -> tuple[str | None, str | None]:
    tokens = set(key_tokens(key))
    if key in {"action", "entry_action", "command", "execution"} or key.endswith("_action"):
        return "Operation", "action/command vocabulary"
    if key in {"scope", "condition", "filter"}:
        return "Rule", "rule vocabulary"
    if key.startswith("active_") or key.endswith("_catalog") or key.endswith("_snapshot"):
        return "State", "active/catalog/snapshot pattern"
    if "context" in tokens or key in {"selection", "history"}:
        return "State", "stateful context/selection/history pattern"
    if key in {"request", "request_message", "chat_session", "retrieve", "organize", "ask"}:
        return "Conversation", "conversation/request flow vocabulary"
    if tokens & {"chat", "session", "message", "response", "turn", "attachment", "intent"}:
        return "Conversation", "conversation/request flow vocabulary"
    if key in {"entry", "property", "directory", "collection", "page", "storage", "provider"}:
        return "Domain", "product-wide entity vocabulary"
    return None, None


def family_relation(left: str, right: str) -> tuple[str, str, str] | None:
    left_tokens = key_tokens(left)
    right_tokens = key_tokens(right)
    if not left_tokens or not right_tokens or left == right:
        return None

    shorter_tokens = left_tokens
    longer_tokens = right_tokens
    shorter_key = left
    longer_key = right
    if len(shorter_tokens) > len(longer_tokens):
        shorter_tokens, longer_tokens = longer_tokens, shorter_tokens
        shorter_key, longer_key = longer_key, shorter_key

    if len(shorter_tokens) == len(longer_tokens):
        return None
    if len(shorter_tokens) > 1 and len(longer_tokens) - len(shorter_tokens) > 1:
        return None

    if longer_tokens[: len(shorter_tokens)] == shorter_tokens:
        return shorter_key, longer_key, "prefix"
    if longer_tokens[-len(shorter_tokens) :] == shorter_tokens:
        return shorter_key, longer_key, "suffix"
    return None


def matches_focus(text: str, focus_terms: list[str]) -> bool:
    lowered = normalize(text, "").lower()
    return any(term in lowered for term in focus_terms)


def build_stats(rows: list[ObjectRow], usages: dict[str, list[Usage]]) -> dict[str, Any]:
    category_counts = Counter(row.category for row in rows)
    referenced = sum(1 for row in rows if usages.get(row.key))
    usage_count = sum(len(row_usages) for row_usages in usages.values())
    return {
        "objects_total": len(rows),
        "referenced_objects": referenced,
        "unreferenced_objects": len(rows) - referenced,
        "contract_object_refs": usage_count,
        "category_counts": {category: category_counts.get(category, 0) for category in CATEGORY_ORDER},
    }


def audit_objects(repo_root: Path, focus_terms: list[str]) -> tuple[dict[str, Any], list[Issue]]:
    objects_path = repo_root / OBJECTS_TSV
    rows = load_objects(objects_path)
    rows_by_key = {row.key: row for row in rows if row.key}
    usages = collect_contract_usages(repo_root)
    issues: list[Issue] = []

    for row in rows:
        row_path = f"{OBJECTS_TSV}:{row.line_no}"
        if row.category not in CATEGORY_ORDER:
            issues.append(
                Issue(
                    "FAIL",
                    "objects.category_unknown",
                    f"Object '{row.key or '-'}' uses unknown category '{row.category or '-'}'",
                    row_path,
                    [row.key] if row.key else [],
                )
            )
        if not row.key:
            issues.append(Issue("FAIL", "objects.key_missing", "Row is missing object key", row_path))
        elif row.key == "TBD":
            issues.append(Issue("FAIL", "objects.key_tbd", "Primary key column must not use TBD", row_path, [row.key]))
        elif not KEY_PATTERN.match(row.key):
            issues.append(
                Issue(
                    "FAIL",
                    "objects.key_invalid",
                    f"Object key '{row.key}' must use lowercase snake_case",
                    row_path,
                    [row.key],
                )
            )

        if is_placeholder(row.label_ko):
            issues.append(
                Issue(
                    "WARN",
                    "objects.label_missing",
                    f"Object '{row.key}' is missing label_ko",
                    row_path,
                    [row.key],
                )
            )
        elif is_tbd(row.label_ko):
            issues.append(
                Issue("WARN", "objects.label_tbd", f"Object '{row.key}' still uses TBD in label_ko", row_path, [row.key])
            )

        if is_placeholder(row.summary):
            issues.append(
                Issue(
                    "WARN",
                    "objects.summary_missing",
                    f"Object '{row.key}' is missing summary",
                    row_path,
                    [row.key],
                )
            )
        elif is_tbd(row.summary):
            issues.append(
                Issue("WARN", "objects.summary_tbd", f"Object '{row.key}' still uses TBD in summary", row_path, [row.key])
            )
        else:
            if normalize_compact(row.summary) in {normalize_compact(row.key), normalize_compact(row.label_ko)}:
                issues.append(
                    Issue(
                        "WARN",
                        "objects.summary_too_literal",
                        f"Object '{row.key}' summary is too literal and does not add product meaning",
                        row_path,
                        [row.key],
                    )
                )

            mentioned_keys = [
                other_key
                for other_key in rows_by_key
                if compile_term_pattern(other_key).search(row.summary)
            ]
            if mentioned_keys:
                issues.append(
                    Issue(
                        "WARN",
                        "objects.summary_mentions_raw_key",
                        f"Object '{row.key}' summary uses raw key names: {mentioned_keys[:3]}",
                        row_path,
                        [row.key, *mentioned_keys[:3]],
                    )
                )

        if not usages.get(row.key):
            issues.append(
                Issue(
                    "WARN",
                    "objects.unreferenced",
                    f"Object '{row.key}' is not referenced by current contracts",
                    row_path,
                    [row.key],
                )
            )

        predicted_category, reason = predict_category(row.key)
        if predicted_category and predicted_category != row.category:
            issues.append(
                Issue(
                    "WARN",
                    "objects.category_heuristic_mismatch",
                    (
                        f"Object '{row.key}' is categorized as '{row.category}' but heuristic suggests "
                        f"'{predicted_category}' ({reason})"
                    ),
                    row_path,
                    [row.key],
                )
            )

    for object_key, object_usages in sorted(usages.items()):
        if object_key in rows_by_key:
            continue
        usage_roles = sorted({usage.role for usage in object_usages})
        issues.append(
            Issue(
                "FAIL",
                "contract.object_unknown",
                (
                    f"Contract object key '{object_key}' is referenced but not defined in IA OBJECTS "
                    f"(roles: {usage_roles[:3]})"
                ),
                object_usages[0].contract_path,
                [object_key],
            )
        )

    labels: dict[str, list[ObjectRow]] = defaultdict(list)
    summaries: dict[str, list[ObjectRow]] = defaultdict(list)
    for row in rows:
        if not is_placeholder(row.label_ko) and not is_tbd(row.label_ko):
            labels[normalize_compact(row.label_ko)].append(row)
        if not is_placeholder(row.summary) and not is_tbd(row.summary):
            summaries[normalize_compact(row.summary)].append(row)

    for value, grouped_rows in labels.items():
        if not value or len(grouped_rows) < 2:
            continue
        label_text = grouped_rows[0].label_ko
        keys = [row.key for row in grouped_rows]
        lines = [str(row.line_no) for row in grouped_rows]
        issues.append(
            Issue(
                "WARN",
                "objects.label_duplicate",
                f"label_ko '{label_text}' is shared by multiple object rows at lines {lines}: {keys}",
                str(OBJECTS_TSV),
                keys,
            )
        )

    for value, grouped_rows in summaries.items():
        if not value or len(grouped_rows) < 2:
            continue
        summary_text = grouped_rows[0].summary
        keys = [row.key for row in grouped_rows]
        lines = [str(row.line_no) for row in grouped_rows]
        issues.append(
            Issue(
                "WARN",
                "objects.summary_duplicate",
                f"summary '{summary_text}' is shared by multiple object rows at lines {lines}: {keys}",
                str(OBJECTS_TSV),
                keys,
            )
        )

    for index, left in enumerate(rows):
        for right in rows[index + 1 :]:
            relation = family_relation(left.key, right.key)
            if not relation:
                continue

            shorter_key, longer_key, relation_type = relation
            shorter = rows_by_key[shorter_key]
            longer = rows_by_key[longer_key]
            same_label = normalize_compact(shorter.label_ko) and normalize_compact(shorter.label_ko) == normalize_compact(longer.label_ko)
            same_summary = normalize_compact(shorter.summary) and normalize_compact(shorter.summary) == normalize_compact(longer.summary)
            risk_reasons: list[str] = []
            if shorter.category == longer.category:
                risk_reasons.append("same category")
            if same_label:
                risk_reasons.append("same label")
            if same_summary:
                risk_reasons.append("same summary")
            if is_placeholder(shorter.summary) or is_placeholder(longer.summary):
                risk_reasons.append("missing summary")
            if not usages.get(shorter.key):
                risk_reasons.append("base key is unreferenced")

            severity = "WARN" if risk_reasons else "INFO"
            reason_suffix = f" Review signals: {', '.join(risk_reasons)}." if risk_reasons else ""
            issues.append(
                Issue(
                    severity,
                    "objects.family_overlap",
                    (
                        f"Key family overlap: '{shorter.key}' ({shorter.category}, line {shorter.line_no}) and "
                        f"'{longer.key}' ({longer.category}, line {longer.line_no}) share a {relation_type} noun sequence."
                        f"{reason_suffix}"
                    ),
                    str(OBJECTS_TSV),
                    [shorter.key, longer.key],
                )
            )

    if focus_terms:
        for row in rows:
            if not any(
                [
                    matches_focus(row.key, focus_terms),
                    matches_focus(row.label_ko, focus_terms),
                    matches_focus(row.summary, focus_terms),
                ]
            ):
                continue
            row_usages = usages.get(row.key, [])
            contract_count = len({usage.contract_path for usage in row_usages})
            issues.append(
                Issue(
                    "INFO",
                    "objects.focus_usage",
                    (
                        f"Focused object '{row.key}' has category '{row.category}', label '{row.label_ko or '-'}', "
                        f"and {len(row_usages)} contract references across {contract_count} contract file(s)"
                    ),
                    f"{OBJECTS_TSV}:{row.line_no}",
                    [row.key],
                )
            )

    if focus_terms:
        filtered_issues = []
        for issue in issues:
            if matches_focus(issue.code, focus_terms):
                filtered_issues.append(issue)
                continue
            if matches_focus(issue.message, focus_terms):
                filtered_issues.append(issue)
                continue
            if matches_focus(issue.path, focus_terms):
                filtered_issues.append(issue)
                continue
            if any(matches_focus(key, focus_terms) for key in issue.keys):
                filtered_issues.append(issue)
        issues = filtered_issues

    issues.sort(key=lambda issue: (SEVERITY_ORDER.get(issue.severity, 9), issue.code, issue.path, ",".join(issue.keys)))
    return build_stats(rows, usages), issues


def render_text(stats: dict[str, Any], issues: list[Issue]) -> str:
    lines = [
        (
            "SUMMARY: "
            f"objects={stats['objects_total']}, referenced={stats['referenced_objects']}, "
            f"unreferenced={stats['unreferenced_objects']}, contract_refs={stats['contract_object_refs']}"
        ),
        "CATEGORIES: " + ", ".join(f"{category}={count}" for category, count in stats["category_counts"].items()),
    ]

    for severity in ["FAIL", "WARN", "INFO"]:
        severity_issues = [issue for issue in issues if issue.severity == severity]
        if not severity_issues:
            continue
        lines.append("")
        lines.append(severity)
        for issue in severity_issues:
            key_suffix = f" [{', '.join(issue.keys)}]" if issue.keys else ""
            lines.append(f"- {issue.code}{key_suffix}: {issue.message} ({issue.path})")

    if not issues:
        lines.append("")
        lines.append("PASS")
        lines.append("- No FAIL/WARN/INFO issues found for the current scope.")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit IA OBJECTS definitions and contract usage.")
    parser.add_argument("--focus", action="append", default=[], help="Filter to one family or substring, for example: context")
    parser.add_argument("--json", action="store_true", help="Emit JSON output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = find_repo_root(Path.cwd())
    focus_terms = [term.strip().lower() for term in args.focus if term.strip()]
    stats, issues = audit_objects(repo_root, focus_terms)
    payload = {
        "ok": not any(issue.severity == "FAIL" for issue in issues),
        "focus": focus_terms,
        "stats": stats,
        "issues": [asdict(issue) for issue in issues],
    }

    if args.json:
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(render_text(stats, issues))
    return 0 if payload["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
