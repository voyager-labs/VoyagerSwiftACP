# Feature Spec Authoring Lifecycle

Use this lifecycle for docs-first feature-spec work that starts from a `기능 스펙 정의` or `기능 스펙 정의 및 정리` issue and ends at `AI Draft Complete`.

This lifecycle exists to keep one stable order across issue drafting, FI authoring, IA support, FS authoring, validation, and the human-review handoff.

## Lifecycle Summary

1. `Docs-first issue defined`
2. `Scope locked`
3. `FI seed locked`
4. `IA keys ready`
5. `Contract locked`
6. `Flow locked`
7. `Interaction specs drafted`
8. `Bundle validated`
9. `AI Draft Complete`
10. `Human reviewing`
11. `Approved`

Do not skip from issue drafting to interaction-spec writing.
`FI` is the seed truth for `FS`.
`IA` is a sidecar lane that supports the bundle with the minimum required `structure_key` maintenance.

## Phase 0. Docs-first Issue Definition

This phase is outside the default `PRODUCT` harness.

Default route:

1. `scope_reviewer`
2. `feature_spec_issue_author`

Expected output:

- ready-to-paste Linear issue body
- target `feature_category` or behavior slice
- expected IA/FI/FS touch set
- known unresolved truth that should stay open instead of being invented
- handoff criteria for entering `Phase 1. AI Draft Authoring`

The issue should lock what behavior must be clarified before downstream design or build work starts.
It should not silently rewrite SSOT.

## Phase 1. AI Draft Authoring

The parent agent stays responsible for integration, routing, and final validation.

### Lane A. Scope lock

Default route:

1. `product_owner`
2. `scope_reviewer` when the touch set is still ambiguous

The parent brief should name:

- target category, feature, and interactions when known
- whether the work is category-wide or one feature bundle
- likely IA/FI/FS files or layers
- unresolved product ambiguity that may block authoring

Exit condition:

- the active bundle and touch set are explicit enough to assign work narrowly

### Lane B. FI seed truth

Default route:

1. `feature_inventory_checker`
2. `inventory_author` and `feature_inventory_author` when rows are missing or stale

Required authoring order:

1. `FI.feature_category`
2. `FI.feature`
3. `FI.interaction`

Rules:

- do not start `FS` authoring while the required `feature`, `feature_id`, or `interaction_id` truth is still unresolved
- reuse existing IDs whenever the current truth is still valid
- surface `TBD` as a real product gap instead of inventing a value to unblock the draft

Exit condition:

- required category, feature, and interaction rows exist and are stable enough to drive the spec set

### Lane C. IA sidecar

This lane may run in parallel with FI or FS preparation.

Primary purpose:

- reuse existing `WINDOW_STRUCTURE.structure_key` values
- add or rename the minimum adjacent IA keys required by the active bundle
- keep `FEATURES.related_ui` and `INTERACTIONS.related_region` resolvable
- keep `OBJECTS.key` additions and wording local to the active bundle when contract-backed object nouns need IA support

Rules:

- keep IA changes local to the requested bundle
- do not broaden this into a separate IA redesign lane
- use the dedicated IA authoring surface for `OBJECTS` and adjacent IA tables when new keys or wording rules are needed
- if no new or changed `structure_key` is needed, leave IA untouched

Exit condition:

- all required `related_ui` and `related_region` references resolve cleanly

### Gate 1. FI/IA precheck

Run before `FS` claims can be treated as stable.

Default checks:

- `feature_inventory_checker`
- deterministic `feature_id` / `interaction_id` / `structure_key` validation

Pass criteria:

- required FI rows exist
- `FEATURES.related_ui` and `INTERACTIONS.related_region` resolve or are intentionally `-`
- no unresolved reference blocks contract or interaction-spec writing

If this gate fails, return only to the FI seed lane or IA sidecar lane.

### Lane D. FS authoring

Default route:

1. `spec_author`
2. `feature_spec_author`

Required authoring order:

1. `FS.contract`
2. `FS.flow`
3. `FS.interaction spec`

Rules:

- use the exact object, state, CTA, and trigger vocabulary declared by the current FI truth and shared contracts
- do not author interaction specs as if they were the source of truth for shared category vocabulary
- keep contract-driven flow docs aligned with the interaction specs they summarize
- preserve settled English UI labels when the product already uses them

Exit conditions:

- the category contract exists or is updated when the bundle depends on shared vocabulary
- the category flow exists or is updated when the category is contract-driven
- all required interaction specs for the active bundle exist and are concretely drafted

### Gate 2. FS local check

This is the `contract -> flow -> interaction spec` gate.

Default route:

1. `feature_spec_checker`
2. reroute to `spec_author` only if fixes are needed

Default checks:

- `check_contract_consistency.py <CATEGORY>`
- strict interaction-spec lint
- semantic flow review against the linked specs

Pass criteria:

- no structural contract or flow failures remain
- interaction specs preserve the required frontmatter and fixed section shell
- flow, contract, and interaction specs do not disagree on ownership, sequence, or state vocabulary in a way that changes implementation or review interpretation

If this gate fails, return only to the FS authoring lane or IA sidecar lane when the failure is caused by missing surface keys.

### Gate 3. Bundle validation

This is the cross-layer gate for the whole bundle.

Default route:

1. `bundle_consistency_checker`
2. `bundle_reviewer`
3. `spec_style_reviewer`

Default checks:

- `check_feature_bundle.py <FEATURE_ID>`
- category evaluation when shared contracts or flows changed
- semantic contradiction review across FI, IA, and FS
- tone and wording consistency review across the affected spec set
- hedge wording and implementation-heavy prose review across the affected spec set

Pass criteria:

- deterministic FI/IA/FS references are clean
- deterministic FEATURE_SPEC sync points are clean
- no blocking contradiction remains across FI, IA, and FS
- tone, wording, and contract language are consistent enough for human review to focus on product decisions instead of structural cleanup
- no blocking tone/style finding remains that would force humans to do basic draft cleanup before reviewing product meaning

## `AI Draft Complete`

Only use `AI Draft Complete` when all of the following are true:

- required FI rows exist for the active bundle
- required IA keys are resolved
- required contract, flow, and interaction-spec files exist
- deterministic validation has no blocking failure
- semantic review found no blocking contradiction
- style review found no blocking tone or writing-quality issue
- any remaining review notes are explicitly framed as `Phase 2` human-review items rather than hidden draft debt

`AI Draft Complete` does not mean the docs are approved.
It means the machine- and reviewer-readable draft is complete enough for focused human review.

## Phase 2. Human Review

This phase starts after `AI Draft Complete`.

Primary goals:

- confirm or revise product decisions
- polish wording and document tone
- remove implementation-heavy language that should not live in product docs
- verify literal UI labels, CTA labels, state names, and branch semantics
- decide whether human-reviewed `<<AI>>` markers should be removed

When the human reviewer explicitly asks to mark one interaction spec as reviewed or `검토 완료`:

- target only the named interaction spec path or `interaction_id`
- remove `<<AI>>` markers from that interaction spec's human-readable frontmatter values and body prose
- if its `status` is `아이디어` or `드래프트`, promote it to `기획 완료`
- sync the matching FI `INTERACTIONS` row in the same pass by removing the matching `<<AI>>` long-text marker and promoting `status` from `아이디어` or `드래프트` to `기획 완료`
- do not auto-promote sibling interaction specs, the parent `FEATURES` row, category `flows/*.md`, or category `contracts/*.toml`
- rerun the touched spec lint and matching FI validation before claiming the handoff is complete

Default outcome:

- `Approved`, or
- explicit return to the smallest failed lane in `Phase 1`

Do not treat `Phase 2` as a second AI-drafting pass by default.
It is a human-in-the-loop review phase.
