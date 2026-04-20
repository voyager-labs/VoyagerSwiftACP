---
name: feature-inventory-checker
description: 'Look up and validate Voyager FEATURE_INVENTORY entries (PRODUCT/04_FEATURE_INVENTORY/*). Use for (1) exact feature_id checks, and (2) impact discovery when users ask "which features need updates" from Korean/English requirement text. Triggers: FEATURE_INVENTORY, 기능 인벤토리, 피쳐 인벤토리, feature_id, related features, 영향 범위, 변경 필요한 feature.'
---

# Voyager Feature Inventory Checker

Check a specific feature entry in `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`.

In this repo, `FI` means `Feature Inventory`.
This skill validates FI rows only.
If the user wants one feature bundle checked across `FI` + `IA (Information Architecture)` + `FS (Feature Specs)`, use `fi-ia-fs-consistency-checker` instead.

This skill supports both:

- Polars-based aggregated search (`scripts/vfi.py`)
- Deterministic row-level checks (`scripts/check_feature.py`)

For cross-document consistency work spanning `FI` + `IA` + `FS`, do not stretch this skill beyond row-level inventory validation. Use:

- `fi-ia-fs-consistency-checker`

## Setup (Polars)

This skill installs Polars into a skill-scoped virtualenv:

- venv: `.agents/skills/.venvs/feature-inventory-checker/`
- deps: `.agents/skills/voyager-product-owner/checker/feature-inventory/requirements.txt`

One-time setup:

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py setup
```

`show`/`search` commands will also auto-bootstrap the venv if needed.

## Quick Start

Show a single feature (Polars):

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py show FMW-001
```

Search across FEATURES + INTERACTIONS (Polars):

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py search "Navigate Pages" --scope all
```

Deterministic check (stdlib, no deps):

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/check_feature.py FMW-001
```

Contains match check (title/description/feature_id substring):

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/check_feature.py "System Properties" --match contains
```

## Operating Modes

### Mode A: Exact ID validation (fast)

Use when the user already gives a `feature_id`.

1. Run `check_feature.py <feature_id>`.
2. Use the printed INTERACTIONS list to confirm related rows.

### Mode B: Impact discovery from requirement text (KR+EN)

Use when the user asks "관련 기능 찾아줘" or "어떤 feature 변경 필요?" without IDs.

Important: this is not true vector semantic search. It is high-recall discovery via bilingual keyword expansion + deterministic ID validation.

1. Build bilingual keyword packs from the request.
    - Prefer inventory language, not implementation buzzwords.
    - Example packs:
        - `결정론`, `deterministic`, `후보`, `candidate`
        - `시스템 프로퍼티`, `system property`, `메타데이터`, `metadata`
        - `인덱싱`, `indexing`, `필터`, `filter`
2. Run broad searches with `vfi.py search` for each keyword.
    - Use `--scope all` and larger `--limit` (50-100) for recall.
3. Run `check_feature.py "<keyword>" --match contains` for ambiguous terms.
    - This searches `feature_id`, `feature_title`, `description`.
    - If ambiguous, it prints candidate IDs; use those IDs next.
4. Validate each candidate ID with exact `check_feature.py <id>`.
5. Classify output as:
    - `must-update`: directly conflicts with requested change
    - `consider-update`: adjacent behavior/wording likely affected
    - `no-change`: related domain but no required row changes

Recommended command pattern:

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py search "결정론" --scope all --limit 80
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py search "deterministic" --scope all --limit 80
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py search "시스템 프로퍼티" --scope all --limit 80
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/vfi.py search "system property" --scope all --limit 80
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/check_feature.py "System Properties" --match contains
```

## What This Checks (check_feature.py)

`scripts/vfi.py` focuses on loading/joining/searching. Use `scripts/check_feature.py` when you want explicit consistency warnings.

- Finds the matching row(s) in FEATURES and prints a compact report
- Matching modes:
    - `id`: exact feature_id
    - `title`: exact title
    - `contains`: substring search over `feature_id`, `feature_title`, `description`
    - `auto`: picks `id` for `ABC-123` patterns, otherwise `contains`
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

- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/schema.json`
- `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/schema.json`
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/schema.json`
- `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`
- `META/tsv_rules.md`

## Schema Migration (v2)

If your local working tree still uses the older headers, migrate deterministically with:

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/migrate_inventory_schema_v2.py
```

This adds:

- FEATURES.category_key
- INTERACTIONS.interaction_id

## TSV Whitespace Normalization

If you see noisy diffs caused by accidental spaces (ex: `- `, NBSP, padding in key columns), run:

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/format_tsv_whitespace.py PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv
```

Apply in-place:

```bash
python3 .agents/skills/voyager-product-owner/checker/feature-inventory/scripts/format_tsv_whitespace.py --write PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv
```

## Notes

- TSV conventions use `-` (not applicable) and `TBD` (must be filled).
- `scripts/check_feature.py` treats `-` as empty for required fields, but allows `TBD` for required fields.
- For impact analysis, always do two-step validation: broad discovery (`vfi.py search`) -> exact confirmation (`check_feature.py <id>`).
