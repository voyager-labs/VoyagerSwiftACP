#!/usr/bin/env python3
"""Audit and sync Voyager FI/IA/FS consistency for a single feature_id."""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_MARKERS = [
    Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv"),
    Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"),
    Path("PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv"),
    Path("PRODUCT/05_FEATURE_SPECS"),
]

FEATURES_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv")
INTERACTIONS_TSV = Path("PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv")
WINDOW_STRUCTURE_TSV = Path("PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv")
FEATURE_SPECS_DIR = Path("PRODUCT/05_FEATURE_SPECS")

FRONTMATTER_FIELDS = [
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
]

SOURCE_INVENTORY_PATH = "PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"


@dataclass
class Issue:
    severity: str
    code: str
    message: str
    path: str = "-"


@dataclass
class SyncChange:
    path: Path
    changed_parts: list[str]


def _try_set_csv_field_limit() -> None:
    try:
        csv.field_size_limit(10 * 1024 * 1024)
    except Exception:
        pass


def find_repo_root(start: Path) -> Path:
    for candidate in [start.resolve(), *start.resolve().parents]:
        if all((candidate / marker).exists() for marker in REPO_MARKERS):
            return candidate
    raise RuntimeError("Could not locate voyager-documentation repo root")


def normalize(value: str | None, default: str = "-") -> str:
    if value is None:
        return default
    stripped = value.strip()
    return stripped if stripped else default


def is_empty_value(value: str | None) -> bool:
    return normalize(value, "") in {"", "-"}


def slugify(value: str, fallback: str) -> str:
    val = normalize(value, "").lower()
    if not val:
        return fallback
    val = re.sub(r"[^0-9a-zA-Z]+", "-", val)
    val = re.sub(r"-{2,}", "-", val)
    val = val.strip("-_")
    return val or fallback


def yaml_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def read_tsv_rows(path: Path) -> list[tuple[int, dict[str, str]]]:
    with path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        rows: list[tuple[int, dict[str, str]]] = []
        for line_no, row in enumerate(reader, start=2):
            clean_row = {key: (value if value is not None else "") for key, value in row.items()}
            rows.append((line_no, clean_row))
        return rows


def parse_frontmatter(text: str) -> tuple[dict[str, str], int, int]:
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return {}, -1, -1

    metadata: dict[str, str] = {}
    cursor = 0
    end_index = -1
    for idx, line in enumerate(lines[1:], start=1):
        cursor += len(lines[idx - 1])
        if line.strip() == "---":
            end_index = cursor + len(line)
            break
        if not line.strip() or line.lstrip().startswith("#") or ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        value = value.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
        metadata[key] = value

    if end_index == -1:
        return {}, -1, -1
    return metadata, 0, end_index


def parse_sections(text: str) -> list[tuple[str, int, int]]:
    matches = list(re.finditer(r"^##\s+(.+)$", text, flags=re.MULTILINE))
    sections: list[tuple[str, int, int]] = []
    for idx, match in enumerate(matches):
        heading = match.group(1).strip()
        start = match.end()
        end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
        sections.append((heading, start, end))
    return sections


def get_section_body(text: str, heading: str) -> str | None:
    for current_heading, start, end in parse_sections(text):
        if current_heading == heading:
            return text[start:end].strip("\n")
    return None


def replace_section_body(text: str, heading: str, new_body: str) -> tuple[str, bool]:
    for current_heading, start, end in parse_sections(text):
        if current_heading != heading:
            continue
        prefix = text[:start]
        suffix = text[end:]
        body = "\n\n" + new_body.strip() + "\n"
        return prefix + body + suffix, True
    return text, False


def replace_h1_title(text: str, new_title: str) -> tuple[str, bool]:
    match = re.search(r"^#\s+.+$", text, flags=re.MULTILINE)
    if not match:
        return text, False
    updated = text[: match.start()] + f"# {new_title}" + text[match.end() :]
    return updated, updated != text


def format_frontmatter(interaction_row: dict[str, str]) -> str:
    lines = ["---"]
    for field in FRONTMATTER_FIELDS:
        value = normalize(interaction_row.get(field), "-")
        lines.append(f"{field}: {yaml_quote(value)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def build_expected_related_links(
    feature_id: str,
    current_interaction_id: str,
    interactions: list[tuple[int, dict[str, str]]],
    spec_basename_by_interaction: dict[str, str] | None = None,
) -> list[str]:
    links: list[str] = []
    for _line, row in sorted(interactions, key=lambda item: normalize(item[1].get("interaction_id"), "")):
        interaction_id = normalize(row.get("interaction_id"), "")
        if not interaction_id or interaction_id == current_interaction_id:
            continue
        interaction_title = normalize(row.get("interaction_title"), "interaction")
        basename = (
            spec_basename_by_interaction.get(interaction_id)
            if spec_basename_by_interaction is not None
            else None
        )
        if not basename:
            basename = f"{interaction_id}-{slugify(interaction_title, 'interaction')}.md"
        links.append(f"- [{interaction_id}]({basename})")
    return links


def expected_source_body(line_no: int) -> str:
    return f"- Inventory: `{SOURCE_INVENTORY_PATH}`\n- Source line: `{line_no}`"


def collect_window_keys(repo_root: Path) -> set[str]:
    return {
        normalize(row.get("structure_key"), "")
        for _line, row in read_tsv_rows(repo_root / WINDOW_STRUCTURE_TSV)
        if normalize(row.get("structure_key"), "")
    }


def get_feature_row(repo_root: Path, feature_id: str) -> tuple[int, dict[str, str]] | None:
    matches = [
        (line_no, row)
        for line_no, row in read_tsv_rows(repo_root / FEATURES_TSV)
        if normalize(row.get("feature_id"), "") == feature_id
    ]
    if len(matches) != 1:
        return None
    return matches[0]


def get_interaction_rows(repo_root: Path, feature_id: str) -> list[tuple[int, dict[str, str]]]:
    return [
        (line_no, row)
        for line_no, row in read_tsv_rows(repo_root / INTERACTIONS_TSV)
        if normalize(row.get("feature_id"), "") == feature_id
    ]


def find_specs_for_feature(repo_root: Path, feature_id: str) -> list[Path]:
    results: list[Path] = []
    for path in sorted((repo_root / FEATURE_SPECS_DIR).rglob("*.md")):
        metadata, _fm_start, _fm_end = parse_frontmatter(path.read_text(encoding="utf-8"))
        if normalize(metadata.get("feature_id"), "") == feature_id:
            results.append(path)
    return results


def build_expected_frontmatter(interaction: dict[str, str]) -> dict[str, str]:
    return {field: normalize(interaction.get(field), "-") for field in FRONTMATTER_FIELDS}


def section_lines_to_links(body: str | None) -> set[str]:
    if body is None:
        return set()
    links: set[str] = set()
    for line in body.splitlines():
        stripped = line.strip()
        if stripped.startswith("- [") and "](" in stripped and stripped.endswith(")"):
            links.add(stripped)
    return links


def is_same_or_nested(parent_key: str, child_key: str) -> bool:
    if parent_key == "-" or child_key == "-":
        return True
    return child_key == parent_key or child_key.startswith(parent_key + ".")


def sync_spec_file(
    path: Path,
    interaction_line_no: int,
    interaction_row: dict[str, str],
    interactions: list[tuple[int, dict[str, str]]],
    spec_basename_by_interaction: dict[str, str],
) -> SyncChange | None:
    text = path.read_text(encoding="utf-8")
    changed_parts: list[str] = []

    metadata, fm_start, fm_end = parse_frontmatter(text)
    if fm_start == -1 or fm_end == -1:
        return None

    expected_frontmatter = format_frontmatter(interaction_row)
    current_frontmatter = text[fm_start:fm_end]
    if current_frontmatter != expected_frontmatter:
        text = expected_frontmatter + text[fm_end:]
        changed_parts.append("frontmatter")

    interaction_title = normalize(interaction_row.get("interaction_title"), "Interaction")
    text, title_changed = replace_h1_title(text, interaction_title)
    if title_changed:
        changed_parts.append("title")

    related_links = build_expected_related_links(
        normalize(interaction_row.get("feature_id"), ""),
        normalize(interaction_row.get("interaction_id"), ""),
        interactions,
        spec_basename_by_interaction=spec_basename_by_interaction,
    )
    related_body = "\n".join(related_links) if related_links else "-"
    text, related_changed = replace_section_body(text, "Related Interactions", related_body)
    if related_changed:
        current_related = get_section_body(path.read_text(encoding="utf-8"), "Related Interactions")
        if normalize(current_related, "") != normalize(related_body, ""):
            changed_parts.append("related_interactions")

    source_body = expected_source_body(interaction_line_no)
    original_source = get_section_body(path.read_text(encoding="utf-8"), "Source")
    text, source_changed = replace_section_body(text, "Source", source_body)
    if source_changed and normalize(original_source, "") != normalize(source_body, ""):
        changed_parts.append("source")

    if not changed_parts:
        return None

    path.write_text(text, encoding="utf-8")
    return SyncChange(path=path, changed_parts=changed_parts)


def audit_feature_bundle(repo_root: Path, feature_id: str, write: bool) -> dict[str, Any]:
    issues: list[Issue] = []
    synced: list[SyncChange] = []

    feature_match = get_feature_row(repo_root, feature_id)
    if feature_match is None:
        issues.append(Issue("FAIL", "feature.missing", f"FEATURES row not found for {feature_id}"))
        return {"ok": False, "issues": issues, "synced": synced}

    feature_line_no, feature_row = feature_match
    issues.append(
        Issue(
            "INFO",
            "feature.found",
            f"FEATURE row found at line {feature_line_no}",
            path=str(FEATURES_TSV),
        )
    )

    window_keys = collect_window_keys(repo_root)
    feature_related_ui = normalize(feature_row.get("related_ui"), "-")
    if feature_related_ui != "-" and feature_related_ui not in window_keys:
        issues.append(
            Issue(
                "FAIL",
                "ia.feature_related_ui_missing",
                f"FEATURES.related_ui does not exist in WINDOW_STRUCTURE: {feature_related_ui}",
                path=str(FEATURES_TSV),
            )
        )

    interactions = get_interaction_rows(repo_root, feature_id)
    if not interactions:
        issues.append(Issue("FAIL", "interaction.none", f"No INTERACTIONS rows found for {feature_id}"))
        return {"ok": False, "issues": issues, "synced": synced}

    issues.append(
        Issue(
            "INFO",
            "interaction.count",
            f"Found {len(interactions)} INTERACTIONS rows for {feature_id}",
            path=str(INTERACTIONS_TSV),
        )
    )

    specs = find_specs_for_feature(repo_root, feature_id)
    spec_by_interaction: dict[str, list[Path]] = {}
    extra_specs: list[Path] = []
    for spec_path in specs:
        metadata, _fm_start, _fm_end = parse_frontmatter(spec_path.read_text(encoding="utf-8"))
        interaction_id = normalize(metadata.get("interaction_id"), "")
        if not interaction_id:
            extra_specs.append(spec_path)
            issues.append(
                Issue(
                    "FAIL",
                    "fs.frontmatter_missing_interaction_id",
                    "FEATURE_SPEC frontmatter is missing interaction_id",
                    path=str(spec_path.relative_to(repo_root)),
                )
            )
            continue
        spec_by_interaction.setdefault(interaction_id, []).append(spec_path)

    expected_interaction_ids = {
        normalize(row.get("interaction_id"), "")
        for _line, row in interactions
        if normalize(row.get("interaction_id"), "")
    }
    actual_interaction_ids = set(spec_by_interaction.keys())
    spec_basename_by_interaction = {
        interaction_id: paths[0].name
        for interaction_id, paths in spec_by_interaction.items()
        if len(paths) == 1
    }

    for extra_interaction_id in sorted(actual_interaction_ids - expected_interaction_ids):
        for path in spec_by_interaction[extra_interaction_id]:
            issues.append(
                Issue(
                    "FAIL",
                    "fs.unexpected_spec",
                    f"FEATURE_SPEC exists for unknown interaction_id: {extra_interaction_id}",
                    path=str(path.relative_to(repo_root)),
                )
            )

    expected_feature_dir = (
        repo_root
        / FEATURE_SPECS_DIR
        / normalize(feature_row.get("category_key"), "").lower()
        / f"{feature_id}-{slugify(normalize(feature_row.get('feature_title'), ''), 'feature')}"
    )

    for interaction_line_no, interaction_row in interactions:
        interaction_id = normalize(interaction_row.get("interaction_id"), "")
        interaction_title = normalize(interaction_row.get("interaction_title"), "Interaction")
        feature_title = normalize(feature_row.get("feature_title"), "")
        category_key = normalize(feature_row.get("category_key"), "")

        if normalize(interaction_row.get("feature"), "") != feature_title:
            issues.append(
                Issue(
                    "FAIL",
                    "interaction.feature_mismatch",
                    f"INTERACTIONS.feature does not match FEATURES.feature_title for {interaction_id}",
                    path=str(INTERACTIONS_TSV),
                )
            )

        if normalize(interaction_row.get("category_key"), "") != category_key:
            issues.append(
                Issue(
                    "FAIL",
                    "interaction.category_mismatch",
                    f"INTERACTIONS.category_key does not match FEATURES.category_key for {interaction_id}",
                    path=str(INTERACTIONS_TSV),
                )
            )

        related_region = normalize(interaction_row.get("related_region"), "-")
        if related_region != "-" and related_region not in window_keys:
            issues.append(
                Issue(
                    "FAIL",
                    "ia.related_region_missing",
                    f"INTERACTIONS.related_region does not exist in WINDOW_STRUCTURE for {interaction_id}: {related_region}",
                    path=str(INTERACTIONS_TSV),
                )
            )
        elif not is_same_or_nested(feature_related_ui, related_region):
            issues.append(
                Issue(
                    "WARN",
                    "ia.region_not_nested",
                    f"{interaction_id} related_region is not equal to or nested under FEATURES.related_ui",
                    path=str(INTERACTIONS_TSV),
                )
            )

        matching_specs = spec_by_interaction.get(interaction_id, [])
        if not matching_specs:
            issues.append(
                Issue(
                    "FAIL",
                    "fs.missing",
                    f"Missing FEATURE_SPEC for {interaction_id}",
                    path=str(expected_feature_dir.relative_to(repo_root)),
                )
            )
            continue
        if len(matching_specs) > 1:
            issues.append(
                Issue(
                    "FAIL",
                    "fs.duplicate",
                    f"Multiple FEATURE_SPEC files found for {interaction_id}",
                    path=", ".join(str(path.relative_to(repo_root)) for path in matching_specs),
                )
            )
            continue

        spec_path = matching_specs[0]
        spec_text = spec_path.read_text(encoding="utf-8")
        metadata, fm_start, fm_end = parse_frontmatter(spec_text)
        if fm_start == -1 or fm_end == -1:
            issues.append(
                Issue(
                    "FAIL",
                    "fs.frontmatter_missing",
                    "FEATURE_SPEC is missing YAML frontmatter",
                    path=str(spec_path.relative_to(repo_root)),
                )
            )
            continue

        expected_frontmatter = build_expected_frontmatter(interaction_row)
        for field, expected_value in expected_frontmatter.items():
            actual_value = normalize(metadata.get(field), "-")
            if actual_value != expected_value:
                issues.append(
                    Issue(
                        "FAIL",
                        "fs.frontmatter_mismatch",
                        f"{interaction_id} frontmatter field '{field}' mismatch: expected '{expected_value}', got '{actual_value}'",
                        path=str(spec_path.relative_to(repo_root)),
                    )
                )

        title_match = re.search(r"^#\s+(.+)$", spec_text, flags=re.MULTILINE)
        if not title_match:
            issues.append(
                Issue(
                    "FAIL",
                    "fs.title_missing",
                    f"H1 title missing for {interaction_id}",
                    path=str(spec_path.relative_to(repo_root)),
                )
            )
        elif normalize(title_match.group(1), "") != interaction_title:
            issues.append(
                Issue(
                    "WARN",
                    "fs.title_mismatch",
                    f"H1 title does not match interaction_title for {interaction_id}",
                    path=str(spec_path.relative_to(repo_root)),
                )
            )

        expected_links = set(
            build_expected_related_links(
                feature_id=feature_id,
                current_interaction_id=interaction_id,
                interactions=interactions,
                spec_basename_by_interaction=spec_basename_by_interaction,
            )
        )
        actual_links = section_lines_to_links(get_section_body(spec_text, "Related Interactions"))
        if actual_links != expected_links:
            issues.append(
                Issue(
                    "WARN",
                    "fs.related_interactions_mismatch",
                    f"Related Interactions list is stale for {interaction_id}",
                    path=str(spec_path.relative_to(repo_root)),
                )
            )

        source_body = normalize(get_section_body(spec_text, "Source"), "")
        expected_source = normalize(expected_source_body(interaction_line_no), "")
        if source_body != expected_source:
            issues.append(
                Issue(
                    "WARN",
                    "fs.source_mismatch",
                    f"Source section is stale for {interaction_id}",
                    path=str(spec_path.relative_to(repo_root)),
                )
            )

        if write:
            sync_change = sync_spec_file(
                spec_path,
                interaction_line_no,
                interaction_row,
                interactions,
                spec_basename_by_interaction,
            )
            if sync_change is not None:
                synced.append(sync_change)

    if write:
        for change in synced:
            issues.append(
                Issue(
                    "INFO",
                    "fs.synced",
                    f"Synced {', '.join(change.changed_parts)}",
                    path=str(change.path.relative_to(repo_root)),
                )
            )

    ok = not any(issue.severity == "FAIL" for issue in issues)
    return {"ok": ok, "issues": issues, "synced": synced}


def print_report(feature_id: str, report: dict[str, Any], repo_root: Path) -> None:
    print(f"FEATURE_ID: {feature_id}")
    print(f"REPO_ROOT: {repo_root}")
    print(f"RESULT: {'PASS' if report['ok'] else 'FAIL'}")
    print("")

    counts = {"FAIL": 0, "WARN": 0, "INFO": 0}
    for issue in report["issues"]:
        counts[issue.severity] += 1

    print("COUNTS")
    print(f"FAIL: {counts['FAIL']}")
    print(f"WARN: {counts['WARN']}")
    print(f"INFO: {counts['INFO']}")
    print("")

    for severity in ("FAIL", "WARN", "INFO"):
        relevant = [issue for issue in report["issues"] if issue.severity == severity]
        if not relevant:
            continue
        print(severity)
        for issue in relevant:
            if issue.path != "-":
                print(f"- [{issue.code}] {issue.message} ({issue.path})")
            else:
                print(f"- [{issue.code}] {issue.message}")
        print("")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit and sync Voyager FI/IA/FS consistency for a feature_id"
    )
    parser.add_argument("feature_id", help="Target feature_id (example: SET-007)")
    parser.add_argument(
        "--write",
        action="store_true",
        help="Sync deterministic FEATURE_SPEC fields after auditing",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Print JSON report instead of plain text",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=None,
        help="Override repo root detection",
    )
    return parser.parse_args()


def main() -> int:
    _try_set_csv_field_limit()
    args = parse_args()

    repo_root = args.repo_root.resolve() if args.repo_root else find_repo_root(Path.cwd())
    report = audit_feature_bundle(repo_root, args.feature_id.strip(), write=args.write)

    if args.json:
        payload = {
            "feature_id": args.feature_id.strip(),
            "repo_root": str(repo_root),
            "ok": report["ok"],
            "issues": [issue.__dict__ for issue in report["issues"]],
            "synced": [
                {
                    "path": str(change.path.relative_to(repo_root)),
                    "changed_parts": change.changed_parts,
                }
                for change in report["synced"]
            ],
        }
        print(json.dumps(payload, ensure_ascii=False, indent=2))
    else:
        print_report(args.feature_id.strip(), report, repo_root)

    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
