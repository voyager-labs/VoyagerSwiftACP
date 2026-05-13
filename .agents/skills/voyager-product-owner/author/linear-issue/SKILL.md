---
name: linear-issue-author
description: "Draft Linear feature-development and implementation issue documents from Voyager SSOT tables. Use when converting one or more feature_id values from PRODUCT/04_FEATURE_INVENTORY into ready-to-paste build issue markdown with scope, requirements, and Given/When/Then acceptance criteria. Do not use for FOUNDATION_DOCS, 기능 스펙 정의, or feature-spec-definition issues; use `feature-spec-issue-author` for those. Triggers: Linear issue, 리니어 이슈, feature_id, implementation issue, build issue, 개발 이슈."
---

# Voyager Linear Issue Author

Generate build and implementation issue drafts from current Voyager feature inventory data.

This skill is for delivery-facing Linear issues.
Use it when the outcome is a developer-owned build slice, not when the outcome is a docs-first `FOUNDATION_DOCS` or `기능 스펙 정의 및 정리` issue.

## Sources of truth

- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `PRODUCT/06_USE_CASES/*.md`
- `.agents/skills/voyager-product-owner/author/linear-issue/assets/TEMPLATE-feature-implementation.md`

## Resource Layout

- Use `assets/` for reusable output shells and any future applied issue examples.
- Keep `references/` for rules, schemas, or workflow docs only.

## Workflow

1. Pick target feature IDs

- Confirm one or more `feature_id` values from `FEATURES`.

2. Generate draft markdown to stdout

```bash
python3 .agents/skills/voyager-product-owner/author/linear-issue/scripts/draft_linear_issue.py EVM-002
```

3. Batch-generate files into an explicit scratch/output directory only when needed

```bash
python3 .agents/skills/voyager-product-owner/author/linear-issue/scripts/draft_linear_issue.py EVM-002 EOP-005 --output-dir /tmp/voyager-linear-issues --overwrite
```

4. Review and refine

- Verify In Scope/Out of Scope and AC fit current roadmap intent.
- Keep title as one-line summary, and keep labels/type handling in Linear labels.
- If the request is really about settling IA/FI/FS contract before design/build, stop and switch to `feature-spec-issue-author` instead of forcing this template.

## What the helper script does

- Loads a feature row by `feature_id`
- Collects related interactions by `INTERACTIONS.feature_id`
- Builds markdown following the skill template structure
- Suggests scope bullets from interaction titles
- Suggests GWT acceptance criteria from interaction summary
- Optionally writes one draft file per feature

## Guardrails

- Do not modify SSOT TSV rows when asked only to draft issues.
- Keep issue drafts deterministic and diff-friendly.
- If a feature ID is missing, fail explicitly instead of guessing.
- Treat this skill as implementation-only. If the issue is mainly deciding what docs should exist or how product behavior should be defined, route to `feature-spec-issue-author`.
- Do not treat any repo-tracked draft directory as canonical; use stdout by default, or a user-chosen scratch directory when file output is required.
- Preserve SSOT placeholder semantics when summarizing inventory truth:
    - `-` means not applicable or intentionally empty
    - `TBD` means unresolved and should surface as an open decision, not be silently normalized away
- Keep explanatory prose in Korean by default, but preserve settled user-visible labels, status names, CTA text, and menu labels in English when they come from product truth.
