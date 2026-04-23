#!/usr/bin/env python3
"""Audit contract-driven consistency between category contracts and interaction specs."""

from __future__ import annotations

import argparse
import csv
import json
import os
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
OBJECTS_TSV = Path("PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv")
FEATURE_SPECS_DIR = Path("PRODUCT/05_FEATURE_SPECS")
MARKDOWN_LINK_RE = re.compile(r"\]\(([^)]+)\)")


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
    parts = [re.escape(part) for part in re.split(r"[\s_]+", term.strip()) if part]
    escaped = r"[\s_]+".join(parts) if parts else re.escape(term)
    return re.compile(rf"(?<![A-Za-z0-9_]){escaped}(?![A-Za-z0-9_])")


def has_any_term(text: str, terms: list[str]) -> bool:
    return any(compile_term_pattern(term).search(text) for term in terms if normalize(term))


def has_exact_state_key(text: str, state_name: str) -> bool:
    if not normalize(state_name):
        return False
    return f"`{state_name}`" in text


def spec_body_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def find_spec_paths(category_dir: Path, interaction_id: str) -> list[Path]:
    return [
        path
        for path in category_dir.rglob(f"{interaction_id}.md")
        if "contracts" not in path.parts and "flows" not in path.parts
    ]


def collect_flow_paths(category_dir: Path) -> list[Path]:
    flow_dir = category_dir / "flows"
    if not flow_dir.exists():
        return []
    return sorted(flow_dir.glob("*.md"))


def relative_markdown_path(from_dir: Path, target_path: Path) -> str:
    return Path(os.path.relpath(target_path, start=from_dir)).as_posix()


def flow_references_spec(flow_path: Path, spec_path: Path) -> bool:
    expected = spec_path.resolve()
    text = spec_body_text(flow_path)
    for raw_target in MARKDOWN_LINK_RE.findall(text):
        target = raw_target.split("#", 1)[0].strip()
        if not target or "://" in target:
            continue
        if (flow_path.parent / target).resolve() == expected:
            return True
    return False


def collect_related_flow_paths_for_spec(flow_paths: list[Path], spec_path: Path) -> list[Path]:
    return [path for path in flow_paths if flow_references_spec(path, spec_path)]


def get_markdown_section_body(text: str, heading: str) -> str | None:
    pattern = re.compile(rf"^##\s+{re.escape(heading)}\s*$([\s\S]*?)(?=^##\s+|\Z)", re.MULTILINE)
    match = pattern.search(text)
    if not match:
        return None
    return match.group(1).strip()


def load_contract(path: Path) -> dict[str, Any]:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def load_object_keys(path: Path) -> set[str]:
    return {
        normalize(row.get("key"), "")
        for _line_no, row in read_tsv_rows(path)
        if normalize(row.get("key"), "")
    }


def load_category_doc_texts(category_dir: Path) -> dict[Path, str]:
    texts: dict[Path, str] = {}
    for path in sorted(category_dir.rglob("*")):
        if path.suffix not in {".md", ".toml"}:
            continue
        if path.is_file():
            texts[path] = spec_body_text(path)
    return texts


def ensure_known_object(
    object_name: str,
    object_keys: set[str],
    issues: list[Issue],
    code: str,
    message: str,
    contract_path: Path,
) -> None:
    if object_name and object_name not in object_keys:
        issues.append(Issue("FAIL", code, message.format(object_name=object_name), str(contract_path)))


def check_contract_file(
    contract_path: Path,
    interactions_by_id: dict[str, tuple[int, dict[str, str]]],
    category_dir: Path,
    flow_paths: list[Path],
    object_keys: set[str],
    category_doc_texts: dict[Path, str],
) -> list[Issue]:
    issues: list[Issue] = []
    data = load_contract(contract_path)

    contract = data.get("contract", {})
    contract_id = normalize(contract.get("id"), contract_path.stem)
    category = normalize(contract.get("category"), "")
    primary_object_key = normalize(contract.get("primary_object_key"), "")
    legacy_primary_object = normalize(contract.get("primary_object"), "")
    primary_object = normalize(primary_object_key or legacy_primary_object, "")
    secondary_object_keys = contract.get("secondary_object_keys") or []
    legacy_secondary_objects = contract.get("secondary_objects") or []
    secondary_objects = secondary_object_keys or legacy_secondary_objects
    if not category:
        issues.append(Issue("FAIL", "contract.missing_category", "Contract is missing category", str(contract_path)))
    if not primary_object:
        issues.append(Issue("FAIL", "contract.primary_object_missing", "Contract is missing primary object key", str(contract_path)))
    elif legacy_primary_object and not primary_object_key:
        issues.append(
            Issue(
                "WARN",
                "contract.primary_object_key_missing",
                "Contract still uses legacy `primary_object` without `primary_object_key`",
                str(contract_path),
            )
        )
    if legacy_secondary_objects and not secondary_object_keys:
        issues.append(
            Issue(
                "WARN",
                "contract.secondary_object_keys_missing",
                "Contract still uses legacy `secondary_objects` without `secondary_object_keys`",
                str(contract_path),
            )
        )
    ensure_known_object(
        primary_object,
        object_keys,
        issues,
        "contract.primary_object_unknown",
        "Primary object '{object_name}' is not defined in IA OBJECTS",
        contract_path,
    )
    for object_name in secondary_objects:
        ensure_known_object(
            normalize(object_name, ""),
            object_keys,
            issues,
            "contract.secondary_object_unknown",
            "Secondary object '{object_name}' is not defined in IA OBJECTS",
            contract_path,
        )
    normalized_secondary_objects = [normalize(object_name, "") for object_name in secondary_objects if normalize(object_name, "")]
    if primary_object and primary_object in normalized_secondary_objects:
        issues.append(
            Issue(
                "FAIL",
                "contract.primary_in_secondary",
                f"Primary object '{primary_object}' must not also appear in secondary objects",
                str(contract_path),
            )
        )
    seen_secondary: set[str] = set()
    for object_name in normalized_secondary_objects:
        if object_name in seen_secondary:
            issues.append(
                Issue(
                    "WARN",
                    "contract.secondary_object_duplicate",
                    f"Secondary object '{object_name}' is listed more than once",
                    str(contract_path),
                )
            )
        else:
            seen_secondary.add(object_name)

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
    vocabulary = data.get("vocabulary", {})
    object_terms = data.get("object_terms", {})
    ownership = data.get("ownership", {})
    transitions = data.get("transitions", {})
    in_scope_objects = {primary_object, *normalized_secondary_objects} - {""}

    for term_name in vocabulary:
        normalized_term = normalize(term_name, "")
        matching_paths = [
            str(path)
            for path, text in category_doc_texts.items()
            if path != contract_path and compile_term_pattern(normalized_term).search(text)
        ]
        if not matching_paths:
            issues.append(
                Issue(
                    "WARN",
                    "contract.local_vocabulary_unused",
                    f"Vocabulary term '{term_name}' is declared in {contract_path.name} but not referenced outside that contract",
                    str(contract_path),
                )
            )
        if normalized_term in object_keys:
            issues.append(
                Issue(
                    "WARN",
                    "contract.vocabulary_redefines_object_key",
                    f"Vocabulary term '{term_name}' duplicates an IA OBJECTS key",
                    str(contract_path),
                )
            )
    transition_targets_by_state: dict[str, set[str]] = {}
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
        entered_by = state_data.get("entered_by", []) or []
        for interaction_id in entered_by:
            if interaction_id not in ownership:
                issues.append(
                    Issue(
                        "WARN",
                        "contract.state_entered_by_unowned",
                        f"State '{state_name}' declares entered_by '{interaction_id}' but ownership has no such key",
                        str(contract_path),
                    )
                )
                continue
            writes = ownership.get(interaction_id, {}).get("writes", []) or []
            if state_name not in writes:
                issues.append(
                    Issue(
                        "WARN",
                        "contract.state_entered_by_write_mismatch",
                        f"State '{state_name}' says '{interaction_id}' enters it, but ownership does not write that state",
                        str(contract_path),
                    )
                )
    for state_name in allowed:
        if state_name not in state_table:
            issues.append(
                Issue(
                    "WARN",
                    "contract.allowed_state_unreferenced",
                    f"Allowed state '{state_name}' has no [state.{state_name}] or [status.{state_name}] definition",
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
        if from_state and from_state not in state_table:
            issues.append(
                Issue(
                    "WARN",
                    "contract.transition_from_undefined",
                    f"{transition_name}: from-state '{from_state}' has no state definition",
                    str(contract_path),
                )
            )
        if to_state and to_state not in state_table:
            issues.append(
                Issue(
                    "WARN",
                    "contract.transition_to_undefined",
                    f"{transition_name}: to-state '{to_state}' has no state definition",
                    str(contract_path),
                )
            )
        if from_state and to_state:
            transition_targets_by_state.setdefault(from_state, set()).add(to_state)
        if trigger and trigger not in ownership:
            issues.append(Issue("WARN", "contract.transition_trigger_unowned", f"{transition_name}: trigger '{trigger}' is not declared in ownership", str(contract_path)))
        elif trigger:
            writes = ownership.get(trigger, {}).get("writes", []) or []
            if to_state and to_state not in writes:
                issues.append(
                    Issue(
                        "WARN",
                        "contract.transition_trigger_write_mismatch",
                        f"{transition_name}: trigger '{trigger}' does not write target state '{to_state}' in ownership",
                        str(contract_path),
                    )
                )

    for state_name, state_data in state_table.items():
        declared_exits = {normalize(name, "") for name in state_data.get("exits_to", []) or [] if normalize(name, "")}
        transition_exits = transition_targets_by_state.get(state_name, set())
        if declared_exits and declared_exits != transition_exits:
            issues.append(
                Issue(
                    "FAIL",
                    "contract.state_exit_transition_mismatch",
                    f"State '{state_name}' exits_to {sorted(declared_exits)} but transitions declare {sorted(transition_exits)}",
                    str(contract_path),
                )
            )
        terminal = state_data.get("terminal")
        if terminal is False and not declared_exits and not transition_exits:
            issues.append(
                Issue(
                    "WARN",
                    "contract.state_without_transition_path",
                    f"Non-terminal state '{state_name}' has no exits_to or outgoing transition",
                    str(contract_path),
                )
            )

    for interaction_id, binding in ownership.items():
        if interaction_id not in interactions_by_id:
            issues.append(Issue("FAIL", "contract.unknown_interaction", f"Ownership references missing interaction '{interaction_id}'", str(contract_path)))
            continue

        _line_no, interaction_row = interactions_by_id[interaction_id]
        interaction_type = normalize(interaction_row.get("interaction_type"), "")
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
        target_object = normalize(binding.get("target_object"), primary_object)
        ensure_known_object(
            target_object,
            object_keys,
            issues,
            "contract.ownership_unknown_object",
            f"{interaction_id} references unknown object '{{object_name}}'",
            contract_path,
        )
        if target_object and target_object not in in_scope_objects:
            issues.append(
                Issue(
                    "WARN",
                    "contract.object_ref_outside_contract_scope",
                    f"{interaction_id} target_object '{target_object}' is outside contract scope {sorted(in_scope_objects)}",
                    str(contract_path),
                )
            )
        for object_name in binding.get("creates_objects", []) or []:
            normalized_object = normalize(object_name, "")
            ensure_known_object(
                normalized_object,
                object_keys,
                issues,
                "contract.ownership_unknown_object",
                f"{interaction_id} references unknown object '{{object_name}}'",
                contract_path,
            )
            if normalized_object and normalized_object not in in_scope_objects:
                issues.append(
                    Issue(
                        "WARN",
                        "contract.object_ref_outside_contract_scope",
                        f"{interaction_id} creates_objects includes '{normalized_object}' outside contract scope {sorted(in_scope_objects)}",
                        str(contract_path),
                    )
                )
        for object_name in binding.get("preserves_objects", []) or []:
            normalized_object = normalize(object_name, "")
            ensure_known_object(
                normalized_object,
                object_keys,
                issues,
                "contract.ownership_unknown_object",
                f"{interaction_id} references unknown object '{{object_name}}'",
                contract_path,
            )
            if normalized_object and normalized_object not in in_scope_objects:
                issues.append(
                    Issue(
                        "WARN",
                        "contract.object_ref_outside_contract_scope",
                        f"{interaction_id} preserves_objects includes '{normalized_object}' outside contract scope {sorted(in_scope_objects)}",
                        str(contract_path),
                    )
                )

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
        related_flow_paths = collect_related_flow_paths_for_spec(flow_paths, spec_path)
        missing_flow_refs = [
            flow_path.name
            for flow_path in related_flow_paths
            if f"]({relative_markdown_path(spec_path.parent, flow_path)})" not in text
        ]
        if missing_flow_refs:
            issues.append(
                Issue(
                    "WARN",
                    "spec.flow_reference_missing",
                    f"{interaction_id} does not reference related flow doc(s): {missing_flow_refs}",
                    str(spec_path),
                )
            )

        candidate_object_terms = object_terms.get(target_object, [])
        if target_object and candidate_object_terms and not has_any_term(text, candidate_object_terms):
            issues.append(Issue("WARN", "spec.object_term_missing", f"{interaction_id} does not mention expected object '{target_object}'", str(spec_path)))

        state_names_to_check = list(writes)
        if interaction_type == "display":
            state_names_to_check = [*reads, *writes]
        deduped_state_names: list[str] = []
        for state_name in state_names_to_check:
            if state_name not in deduped_state_names:
                deduped_state_names.append(state_name)

        for state_name in deduped_state_names:
            if not has_exact_state_key(text, state_name):
                issues.append(Issue("WARN", "spec.state_key_missing", f"{interaction_id} does not mention expected state key '{state_name}'", str(spec_path)))

        for forbidden_state in forbidden:
            if has_exact_state_key(text, forbidden_state):
                issues.append(Issue("WARN", "spec.forbidden_state_key_present", f"{interaction_id} mentions forbidden state '{forbidden_state}'", str(spec_path)))

    if not ownership:
        issues.append(Issue("WARN", "contract.ownership_empty", f"Contract '{contract_id}' has no ownership entries", str(contract_path)))

    return issues


def check_flow_files(flow_paths: list[Path], contract_paths: list[Path]) -> list[Issue]:
    issues: list[Issue] = []
    spec_link_pattern = re.compile(r"\]\(\.\./(?!contracts/)(?!flows/)[^)]+\.md\)")
    contract_link_pattern = re.compile(r"\]\(\.\./contracts/[^)]+\.toml\)")

    for flow_path in flow_paths:
        text = spec_body_text(flow_path)
        if not any(contract_path.name in text for contract_path in contract_paths):
            issues.append(
                Issue(
                    "FAIL",
                    "flow.contract_reference_missing",
                    f"Flow doc '{flow_path.name}' does not reference any category contract file",
                    str(flow_path),
                )
            )
        source_body = get_markdown_section_body(text, "Source")
        if source_body and "Related contracts:" in source_body and not contract_link_pattern.search(source_body):
            issues.append(
                Issue(
                    "WARN",
                    "flow.source_contract_link_missing",
                    f"Flow doc '{flow_path.name}' lists related contracts in Source without markdown links",
                    str(flow_path),
                )
            )
        if not spec_link_pattern.search(text):
            issues.append(
                Issue(
                    "FAIL",
                    "flow.spec_reference_missing",
                    f"Flow doc '{flow_path.name}' does not link any interaction spec markdown file",
                    str(flow_path),
                )
            )
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
    flow_paths = collect_flow_paths(category_dir)

    interactions_rows = read_tsv_rows(repo_root / INTERACTIONS_TSV)
    object_keys = load_object_keys(repo_root / OBJECTS_TSV)
    category_doc_texts = load_category_doc_texts(category_dir)
    interactions_by_id = {
        normalize(row.get("interaction_id"), ""): (line_no, row)
        for line_no, row in interactions_rows
        if normalize(row.get("interaction_id"), "")
    }

    issues: list[Issue] = [
        Issue("INFO", "contracts.found", f"Loaded {len(contract_paths)} contract file(s)", str(path))
        for path in contract_paths
    ]
    if not flow_paths:
        issues.append(
            Issue(
                "FAIL",
                "flow.missing",
                f"Category '{category}' has no required flow doc under PRODUCT/05_FEATURE_SPECS/{category.lower()}/flows/",
                str(category_dir / "flows"),
            )
        )
    else:
        issues.extend(
            Issue("INFO", "flows.found", f"Loaded {len(flow_paths)} flow doc(s)", str(path))
            for path in flow_paths
        )
        issues.extend(check_flow_files(flow_paths, contract_paths))
    for contract_path in contract_paths:
        issues.extend(check_contract_file(contract_path, interactions_by_id, category_dir, flow_paths, object_keys, category_doc_texts))

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
