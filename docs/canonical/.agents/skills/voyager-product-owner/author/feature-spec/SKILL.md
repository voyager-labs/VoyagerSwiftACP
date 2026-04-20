---
name: feature-spec-author
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

## Policy Reminders

- Keep `SKILL.md` light; put detailed writing rules and contract/consistency workflow in the reference files.
- Follow the guide for shortcut notation, interaction links, ambiguity avoidance, exact UI labels, and AI-marker handling.
- Use the contract/consistency workflow when deciding whether to create category-level `contracts/*.toml` or `flows/*.md`.
- Keep category contracts simple: prefer `contract` + `vocabulary` + `policy` + `status/ownership/transitions`, and avoid extra alias layers such as `object_terms` unless the user explicitly asks for them.

## Source of Truths

- `.agents/skills/voyager-product-owner/author/feature-spec/references/TEMPLATE-feature-spec.md` (actual generation template)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/feature-spec-guide.md` (guide/reference)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-writing-guide.md` (contract authoring guide)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-toml-spec.md` (contract TOML field spec)
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-consistency-workflow.md` (contracts/flows workflow)
- `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`

## Workflow

Before writing or refactoring a spec body, use the reference files for the document contract and writing rules:

- `.agents/skills/voyager-product-owner/author/feature-spec/references/TEMPLATE-feature-spec.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/feature-spec-guide.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-writing-guide.md` when deciding object/state vocabulary or transition scope
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-toml-spec.md` when editing `contracts/*.toml`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-consistency-workflow.md` when shared `contracts/` or `flows/` may be needed

### 1) Generate a concrete draft from `interaction_id`

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/generate_feature_spec.py <interaction_id>
```

For batch generation:

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/generate_feature_spec.py \
  CDA-003-show_retrieval_results \
  FMW-001-open_new_file_manager_window \
  --output-dir PRODUCT/05_FEATURE_SPECS/_concrete-drafts \
  --overwrite
```

Behavior:

- reads matching row(s) from `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- resolves feature metadata from `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- emits a markdown draft whose metadata lives in YAML frontmatter
- writes to `PRODUCT/05_FEATURE_SPECS/<category>/<feature_id>-<slug>/<interaction_id>.md` unless `--output-dir` is provided

### 2) Lint existing specs

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py PRODUCT/05_FEATURE_SPECS/.../*.md
```

Useful with strict mode:

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/cda/CDA-003-handle_retrieve_intent/*.md
```

### 3) Review and refine

- review generated sections and replace draft wording with concrete behavior text where needed
- keep the document aligned with the template and guide
- commit as a focused docs change

## Guardrails

- Keep generation-time reminders in the skill or guide only; do not emit internal instruction comments into generated markdown files.
- Prefer product-facing wording over implementation-facing wording.
- Use the reference guide for frontmatter keys, fixed sections, section intent, shortcut notation, exact UI labels, interaction-link formatting, ambiguity avoidance, and `-` / `TBD` handling.
- Keep generated prose Korean by default, but preserve literal product-facing UI copy in English when that is the settled label shown to users.
- Use strict lint as a review aid for unresolved `TBD` values and draft completeness.
- Do not mass-edit unrelated spec files unless explicitly requested.

## Reference files

- generation template
- guide/reference document
- contract writing guide
- contract TOML spec
- contract/consistency workflow

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
