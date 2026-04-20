#!/usr/bin/env python3
"""Audit contract-driven consistency between category contracts and interaction specs."""

from __future__ import annotations

import argparse
import csv
import json
import re
import tomllib
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


REPO_MARKERS = [
    Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"),
    Path("PRODUCT/05_FEATURE_SPECS"),
]

INTERACTIONS_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")
FEATURE_SPECS_DIR = Path("PRODUCT/05_FEATURE_SPECS")


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    path: str = "-"


def normalize(value: str | None, default: str = "") -> str:
    if value is None:
        return default
    stripped = value.strip()
    return stripped if stripped else default


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
            clean_row = {key: (value if value is not None else "") for key, value in row.items()}
            rows.append((line_no, clean_row))
        return rows


def compile_term_pattern(term: str) -> re.Pattern[str]:
    escaped = re.escape(term)
    if " " in term:
        escaped = escaped.replace(r"\ ", r"[\s_]+")
    return re.compile(rf"(?<![A-Za-z0-9_]){escaped}(?![A-Za-z0-9_])")


def has_any_term(text: str, terms: list[str]) -> bool:
    return any(compile_term_pattern(term).search(text) for term in terms if normalize(term))


def spec_body_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def find_spec_paths(category_dir: Path, interaction_id: str) -> list[Path]:
    return [
        path
        for path in category_dir.rglob(f"{interaction_id}.md")
        if "contracts" not in path.parts and "flows" not in path.parts
    ]


def load_contract(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def check_contract_file(
    contract_path: Path,
    interactions_by_id: dict[str, tuple[int, dict[str, str]]],
    category_dir: Path,
) -> list[Issue]:
    issues: list[Issue] = []
    data = load_contract(contract_path)

    contract = data.get("contract", {})
    contract_id = normalize(contract.get("id"), contract_path.stem)
    category = normalize(contract.get("category"), "")
    primary_object = normalize(contract.get("primary_object_key") or contract.get("primary_object"), "")
    if not category:
        issues.append(Issue("FAIL", "contract.missing_category", "Contract is missing category", str(contract_path)))

    allowed = set(data.get("user_visible_states", {}).get("allowed", []) or data.get("user_visible_status", {}).get("allowed", []))
    forbidden = set(data.get("user_visible_states", {}).get("forbidden", []) or data.get("user_visible_status", {}).get("forbidden", []))
    if allowed & forbidden:
        issues.append(
            Issue(
                "FAIL",
                "contract.state_overlap",
                f"Allowed and forbidden states overlap: {sorted(allowed & forbidden)}",
                str(contract_path),
            )
        )

    state_table = data.get("state", {}) or data.get("status", {})
    object_terms = data.get("object_terms", {})
    ownership = data.get("ownership", {})
    transitions = data.get("transitions", {})

    for state_name, state_data in state_table.items():
        if allowed and state_name not in allowed:
            issues.append(
                Issue(
                    "FAIL",
                    "contract.state_not_allowed",
                    f"Declared state '{state_name}' is not listed in allowed states",
                    str(contract_path),
                )
            )
        if not state_data.get("terms"):
            issues.append(
                Issue(
                    "WARN",
                    "contract.state_terms_missing",
                    f"Declared state '{state_name}' has no terms list for prose matching",
                    str(contract_path),
                )
            )

    for transition_name, transition in transitions.items():
        from_state = normalize(transition.get("from"), "")
        to_state = normalize(transition.get("to"), "")
        trigger = normalize(transition.get("trigger"), "")
        if allowed and from_state not in allowed:
            issues.append(Issue("FAIL", "contract.transition_from_unknown", f"{transition_name}: unknown from-state '{from_state}'", str(contract_path)))
        if allowed and to_state not in allowed:
            issues.append(Issue("FAIL", "contract.transition_to_unknown", f"{transition_name}: unknown to-state '{to_state}'", str(contract_path)))
        if trigger and trigger not in ownership:
            issues.append(Issue("WARN", "contract.transition_trigger_unowned", f"{transition_name}: trigger '{trigger}' is not declared in ownership", str(contract_path)))

    for interaction_id, binding in ownership.items():
        if interaction_id not in interactions_by_id:
            issues.append(Issue("FAIL", "contract.unknown_interaction", f"Ownership references missing interaction '{interaction_id}'", str(contract_path)))
            continue

        _line_no, interaction_row = interactions_by_id[interaction_id]
        if category and normalize(interaction_row.get("category_key"), "") != category:
            issues.append(
                Issue(
                    "FAIL",
                    "contract.interaction_category_mismatch",
                    f"Ownership interaction '{interaction_id}' belongs to category '{interaction_row.get('category_key')}', expected '{category}'",
                    str(contract_path),
                )
            )

        reads = binding.get("reads", []) or []
        writes = binding.get("writes", []) or []
        for state_name in [*reads, *writes]:
            if allowed and state_name not in allowed:
                issues.append(Issue("FAIL", "contract.ownership_unknown_state", f"{interaction_id} references unknown state '{state_name}'", str(contract_path)))

        spec_paths = find_spec_paths(category_dir, interaction_id)
        if not spec_paths:
            issues.append(Issue("FAIL", "spec.missing", f"No FEATURE_SPEC found for '{interaction_id}'", str(contract_path)))
            continue
        if len(spec_paths) > 1:
            issues.append(Issue("FAIL", "spec.ambiguous", f"Multiple FEATURE_SPEC files found for '{interaction_id}'", str(contract_path)))
            continue

        spec_path = spec_paths[0]
        text = spec_body_text(spec_path)
        if contract_path.name not in text:
            issues.append(Issue("WARN", "spec.contract_reference_missing", f"{interaction_id} does not reference {contract_path.name}", str(spec_path)))

        target_object = normalize(binding.get("target_object"), primary_object)
        candidate_object_terms = object_terms.get(target_object, [])
        if target_object and candidate_object_terms and not has_any_term(text, candidate_object_terms):
            issues.append(Issue("WARN", "spec.object_term_missing", f"{interaction_id} does not mention expected object '{target_object}'", str(spec_path)))

        for state_name in [*reads, *writes]:
            terms = state_table.get(state_name, {}).get("terms", [state_name])
            if not has_any_term(text, terms):
                issues.append(Issue("WARN", "spec.state_term_missing", f"{interaction_id} does not mention expected state '{state_name}'", str(spec_path)))

        for forbidden_state in forbidden:
            terms = state_table.get(forbidden_state, {}).get("terms", [forbidden_state])
            if has_any_term(text, terms):
                issues.append(Issue("WARN", "spec.forbidden_state_term_present", f"{interaction_id} mentions forbidden state '{forbidden_state}'", str(spec_path)))

    if not ownership:
        issues.append(Issue("WARN", "contract.ownership_empty", f"Contract '{contract_id}' has no ownership entries", str(contract_path)))

    return issues


def collect_contract_paths(repo_root: Path, target: str) -> tuple[str, list[Path]]:
    path_like = Path(target)
    if path_like.suffix == ".toml":
        contract_path = path_like if path_like.is_absolute() else repo_root / path_like
        if not contract_path.exists():
            raise FileNotFoundError(f"Contract file not found: {target}")
        category = normalize(load_contract(contract_path).get("contract", {}).get("category"), contract_path.parent.parent.name.upper())
        return category, [contract_path]

    category = target.upper()
    contract_dir = repo_root / FEATURE_SPECS_DIR / category.lower() / "contracts"
    paths = sorted(contract_dir.glob("*.toml"))
    if not paths:
        raise FileNotFoundError(f"No contract TOML files found for category: {category}")
    return category, paths


def summarize(category: str, contract_paths: list[Path], issues: list[Issue]) -> str:
    fail_count = sum(1 for issue in issues if issue.severity == "FAIL")
    warn_count = sum(1 for issue in issues if issue.severity == "WARN")
    info_count = sum(1 for issue in issues if issue.severity == "INFO")
    result = "PASS" if fail_count == 0 else "FAIL"
    lines = [
        f"CATEGORY: {category}",
        f"CONTRACTS: {len(contract_paths)}",
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
            lines.append(f"- [{issue.code}] {issue.message} ({issue.path})")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit contract-driven consistency for one category or contract file")
    parser.add_argument("target", help="Category key like CBW or a path to one contract TOML file")
    parser.add_argument("--json", action="store_true", help="Emit JSON result")
    parser.add_argument("--repo-root", type=Path, default=None, help="Override repo root detection")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve() if args.repo_root else find_repo_root(Path(__file__).resolve().parent)
    category, contract_paths = collect_contract_paths(repo_root, args.target)
    category_dir = repo_root / FEATURE_SPECS_DIR / category.lower()

    interactions_rows = read_tsv_rows(repo_root / INTERACTIONS_TSV)
    interactions_by_id = {
        normalize(row.get("interaction_id"), ""): (line_no, row)
        for line_no, row in interactions_rows
        if normalize(row.get("interaction_id"), "")
    }

    issues: list[Issue] = [
        Issue("INFO", "contracts.found", f"Loaded {len(contract_paths)} contract file(s)", str(path))
        for path in contract_paths
    ]
    for contract_path in contract_paths:
        issues.extend(check_contract_file(contract_path, interactions_by_id, category_dir))

    if args.json:
        payload = {
            "category": category,
            "contracts": [str(path) for path in contract_paths],
            "ok": not any(issue.severity == "FAIL" for issue in issues),
            "issues": [asdict(issue) for issue in issues],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print(summarize(category, contract_paths, issues))

    return 1 if any(issue.severity == "FAIL" for issue in issues) else 0


if __name__ == "__main__":
    raise SystemExit(main())
