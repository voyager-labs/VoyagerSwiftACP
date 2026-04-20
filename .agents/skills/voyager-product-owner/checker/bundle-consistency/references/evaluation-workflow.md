# Evaluation Workflow

Use this workflow when you want a repeatable validation pass after changing contracts, interaction specs, or FI rows inside one category.

## Goal

Run one command that evaluates:

- category-level `contracts/*.toml`
- every feature bundle in that category via the existing FI/IA/FS checker

This is the default evaluation loop for categories that already have contract files.

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
2. Update the affected interaction specs and FI rows.
3. Run the category evaluation command.
4. Fix `FAIL` first, then `WARN`.
5. Repeat until the category result is `PASS`.

## Severity Meaning

### `FAIL`

- broken contract structure
- unknown interaction referenced by a contract
- invalid transition state
- bundle-level broken references or frontmatter mismatches

### `WARN`

- missing contract references in specs
- spec prose missing declared object/state terms
- forbidden state terms still present
- semantic drift that is review-relevant but not structurally broken

## When To Use Category Eval

Use category eval whenever:

- a `contracts/*.toml` file changed
- a `flows/*.md` file changed and that flow affects interaction wording
- one interaction change may have changed shared state vocabulary
- the user asks for "전체 정합성 체크", "카테고리 단위 review", or "계속적으로 유지되게"
