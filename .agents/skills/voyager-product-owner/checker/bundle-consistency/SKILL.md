---
name: fi-ia-fs-consistency-checker
description: "Audit and align Voyager feature documentation for a single feature_id across FI (Feature Inventory), IA (Information Architecture), and FS (Feature Specs). Use whenever the user asks to review, audit, sync, or fix a feature bundle for 정합성, mismatch, drift, stale spec metadata, or \"FI/IA/FS 맞춰줘\", especially when FEATURES, INTERACTIONS, WINDOW_STRUCTURE, and FEATURE_SPEC markdown need to be checked together instead of row-by-row."
---

# Voyager FI/IA/FS Consistency Checker

Audit a single Voyager feature bundle and sync deterministic FEATURE_SPEC fields.

In this repo, the abbreviations mean:

- `FI` = `Feature Inventory`
- `IA` = `Information Architecture`
- `FS` = `Feature Specs`

This skill exists for cross-document consistency work across those three document layers:

- `FI (Feature Inventory)`: `PRODUCT/04_FEATURE_INVENTORY/FEATURES/data.tsv`
- `FI (Feature Inventory)`: `PRODUCT/04_FEATURE_INVENTORY/INTERACTIONS/data.tsv`
- `IA (Information Architecture)`: `PRODUCT/03_INFORMATION_ARCHITECTURE/WINDOW_STRUCTURE/data.tsv`
- `FS (Feature Specs)`: `PRODUCT/05_FEATURE_SPECS/**/*.md`

Reference workflows:

- `.agents/skills/voyager-product-owner/checker/bundle-consistency/references/evaluation-workflow.md`

Do not use this skill for drafting brand new inventory rows from scratch. For authoring, use:

- `feature-inventory-author`
- `feature-spec-author`

## What This Skill Optimizes For

Catch and fix review-relevant drift, not document-style debates.

Treat these as **in scope**:

- missing or broken `feature_id` / `interaction_id` / `structure_key` references
- FEATURE `related_ui` and INTERACTION `related_region` hierarchy mismatches
- missing FEATURE_SPEC files for known interactions
- stale FEATURE_SPEC frontmatter values compared to INTERACTIONS
- stale `Related Interactions` links inside FEATURE_SPEC files
- stale `Source line` values inside FEATURE_SPEC files
- functional contract drift across FI/IA/FS, such as inconsistent state names, CTA names, supported provider set, or trigger/result boundaries
- primary object drift across FI/IA/FS, such as one document talking about `request` while another talks about `response` for the same contract

Treat these as **out of scope unless the user asks**:

- cleaning up duplication just because the same fact appears in FI, IA, and FS
- rewriting document structure for elegance
- large wording-only rewrites with no contract impact

## Workflow

### 1. Run deterministic audit first

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py SET-007
```

This script audits one `feature_id` bundle across FI, IA, and FS.

If the category has machine-readable contracts, run the contract checker first:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py CBW
```

This script audits category-level `contracts/*.toml` against the corresponding interaction specs.

For a repeatable category-wide evaluation pass, use:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/evaluate_category_consistency.py CBW
```

For stable regression evals against managed fixtures, use:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/run_skill_evals.py
```

### 2. Read the output by severity

- `FAIL`: broken references, missing specs, frontmatter mismatches, ambiguous spec mapping
- `WARN`: likely drift, hierarchy mismatch, stale deterministic sections, semantic review needed
- `INFO`: found rows, synced files, counts, expected layout
- For the contract checker:
  - `FAIL`: broken contract structure, unknown interactions, invalid transitions
  - `WARN`: missing contract references, missing required object/state terms, forbidden state terms still present

If the user asked only for review, stop after the audit and report findings before writing.

Important limit:

- The deterministic checker cannot prove that free-form prose is talking about the same object or the same state across documents.
- Treat object/state identity as a semantic review problem unless the docs declare an explicit contract you can compare.
- If category-level `contracts/*.toml` or `flows/` docs exist, read them during the semantic pass before judging interaction prose.

### 3. If the problem is deterministic, sync FEATURE_SPEC files

Use write mode only after reading the audit once:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py SET-007 --write
```

`--write` only syncs deterministic FEATURE_SPEC content:

- YAML frontmatter
- document H1 title
- `Related Interactions`
- `Source`

It does **not** invent missing product behavior or rewrite body sections.

Use `--json` when another tool or script needs a structured result:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py SET-007 --json
```

### 4. If FEATURE_SPEC files are missing, generate them

Use the feature spec author's generator:

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/generate_feature_spec.py SET-007-show_ai_provider_list
```

Generate only the missing specs, then rerun the bundle checker.

### 5. Do a short semantic contract pass

After deterministic checks are clean, inspect the affected FI/IA/FS docs and verify that these contracts line up:

- primary object ownership
- state vocabulary
- CTA vocabulary
- supported provider set or capability set
- trigger / entry-point ownership
- expected outcome vs state changes boundary
- failure-state semantics

Only flag semantic drift when it changes implementation or review interpretation. Repeated wording by itself is not a problem.

If the user explicitly says an FS long-text field has been human-reviewed and its `<<AI>>` marker should be removed, mirror that removal in the corresponding FI long-text cell in the same edit pass.

### 6. Re-validate before finishing

Always rerun the bundle checker and lint any touched FEATURE_SPEC files:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py SET-007
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/set/SET-007-manage_ai_connections/*.md
```

## Deterministic Rules Enforced By The Script

- `FEATURES.feature_id` exists exactly once
- `FEATURES.related_ui` exists in `WINDOW_STRUCTURE.structure_key` unless `-`
- each INTERACTION for the feature has:
    - matching `feature`
    - matching `category_key`
    - valid `related_region`
    - `related_region` equal to or nested under `FEATURES.related_ui` unless one side is `-`
- each interaction has exactly one matching FEATURE_SPEC file
- FEATURE_SPEC frontmatter matches INTERACTIONS exactly for:
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
- FEATURE_SPEC `Source line` matches the current INTERACTIONS TSV line
- FEATURE_SPEC `Related Interactions` matches sibling interactions for the same feature

## Report Structure

When reporting back to the user, keep the output compact and action-oriented:

- `Findings`: `FAIL` first, then `WARN`
- `Synced`: only if `--write` changed files
- `Validation`: rerun commands and results

If there are no `FAIL` or `WARN` items, say that the bundle is deterministically aligned and call out any remaining semantic decisions separately.

## Example Prompts

- `SET-007 초안 정합성 한번 봐줘. FI, IA, FS 셋 다 서로 안 맞는 부분 있으면 찾아줘`
- `RCL-002 관련해서 spec frontmatter랑 source line 밀린 것들 맞춰줘`
- `이 feature bundle 문서들 review만 해줘. 자동 수정은 하지 말고 mismatch만 정리해줘`

## Notes

- This skill is strict by design. Prefer concrete `FAIL`/`WARN` output over vague prose.
- When editing files yourself, keep patches narrow and rerun validation immediately.
- If the bundle has a real product ambiguity, stop calling it a consistency problem and surface the decision explicitly.
