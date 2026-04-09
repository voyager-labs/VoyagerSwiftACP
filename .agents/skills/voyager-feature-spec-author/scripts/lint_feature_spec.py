#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Dict, Iterable, List, Tuple


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
    "summary",
    "related_region",
    "menu",
    "shortcut",
}

LEGACY_METADATA_FIELD_MAP = {
    "Interaction ID": "interaction_id",
    "Interaction Type": "interaction_type",
    "Feature": "feature",
    "Category Key": "category_key",
    "Feature ID": "feature_id",
    "Status": "status",
    "Summary": "summary",
    "Related Region": "related_region",
    "Menu": "menu",
    "Shortcut": "shortcut",
}

SECTION_RE = re.compile(r"^##\s+(.*)$")
TABLE_ROW_RE = re.compile(r"^\|\s*([^|]+?)\s*\|\s*([^|]*?)\s*\|")


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


def parse_frontmatter(text: str) -> Dict[str, str]:
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


def parse_legacy_metadata(lines: List[str]) -> Dict[str, str]:
    fields: Dict[str, str] = {}
    for line in lines:
        if not line.strip().startswith("|"):
            continue
        if re.match(r"^\|\s*-+", line):
            continue
        match = TABLE_ROW_RE.match(line)
        if not match:
            continue
        key = match.group(1).strip()
        value = match.group(2).strip()
        normalized_key = LEGACY_METADATA_FIELD_MAP.get(key)
        if normalized_key:
            fields[normalized_key] = value
    return fields


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


def has_fields(metadata: Dict[str, str], required: Iterable[str]) -> Tuple[bool, List[str]]:
    missing = [field for field in required if field not in metadata or metadata[field].strip() == ""]
    return len(missing) == 0, missing


def lint_path(path: Path, strict: bool) -> LintResult:
    result = LintResult(path)
    text = path.read_text(encoding="utf-8")
    headings, sections = parse_sections(text)
    result.headings = headings
    result.sections = sections

    for section in REQUIRED_SECTIONS:
        if section not in headings:
            result.fail(f"missing required section: ## {section}")

    metadata = parse_frontmatter(text)
    if metadata:
        result.metadata = metadata
    elif "Metadata" in sections:
        result.metadata = parse_legacy_metadata(sections["Metadata"])
        if result.metadata:
            result.warn("uses legacy Metadata table, prefer YAML frontmatter")

    if not result.metadata:
        result.fail("missing metadata frontmatter (or legacy Metadata table)")
    else:
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

    if "Source" in sections:
        source_text = "\n".join(sections["Source"])
        if "Inventory" not in source_text and not strict:
            result.warn("Source section does not reference Inventory; check if intended.")

    return result


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Lint Voyager FEATURE_SPEC markdown files")
    parser.add_argument("paths", nargs="+", help="Markdown files to lint")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Emit additional warnings for unresolved TBD values while keeping repo-wide '-' / 'TBD' rules",
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
