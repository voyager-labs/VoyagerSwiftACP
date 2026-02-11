---
name: voyager-feature-inventory-checker
description: Look up and validate a Voyager feature in the FEATURE_INVENTORY tables (04_FEATURE_INVENTORY/*). Use when you need to check whether a feature_id exists, inspect its metadata (release_phase/status/related_ui), or list related INTERACTIONS. Triggers: FEATURE_INVENTORY, 기능 인벤토리, feature_id.
---

# Voyager Feature Inventory Checker

Check a specific feature entry in `04_FEATURE_INVENTORY/FEATURES/data.tsv`.

This skill supports both:

- Polars-based aggregated search (`scripts/vfi.py`)
- Deterministic row-level checks (`scripts/check_feature.py`)

## Setup (Polars)

This skill installs Polars into a skill-scoped virtualenv:

- venv: `.agents/skills/.venvs/voyager-feature-inventory-checker/`
- deps: `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/requirements.txt`

One-time setup:

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py setup
```

`show`/`search` commands will also auto-bootstrap the venv if needed.

## Quick Start

Show a single feature (Polars):

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py show FMW-001
```

Search across FEATURES + INTERACTIONS (Polars):

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/vfi.py search "Navigate Pages" --scope all
```

Deterministic check (stdlib, no deps):

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/check_feature.py FMW-001
```

## What This Checks (check_feature.py)

`scripts/vfi.py` focuses on loading/joining/searching. Use `scripts/check_feature.py` when you want explicit consistency warnings.

- Finds the matching row(s) in FEATURES and prints a compact report
- Validates required fields (ex: `feature_category`, `category_key`, `feature_title`, `feature_id`)
- Checks category consistency:
  - FEATURES.category_key exists in FEATURE_CATEGORIES.category_key
  - `feature_category` matches FEATURE_CATEGORIES.category_title (warn on mismatch)
  - (fallback) if FEATURES.category_key is missing, uses the `feature_id` prefix (ex: `FMW`)
- Checks UI reference consistency:
  - FEATURES.related_ui exists in WINDOW_STRUCTURE.structure_key (warn on missing)
- Lists related INTERACTIONS (same `feature_id`), with basic counts and a preview list
  - Includes `interaction_id` (stable key, ex: `FMW-001-open_new_file_manager_window`)
  - Validates INTERACTIONS.related_region exists in WINDOW_STRUCTURE.structure_key (warn on missing)
  - Warns if INTERACTIONS.category_key mismatches FEATURES.category_key (fallback: feature_id prefix)

## Sources Of Truth (Repo)

- `04_FEATURE_INVENTORY/FEATURES/data.tsv`
- `04_FEATURE_INVENTORY/FEATURES/schema.json`
- `04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`
- `04_FEATURE_INVENTORY/FEATURE_CATEGORIES/schema.json`
- `04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `04_FEATURE_INVENTORY/INTERACTIONS/schema.json`
- `03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`
- `META/tsv_rules.md`

## Schema Migration (v2)

If your local working tree still uses the older headers, migrate deterministically with:

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/migrate_inventory_schema_v2.py
```

This adds:

- FEATURES.category_key
- INTERACTIONS.interaction_id

## TSV Whitespace Normalization

If you see noisy diffs caused by accidental spaces (ex: `- `, NBSP, padding in key columns), run:

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/format_tsv_whitespace.py 04_FEATURE_INVENTORY/INTERACTIONS/data.tsv
```

Apply in-place:

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/scripts/format_tsv_whitespace.py --write 04_FEATURE_INVENTORY/INTERACTIONS/data.tsv
```

## Notes

- TSV conventions use `-` (not applicable) and `TBD` (must be filled).
- `scripts/check_feature.py` treats `-` as empty for required fields, but allows `TBD` for required fields.
