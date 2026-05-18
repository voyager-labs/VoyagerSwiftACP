# TSV Writing Guide

Use this guide when `feature-inventory-author` work edits `FEATURES/data.tsv` or `INTERACTIONS/data.tsv`.

This repo treats TSV as a human-readable and machine-checked SSOT.

## Core rules

- no empty lines
- every row must keep the same column count as the header
- no multi-line cells
- tabs are separators only, never cell content
- keep edits deterministic and diff-friendly

## Placeholder semantics

- `-` means not applicable or intentionally empty
- `TBD` means unresolved and still requires a decision
- `TBD` must not be used in primary-key fields

## AI marker semantics

- use `<<AI>>` only at the start of a long-text cell, followed by one trailing space
- keep one trailing space after `<<AI>>`
- do not use `<<AI>>` in key, ID, enum, or status-like columns
- if AI newly writes or meaningfully rewrites a long-text TSV cell, prefix that cell with `<<AI>>` and one trailing space
- remove `<<AI>>` plus the trailing space only after explicit user instruction or confirmed human review

## Wording rules

- write explanatory long-text prose in Korean by default
- keep settled literal UI labels in English when the product uses English labels
- prefer product-facing wording over implementation-facing wording
- describe what the user can do, what the system shows, or what state is managed
- avoid vague near-synonyms for settled objects or states
- if terminology is ambiguous, surface the ambiguity instead of inventing a new label

## Field-specific guidance

### FEATURES

- `feature_category`: Korean display label
- `category_key`: stable foreign-key style identifier
- `feature_title`: short English title
- `feature_id`: stable ID, never `TBD`
- `description`: Korean one-liner; use `<<AI>>` plus one trailing space when AI-drafted or AI-edited
    - prefer product labels or natural Korean concept names over raw object keys
    - for example, prefer `현재 요청 컨텍스트`, `요청 메시지`, `이전 대화 이력`, `첨부 대상`
      over raw keys such as `request_context`, `request_message`, `turn_history`, `attachment`
    - do not let interaction-spec body-prose preferences leak here
    - whether a long-text cell is using an inappropriate English label form is a human review judgment, not a deterministic script rule
- `related_ui`: `WINDOW_STRUCTURE.structure_key` when known, else `-`
- `entitlement_key`: feature unlock entitlement enum; allowed values follow the adjacent `schema.json`
- `objects`: `-` unless specific stable object keys are known

### INTERACTIONS

- `interaction_title`: imperative verb phrase
- `interaction_id`: stable `<feature_id>-<snake_slug>` form
- `interaction_type`: use the table's settled enum vocabulary
- `status`: implementation state; allowed values: `idea`, `drafted`, `planned`, `implementing`, `shipped`, `deprecated`
- `phase`: work scheduling; allowed values: `-` (stable), `now` (this cycle), `next` (next cycle), `later` (no timeline)
- `summary`: Korean one-liner; use `<<AI>>` plus one trailing space when AI-drafted or AI-edited
    - prefer product labels or natural Korean concept names over raw object keys
    - use raw object keys only when the key itself is the settled literal label or contract comparison requires it
    - do not normalize summary wording into interaction-spec body-prose English labels
    - whether a long-text cell is using an inappropriate English label form is a human review judgment, not a deterministic script rule
- `related_region`: `WINDOW_STRUCTURE.structure_key` when known, else `-`
- `menu` and `shortcut`: `-` when unknown

## Shortcut notation

- prefer modifier glyphs such as `⌘L`, `⌥⌘K`, `⇧⌘P`
- do not write `Cmd`, `Ctrl`, `Shift`, or `Option` unless the user explicitly asks for text-form labels

## Review checklist

Before finishing a TSV edit, verify:

- header and row column counts still match
- no accidental whitespace-only churn
- IDs remain stable
- new rows do not duplicate existing interactions
- long-text AI edits are marked correctly
- placeholder use matches intent: `-` vs `TBD`
