---
name: voyager-fi-ia-fs-consistency-checker
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

Do not use this skill for drafting brand new inventory rows from scratch. For authoring, use:

- `voyager-feature-inventory-author`
- `voyager-feature-spec-author`

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

Treat these as **out of scope unless the user asks**:

- cleaning up duplication just because the same fact appears in FI, IA, and FS
- rewriting document structure for elegance
- large wording-only rewrites with no contract impact

## Workflow

### 1. Run deterministic audit first

```bash
python3 .agents/skills/voyager-fi-ia-fs-consistency-checker/scripts/check_feature_bundle.py SET-007
```

This script audits one `feature_id` bundle across FI, IA, and FS.

### 2. Read the output by severity

- `FAIL`: broken references, missing specs, frontmatter mismatches, ambiguous spec mapping
- `WARN`: likely drift, hierarchy mismatch, stale deterministic sections, semantic review needed
- `INFO`: found rows, synced files, counts, expected layout

If the user asked only for review, stop after the audit and report findings before writing.

### 3. If the problem is deterministic, sync FEATURE_SPEC files

Use write mode only after reading the audit once:

```bash
python3 .agents/skills/voyager-fi-ia-fs-consistency-checker/scripts/check_feature_bundle.py SET-007 --write
```

`--write` only syncs deterministic FEATURE_SPEC content:

- YAML frontmatter
- document H1 title
- `Related Interactions`
- `Source`

It does **not** invent missing product behavior or rewrite body sections.

Use `--json` when another tool or script needs a structured result:

```bash
python3 .agents/skills/voyager-fi-ia-fs-consistency-checker/scripts/check_feature_bundle.py SET-007 --json
```

### 4. If FEATURE_SPEC files are missing, generate them

Use the feature spec author's generator:

```bash
python3 .agents/skills/voyager-feature-spec-author/scripts/generate_feature_spec.py SET-007-show_ai_provider_list
```

Generate only the missing specs, then rerun the bundle checker.

### 5. Do a short semantic contract pass

After deterministic checks are clean, inspect the affected FI/IA/FS docs and verify that these contracts line up:

- state vocabulary
- CTA vocabulary
- supported provider set or capability set
- trigger / entry-point ownership
- expected outcome vs state changes boundary
- failure-state semantics

Only flag semantic drift when it changes implementation or review interpretation. Repeated wording by itself is not a problem.

### 6. Re-validate before finishing

Always rerun the bundle checker and lint any touched FEATURE_SPEC files:

```bash
python3 .agents/skills/voyager-fi-ia-fs-consistency-checker/scripts/check_feature_bundle.py SET-007
python3 .agents/skills/voyager-feature-spec-author/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/set/SET-007-manage_ai_connections/*.md
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
