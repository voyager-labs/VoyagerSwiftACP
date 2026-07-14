#!/usr/bin/env python3
"""Spec-test topology validator.

Reads FEATURES/data.tsv and INTERACTIONS/data.tsv from the feature inventory
root to compute expected spec-owner suite names, then scans target paths for
topology violations.

Exit codes:
    0 = pass (no violations)
    1 = violations found
    2 = error (missing files, bad args)
"""

import argparse
import csv
import os
import re
import sys
from pathlib import Path

# MARK heading canonical pattern
MARK_RE = re.compile(r"^// MARK: - ([A-Z]{2,4})-(\d{3})-([a-z0-9_]+)$")

# Spec-like filename pattern (prefix + digits + anything + Tests.swift)
SPEC_LIKE_RE = re.compile(r"^[A-Z]{2,4}\d{3}.*Tests\.swift$")

# Non-canonical MARK detection (lines that look like MARK headings but are wrong)
MARK_LINE_RE = re.compile(r"// MARK: - ")

# Allowed feature_id values in INTERACTIONS (the column header)
FEATURE_ID_COL = "feature_id"
INTERACTION_ID_COL = "interaction_id"


def to_compact_prefix(feature_id: str) -> str:
    """ONB-002 -> ONB002"""
    return feature_id.replace("-", "")


def to_pascal_case(title: str) -> str:
    """'Present Access Unlock Step' -> 'PresentAccessUnlockStep'"""
    return "".join(word.capitalize() for word in title.split())


def expected_suite_name(feature_id: str, feature_title: str) -> str:
    """Compute expected suite filename from feature inventory data."""
    prefix = to_compact_prefix(feature_id)
    pascal = to_pascal_case(feature_title)
    return f"{prefix}{pascal}Tests.swift"


def read_features_tsv(path: Path) -> dict[str, str]:
    """Read FEATURES/data.tsv, return {compact_prefix: expected_suite_filename}."""
    features: dict[str, str] = {}
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            fid = row.get("feature_id", "").strip()
            ftitle = row.get("feature_title", "").strip()
            if not fid or fid == "TBD":
                continue
            prefix = to_compact_prefix(fid)
            features[prefix] = expected_suite_name(fid, ftitle)
    return features


def read_interactions_tsv(path: Path) -> dict[str, list[str]]:
    """Read INTERACTIONS/data.tsv, return {feature_id: [interaction_id, ...]}."""
    interactions: dict[str, list[str]] = {}
    with open(path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter="\t")
        for row in reader:
            fid = row.get(FEATURE_ID_COL, "").strip()
            iid = row.get(INTERACTION_ID_COL, "").strip()
            if not fid or fid == "-" or fid == "TBD":
                continue
            if not iid or iid == "-" or iid == "TBD":
                continue
            interactions.setdefault(fid, []).append(iid)
    return interactions


def compact_to_feature_id(compact: str) -> str:
    """ONB002 -> ONB-002, SET003 -> SET-003."""
    match = re.match(r"^([A-Z]+)(\d{3})$", compact)
    if match:
        return f"{match.group(1)}-{match.group(2)}"
    return compact


class Violation:
    """A single topology violation."""

    def __init__(self, file_path: str, line: int, description: str):
        self.file_path = file_path
        self.line = line
        self.description = description

    def __str__(self):
        return f"{self.file_path}:{self.line}: {self.description}"


def scan_file(
    file_path: Path,
    features: dict[str, str],
    interactions: dict[str, list[str]],
    strict: bool,
) -> list[Violation]:
    """Scan a single Swift file for topology violations."""
    violations: list[Violation] = []
    filename = file_path.name
    is_spec_like = bool(SPEC_LIKE_RE.match(filename))

    # Determine if this file is a valid spec-owner suite
    is_valid_owner = False
    matched_prefix = ""
    if is_spec_like:
        # Extract compact prefix from filename
        prefix_match = re.match(r"^([A-Z]{2,4}\d{3})", filename)
        if prefix_match:
            matched_prefix = prefix_match.group(1)
            expected = features.get(matched_prefix)
            if expected and filename == expected:
                is_valid_owner = True

    try:
        lines = file_path.read_text(encoding="utf-8").splitlines()
    except Exception as e:
        violations.append(Violation(str(file_path), 0, f"cannot read file: {e}"))
        return violations

    for line_num, line in enumerate(lines, 1):
        stripped = line.strip()

        # Check for non-canonical MARK headings
        if "// MARK: - " in stripped:
            mark_match = MARK_RE.match(stripped)
            if not mark_match:
                violations.append(
                    Violation(
                        str(file_path),
                        line_num,
                        f"non-canonical MARK heading: {stripped}",
                    )
                )
            else:
                # Canonical MARK found, validate the feature_id and interaction_id
                prefix_part = mark_match.group(1)
                digits = mark_match.group(2)
                interaction_slug = mark_match.group(3)
                fid = f"{prefix_part}-{digits}"
                compact = f"{prefix_part}{digits}"

                # Check feature_id exists in interactions
                valid_iids = interactions.get(fid, [])
                if not valid_iids:
                    # Maybe feature exists but has no interactions tracked
                    if fid not in interactions:
                        violations.append(
                            Violation(
                                str(file_path),
                                line_num,
                                f"feature_id '{fid}' not found in INTERACTIONS data",
                            )
                        )

                # Check interaction_id belongs to the right feature
                iid_candidate = f"{fid}-{interaction_slug}"
                if valid_iids and iid_candidate not in valid_iids:
                    violations.append(
                        Violation(
                            str(file_path),
                            line_num,
                            f"interaction_id '{iid_candidate}' not in INTERACTIONS for {fid}",
                        )
                    )

                # In strict mode: product interaction MARKs in non-owner files
                if strict and not is_valid_owner and is_spec_like:
                    violations.append(
                        Violation(
                            str(file_path),
                            line_num,
                            f"product interaction MARK in non-owner suite '{filename}' "
                            f"(expected owner: {features.get(compact, 'unknown')})",
                        )
                    )

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate spec-test topology against feature inventory TSV data"
    )
    parser.add_argument(
        "--inventory-root",
        default="docs/canonical/PRODUCT/04_FEATURE_INVENTORY",
        help="Root directory containing FEATURES/ and INTERACTIONS/ TSV data",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail on spec-like files that are not valid spec-owner suites but contain product interaction MARKs",
    )
    parser.add_argument(
        "targets",
        nargs="+",
        help="Target directories or files to scan",
    )
    args = parser.parse_args()

    # Read TSV data
    inventory = Path(args.inventory_root)
    features_path = inventory / "FEATURES" / "data.tsv"
    interactions_path = inventory / "INTERACTIONS" / "data.tsv"

    if not features_path.exists():
        print(f"Error: {features_path} not found", file=sys.stderr)
        return 2
    if not interactions_path.exists():
        print(f"Error: {interactions_path} not found", file=sys.stderr)
        return 2

    try:
        features = read_features_tsv(features_path)
    except Exception as e:
        print(f"Error reading FEATURES TSV: {e}", file=sys.stderr)
        return 2

    try:
        interactions = read_interactions_tsv(interactions_path)
    except Exception as e:
        print(f"Error reading INTERACTIONS TSV: {e}", file=sys.stderr)
        return 2

    # Collect Swift files to scan
    swift_files: list[Path] = []
    for target in args.targets:
        p = Path(target)
        if not p.exists():
            print(f"Error: target '{target}' not found", file=sys.stderr)
            return 2
        if p.is_file():
            if p.suffix == ".swift":
                swift_files.append(p)
        else:
            for root, _dirs, files in os.walk(p):
                for f in files:
                    if f.endswith(".swift"):
                        swift_files.append(Path(root) / f)

    # Scan all files
    all_violations: list[Violation] = []
    for sf in swift_files:
        violations = scan_file(sf, features, interactions, args.strict)
        all_violations.extend(violations)

    # Output results
    if all_violations:
        for v in all_violations:
            print(str(v))
        print(f"\n{len(all_violations)} violation(s) found.")
        return 1

    print(f"OK: {len(swift_files)} file(s) scanned, no violations.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
