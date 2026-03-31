---
name: voyager-feature-inventory-author
description: Draft and refine new FEATURE/INTERACTION inventory rows in Voyager documentation, matching existing TSV conventions and document tone. Use when creating a new feature (allocate ids, draft Korean descriptions with AI draft markers, suggest related UI/INTERACTIONS/FEATURES) and when expanding a feature with more concrete interactions/relationships.
---

# Voyager Feature Inventory Author

Create and refine new feature inventory rows while keeping the repo SSOT rules intact.

This skill is for "authoring" tasks (drafting new rows, allocating IDs, suggesting relationships). For lookups and validation, use the companion skill:

- `.agents/skills/voyager-feature-inventory/voyager-feature-inventory-checker/`
  - Deterministic checks: `scripts/check_feature.py`
  - Aggregated search: `scripts/vfi.py`

## Guardrails (Hard Rules)

- Follow TSV hard rules in `META/tsv_rules.md`:
  - No empty lines
  - Fixed column count per row
  - No multi-line cells
  - Use `-` for not-applicable, `TBD` for not-yet-written
- Use `<<AI>> ` only at the start of a cell (single space after), and only for long-text fields.
  - If AI newly writes or edits a long-text TSV cell (including edits to existing rows), prefix that cell with `<<AI>> `.
  - Keep/remove `<<AI>> ` only by explicit user request or after confirmed human review.
  - Do not use `<<AI>>` in key/ID/enum columns (ex: `feature_id`, `category_key`, `interaction_id`, `status`).
- Do not write `TBD` into primary keys.
- Keep output deterministic and diff-friendly (avoid reformatting unrelated rows).

## Workflow: Draft A New Feature

1) Preflight search (avoid duplicates)
- Search FEATURES/INTERACTIONS with the checker skill for similar titles/keywords.
- Identify the intended `category_key` and the likely `related_ui` (`WINDOW_STRUCTURE.structure_key`).

2) Allocate IDs
- Choose `category_key` from `PRODUCT/04_FEATURE_INVENTORY/FEATURE_CATEGORIES/data.tsv`.
- Allocate a new `feature_id` in that category by scanning existing `FEATURES.feature_id` values and picking the next numeric suffix.

3) Draft the FEATURES row
Draft a TSV row for `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`.

- `feature_category`: Korean category title (display)
- `category_key`: stable FK
- `feature_title`: short English title
- `feature_id`: stable ID
- `release_phase`, `status`
- `description`: Korean one-liner; if AI-drafted or AI-edited, prefix `<<AI>> `
- `related_ui`: if known, set a `structure_key`; else `-`
- `objects`: `-` unless you have specific keys

4) Suggest related INTERACTIONS
Propose atomic interactions in the existing style for `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`:

- `interaction_title`: imperative verb phrase
- `interaction_id`: `<feature_id>-<snake_slug>` (stable). Example: `FMW-001-open_new_file_manager_window`
- `interaction_type`: `command`/`input`/`display`/`background`
- `feature`: feature title (display)
- `category_key`, `feature_id`
- `status`
- `summary`: Korean one-liner; if AI-drafted or AI-edited, prefix `<<AI>> `
- `related_region`: `WINDOW_STRUCTURE.structure_key` when known; else `-`
- `menu`/`shortcut`: `-` if unknown

If an interaction already exists, do not create a duplicate; link to the existing `interaction_id` instead.

5) Validate
- Run the checker skill on the new `feature_id` and ensure warnings are intentional.

## Output Format

When drafting, output:

- The new FEATURES row as a single TSV line
- Optional: INTERACTIONS row proposals (each as a single TSV line)
- A short list of "needs human decision" items (where you used `TBD` or `-`)

Do not apply changes unless the user explicitly asks to update the TSV files.

## Helper Script (Optional)

Generate a draft FEATURES row (no file writes):

```bash
python3 .agents/skills/voyager-feature-inventory/voyager-feature-inventory-author/scripts/draft_feature_row.py FMW "File Manager Window" "My New Feature" --release-phase BACKLOG --status 드래프트 --related-ui file_manager_window
```
