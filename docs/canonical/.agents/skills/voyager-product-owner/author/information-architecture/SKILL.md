---
name: information-architecture-author
description: "Draft and refine Voyager Information Architecture tables such as OBJECTS, WINDOW_STRUCTURE, and MENUS, matching TSV conventions and IA naming rules. Use when IA keys, labels, summaries, or adjacent schema support must be created or revised for product docs work."
---

# Voyager Information Architecture Author

Create and refine Voyager Information Architecture tables.

In this repo:

- `IA` means `Information Architecture`
- authoring targets are:
    - `PRODUCT/03_INFORMATION_ARCHITECTURE/OBJECTS/data.tsv`
    - `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`
    - `PRODUCT/03_INFORMATION_ARCHITECTURE/MENUS/data.tsv`

Use this skill when the request needs IA-side authoring such as:

- adding or revising `OBJECTS.key`
- refining `OBJECTS.label_ko` or `OBJECTS.summary`
- adding or renaming `WINDOW_STRUCTURE.structure_key`
- maintaining adjacent IA rows that FI or FS contracts depend on

## Resource Layout

- This skill currently has no local `assets/` directory because its primary outputs are TSV row edits rather than reusable output assets.
- Keep `references/` for rules and table-specific guidance only.
- If this skill later needs reusable row skeletons or applied row examples, add them under `assets/`, not `references/`.

## Required References

Read these before editing rows:

- `PRODUCT/03_INFORMATION_ARCHITECTURE/index.md`
- `references/objects-writing-guide.md` when editing `OBJECTS/data.tsv`
- `.agents/skills/voyager-product-owner/author/feature-inventory/references/schema-json-guide.md` when the task also changes `schema.json`

## Workflow

1. Confirm the target IA table.

- `OBJECTS` for canonical object nouns and one-line concept summaries
- `WINDOW_STRUCTURE` for stable UI surface keys
- `MENUS` for menu tree nodes

2. Reuse before adding.

- search for an existing stable key before creating a new one
- prefer revising wording over creating near-duplicate IA rows

3. Keep edits local.

- only add the minimum keys needed for the active bundle or category change
- do not turn sidecar IA work into unrelated taxonomy cleanup

4. Validate references after editing.

- if FS contracts depend on `OBJECTS.key`, rerun the contract checker
- if FI rows depend on `WINDOW_STRUCTURE.structure_key`, rerun the relevant FI/IA/FS checker

## Guardrails

- write IA explanatory prose in Korean by default
- keep keys stable, reviewable, and implementation-agnostic
- treat `OBJECTS.summary` as product-concept prose, not schema commentary
- do not invent alternate labels for already-settled object nouns
