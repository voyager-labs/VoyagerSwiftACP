#!/usr/bin/env python3
"""Voyager Feature Inventory (VFI) CLI.

This script bootstraps a skill-scoped virtualenv and installs Polars into it,
then uses Polars to load/join/search the FEATURE_INVENTORY TSV tables.

Virtualenv location (not packaged into the .skill zip):
  .agents/skills/.venvs/feature-inventory/
"""

from __future__ import annotations

import argparse
import importlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


def _find_repo_root(start: Path) -> Path:
    start = start.resolve()
    for p in [start] + list(start.parents):
        if (p / ".git").is_dir():
            return p
    return start


SKILL_DIR = Path(__file__).resolve().parents[1]
REPO_ROOT = _find_repo_root(SKILL_DIR)
VENV_DIR = REPO_ROOT / ".agents" / "skills" / ".venvs" / SKILL_DIR.name
REQUIREMENTS_TXT = SKILL_DIR / "requirements.txt"


def _venv_python(venv_dir: Path) -> Path:
    if os.name == "nt":
        return venv_dir / "Scripts" / "python.exe"
    return venv_dir / "bin" / "python"


def _run(cmd: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(cmd, cwd=str(cwd) if cwd else None, check=True)


def _run_quiet(cmd: list[str], *, cwd: Path | None = None) -> None:
    subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def _in_target_venv(venv_dir: Path) -> bool:
    try:
        return Path(sys.prefix).resolve() == venv_dir.resolve()
    except Exception:
        return False


def _venv_can_import(venv_python: Path, module: str) -> bool:
    try:
        _run_quiet([str(venv_python), "-c", f"import {module}"])
        return True
    except subprocess.CalledProcessError:
        return False


def _ensure_venv(*, recreate: bool) -> Path:
    venv_python = _venv_python(VENV_DIR)

    if recreate and VENV_DIR.exists():
        shutil.rmtree(VENV_DIR)

    if not venv_python.exists():
        (VENV_DIR.parent).mkdir(parents=True, exist_ok=True)
        _run([sys.executable, "-m", "venv", str(VENV_DIR)])

    # Fast path: if polars is already importable, do nothing.
    if not recreate and _venv_can_import(venv_python, "polars"):
        return venv_python

    # Ensure pip exists/updated.
    try:
        _run_quiet([str(venv_python), "-m", "pip", "--version"])
    except subprocess.CalledProcessError:
        _run([str(venv_python), "-m", "ensurepip", "--upgrade"])

    _run([str(venv_python), "-m", "pip", "install", "-U", "pip"])

    # Install dependencies for this skill.
    if REQUIREMENTS_TXT.exists():
        _run([str(venv_python), "-m", "pip", "install", "-r", str(REQUIREMENTS_TXT)])
    else:
        _run([str(venv_python), "-m", "pip", "install", "polars"])

    return venv_python


def _reexec_in_venv() -> None:
    venv_python = _venv_python(VENV_DIR)
    os.execv(
        str(venv_python),
        [str(venv_python), str(Path(__file__).resolve()), *sys.argv[1:]],
    )


def _read_tsv(pl, path: Path):
    df = pl.read_csv(
        path,
        separator="\t",
        has_header=True,
        null_values=["-"],
        infer_schema_length=0,
    )

    # Normalize all columns to Utf8 for stable string ops.
    return df.with_columns([pl.col(c).cast(pl.Utf8) for c in df.columns])


def _fill(v: str | None) -> str:
    if v is None:
        return "-"
    s = str(v).strip()
    return s if s else "-"


def cmd_setup(args: argparse.Namespace) -> int:
    try:
        _ensure_venv(recreate=args.recreate)
    except subprocess.CalledProcessError as e:
        print(f"ERROR: setup failed: {e}")
        return 2
    print(f"OK: venv ready: {VENV_DIR}")
    print(f"OK: python: {_venv_python(VENV_DIR)}")
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    pl = importlib.import_module("polars")

    repo_root = _find_repo_root(SKILL_DIR)

    features_path = repo_root / "PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv"
    interactions_path = repo_root / "PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"

    features = _read_tsv(pl, features_path)
    feature_id = args.feature_id.strip()
    feature = features.filter(pl.col("feature_id") == feature_id)

    if feature.height == 0:
        print(f"NOT FOUND: {feature_id}")
        return 1

    row = feature.row(0, named=True)
    print("FOUND")
    print(f"feature_id: {_fill(row.get('feature_id'))}")
    print(f"feature_title: {_fill(row.get('feature_title'))}")
    print(f"feature_category: {_fill(row.get('feature_category'))}")
    if "category_key" in row:
        print(f"category_key: {_fill(row.get('category_key'))}")
    print(f"release_phase: {_fill(row.get('release_phase'))}")
    print(f"status: {_fill(row.get('status'))}")
    print(f"related_ui: {_fill(row.get('related_ui'))}")
    print(f"description: {_fill(row.get('description'))}")

    interactions = _read_tsv(pl, interactions_path)
    related = (
        interactions.filter(pl.col("feature_id") == feature_id)
        .sort(["interaction_title"])
        .select(
            [
                "interaction_title",
                "interaction_id",
                "interaction_type",
                "status",
                "shortcut",
                "menu",
                "related_region",
            ]
        )
    )

    print("\nINTERACTIONS")
    print(f"count: {related.height}")
    for r in related.iter_rows(named=True):
        title = _fill(r.get("interaction_title"))
        iid = _fill(r.get("interaction_id"))
        itype = _fill(r.get("interaction_type"))
        status = _fill(r.get("status"))
        shortcut = _fill(r.get("shortcut"))
        menu = _fill(r.get("menu"))
        region = _fill(r.get("related_region"))
        print(
            f"- {title} | {iid} | {itype} | {status} | shortcut={shortcut} | menu={menu} | related_region={region}"
        )

    return 0


def _contains_expr(pl, col_name: str, query_lower: str):
    pattern = re.escape(query_lower)
    return pl.col(col_name).fill_null("").str.to_lowercase().str.contains(pattern)


def cmd_search(args: argparse.Namespace) -> int:
    pl = importlib.import_module("polars")

    repo_root = _find_repo_root(SKILL_DIR)

    q = args.query.strip()
    if not q:
        print("ERROR: empty query")
        return 2
    q_lower = q.lower()

    features_path = repo_root / "PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv"
    interactions_path = repo_root / "PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv"
    window_path = repo_root / "PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv"

    features = _read_tsv(pl, features_path)
    interactions = _read_tsv(pl, interactions_path)
    window = _read_tsv(pl, window_path)

    # Enrich features with UI labels.
    features_ui = features.join(
        window.select(
            [
                pl.col("structure_key").alias("related_ui"),
                pl.col("region_label").alias("related_ui_label"),
                pl.col("region_label_ko").alias("related_ui_label_ko"),
            ]
        ),
        on="related_ui",
        how="left",
    )

    # Enrich interactions with feature title and region labels.
    interactions_full = interactions.join(
        features.select(
            [
                pl.col("feature_id"),
                pl.col("feature_title").alias("feature_title"),
                pl.col("feature_category").alias("feature_category"),
            ]
        ),
        on="feature_id",
        how="left",
    ).join(
        window.select(
            [
                pl.col("structure_key").alias("related_region"),
                pl.col("region_label").alias("related_region_label"),
                pl.col("region_label_ko").alias("related_region_label_ko"),
            ]
        ),
        on="related_region",
        how="left",
    )

    # Scope selection.
    want_features = args.scope in ("all", "features")
    want_interactions = args.scope in ("all", "interactions")

    print(f"QUERY: {q}")
    printed_any = False

    if want_features:
        feature_hit = (
            _contains_expr(pl, "feature_id", q_lower)
            | _contains_expr(pl, "category_key", q_lower)
            | _contains_expr(pl, "feature_title", q_lower)
            | _contains_expr(pl, "feature_category", q_lower)
            | _contains_expr(pl, "description", q_lower)
            | _contains_expr(pl, "related_ui", q_lower)
        )

        feature_matches = (
            features_ui.filter(feature_hit)
            .select(
                [
                    "feature_id",
                    "category_key",
                    "feature_title",
                    "feature_category",
                    "release_phase",
                    "status",
                    "related_ui",
                    "related_ui_label",
                    "related_ui_label_ko",
                ]
            )
            .sort(["feature_id"])
        )

        print("\nFEATURES")
        print(f"count: {feature_matches.height}")
        for r in feature_matches.head(args.limit).iter_rows(named=True):
            fid = _fill(r.get("feature_id"))
            ckey = _fill(r.get("category_key"))
            title = _fill(r.get("feature_title"))
            status = _fill(r.get("status"))
            phase = _fill(r.get("release_phase"))
            ui = _fill(r.get("related_ui"))
            ui_label = _fill(r.get("related_ui_label_ko"))
            print(
                f"- {fid} | {ckey} | {title} | {status} | {phase} | ui={ui} ({ui_label})"
            )
        if feature_matches.height > args.limit:
            print(f"(truncated; use --limit to increase)")
        printed_any = printed_any or (feature_matches.height > 0)

    if want_interactions:
        interaction_hit = (
            _contains_expr(pl, "interaction_title", q_lower)
            | _contains_expr(pl, "interaction_id", q_lower)
            | _contains_expr(pl, "summary", q_lower)
            | _contains_expr(pl, "shortcut", q_lower)
            | _contains_expr(pl, "menu", q_lower)
            | _contains_expr(pl, "feature_id", q_lower)
            | _contains_expr(pl, "feature_title", q_lower)
            | _contains_expr(pl, "related_region", q_lower)
        )

        interaction_matches = (
            interactions_full.filter(interaction_hit)
            .select(
                [
                    "interaction_title",
                    "interaction_id",
                    "interaction_type",
                    "status",
                    "feature_id",
                    "feature_title",
                    "shortcut",
                    "menu",
                    "related_region",
                    "related_region_label_ko",
                ]
            )
            .sort(["feature_id", "interaction_title"])
        )

        print("\nINTERACTIONS")
        print(f"count: {interaction_matches.height}")
        for r in interaction_matches.head(args.limit).iter_rows(named=True):
            title = _fill(r.get("interaction_title"))
            iid = _fill(r.get("interaction_id"))
            itype = _fill(r.get("interaction_type"))
            status = _fill(r.get("status"))
            fid = _fill(r.get("feature_id"))
            ftitle = _fill(r.get("feature_title"))
            shortcut = _fill(r.get("shortcut"))
            menu = _fill(r.get("menu"))
            region = _fill(r.get("related_region"))
            region_ko = _fill(r.get("related_region_label_ko"))
            print(
                f"- {title} | {iid} | {itype} | {status} | feature={fid} ({ftitle}) | shortcut={shortcut} | menu={menu} | region={region} ({region_ko})"
            )
        if interaction_matches.height > args.limit:
            print(f"(truncated; use --limit to increase)")
        printed_any = printed_any or (interaction_matches.height > 0)

    return 0 if printed_any else 1


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="vfi.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    p_setup = sub.add_parser("setup", help="Create venv and install polars")
    p_setup.add_argument(
        "--recreate",
        action="store_true",
        help="Delete and recreate the venv before installing",
    )
    p_setup.set_defaults(func=cmd_setup)

    p_show = sub.add_parser("show", help="Show a single feature and its interactions")
    p_show.add_argument("feature_id", help="Exact feature_id (ex: FMW-001)")
    p_show.set_defaults(func=cmd_show)

    p_search = sub.add_parser("search", help="Search across FEATURES and INTERACTIONS")
    p_search.add_argument("query", help="Search string")
    p_search.add_argument(
        "--scope",
        choices=["all", "features", "interactions"],
        default="all",
        help="Which tables to search (default: all)",
    )
    p_search.add_argument(
        "--limit",
        type=int,
        default=20,
        help="Max rows to print per section (default: 20)",
    )
    p_search.set_defaults(func=cmd_search)

    return p


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    if args.cmd == "setup":
        return cmd_setup(args)

    # For commands that require Polars, ensure we're running inside the skill venv.
    if not _in_target_venv(VENV_DIR):
        try:
            _ensure_venv(recreate=False)
        except subprocess.CalledProcessError as e:
            print("ERROR: failed to bootstrap polars virtualenv")
            print(f"venv: {VENV_DIR}")
            print(f"error: {e}")
            print(
                "Hint: run: python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py setup"
            )
            return 2
        _reexec_in_venv()

    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
