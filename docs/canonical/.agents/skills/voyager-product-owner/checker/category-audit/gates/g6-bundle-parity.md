# Gate 6: Bundle / Category Parity

## Input

- Category scope manifest (from Gate 0)
- All interaction spec files that passed Gate 5
- FI INTERACTIONS TSV
- IA WINDOW_STRUCTURE TSV
- FEATURES TSV
- Category contracts and flows

## Purpose

Final deterministic verification that FI, IA, and FS are fully aligned at the cross-layer level. This is the last gate before Category PASS.

## Procedure

### 1. Run bundle checker per feature_id

For each feature_id in scope:

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/check_feature_bundle.py <FEATURE_ID>
```

This verifies:
- `FEATURES.feature_id` exists exactly once
- `FEATURES.related_ui` exists in `WINDOW_STRUCTURE.structure_key` unless `-`
- Each INTERACTION has matching `feature`, `category_key`, `related_region`
- `related_region` equals or nests under `FEATURES.related_ui`
- Each interaction has exactly one matching FEATURE_SPEC file
- FEATURE_SPEC frontmatter matches INTERACTIONS exactly for all required fields
- FEATURE_SPEC `Inventory row` matches current INTERACTIONS TSV
- FEATURE_SPEC `Related Interactions` matches sibling interactions
- One-file handoff signals are mirrored between FS and FI

### 2. Run category-wide evaluation

```bash
python3 .agents/skills/voyager-product-owner/checker/bundle-consistency/scripts/evaluate_category_consistency.py <CATEGORY>
```

This aggregates bundle results across the entire category and checks for:
- Cross-feature consistency
- Shared vocabulary alignment
- Category-level contract coverage

### 3. Run final lint pass

```bash
python3 .agents/skills/voyager-product-owner/author/feature-spec/scripts/lint_feature_spec.py --strict PRODUCT/05_FEATURE_SPECS/<category>/<category>-*/*.md
```

Confirm 0 FAIL across all category specs. This catches any regressions introduced during earlier gate fixes.

### 4. Verify audit matrix completion

Read the audit matrix. Confirm:
- All in-scope interaction_ids are listed
- All gate columns are filled (P or out_of_scope)
- No NP cells remain
- No empty cells remain

## P Criteria

All of the following:

- `check_feature_bundle.py` returns 0 FAIL for every feature_id
- `evaluate_category_consistency.py` returns 0 FAIL for the category
- `lint_feature_spec.py --strict` returns 0 FAIL for all category specs
- Audit matrix has no NP or empty cells for in-scope items

## NP Criteria

Any of the following:

- Any feature_id bundle check returns FAIL
- Category evaluation returns FAIL
- Any spec lint returns FAIL
- Audit matrix has unfilled or NP cells

## Fix Protocol

For each NP item:

1. **Bundle FAIL**: Use `check_feature_bundle.py --write` to sync deterministic fields, then re-run
2. **Category eval FAIL**: Identify the specific cross-feature issue, fix in the relevant FI/IA/FS doc
3. **Lint FAIL**: Fix the specific lint issue (usually frontmatter drift from earlier edits)
4. **Matrix gap**: Run the missing gate or mark as out_of_scope with reason

After fixes, re-run ALL verification commands (not just the one that failed).

## Commit Format

```
audit(<CATEGORY>): Gate 6 — 번들/카테고리 정합성 PASS
```

If fixes were applied:

```
audit(<CATEGORY>): Gate 6 — 번들 정합성 수정 후 PASS (<count>건)
```

## Output

- Bundle check results per feature_id
- Category evaluation results
- Final lint results
- Completed audit matrix (all cells P)
- **Category PASS declaration**: "Category <CATEGORY> audit complete. All gates PASS. <N> in-scope interaction_ids verified."

## Final: Category PASS

After Gate 6 PASS, produce the final audit report:

```markdown
# Category Audit Report: <CATEGORY>

## Scope
- Category: <CATEGORY>
- In-scope interaction_ids: <count> (<list>)
- Out-of-scope: <count> (<list with reasons>)

## Gate Results
| Gate | Result | Fixes Applied |
|------|--------|---------------|
| 0    | P      | -             |
| 0.5  | P      | -             |
| 1    | P      | <count>       |
| 2    | P      | <count>       |
| 3    | P      | <count>       |
| 4    | P      | <count>       |
| 5    | P      | <count>       |
| 6    | P      | <count>       |

## Commit History
<list of gate commits>

## Remaining Phase 2 Items
<any semantic/style items deferred to human review>

## Category PASS
<Category> audit complete. All gates PASS. Ready for human review handoff.
```
