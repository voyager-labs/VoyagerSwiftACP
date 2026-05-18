#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import os
import re
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

try:
    import yaml

    _HAS_YAML = True
except ImportError:
    _HAS_YAML = False


REQUIRED_SECTIONS = [
    "Intent",
    "Trigger / Entry Points",
    "Preconditions",
    "Expected Outcome",
    "State Changes",
    "User-visible Feedback",
    "Edge Cases / Failure Handling",
    "Acceptance Criteria",
    "Permissions / Dependencies",
    "Observability / Analytics",
    "Related Interactions",
    "Source",
]

REQUIRED_METADATA_FIELDS = {
    "interaction_id",
    "interaction_type",
    "feature",
    "category_key",
    "feature_id",
    "status",
    "phase",
    "summary",
    "related_region",
    "menu",
    "shortcut",
}

REPO_MARKERS = [
    Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"),
    Path("PRODUCT/05_FEATURE_SPECS"),
]

INTERACTIONS_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")

SECTION_RE = re.compile(r"^##\s+(.*)$")
MARKDOWN_LINK_RE = re.compile(r"\]\(([^)]+)\)")

ALLOWED_SOURCE_REFERENCE_PREFIXES = (
    "- Inventory row:",
    "- Contracts:",
    "- Flows:",
)

AC_TASK_ITEM_RE = re.compile(r"^\s*-\s+\[\s*\]\s+(.+)")
AC_FORMAL_END_RE = re.compile(r"한다\.\s*$")
AC_STRICT_CONDITIONAL_RE = re.compile(r"(상황에서|상태에서|상태인|경우에|조건에서|경우)")
AC_STRICT_TRIGGER_RE = re.compile(r"(하면|되면|실행하려\s*하면|실패하면)")

FI_CROSS_CHECK_FIELDS = (
    "interaction_type",
    "feature",
    "category_key",
    "feature_id",
    "status",
    "phase",
    "summary",
    "related_region",
    "menu",
    "shortcut",
)


class LintResult:
    def __init__(self, path: Path):
        self.path = path
        self.ok = True
        self.errors: List[str] = []
        self.warnings: List[str] = []
        self.headings: List[str] = []
        self.sections: Dict[str, List[str]] = {}
        self.metadata: Dict[str, str] = {}

    def fail(self, msg: str) -> None:
        self.ok = False
        self.errors.append(msg)

    def warn(self, msg: str) -> None:
        self.warnings.append(msg)


def parse_sections(text: str) -> Tuple[List[str], Dict[str, List[str]]]:
    headings: List[str] = []
    sections: Dict[str, List[str]] = {}
    current = ""
    for raw in text.splitlines():
        match = SECTION_RE.match(raw)
        if match:
            current = match.group(1).strip()
            headings.append(current)
            sections.setdefault(current, [])
            continue
        if current:
            sections[current].append(raw)
    return headings, sections


def _parse_frontmatter_yaml(text: str) -> Dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    end_idx = None
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == "---":
            end_idx = i
            break

    if end_idx is None:
        return {}

    yaml_text = "\n".join(lines[1:end_idx])
    try:
        data = yaml.safe_load(yaml_text)
        if isinstance(data, dict):
            return {str(k): (str(v) if v is not None else "") for k, v in data.items()}
    except yaml.YAMLError:
        pass
    return {}


def _parse_frontmatter_manual(text: str) -> Dict[str, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    metadata: Dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            return metadata
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        value = value.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
        metadata[key] = value
    return {}


def parse_frontmatter(text: str) -> Dict[str, str]:
    if _HAS_YAML:
        return _parse_frontmatter_yaml(text)
    return _parse_frontmatter_manual(text)


def find_repo_root(start: Path) -> Path:
    for candidate in [start.resolve(), *start.resolve().parents]:
        if all((candidate / marker).exists() for marker in REPO_MARKERS):
            return candidate
    raise RuntimeError("Could not locate voyager-documentation repo root")


def relative_markdown_path(from_dir: Path, target_path: Path) -> str:
    return Path(os.path.relpath(target_path, start=from_dir)).as_posix()


def flow_references_spec(flow_path: Path, spec_path: Path) -> bool:
    expected = spec_path.resolve()
    text = flow_path.read_text(encoding="utf-8")
    for raw_target in MARKDOWN_LINK_RE.findall(text):
        target = raw_target.split("#", 1)[0].strip()
        if not target or "://" in target:
            continue
        if (flow_path.parent / target).resolve() == expected:
            return True
    return False


def expected_flow_source_line(repo_root: Path, spec_path: Path) -> str | None:
    feature_specs_root = (repo_root / "PRODUCT/05_FEATURE_SPECS").resolve()
    resolved_spec = spec_path.resolve()
    try:
        relative_spec = resolved_spec.relative_to(feature_specs_root)
    except ValueError:
        return None

    if len(relative_spec.parts) < 3:
        return None
    if relative_spec.parts[1] in {"flows", "contracts"}:
        return None

    category_dir = feature_specs_root / relative_spec.parts[0]
    flow_dir = category_dir / "flows"
    if not flow_dir.exists():
        return None

    flow_paths = [path for path in sorted(flow_dir.glob("*.md")) if flow_references_spec(path, resolved_spec)]
    if not flow_paths:
        return None

    flow_links = ", ".join(
        f"[{path.name}]({relative_markdown_path(resolved_spec.parent, path)})" for path in flow_paths
    )
    return f"- Flows: {flow_links}"


def is_placeholder_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return True
    return stripped in {"-", "- TBD", "TBD"}


def section_has_concrete(lines: List[str]) -> bool:
    return any(not is_placeholder_line(line) for line in lines)


def is_tbd_line(line: str) -> bool:
    stripped = line.strip()
    if not stripped:
        return False
    return stripped in {"TBD", "- TBD", "- [ ] TBD"} or stripped.startswith("- TBD")


def metadata_value_is_tbd(value: str) -> bool:
    return value.strip() == "TBD"


def section_has_unresolved_tbd(lines: List[str]) -> bool:
    has_concrete = False
    has_tbd = False
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if is_tbd_line(line):
            has_tbd = True
            continue
        if stripped == "-":
            continue
        has_concrete = True
    return has_tbd and not has_concrete


def unsupported_source_reference_lines(lines: List[str]) -> List[str]:
    unsupported: List[str] = []
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if not stripped.startswith(ALLOWED_SOURCE_REFERENCE_PREFIXES):
            unsupported.append(stripped)
    return unsupported


def has_fields(metadata: Dict[str, str], required: Iterable[str]) -> Tuple[bool, List[str]]:
    missing = [field for field in required if field not in metadata or metadata[field].strip() == ""]
    return len(missing) == 0, missing


def load_interactions_map(repo_root: Path) -> Dict[str, Dict[str, str]]:
    tsv_path = repo_root / INTERACTIONS_TSV
    if not tsv_path.exists():
        return {}
    result: Dict[str, Dict[str, str]] = {}
    with tsv_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            iid = (row.get("interaction_id") or "").strip()
            if iid:
                clean = {k: (v if v is not None else "") for k, v in row.items()}
                result[iid] = clean
    return result


def _normalize_for_compare(value: str) -> str:
    v = value.strip()
    if v.startswith("<<AI>>"):
        v = v[len("<<AI>>"):].strip()
    return v


def validate_fi_match(
    metadata: Dict[str, str],
    interactions_map: Dict[str, Dict[str, str]],
) -> List[Tuple[str, str, str]]:
    iid = metadata.get("interaction_id", "").strip()
    if not iid or iid not in interactions_map:
        return []

    fi_row = interactions_map[iid]
    mismatches: List[Tuple[str, str, str]] = []
    for field in FI_CROSS_CHECK_FIELDS:
        fm_val = _normalize_for_compare(metadata.get(field, ""))
        fi_val = _normalize_for_compare(fi_row.get(field, ""))
        if not fm_val or not fi_val:
            continue
        if fm_val != fi_val:
            mismatches.append((field, fm_val, fi_val))
    return mismatches


def validate_ac_pattern(lines: List[str], strict: bool) -> List[str]:
    issues: List[str] = []
    ac_lines = [line for line in lines if line.strip()]

    if not ac_lines:
        return issues

    for line in ac_lines:
        match = AC_TASK_ITEM_RE.match(line)
        if not match:
            issues.append(f"AC line is not a task list item (expected '- [ ] ...'): {line.strip()}")
            continue

        body = match.group(1).strip()

        if not AC_FORMAL_END_RE.search(body):
            issues.append(f"AC does not end with '한다.': {line.strip()}")

        if strict:
            has_conditional = AC_STRICT_CONDITIONAL_RE.search(body) is not None
            has_trigger = AC_STRICT_TRIGGER_RE.search(body) is not None

            if not has_conditional and not has_trigger:
                issues.append(
                    f"strict: AC lacks conditional/trigger structure "
                    f"(expected '...상황에서 ...하면 ...해야 한다'): {line.strip()}"
                )

    return issues


def validate_section_order(headings: List[str]) -> List[str]:
    issues: List[str] = []

    required_in_headings = [h for h in headings if h in REQUIRED_SECTIONS]
    expected = [s for s in REQUIRED_SECTIONS if s in required_in_headings]

    if required_in_headings != expected:
        issues.append("Required sections are not in the canonical order")

    seen: Dict[str, int] = {}
    for h in headings:
        if h in REQUIRED_SECTIONS:
            seen[h] = seen.get(h, 0) + 1
    for section, count in seen.items():
        if count > 1:
            issues.append(f"Duplicate section '## {section}' appears {count} times")

    return issues



def lint_path(path: Path, strict: bool) -> LintResult:
    result = LintResult(path)
    text = path.read_text(encoding="utf-8")
    headings, sections = parse_sections(text)
    result.headings = headings
    result.sections = sections

    # 1. Required sections existence
    for section in REQUIRED_SECTIONS:
        if section not in headings:
            result.fail(f"missing required section: ## {section}")

    order_issues = validate_section_order(headings)
    for issue in order_issues:
        result.fail(issue)

    metadata = parse_frontmatter(text)
    if metadata:
        result.metadata = metadata
    else:
        result.fail("missing YAML frontmatter")

    if result.metadata:
        has_all_fields, missing = has_fields(result.metadata, REQUIRED_METADATA_FIELDS)
        if not has_all_fields:
            result.fail(f"metadata missing required fields: {', '.join(sorted(missing))}")
        elif strict:
            tbd_fields = [
                field for field in REQUIRED_METADATA_FIELDS if metadata_value_is_tbd(result.metadata.get(field, ""))
            ]
            if tbd_fields:
                result.warn(f"strict mode: metadata has unresolved TBD fields: {', '.join(sorted(tbd_fields))}")

    if strict:
        for section in REQUIRED_SECTIONS:
            if section == "Source":
                continue
            if section_has_unresolved_tbd(sections.get(section, [])):
                result.warn(f"strict mode: section '## {section}' has unresolved TBD content")

    if "Acceptance Criteria" in sections:
        ac_issues = validate_ac_pattern(sections["Acceptance Criteria"], strict)
        for issue in ac_issues:
            result.warn(issue)

    if "Source" in sections:
        source_text = "\n".join(sections["Source"])
        if "Inventory" not in source_text and not strict:
            result.warn("Source section does not reference Inventory; check if intended.")
        unsupported_source_lines = unsupported_source_reference_lines(sections["Source"])
        if unsupported_source_lines:
            message = (
                "Source section has unsupported reference line(s): "
                f"{'; '.join(unsupported_source_lines)}. "
                "Allowed Source references are Inventory row, Contracts, and Flows."
            )
            if strict:
                result.fail(message)
            else:
                result.warn(message)
        try:
            repo_root = find_repo_root(path.parent)
        except RuntimeError:
            repo_root = None
        if repo_root is not None:
            actual_flow_lines = [line.strip() for line in sections["Source"] if line.strip().startswith("- Flows:")]
            expected_flow_line = expected_flow_source_line(repo_root, path)
            if expected_flow_line is not None:
                if actual_flow_lines != [expected_flow_line]:
                    result.warn("Source section has stale or missing Flows reference; check related category flow docs.")
            elif actual_flow_lines:
                result.warn("Source section has a Flows reference, but no category flow currently links this interaction spec.")

            interactions_map = load_interactions_map(repo_root)
            mismatches = validate_fi_match(result.metadata, interactions_map)
            if mismatches:
                iid = result.metadata.get("interaction_id", "")
                for field, fm_val, fi_val in mismatches:
                    if strict:
                        result.fail(
                            f"frontmatter '{field}' = '{fm_val}' "
                            f"does not match FI INTERACTIONS row '{fi_val}' "
                            f"for {iid}"
                        )
                    else:
                        result.warn(
                            f"frontmatter '{field}' = '{fm_val}' "
                            f"does not match FI INTERACTIONS row '{fi_val}' "
                            f"for {iid}"
                        )

    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lint Voyager FEATURE_SPEC markdown files")
    parser.add_argument("paths", nargs="+", help="Markdown files to lint")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Emit additional warnings for unresolved TBD values and enforce FI-frontmatter match as FAIL",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    all_ok = True

    for raw_path in args.paths:
        path = Path(raw_path)
        if not path.exists():
            print(f"[MISS] {raw_path} (not found)")
            all_ok = False
            continue

        result = lint_path(path, args.strict)
        if result.ok:
            print(f"PASS {path}")
            for warning in result.warnings:
                print(f"  WARN: {warning}")
        else:
            all_ok = False
            print(f"FAIL {path}")
            for error in result.errors:
                print(f"  ERROR: {error}")
            for warning in result.warnings:
                print(f"  WARN: {warning}")

    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
