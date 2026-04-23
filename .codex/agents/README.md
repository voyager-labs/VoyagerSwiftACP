# Voyager Codex Agents

Project-scoped custom agents for `voyager-documentation`.

These files follow the Codex custom subagent format documented here:

- [Codex custom subagent format](https://developers.openai.com/codex/subagents)

Codex loads project agents from `.codex/agents/*.toml`.

## Included agents

- `product_interviewer`
    - Clarify fuzzy product requests before editing IA, FI, or FS, using thesis and persona as reference-only context when helpful.
- `scope_reviewer`
    - Classify requested changes and identify the minimal document touch set inside the product harness, including when thesis/persona should stay reference-only.
- `inventory_author`
    - Draft or refine FI rows in `FEATURES` and `INTERACTIONS`, and update adjacent IA keys when the feature change requires it.
- `spec_author`
    - Draft or refine FEATURE_SPEC files, required category flow docs, and adjacent contract-backed spec artifacts from inventory truth, and update adjacent IA keys when spec work requires it.
- `bundle_reviewer`
    - Audit FI/IA/FS consistency for one feature bundle, including contract-aware drift when relevant.
- `spec_style_reviewer`
    - Review FEATURE_SPEC docs for tone, writing style, hedge wording, literal label consistency, and product-facing clarity.
- `product_researcher`
    - Research a named product deeply and explain its features, UI/UX, screenshots, demos, and behavior. This agent analyzes only; it does not draft Voyager docs.
- `linear_issue_author`
    - Draft build and implementation issue docs from current SSOT outside the default `PRODUCT` harness.
- `feature_spec_issue_author`
    - Draft docs-first `FOUNDATION_DOCS` / feature-spec-definition issue bodies for Linear from current IA/FI/FS truth outside the default `PRODUCT` harness.

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

1. `feature_inventory_checker`
2. `inventory_author` when the FI seed truth is missing or stale
3. `spec_author`
4. `bundle_reviewer` if contract or bundle parity needs review
5. `spec_style_reviewer` if wording, tone, or style readiness also matters

For consistency review only:

1. `bundle_reviewer`

For tone or writing-style review only:

1. `spec_style_reviewer`

For reference alignment review against thesis/persona:

1. `scope_reviewer`
2. `bundle_reviewer`
3. keep thesis/persona read-only unless the parent explicitly asks for a reference-doc rewrite

For implementation issue drafting outside the `PRODUCT` harness:

1. `scope_reviewer`
2. `linear_issue_author`

For docs-first feature-spec issue drafting outside the `PRODUCT` harness:

1. `scope_reviewer`
2. `feature_spec_issue_author`

For the end-to-end feature-spec authoring lifecycle:

1. docs-first issue drafting: `scope_reviewer` -> `feature_spec_issue_author`
2. Phase 1 AI drafting: `feature_inventory_checker` -> `inventory_author`
3. IA sidecar updates only when bundle keys are missing or stale
4. FS lane in fixed order: `spec_author` for `contract -> flow -> interaction spec`
5. `feature_spec_checker`
6. `bundle_reviewer` and/or `fi-ia-fs-consistency-checker`
7. `spec_style_reviewer`
8. hand off to Phase 2 only after the bundle reaches `AI Draft Complete`

## Notes

- These agents are intentionally narrow and documentation-focused.
- They prefer product-facing language over implementation language.
- Review agents are read-only by default.
- The default `PRODUCT` harness writes IA, FI, and FS only.
- `PRODUCT/01_PRODUCT_THESIS/` and `PRODUCT/02_USER_PERSONA/` are reference-only baseline docs used to check whether downstream docs still match the current product truth.
- `PRODUCT/06_USE_CASES/` and repo-tracked Linear draft lanes are outside that default harness unless explicitly requested.
- `product_researcher` is intentionally analysis-only. Use an author agent for actual document changes.
- Author agents may update IA, but only when the requested feature/spec change clearly requires minimal UI structure maintenance.
- `AI Draft Complete` is a lifecycle handoff state, not an approval state.
