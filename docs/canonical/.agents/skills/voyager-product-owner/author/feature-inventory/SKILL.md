---
name: feature-inventory-author
description: "Draft and refine new FEATURE/INTERACTION inventory rows in Voyager documentation, matching existing TSV conventions and document tone. Use when creating a new feature (allocate ids, draft Korean descriptions with AI draft markers, suggest related UI/INTERACTIONS/FEATURES) and when expanding a feature with more concrete interactions/relationships."
---

# Voyager Feature Inventory Author

Create and refine Voyager Feature Inventory rows.

In this repo:

- `FI` means `Feature Inventory`
- authoring targets are:
    - `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
    - `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`

For lookups and validation, use the companion skill:

- `.agents/skills/voyager-product-owner/checker/feature-inventory/`
    - Deterministic checks: `scripts/check_feature.py`
    - Aggregated search: `scripts/vfi.py`

## Resource Layout

- This skill currently has no local `assets/` directory because its primary outputs are TSV row edits rather than reusable output assets.
- Keep `references/` for rules and field guidance only.
- If this skill later needs reusable row skeletons or applied row examples, add them under `assets/`, not `references/`.

## Required References

Read these before editing rows:

- `references/tsv-writing-guide.md`
- `references/schema-json-guide.md` when the task also changes `schema.json`

## Workflow

1. Preflight search

- Search `FEATURES` and `INTERACTIONS` for duplicates or near-duplicates.
- Identify the intended `category_key` and likely UI surface key.

1. Draft or refine rows

- Draft the `FEATURES` row first.
- Add or refine atomic `INTERACTIONS` rows only when they do not duplicate existing interactions.
- Keep row edits narrow and scoped to the requested feature work.
- In `FEATURES.description` and `INTERACTIONS.summary`, prefer product labels or natural Korean concept names over raw object keys.
- For example, prefer `현재 요청 컨텍스트`, `요청 메시지`, `이전 대화 이력`, `첨부 대상` over raw keys such as `request_context`, `request_message`, `turn_history`, `attachment`.
- Do not carry interaction-spec body-prose English label preferences back into FI long-text cells.
- Review `FEATURES.description` and `INTERACTIONS.summary` manually when they read like English label prose or copied internal terminology; do not treat that judgment as deterministic script output.

1. Update schema when needed

- If the task adds, renames, reorders, or constrains TSV columns, update the matching `schema.json` in the same pass.
- Use `references/schema-json-guide.md` before changing schema structure.

1. Validate

- Run the checker skill on the touched `feature_id` values.
- Treat warnings as review items, not silent cleanup opportunities.

## Output Format

When drafting without file edits, return:

- the new or updated `FEATURES` row as a single TSV line
- optional `INTERACTIONS` row proposals as single TSV lines
- a short list of unresolved human decisions

Do not apply TSV changes unless the user explicitly asks for file edits.

## Helper Script

Generate a draft `FEATURES` row without file writes:

```bash
python3 .agents/skills/voyager-product-owner/author/feature-inventory/scripts/draft_feature_row.py FMW "File Manager Window" "My New Feature" --release-phase BACKLOG --status 드래프트 --related-ui file_manager_window
```
