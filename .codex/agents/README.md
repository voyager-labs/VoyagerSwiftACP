# Voyager Codex Agents

Project-scoped custom agents for `voyager-documentation`.

These files follow the Codex custom subagent format documented here:

- [Codex custom subagent format](https://developers.openai.com/codex/subagents)

Codex loads project agents from `.codex/agents/*.toml`.

## Included agents

- `product_interviewer`
    - Clarify fuzzy product requests before editing thesis, persona, IA, FI, or FS.
- `scope_reviewer`
    - Classify requested changes and identify the minimal document touch set inside the product harness.
- `inventory_author`
    - Draft or refine FI rows in `FEATURES` and `INTERACTIONS`, and update adjacent IA keys when the feature change requires it.
- `spec_author`
    - Draft or refine FEATURE_SPEC files from inventory truth, and update adjacent IA keys when spec work requires it.
- `bundle_reviewer`
    - Audit FI/IA/FS consistency for one feature bundle, including contract-aware drift when relevant.
- `product_researcher`
    - Research a named product deeply and explain its features, UI/UX, screenshots, demos, and behavior. This agent analyzes only; it does not draft Voyager docs.
- `linear_issue_author`
    - Draft implementation issue docs from current SSOT outside the default `PRODUCT` harness.

## Suggested orchestration

For a fuzzy product request inside the `PRODUCT` harness:

1. `product_interviewer`
2. `scope_reviewer`
3. `inventory_author` and/or `spec_author`
4. `bundle_reviewer` if the task touches more than one bundle layer

For comparative product/UI research:

1. `product_researcher`
2. `scope_reviewer`
3. `inventory_author` and/or `spec_author`

For new or changed FI rows:

1. `scope_reviewer` when the scope is unclear
2. `inventory_author`
3. `bundle_reviewer` if the FI change also affects IA or FS

For FS drafting or refinement:

1. `scope_reviewer` when the bundle impact is unclear
2. `spec_author`
3. `bundle_reviewer` if contract or bundle parity needs review

For consistency review only:

1. `bundle_reviewer`

For implementation issue drafting outside the `PRODUCT` harness:

1. `scope_reviewer`
2. `linear_issue_author`

## Notes

- These agents are intentionally narrow and documentation-focused.
- They prefer product-facing language over implementation language.
- Review agents are read-only by default.
- The default `PRODUCT` harness covers thesis, persona, IA, FI, and FS only.
- `PRODUCT/06_USE_CASES/` and repo-tracked Linear draft lanes are outside that default harness unless explicitly requested.
- `product_researcher` is intentionally analysis-only. Use an author agent for actual document changes.
- Author agents may update IA, but only when the requested feature/spec change clearly requires minimal UI structure maintenance.
