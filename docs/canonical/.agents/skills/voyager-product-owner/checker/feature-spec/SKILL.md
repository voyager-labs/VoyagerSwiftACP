---
name: feature-spec-checker
description: "Review Voyager FEATURE_SPEC documents against category-level contracts and flows. Use whenever the user asks whether spec wording, object terms, state names, CTA labels, or flow steps are aligned with `contracts/*.toml` or `flows/*.md`, even if they do not ask for a full FI/IA/FS bundle audit."
---

# Voyager Feature Spec Checker

Review `PRODUCT/05_FEATURE_SPECS` documents against category-level contracts and flows.

In this repo:

- `FS` means `Feature Specs`
- this skill focuses on:
    - `PRODUCT/05_FEATURE_SPECS/<category>/**/*.md`
    - `PRODUCT/05_FEATURE_SPECS/<category>/contracts/*.toml`
    - `PRODUCT/05_FEATURE_SPECS/<category>/flows/*.md`

Use this skill when the user wants to know whether FEATURE_SPEC wording is using the same terms, states, and sequence assumptions as the current contract and flow docs.

Do not use this skill for:

- FI/IA/FS bundle parity across tables and specs
- creating or editing new inventory rows
- generating new FEATURE_SPEC drafts from scratch

For those, use:

- `fi-ia-fs-consistency-checker`
- `feature-inventory-author`
- `feature-spec-author`

This skill is `Gate 2. FS local check` in the feature-spec authoring lifecycle.
Use it after `contract -> flow -> interaction spec` authoring and before claiming `AI Draft Complete`.

## Required References

Read these before reviewing:

- `references/spec-contract-flow-review.md`
- `.agents/skills/voyager-product-owner/author/feature-spec/references/contract-consistency-workflow.md`
- `.agents/skills/voyager-product-owner/orchestrator/references/feature-spec-authoring-lifecycle.md`

## Workflow

1. Determine scope

- Prefer one category key such as `CBW`.
- Accept a specific contract TOML path when the user is reviewing one contract.

2. Run deterministic contract/spec checks

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py CBW
```

Use `--json` when structured output helps:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_contract_consistency.py CBW --json
```

This pass should also catch missing category flow docs and flow docs that fail to reference the current contract/spec set.
It also enforces OBJECTS-first contract checks such as unknown object keys, legacy object-key fields, unused or `OBJECTS`-redefining vocabulary entries, and state/transition ownership mismatches.

3. Lint the affected interaction specs

Run strict lint only on interaction spec markdown, not `flows/*.md`:

```bash
find PRODUCT/05_FEATURE_SPECS/cbw -name '*.md' ! -path '*/flows/*' | xargs python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict
```

4. Review flow alignment

- Compare `flows/*.md` against the linked interaction specs.
- Check that step ordering, state names, object names, and branch semantics match the current contracts and specs.
- If the category has no flow doc, treat that as a structural failure, not a style preference.
- Treat this as semantic review even when deterministic scripts pass.

5. Report findings or re-validate after edits

- If the user asked only for review, report findings before editing.
- If the user asked for fixes, rerun the same checks after editing.
- Do not hand the bundle to `Phase 2. Human Review` while this gate still has a blocking structural or semantic failure.

## Output Format

Report back in this order:

- `Findings`: `FAIL` first, then `WARN`
- `Flow Drift`: only if flow docs disagree with contracts or interaction specs
- `Validation`: commands run and whether they passed

If there are no failures or warnings, say the category's FEATURE_SPEC docs are aligned with the current contracts and flows, and call out any remaining human judgment separately.
