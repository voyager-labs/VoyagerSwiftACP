---
name: voyager-linear-issue-author
description: Draft Linear feature-implementation issue documents from Voyager SSOT tables. Use when converting one or more feature_id values from PRODUCT/04_FEATURE_INVENTORY into ready-to-paste Linear issue markdown with scope, requirements, and Given/When/Then acceptance criteria. Triggers: Linear issue, 리니어 이슈, feature_id, implementation issue.
---

# Voyager Linear Issue Author

Generate implementation issue drafts from current Voyager feature inventory data.

## Sources of truth

- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `PRODUCT/06_USE_CASES/*.md`
- `.agents/skills/voyager-linear-issue-author/templates/TEMPLATE-feature-implementation.md`

## Workflow

1) Pick target feature IDs
- Confirm one or more `feature_id` values from `FEATURES`.

2) Generate draft markdown

```bash
python3 .agents/skills/voyager-linear-issue-author/scripts/draft_linear_issue.py EVM-002
```

3) Batch-generate files into draft directory

```bash
python3 .agents/skills/voyager-linear-issue-author/scripts/draft_linear_issue.py EVM-002 EAC-005 --output-dir PRODUCT/LINEAR_ISSUE_DRAFTS/generated --overwrite
```

4) Review and refine
- Verify In Scope/Out of Scope and AC fit current roadmap intent.
- Keep title as one-line summary, and keep labels/type handling in Linear labels.

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
