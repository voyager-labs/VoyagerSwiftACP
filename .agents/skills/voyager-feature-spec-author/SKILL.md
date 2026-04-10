---
name: voyager-feature-spec-author
description: "Draft and concretize Voyager FEATURE_SPEC markdown documents from INVENTORY rows into the fixed interaction specification format, using YAML frontmatter for metadata and linting for completeness and placeholder quality."
---

# Voyager Feature Spec Author

Create and refine concrete, consistently structured `PRODUCT/05_FEATURE_SPECS` documents.

In this repo:

- `FS` = `Feature Specs`
- `FI` = `Feature Inventory`

This skill writes and refines `FS` documents using `FI` rows as source inputs.

This skill is useful when you need to:

- turn an `interaction_id` into a concrete FEATURE_SPEC draft,
- bring existing specs into the current frontmatter + fixed-section format,
- check that required sections and metadata fields are present before PR review.

## Source of Truths

- `META/feature_specs_writing.md`
- `.agents/skills/voyager-feature-spec-author/references/TEMPLATE-feature-spec.md` (actual generation template)
- `.agents/skills/voyager-feature-spec-author/references/feature-spec-guide.md` (guide/reference)
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`

## Workflow

### 1) Generate a concrete draft from `interaction_id`

```bash
python3 .agents/skills/voyager-feature-spec-author/scripts/generate_feature_spec.py <interaction_id>
```

For batch generation:

```bash
python3 .agents/skills/voyager-feature-spec-author/scripts/generate_feature_spec.py \
  CDA-003-show_retrieval_results \
  FMW-001-open_new_file_manager_window \
  --output-dir PRODUCT/05_FEATURE_SPECS/_concrete-drafts \
  --overwrite
```

Behavior:

- reads matching row(s) from `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- resolves feature metadata from `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- emits a markdown draft whose metadata lives in YAML frontmatter
- writes to `PRODUCT/05_FEATURE_SPECS/<category>/<feature_id>-<slug>/<interaction_id>-<slug>.md` unless `--output-dir` is provided

### 2) Lint existing specs

```bash
python3 .agents/skills/voyager-feature-spec-author/scripts/lint_feature_spec.py PRODUCT/05_FEATURE_SPECS/.../*.md
```

Useful with strict mode:

```bash
python3 .agents/skills/voyager-feature-spec-author/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/cda/CDA-003-handle_retrieve_intent/*.md
```

### 3) Review and refine

- review generated sections and replace draft wording with concrete behavior text where needed
- keep metadata keys present and use the repo-wide `-` / `TBD` conventions consistently in frontmatter
- commit as a focused docs change

## Guardrails

- Metadata should live in YAML frontmatter, not in a markdown table.
- Keep generated spec body content in Korean (`Intent`, `Expected Outcome`, `State Changes`, etc.). Section titles can remain the fixed contract names.
- Prefer product-facing wording over implementation-facing wording.
    - Frontmatter `summary` should describe the interaction as experienced or observed in the product.
    - Body sections should focus on user-visible behavior, product rules, state changes, and operational constraints.
    - Avoid internal abstractions or modeling terminology unless they are necessary for correctness and already part of the product language.
- Required body sections are:
    - `Intent`
    - `Trigger / Entry Points`
    - `Preconditions`
    - `Expected Outcome`
    - `State Changes`
    - `User-visible Feedback`
    - `Edge Cases / Failure Handling`
    - `Acceptance Criteria`
    - `Permissions / Dependencies`
    - `Observability / Analytics`
    - `Related Interactions`
    - `Source`
- Required frontmatter fields are:
    - `interaction_id`
    - `interaction_type`
    - `feature`
    - `category_key`
    - `feature_id`
    - `status`
    - `summary`
    - `related_region`
    - `menu`
    - `shortcut`
- Frontmatter values follow the same repo-wide null conventions as TSV/body content:
    - `-` = intentionally empty / not applicable
    - `TBD` = not yet decided
- Placeholder values in body sections are also allowed by repo rules.
- strict mode is a review aid for unresolved `TBD` values and draft completeness.
- strict mode does not fail a document solely because body/frontmatter contains `-` / `TBD`.
- In strict mode, `-` is treated as confirmed not-applicable and does not emit a warning.
- In strict mode, `TBD` is treated as unresolved and emits a warning.
- Do not mass-edit unrelated spec files unless explicitly requested.

## Reference files

- generation template
- guide/reference document

## Scripts

- `scripts/generate_feature_spec.py`
    - `--output-dir` / `--overwrite` / `--template` / `--dry-run`
- `scripts/lint_feature_spec.py`
    - `--strict` for additional `TBD`-density warnings
    - exits non-zero on missing required sections or required metadata keys

## Notes

- Generation uses the skill's default reference template by default.
- Guide/reference material should explain how to use the template, not duplicate the template body.
- The linter still accepts legacy `## Metadata` markdown tables during transition, but YAML frontmatter is the preferred format.
