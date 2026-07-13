#!/usr/bin/env python3
"""Deterministic flow-to-XCTest mapper and structural checker."""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple


CATEGORY_RE = re.compile(r"^[a-z][a-z0-9]*$")
SLUG_RE = re.compile(r"^[a-z0-9]+(?:_[a-z0-9]+)*$")
CLASS_RE = re.compile(r"\b(?:final\s+)?class\s+(\w+)")
ROOT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_SHELL = ROOT_DIR / "scripts/dev/macos-test.sh"


class FlowMapping(NamedTuple):
    category: str
    slug: str
    document_path: str
    swift_path: str
    class_name: str
    selector: str


def parse_flow_id(flow_id: str) -> tuple[str, str]:
    """Parse ``category.slug`` into a validated category and slug."""
    if "." not in flow_id:
        raise ValueError("Flow ID must be formatted as category.slug")
    category, slug = flow_id.split(".", 1)
    if not CATEGORY_RE.fullmatch(category):
        raise ValueError(f"Invalid flow category: {category}")
    if not SLUG_RE.fullmatch(slug):
        raise ValueError(f"Invalid flow slug: {slug}")
    return category, slug


def slug_to_pascal(slug: str) -> str:
    """Convert a snake_case flow slug to PascalCase."""
    return "".join(word.capitalize() for word in slug.split("_"))


def pascal_to_snake(value: str) -> str:
    """Convert deterministic FlowTests stems back to snake_case IDs."""
    return re.sub(r"(?<!^)(?=[A-Z])", "_", value).lower()


def resolve_mapping(category: str, slug: str) -> FlowMapping:
    """Compute the canonical document, suite, class, and selector."""
    category, slug = parse_flow_id(f"{category}.{slug}")
    pascal_slug = slug_to_pascal(slug)
    class_name = f"{pascal_slug}FlowTests"
    return FlowMapping(
        category=category,
        slug=slug,
        document_path=f"{category}/flows/{slug}_flow.md",
        swift_path=(
            "apps/macos/Voyager/VoyagerTests/Flows/"
            f"{category.upper()}/{class_name}.swift"
        ),
        class_name=class_name,
        selector=f"VoyagerTests/{class_name}",
    )


def resolve_docs_root(cli_root: str | None, repo_root: Path) -> Path:
    """Resolve docs root: CLI flag, environment, then repository default."""
    if cli_root:
        return Path(cli_root)
    env = os.environ.get("VOYAGER_PRODUCT_DOCS_ROOT")
    if env:
        return Path(env)
    return repo_root / "docs" / "canonical"


def discover_suites(tests_root: Path) -> list[tuple[Path, str]]:
    """Find FlowTests suites and their declared class names."""
    suites: list[tuple[Path, str]] = []
    flows_root = tests_root / "Flows"
    for path in (
        sorted(flows_root.rglob("*FlowTests.swift")) if flows_root.exists() else []
    ):
        match = CLASS_RE.search(path.read_text())
        suites.append((path, match.group(1) if match else ""))
    return suites


def discover_flow_docs(docs_root: Path) -> list[tuple[str, str, Path]]:
    """Find canonical flow documents under feature-spec categories."""
    specs_root = docs_root / "PRODUCT" / "05_FEATURE_SPECS"
    docs: list[tuple[str, str, Path]] = []
    if not specs_root.exists():
        return docs
    for path in sorted(specs_root.glob("*/flows/*_flow.md")):
        category = path.parent.parent.name
        slug = path.name.removesuffix("_flow.md")
        if CATEGORY_RE.fullmatch(category) and SLUG_RE.fullmatch(slug):
            docs.append((category, slug, path))
    return docs


def suite_flow_id(path: Path) -> str | None:
    """Infer the deterministic ID encoded by a FlowTests filename."""
    if not CATEGORY_RE.fullmatch(path.parent.name.lower()):
        return None
    stem = path.name.removesuffix("FlowTests.swift")
    if not stem:
        return None
    return f"{path.parent.name.lower()}.{pascal_to_snake(stem)}"


def check_structure(docs_root: Path, tests_root: Path) -> list[str]:
    """Return mapped-suite mismatches while allowing unmigrated documents."""
    docs = discover_flow_docs(docs_root)
    mappings = {
        f"{category}.{slug}": resolve_mapping(category, slug)
        for category, slug, _ in docs
    }
    errors: list[str] = []
    slug_categories: dict[str, list[str]] = {}
    for category, slug, _ in docs:
        slug_categories.setdefault(slug, []).append(category)
    for slug, categories in sorted(slug_categories.items()):
        if len(categories) > 1:
            errors.append(
                f"duplicate flow slug {slug}: {', '.join(sorted(categories))}"
            )

    known_suite_paths = {
        tests_root
        / mapping.swift_path.removeprefix("apps/macos/Voyager/VoyagerTests/"): flow_id
        for flow_id, mapping in mappings.items()
    }
    for path, class_name in discover_suites(tests_root):
        flow_id = known_suite_paths.get(path)
        if flow_id is None:
            errors.append(f"orphan suite: {path}")
            continue
        mapping = mappings[flow_id]
        if class_name != mapping.class_name:
            errors.append(
                f"class mismatch in {path}: expected {mapping.class_name}, found {class_name or 'none'}"
            )
        marker = f"// FLOW-ID: {flow_id}"
        if marker not in path.read_text().splitlines():
            errors.append(f"missing FLOW-ID marker in {path}: expected {marker}")
    return errors


def list_mappings(tests_root: Path) -> list[str]:
    """Return flow IDs encoded by existing suites in lexical order."""
    return sorted(
        flow_id
        for path, _ in discover_suites(tests_root)
        if (flow_id := suite_flow_id(path))
    )


def category_mappings(category: str, tests_root: Path) -> list[str]:
    """Return flow IDs encoded by suites in one validated category."""
    if not CATEGORY_RE.fullmatch(category):
        raise ValueError(f"Invalid flow category: {category}")
    return [
        flow_id
        for flow_id in list_mappings(tests_root)
        if flow_id.startswith(f"{category}.")
    ]


def run_flow_mode(mapping: FlowMapping, shell_path: str, dry_run: bool) -> int:
    """Run the shared test shell for a resolved XCTest selector."""
    command = [shell_path, f"-only-testing:{mapping.selector}"]
    if dry_run:
        print(" ".join(command))
        return 0
    return subprocess.run(command, check=False).returncode


def parser() -> argparse.ArgumentParser:
    """Build the command-line parser."""
    argument_parser = argparse.ArgumentParser(description=__doc__)
    modes = argument_parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--flow")
    modes.add_argument("--category")
    modes.add_argument("--list", action="store_true")
    modes.add_argument("--check", action="store_true")
    argument_parser.add_argument("--docs-root")
    argument_parser.add_argument("--dry-run", action="store_true")
    return argument_parser


def main(argv: list[str] | None = None) -> int:
    """Run a mapper, suite discovery, list, or structural check command."""
    try:
        args = parser().parse_args(argv)
    except SystemExit as error:
        if isinstance(error.code, int):
            return error.code
        return 0 if error.code is None else 1

    repo_root = ROOT_DIR
    docs_root = resolve_docs_root(args.docs_root, repo_root)
    tests_root = repo_root / "apps/macos/Voyager/VoyagerTests"
    shell_path = str(DEFAULT_SHELL)

    try:
        if args.check:
            errors = check_structure(docs_root, tests_root)
            mappings = {
                f"{category}.{slug}"
                for category, slug, _ in discover_flow_docs(docs_root)
            }
            suites = set(list_mappings(tests_root))
            for flow_id in sorted(mappings - suites):
                print(f"unmigrated: {flow_id}")
            for error in errors:
                print(error, file=sys.stderr)
            return 1 if errors else 0
        if args.list:
            for flow_id in list_mappings(tests_root):
                category, slug = parse_flow_id(flow_id)
                print(f"{flow_id} {resolve_mapping(category, slug).selector}")
            return 0
        if args.category:
            for flow_id in category_mappings(args.category, tests_root):
                category, slug = parse_flow_id(flow_id)
                mapping = resolve_mapping(category, slug)
                if not (
                    docs_root / "PRODUCT/05_FEATURE_SPECS" / mapping.document_path
                ).is_file():
                    print(
                        f"Missing canonical flow document: {flow_id}", file=sys.stderr
                    )
                    return 2
                result = run_flow_mode(mapping, shell_path, args.dry_run)
                if result:
                    return result
            return 0

        category, slug = parse_flow_id(args.flow)
        mapping = resolve_mapping(category, slug)
        document = docs_root / "PRODUCT/05_FEATURE_SPECS" / mapping.document_path
        suite = repo_root / mapping.swift_path
        if not document.is_file():
            print(f"Missing canonical flow document: {document}", file=sys.stderr)
            return 2
        if not suite.is_file() and not args.dry_run:
            print(f"Missing flow suite: {suite}", file=sys.stderr)
            return 2
        return run_flow_mode(mapping, shell_path, args.dry_run)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
