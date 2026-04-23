# Evaluation Workflow

Use this workflow when you want a repeatable validation pass after changing contracts, interaction specs, or FI rows inside one category.

This is the default `Gate 3. Bundle validation` loop in the feature-spec authoring lifecycle.

## Goal

Run one command that evaluates:

- category-level `contracts/*.toml`
- required category-level `flows/*.md`
- every feature bundle in that category via the existing FI/IA/FS checker

This is the default evaluation loop for categories that already have contract-driven spec files.

## Default Command

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/evaluate_category_consistency.py CBW
```

This command aggregates:

1. `check_contract_consistency.py <CATEGORY>`
2. `check_feature_bundle.py <FEATURE_ID>` for every feature in the category

## Regression Eval Command

For stable regression checks against managed fixtures, run:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/run_skill_evals.py
```

Optional JSON output:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/run_skill_evals.py \
  --output /tmp/vfi-checker-evals.json
```

This command reads `evals/evals.json`, runs the declared fixture-based cases, and verifies the expected checker results.

## How To Use It

1. Update the contract TOML file first if the vocabulary or transition contract changed.
2. Update the category flow doc.
3. Update the affected interaction specs and FI rows.
4. Run the category evaluation command.
5. Fix `FAIL` first, then `WARN`.
6. Repeat until the category result is `PASS`.

## Severity Meaning

### `FAIL`

- broken contract structure
- missing primary object key or unknown `OBJECTS.key`
- unknown interaction referenced by a contract
- invalid transition state
- `exits_to` and transition definitions that disagree
- missing category flow doc
- flow doc missing required contract/spec references
- bundle-level broken references or frontmatter mismatches

### `WARN`

- legacy object-key fields still present
- unused vocabulary entries, vocabulary entries that redefine `OBJECTS` keys, or other review-relevant contract wording drift
- ownership object references outside declared contract scope
- `entered_by` / transition trigger ownership mismatches
- missing contract references in specs
- spec prose missing declared object names or exact state/status keys
- forbidden state keys still present
- semantic drift that is review-relevant but not structurally broken

## When To Use Category Eval

Use category eval whenever:

- a `contracts/*.toml` file changed
- a `flows/*.md` file changed and that flow affects interaction wording
- one interaction change may have changed shared state vocabulary
- the user asks for "전체 정합성 체크", "카테고리 단위 review", or "계속적으로 유지되게"

Passing this gate supports `AI Draft Complete`.
It does not by itself mean the docs are approved.
