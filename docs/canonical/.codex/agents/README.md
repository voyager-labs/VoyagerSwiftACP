# Voyager Codex Agents

Project-scoped custom agents for `voyager-documentation`.

These files follow the Codex custom subagent format documented here:

- https://developers.openai.com/codex/subagents

Codex loads project agents from `.codex/agents/*.toml`.

## Included agents

- `product_interviewer`
  - Clarify fuzzy product requests before editing FI/IA/FS.
- `scope_reviewer`
  - Classify requested changes and identify which document layers should change.
- `inventory_author`
  - Draft or refine FI rows in `FEATURES` and `INTERACTIONS`, and update adjacent IA keys when the feature change requires it.
- `spec_author`
  - Draft or refine FEATURE_SPEC files from inventory truth, and update adjacent IA keys when spec work requires it.
- `bundle_reviewer`
  - Audit FI/IA/FS consistency for one feature bundle.
- `product_researcher`
  - Research a named product deeply and explain its features, UI/UX, screenshots, demos, and behavior. This agent analyzes only; it does not draft Voyager docs.
- `linear_issue_author`
  - Draft implementation issue docs from current SSOT.

## Suggested orchestration

For a fuzzy product request:

1. `product_interviewer`
2. `scope_reviewer`
3. `inventory_author` and/or `spec_author`
4. `bundle_reviewer`

For comparative product/UI research:

1. `product_researcher`
2. `scope_reviewer`
3. `inventory_author` and/or `spec_author`

For consistency review only:

1. `bundle_reviewer`

For implementation issue drafting:

1. `scope_reviewer`
2. `linear_issue_author`

## Notes

- These agents are intentionally narrow and documentation-focused.
- They prefer product-facing language over implementation language.
- Review agents are read-only by default.
- `product_researcher` is intentionally analysis-only. Use an author agent for actual document changes.
- Author agents may update IA, but only when the requested feature/spec change clearly requires minimal UI structure maintenance.
